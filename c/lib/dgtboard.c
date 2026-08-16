/* ***************************************************************************
 *                    DGT Smart Board - Minimal C Library
 *
 *          Copyright (C) 2026 By Ulrik Hoerlyk Hjort
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 * LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 * OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 * WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 * ***************************************************************************
 *
 * DGT wire protocol 
 *
 *   Every message from the board is [msg_id, len_hi, len_lo, ...payload],
 *   where len includes the 3 header bytes.
 *
 *   Board squares are indexed 0=a8 .. 63=h1 (row-major, top-left origin).
 *   This file keeps that layout internally and only converts to
 *   algebraic/UCI text at the API boundary.
 */

#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE /* cfmakeraw() is a glibc/BSD extension, not POSIX */

#include "dgtboard.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

/* ---- Wire protocol constants ------------------------------------------ */

#define CMD_RESET            0x40
#define CMD_SEND_BRD         0x42
#define CMD_SEND_UPDATE      0x43

#define MSG_BOARD_DUMP        0x86
#define MSG_FIELD_UPDATE      0x8E

/* Piece codes as sent by the board. */
enum {
    P_EMPTY = 0x00,
    P_WPAWN = 0x01, P_WROOK = 0x02, P_WKNIGHT = 0x03,
    P_WBISHOP = 0x04, P_WKING = 0x05, P_WQUEEN = 0x06,
    P_BPAWN = 0x07, P_BROOK = 0x08, P_BKNIGHT = 0x09,
    P_BBISHOP = 0x0A, P_BKING = 0x0B, P_BQUEEN = 0x0C
};

static int is_white_piece(unsigned char p) { return p >= P_WPAWN && p <= P_WQUEEN; }
static int is_pawn(unsigned char p)  { return p == P_WPAWN || p == P_BPAWN; }
static int is_king(unsigned char p)  { return p == P_WKING || p == P_BKING; }

/* DGT layout: file = sq % 8 (0=a), row = sq / 8 (0 = rank 8, 7 = rank 1). */
static int file_of(int sq) { return sq % 8; }
static int row_of(int sq)  { return sq / 8; }
static int sq_at(int row, int file) { return row * 8 + file; }

/* ---- Move detection state ---------------------------------------------- */

typedef enum {
    PH_IDLE,
    PH_HOLDING,           /* piece lifted, waiting for placement */
    PH_CASTLE_ROOK_LIFT,  /* king placed, waiting for the rook to be lifted */
    PH_CASTLE_ROOK_PLACE, /* rook lifted, waiting for the rook to be placed */
    PH_EP_CLEANUP         /* en-passant pawn placed, captured pawn still on board */
} phase_t;

typedef struct {
    int from, to;
    unsigned char piece, captured, promo;
    int castle_k, castle_q, is_ep;
} pend_move_t;

struct dgt_board {
    int fd;
    unsigned char pos[64];   /* current board, DGT layout */
    int white_to_move;

    int ep_sq;                /* DGT square index, -1 = none */
    int castle_wk, castle_wq, castle_bk, castle_bq;

    phase_t phase;
    int lift_from;
    unsigned char lift_piece;
    unsigned char pre_move[64];
    int rook_from;
    int ep_cap_sq;
    pend_move_t pend;

    char error[128];
};

/* ---- Serial I/O -----------------------------------------------------------
 * read() with VTIME giving ~0.1s partial timeouts, retried against an
 * overall deadline so a message that arrives in two chunks (common over a
 * virtual serial port) is still assembled. */

/* Return codes: 0 = got all len bytes, 1 = timed out with nothing fatal
 * (caller may retry), -1 = fatal I/O error (device gone). */
static int read_bytes(int fd, unsigned char *buf, size_t len, char *err) {
    struct timespec deadline, now;
    clock_gettime(CLOCK_MONOTONIC, &deadline);
    deadline.tv_nsec += 500 * 1000000L; /* 500ms */
    if (deadline.tv_nsec >= 1000000000L) { deadline.tv_sec++; deadline.tv_nsec -= 1000000000L; }

    size_t got = 0;
    while (got < len) {
        ssize_t n = read(fd, buf + got, len - got);
        if (n > 0) {
            got += (size_t) n;
            continue;
        }
        if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
            if (err) snprintf(err, 128, "read: %s", strerror(errno));
            return -1;
        }
        clock_gettime(CLOCK_MONOTONIC, &now);
        if (now.tv_sec > deadline.tv_sec ||
            (now.tv_sec == deadline.tv_sec && now.tv_nsec > deadline.tv_nsec)) {
            if (err) snprintf(err, 128, "DGT read timeout");
            return got == 0 ? 1 : -1; /* partial message on timeout is fatal */
        }
    }
    return 0;
}

