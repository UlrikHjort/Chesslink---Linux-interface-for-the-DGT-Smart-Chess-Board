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
 * Unit tests for the move-detection state machine in dgtboard.c, driven
 * with synthetic lift/place events (no real board needed). Pulls in the
 * .c file directly so it can call the internal feed_event() and poke at
 * dgt_board_t, which is opaque outside dgtboard.c. */

#include "../lib/dgtboard.c"

#include <stdio.h>
#include <string.h>

static int n_pass = 0, n_fail = 0;

#define CHECK(cond) do { \
        if (cond) { n_pass++; } \
        else { n_fail++; printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } \
    } while (0)

static const unsigned char START[64] = {
    P_BROOK, P_BKNIGHT, P_BBISHOP, P_BQUEEN, P_BKING, P_BBISHOP, P_BKNIGHT, P_BROOK,
    P_BPAWN, P_BPAWN,   P_BPAWN,   P_BPAWN,  P_BPAWN, P_BPAWN,   P_BPAWN,   P_BPAWN,
    0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,
    P_WPAWN, P_WPAWN,   P_WPAWN,   P_WPAWN,  P_WPAWN, P_WPAWN,   P_WPAWN,   P_WPAWN,
    P_WROOK, P_WKNIGHT, P_WBISHOP, P_WQUEEN, P_WKING, P_WBISHOP, P_WKNIGHT, P_WROOK,
};

static int sq_alg(const char *alg) { /* "e2" -> DGT index (0=a8..63=h1) */
    int file = alg[0] - 'a';
    int rank = alg[1] - '0';
    return sq_at(8 - rank, file);
}

static void init_board(dgt_board_t *b, const unsigned char *pos, int white_to_move) {
    memset(b, 0, sizeof *b);
    memcpy(b->pos, pos, 64);
    b->white_to_move = white_to_move;
    b->ep_sq = -1;
    b->castle_wk = b->castle_wq = b->castle_bk = b->castle_bq = 1;
    b->phase = PH_IDLE;
}

static void test_quiet_pawn_push(void) {
    dgt_board_t b;
    init_board(&b, START, 1);
    char uci[6] = {0};

    CHECK(feed_event(&b, sq_alg("e2"), P_EMPTY, uci) == 1);
    CHECK(feed_event(&b, sq_alg("e4"), P_WPAWN, uci) == 0);
    CHECK(strcmp(uci, "e2e4") == 0);
    CHECK(b.white_to_move == 0);
    CHECK(b.pos[sq_alg("e4")] == P_WPAWN);
    CHECK(b.pos[sq_alg("e2")] == P_EMPTY);
}

static void test_knight_move(void) {
    dgt_board_t b;
    init_board(&b, START, 1);
    char uci[6] = {0};

    CHECK(feed_event(&b, sq_alg("g1"), P_EMPTY, uci) == 1);
    CHECK(feed_event(&b, sq_alg("f3"), P_WKNIGHT, uci) == 0);
    CHECK(strcmp(uci, "g1f3") == 0);
}

static void test_capture_lift_capturer_then_victim(void) {
    unsigned char pos[64];
    memset(pos, P_EMPTY, sizeof pos);
    pos[sq_alg("d4")] = P_WKNIGHT;
    pos[sq_alg("e6")] = P_BPAWN;

    dgt_board_t b;
    init_board(&b, pos, 1);
    char uci[6] = {0};

    CHECK(feed_event(&b, sq_alg("d4"), P_EMPTY, uci) == 1); /* lift capturer */
    CHECK(feed_event(&b, sq_alg("e6"), P_EMPTY, uci) == 1); /* lift victim */
    CHECK(feed_event(&b, sq_alg("e6"), P_WKNIGHT, uci) == 0); /* place capturer */
    CHECK(strcmp(uci, "d4e6") == 0);
    CHECK(b.pos[sq_alg("e6")] == P_WKNIGHT);
    CHECK(b.pos[sq_alg("d4")] == P_EMPTY);
}

static void test_kingside_castle(void) {
    unsigned char pos[64];
    memset(pos, P_EMPTY, sizeof pos);
    pos[sq_alg("e1")] = P_WKING;
    pos[sq_alg("h1")] = P_WROOK;
    pos[sq_alg("e8")] = P_BKING;

    dgt_board_t b;
    init_board(&b, pos, 1);
    char uci[6] = {0};

    CHECK(feed_event(&b, sq_alg("e1"), P_EMPTY, uci) == 1);
    CHECK(feed_event(&b, sq_alg("g1"), P_WKING, uci) == 1); /* king lands, awaits rook */
    CHECK(feed_event(&b, sq_alg("h1"), P_EMPTY, uci) == 1);
    CHECK(feed_event(&b, sq_alg("f1"), P_WROOK, uci) == 0);
    CHECK(strcmp(uci, "e1g1") == 0);
    CHECK(b.pos[sq_alg("g1")] == P_WKING);
    CHECK(b.pos[sq_alg("f1")] == P_WROOK);
    CHECK(b.pos[sq_alg("e1")] == P_EMPTY);
    CHECK(b.pos[sq_alg("h1")] == P_EMPTY);
}

