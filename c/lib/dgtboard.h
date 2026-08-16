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
 * ***************************************************************************/

#ifndef DGTBOARD_H
#define DGTBOARD_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct dgt_board dgt_board_t;

/* Opens the serial device (e.g. "/dev/ttyACM0"), reads the initial board
 * dump and starts the update stream. The board is assumed to be in the
 * standard starting position with White to move -- there is no way to
 * ask the hardware who is to move, so callers starting from a custom
 * position must track that themselves.
 * Returns NULL on failure. */
dgt_board_t *dgt_open(const char *device);

void dgt_close(dgt_board_t *board);

/* Blocks until one full move is detected on the board, then writes it in
 * UCI notation ("e2e4", "e7e8q", ...) into uci, which must be at least
 * 6 bytes. Castling is reported as the king's move (e.g. "e1g1").
 *
 * Only piece-movement geometry is checked (can this piece physically
 * reach that square, is a path blocked, is en passant/castling
 * structurally sane). Check, pins and checkmate are NOT validated --
 * this is a board-to-UCI translator, not a chess engine. Feed the
 * result through your own legality check if you need that.
 *
 * Returns 0 on success, -1 on I/O error (board disconnected), 1 if the
 * physical move made no chess sense (wrong-coloured piece moved, piece
 * placed somewhere it cannot reach, ...) -- the board position is left
 * as reported by the hardware either way, so callers can inspect it
 * with dgt_square() to recover. */
int dgt_next_move(dgt_board_t *board, char uci[6]);

/* Piece currently on a square, using python-chess-style FEN letters
 * (P N B R Q K = white, lowercase = black, '.' = empty). sq follows
 * algebraic order 0=a1 .. 63=h8. */
char dgt_square(dgt_board_t *board, int sq);

/* True if it is White to move. */
int dgt_white_to_move(dgt_board_t *board);

/* Longest possible dgt_scan_fen() output, including the terminating NUL. */
#define DGT_FEN_MAX 90

/* Re-scans the whole board over the wire (not just the tracked position)
 * and writes it out as a FEN string into fen, which must be at least
 * DGT_FEN_MAX bytes. Active colour, castling rights and the en-passant
 * square reflect moves seen since dgt_open(); halfmove/fullmove counters
 * are not tracked by this library and are always written as "0 1".
 * Returns 0 on success, -1 on I/O error (board disconnected). */
int dgt_scan_fen(dgt_board_t *board, char fen[DGT_FEN_MAX]);

const char *dgt_last_error(dgt_board_t *board);

#ifdef __cplusplus
}
#endif

#endif