/* Same return convention as read_bytes. */
static int read_header(int fd, unsigned char *msg_id, int *length, char *err) {
    unsigned char hdr[3];
    int rc = read_bytes(fd, hdr, 3, err);
    if (rc != 0) return rc;
    *msg_id = hdr[0];
    *length = hdr[1] * 256 + hdr[2];
    return 0;
}

static int send_cmd(int fd, unsigned char cmd) {
    return write(fd, &cmd, 1) == 1 ? 0 : -1;
}

/* ---- Board access -------------------------------------------------------- */

char dgt_square(dgt_board_t *b, int sq) {
    static const char white_letters[] = { 0, 'P', 'R', 'N', 'B', 'K', 'Q' };
    static const char black_letters[] = { 0, 'p', 'r', 'n', 'b', 'k', 'q' };
    if (sq < 0 || sq > 63) return '.';
    /* caller uses 0=a1..63=h8; internal layout is 0=a8..63=h1 */
    int file = sq % 8, rank = sq / 8;
    int dgt_sq = sq_at(7 - rank, file);
    unsigned char p = b->pos[dgt_sq];
    if (p == P_EMPTY) return '.';
    if (is_white_piece(p)) return white_letters[p];
    return black_letters[p - P_BPAWN + 1];
}

int dgt_white_to_move(dgt_board_t *b) { return b->white_to_move; }

const char *dgt_last_error(dgt_board_t *b) { return b->error; }

/* ---- Geometry (minimal legality: movement pattern only, no check test) - */

static int path_clear(const unsigned char *board, int from, int to) {
    int df = file_of(to) - file_of(from);
    int dr = row_of(to) - row_of(from);
    int step_f = (df > 0) - (df < 0);
    int step_r = (dr > 0) - (dr < 0);
    int f = file_of(from) + step_f, r = row_of(from) + step_r;
    while (f != file_of(to) || r != row_of(to)) {
        if (board[sq_at(r, f)] != P_EMPTY) return 0;
        f += step_f;
        r += step_r;
    }
    return 1;
}

/* Can `piece` (non-pawn) reach `to` from `from` on `board`? */
static int can_attack(const unsigned char *board, int from, int to, unsigned char piece) {
    int df = file_of(to) - file_of(from);
    int dr = row_of(to) - row_of(from);
    int adf = df < 0 ? -df : df;
    int adr = dr < 0 ? -dr : dr;

    switch (piece) {
    case P_WKNIGHT: case P_BKNIGHT:
        return (adf == 1 && adr == 2) || (adf == 2 && adr == 1);
    case P_WBISHOP: case P_BBISHOP:
        return adf == adr && adf != 0 && path_clear(board, from, to);
    case P_WROOK: case P_BROOK:
        return ((df == 0) != (dr == 0)) && path_clear(board, from, to);
    case P_WQUEEN: case P_BQUEEN:
        return ((adf == adr && adf != 0) || ((df == 0) != (dr == 0)))
               && path_clear(board, from, to);
    case P_WKING: case P_BKING:
        return adf <= 1 && adr <= 1 && (adf != 0 || adr != 0);
    default:
        return 0;
    }
}

static int is_castle_attempt(unsigned char piece, int from, int to) {
    return is_king(piece) && row_of(from) == row_of(to)
           && (file_of(to) - file_of(from) == 2 || file_of(to) - file_of(from) == -2);
}

static int is_ep_attempt(unsigned char piece, int from, int to, int dest_was_empty) {
    if (!is_pawn(piece) || !dest_was_empty) return 0;
    int df = file_of(to) - file_of(from);
    int fwd = (piece == P_WPAWN) ? -1 : 1;
    return (df == 1 || df == -1) && row_of(to) - row_of(from) == fwd;
}

static int ep_captured_sq(int from, int to) { return sq_at(row_of(from), file_of(to)); }

static int is_promo(unsigned char piece, int to) {
    if (piece == P_WPAWN) return row_of(to) == 0;
    if (piece == P_BPAWN) return row_of(to) == 7;
    return 0;
}

static void kill_castling(dgt_board_t *b, int sq) {
    if (sq == sq_at(7, 4)) { b->castle_wk = b->castle_wq = 0; } /* e1 moved/captured */
    if (sq == sq_at(0, 4)) { b->castle_bk = b->castle_bq = 0; } /* e8 */
    if (sq == sq_at(7, 7)) b->castle_wk = 0; /* h1 */
    if (sq == sq_at(7, 0)) b->castle_wq = 0; /* a1 */
    if (sq == sq_at(0, 7)) b->castle_bk = 0; /* h8 */
    if (sq == sq_at(0, 0)) b->castle_bq = 0; /* a8 */
}