static void test_en_passant(void) {
    unsigned char pos[64];
    memset(pos, P_EMPTY, sizeof pos);
    pos[sq_alg("e5")] = P_WPAWN;
    pos[sq_alg("d5")] = P_BPAWN; /* just double-pushed d7-d5 */

    dgt_board_t b;
    init_board(&b, pos, 1);
    b.ep_sq = sq_alg("d6");
    char uci[6] = {0};

    CHECK(feed_event(&b, sq_alg("e5"), P_EMPTY, uci) == 1);
    CHECK(feed_event(&b, sq_alg("d6"), P_WPAWN, uci) == 0);
    CHECK(strcmp(uci, "e5d6") == 0);
    CHECK(b.phase == PH_EP_CLEANUP);
    CHECK(b.pos[sq_alg("d5")] == P_BPAWN); /* not removed until cleanup lift */

    CHECK(feed_event(&b, sq_alg("d5"), P_EMPTY, uci) == 1);
    CHECK(b.pos[sq_alg("d5")] == P_EMPTY);
    CHECK(b.phase == PH_IDLE);
}

static void test_promotion(void) {
    unsigned char pos[64];
    memset(pos, P_EMPTY, sizeof pos);
    pos[sq_alg("e7")] = P_WPAWN;

    dgt_board_t b;
    init_board(&b, pos, 1);
    char uci[6] = {0};

    CHECK(feed_event(&b, sq_alg("e7"), P_EMPTY, uci) == 1);
    CHECK(feed_event(&b, sq_alg("e8"), P_WQUEEN, uci) == 0);
    CHECK(strcmp(uci, "e7e8q") == 0);
}

static void test_fen_start_position(void) {
    dgt_board_t b;
    init_board(&b, START, 1);
    char fen[DGT_FEN_MAX];

    render_fen(&b, fen);
    CHECK(strcmp(fen, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1") == 0);
}

static void test_fen_after_moves(void) {
    dgt_board_t b;
    init_board(&b, START, 1);
    char uci[6] = {0};

    CHECK(feed_event(&b, sq_alg("e2"), P_EMPTY, uci) == 1);
    CHECK(feed_event(&b, sq_alg("e4"), P_WPAWN, uci) == 0); /* opens e3 for e.p. */

    char fen[DGT_FEN_MAX];
    render_fen(&b, fen);
    CHECK(strcmp(fen,
        "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1") == 0);
}

static void test_fen_after_castle_drops_rights(void) {
    unsigned char pos[64];
    memset(pos, P_EMPTY, sizeof pos);
    pos[sq_alg("e1")] = P_WKING;
    pos[sq_alg("h1")] = P_WROOK;
    pos[sq_alg("e8")] = P_BKING;

    dgt_board_t b;
    init_board(&b, pos, 1);
    char uci[6] = {0};

    CHECK(feed_event(&b, sq_alg("e1"), P_EMPTY, uci) == 1);
    CHECK(feed_event(&b, sq_alg("g1"), P_WKING, uci) == 1);
    CHECK(feed_event(&b, sq_alg("h1"), P_EMPTY, uci) == 1);
    CHECK(feed_event(&b, sq_alg("f1"), P_WROOK, uci) == 0);

    char fen[DGT_FEN_MAX];
    render_fen(&b, fen);
    CHECK(strcmp(fen, "4k3/8/8/8/8/8/8/5RK1 b kq - 0 1") == 0);
}

static void test_illegal_geometry_rejected(void) {
    dgt_board_t b;
    init_board(&b, START, 1);
    char uci[6] = {0};

    /* Rook can't jump to a square three ranks away with pieces in the way. */
    CHECK(feed_event(&b, sq_alg("a1"), P_EMPTY, uci) == 1);
    CHECK(feed_event(&b, sq_alg("a4"), P_WROOK, uci) == -1);
    CHECK(b.pos[sq_alg("a1")] == P_WROOK); /* restored */
    CHECK(b.phase == PH_IDLE);
}

static void test_wrong_side_to_move_rejected(void) {
    dgt_board_t b;
    init_board(&b, START, 1); /* White to move */
    char uci[6] = {0};

    CHECK(feed_event(&b, sq_alg("e7"), P_EMPTY, uci) == 1); /* black pawn lifted */
    CHECK(feed_event(&b, sq_alg("e5"), P_BPAWN, uci) == -1);
    CHECK(b.pos[sq_alg("e7")] == P_BPAWN); /* restored */
}

int main(void) {
    test_quiet_pawn_push();
    test_knight_move();
    test_capture_lift_capturer_then_victim();
    test_kingside_castle();
    test_en_passant();
    test_promotion();
    test_illegal_geometry_rejected();
    test_wrong_side_to_move_rejected();
    test_fen_start_position();
    test_fen_after_moves();
    test_fen_after_castle_drops_rights();

    printf("%d passed, %d failed\n", n_pass, n_fail);
    return n_fail == 0 ? 0 : 1;
}