/* ---- UCI rendering -------------------------------------------------------- */

static void write_uci(char out[6], int from, int to, unsigned char promo) {
    static const char files[] = "abcdefgh";
    out[0] = files[file_of(from)];
    out[1] = (char) ('0' + (8 - row_of(from)));
    out[2] = files[file_of(to)];
    out[3] = (char) ('0' + (8 - row_of(to)));
    int n = 4;
    if (promo != P_EMPTY) {
        char c = 'q';
        switch (promo) {
        case P_WROOK: case P_BROOK: c = 'r'; break;
        case P_WKNIGHT: case P_BKNIGHT: c = 'n'; break;
        case P_WBISHOP: case P_BBISHOP: c = 'b'; break;
        default: c = 'q'; break;
        }
        out[n++] = c;
    }
    out[n] = '\0';
}

/* ---- Move detection state machine ----------------------------------------
 * Turns raw lift/place field-update events into UCI moves. Deliberately
 * does not validate check, pins or checkmate -- this only verifies that
 * the physically lifted piece can reach the square it was placed on, not
 * whether doing so is legal for the side to move. See dgtboard.h. */

static int commit(dgt_board_t *b, char uci[6]) {
    write_uci(uci, b->pend.from, b->pend.to, b->pend.promo);
    b->white_to_move = !b->white_to_move;
    return 0;
}

/* Returns: 0 = move complete (uci filled), 1 = event consumed, no move yet,
 * -1 = event made no sense and was rejected (board restored). */
static int feed_event(dgt_board_t *b, int square, unsigned char piece, char uci[6]) {
    if (piece == P_EMPTY) {
        /* ---- lift ---- */
        switch (b->phase) {
        case PH_IDLE:
            memcpy(b->pre_move, b->pos, 64);
            b->lift_from = square;
            b->lift_piece = b->pos[square];
            b->pos[square] = P_EMPTY;
            b->phase = PH_HOLDING;
            return 1;

        case PH_HOLDING: {
            unsigned char second = b->pos[square];
            if (b->lift_piece != P_EMPTY && second != P_EMPTY &&
                is_white_piece(second) != is_white_piece(b->lift_piece)) {
                /* Opponent's piece lifted second (capture): leave it in
                 * pos[] so the placement handler records it as captured. */
                return 1;
            }
            /* Changed mind: put the held piece back. */
            b->pos[b->lift_from] = b->lift_piece;
            if (second == P_EMPTY || is_white_piece(second) != b->white_to_move) {
                b->phase = PH_IDLE;
                return 1;
            }
            memcpy(b->pre_move, b->pos, 64);
            b->lift_from = square;
            b->lift_piece = second;
            b->pos[square] = P_EMPTY;
            return 1;
        }

        case PH_CASTLE_ROOK_LIFT:
            b->rook_from = square;
            b->pos[square] = P_EMPTY;
            b->phase = PH_CASTLE_ROOK_PLACE;
            return 1;

        case PH_EP_CLEANUP:
            if (square == b->ep_cap_sq) {
                b->pos[square] = P_EMPTY;
                b->phase = PH_IDLE;
            } else {
                memcpy(b->pre_move, b->pos, 64);
                b->lift_from = square;
                b->lift_piece = b->pos[square];
                b->pos[square] = P_EMPTY;
                b->phase = PH_HOLDING;
            }
            return 1;

        case PH_CASTLE_ROOK_PLACE:
        default:
            return 1;
        }
    }

    /* ---- place ---- */
    switch (b->phase) {
    case PH_HOLDING: {
        unsigned char captured = b->pos[square];

        if (b->lift_piece == P_EMPTY) { b->phase = PH_IDLE; return 1; } /* ghost lift */

        if (is_white_piece(b->lift_piece) != b->white_to_move) {
            memcpy(b->pos, b->pre_move, 64);
            b->phase = PH_IDLE;
            snprintf(b->error, sizeof b->error, "wrong-colour piece moved");
            return -1;
        }

        b->pos[square] = piece;
        b->pend.from = b->lift_from;
        b->pend.to = square;
        b->pend.piece = b->lift_piece;
        b->pend.captured = captured;
        b->pend.promo = P_EMPTY;
        b->pend.castle_k = b->pend.castle_q = b->pend.is_ep = 0;

        if (is_castle_attempt(b->lift_piece, b->lift_from, square)) {
            b->pend.castle_k = square > b->lift_from;
            b->pend.castle_q = square < b->lift_from;
            kill_castling(b, b->lift_from);
            b->phase = PH_CASTLE_ROOK_LIFT;
            return 1;
        }

        if (is_ep_attempt(b->lift_piece, b->lift_from, square, captured == P_EMPTY)) {
            if (b->ep_sq < 0 || square != b->ep_sq) {
                memcpy(b->pos, b->pre_move, 64);
                b->phase = PH_IDLE;
                snprintf(b->error, sizeof b->error, "diagonal pawn move with no en-passant target");
                return -1;
            }
            b->pend.is_ep = 1;
            b->ep_cap_sq = ep_captured_sq(b->lift_from, square);
            b->pend.captured = b->pos[b->ep_cap_sq];
            kill_castling(b, b->lift_from);
            int rc = commit(b, uci);
            b->phase = PH_EP_CLEANUP;
            b->ep_sq = -1;
            return rc;
        }

        {
            int geo_ok;
            int df = file_of(square) - file_of(b->lift_from);
            int dr = row_of(square) - row_of(b->lift_from);
            int fwd = (b->lift_piece == P_WPAWN) ? -1 : 1;

            if (is_pawn(b->lift_piece)) {
                geo_ok =
                    (df == 0 && dr == fwd && captured == P_EMPTY) ||
                    (df == 0 && dr == 2 * fwd && captured == P_EMPTY &&
                     row_of(b->lift_from) == (b->lift_piece == P_WPAWN ? 6 : 1) &&
                     b->pre_move[sq_at(row_of(b->lift_from) + fwd, file_of(b->lift_from))] == P_EMPTY) ||
                    ((df == 1 || df == -1) && dr == fwd && captured != P_EMPTY);
            } else {
                geo_ok = can_attack(b->pre_move, b->lift_from, square, b->lift_piece);
            }

            if (!geo_ok) {
                memcpy(b->pos, b->pre_move, 64);
                b->phase = PH_IDLE;
                snprintf(b->error, sizeof b->error, "piece cannot reach that square");
                return -1;
            }

            if (is_promo(b->lift_piece, square)) b->pend.promo = piece;

            /* New en-passant target: a pawn just double-pushed. */
            b->ep_sq = (is_pawn(b->lift_piece) && (dr == 2 || dr == -2))
                       ? sq_at(row_of(b->lift_from) + fwd, file_of(b->lift_from)) : -1;

            kill_castling(b, b->lift_from);
            kill_castling(b, square);
            int rc = commit(b, uci);
            b->phase = PH_IDLE;
            return rc;
        }
    }

    case PH_CASTLE_ROOK_PLACE:
        b->pos[square] = piece;
        kill_castling(b, b->rook_from);
        {
            int rc = commit(b, uci);
            b->phase = PH_IDLE;
            return rc;
        }

    case PH_IDLE:
    case PH_CASTLE_ROOK_LIFT:
    case PH_EP_CLEANUP:
    default:
        b->pos[square] = piece; /* out-of-band placement: just absorb it */
        return 1;
    }
}

/* Request a fresh full board dump and store it in b->pos, tolerating any
 * field-update messages already queued from the streaming mode started in
 * dgt_open(). */
static int scan_board_during_updates(dgt_board_t *b) {
    if (send_cmd(b->fd, CMD_SEND_BRD) != 0) {
        snprintf(b->error, sizeof b->error, "write: %s", strerror(errno));
        return -1;
    }
    for (;;) {
        unsigned char msg_id = 0; int length = 0;
        if (read_header(b->fd, &msg_id, &length, b->error) != 0) return -1;
        if (msg_id == MSG_BOARD_DUMP) {
            return read_bytes(b->fd, b->pos, 64, b->error) == 0 ? 0 : -1;
        }
        if (length > 3) {
            unsigned char skip[256];
            int n = length - 3;
            if (n > (int) sizeof skip) n = (int) sizeof skip;
            if (read_bytes(b->fd, skip, (size_t) n, b->error) != 0) return -1;
        }
    }
}

/* Renders the tracked position as a FEN string (no I/O). Piece placement
 * comes straight from b->pos, which is already in rank-8-to-rank-1, DGT
 * row-major order -- the same order FEN wants. Active colour, castling
 * rights and the en-passant square come from state tracked since dgt_open()
 * via committed moves; halfmove/fullmove counters are not tracked by this
 * minimal library and are always written as "0 1". fen must be at least
 * DGT_FEN_MAX bytes. */
static void render_fen(const dgt_board_t *b, char *fen) {
    static const char white_letters[] = { 0, 'P', 'R', 'N', 'B', 'K', 'Q' };
    static const char black_letters[] = { 0, 'p', 'r', 'n', 'b', 'k', 'q' };
    static const char files[] = "abcdefgh";
    char *p = fen;

    for (int row = 0; row < 8; row++) {
        int empty = 0;
        for (int file = 0; file < 8; file++) {
            unsigned char piece = b->pos[sq_at(row, file)];
            if (piece == P_EMPTY) { empty++; continue; }
            if (empty) { *p++ = (char) ('0' + empty); empty = 0; }
            *p++ = is_white_piece(piece) ? white_letters[piece]
                                          : black_letters[piece - P_BPAWN + 1];
        }
        if (empty) *p++ = (char) ('0' + empty);
        if (row != 7) *p++ = '/';
    }

    *p++ = ' ';
    *p++ = b->white_to_move ? 'w' : 'b';
    *p++ = ' ';
    if (b->castle_wk) *p++ = 'K';
    if (b->castle_wq) *p++ = 'Q';
    if (b->castle_bk) *p++ = 'k';
    if (b->castle_bq) *p++ = 'q';
    if (!(b->castle_wk || b->castle_wq || b->castle_bk || b->castle_bq)) *p++ = '-';
    *p++ = ' ';
    if (b->ep_sq >= 0) {
        *p++ = files[file_of(b->ep_sq)];
        *p++ = (char) ('0' + (8 - row_of(b->ep_sq)));
    } else {
        *p++ = '-';
    }
    memcpy(p, " 0 1", 4);
    p += 4;
    *p = '\0';
}

/* ---- Public API ------------------------------------------------------- */

dgt_board_t *dgt_open(const char *device) {
    dgt_board_t *b = calloc(1, sizeof *b);
    if (!b) return NULL;
    b->white_to_move = 1;
    b->ep_sq = -1;
    b->castle_wk = b->castle_wq = b->castle_bk = b->castle_bq = 1;
    b->phase = PH_IDLE;

    b->fd = open(device, O_RDWR | O_NOCTTY);
    if (b->fd < 0) {
        snprintf(b->error, sizeof b->error, "open %s: %s", device, strerror(errno));
        free(b);
        return NULL;
    }

    struct termios tio;
    if (tcgetattr(b->fd, &tio) != 0) {
        snprintf(b->error, sizeof b->error, "tcgetattr: %s", strerror(errno));
        close(b->fd); free(b); return NULL;
    }
    cfmakeraw(&tio);
    cfsetispeed(&tio, B9600);
    cfsetospeed(&tio, B9600);
    tio.c_cflag = (tio.c_cflag & ~(CSIZE | PARENB)) | CS8 | CLOCAL | CREAD;
    tio.c_cc[VMIN] = 0;
    tio.c_cc[VTIME] = 1; /* 0.1s */
    if (tcsetattr(b->fd, TCSANOW, &tio) != 0) {
        snprintf(b->error, sizeof b->error, "tcsetattr: %s", strerror(errno));
        close(b->fd); free(b); return NULL;
    }
    tcflush(b->fd, TCIOFLUSH);

    if (scan_board_during_updates(b) != 0) { close(b->fd); free(b); return NULL; }

    if (send_cmd(b->fd, CMD_SEND_UPDATE) != 0) {
        snprintf(b->error, sizeof b->error, "write: %s", strerror(errno));
        close(b->fd); free(b); return NULL;
    }

    return b;
}

void dgt_close(dgt_board_t *b) {
    if (!b) return;
    close(b->fd);
    free(b);
}

int dgt_next_move(dgt_board_t *b, char uci[6]) {
    for (;;) {
        unsigned char msg_id = 0; int length = 0;
        int hdr_rc = read_header(b->fd, &msg_id, &length, b->error);
        if (hdr_rc == 1) continue;   /* timeout with no data: keep waiting */
        if (hdr_rc == -1) return -1; /* fatal I/O error: board gone */
        if (msg_id == MSG_FIELD_UPDATE) {
            unsigned char data[2];
            if (read_bytes(b->fd, data, 2, b->error) != 0) return -1;
            int rc = feed_event(b, data[0], data[1], uci);
            if (rc == 0) return 0;
            if (rc == -1) return 1;
            /* rc == 1: event consumed, keep reading */
        } else if (length > 3) {
            unsigned char skip[256];
            int n = length - 3;
            if (n > (int) sizeof skip) n = (int) sizeof skip;
            if (read_bytes(b->fd, skip, (size_t) n, b->error) != 0) return -1;
        }
    }
}

int dgt_scan_fen(dgt_board_t *b, char fen[DGT_FEN_MAX]) {
    if (scan_board_during_updates(b) != 0) return -1;
    render_fen(b, fen);
    return 0;
}
