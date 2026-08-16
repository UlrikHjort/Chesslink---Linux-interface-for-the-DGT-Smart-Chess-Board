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
 * One-shot CLI: connect, scan the whole board over the wire, print it as
 * a FEN string, exit.
 *
 *   ./dgt_scan [/dev/ttyACM0]
 */

#include "dgtboard.h"

#include <stdio.h>

int main(int argc, char **argv) {
    const char *device = argc > 1 ? argv[1] : "/dev/ttyACM0";

    dgt_board_t *board = dgt_open(device);
    if (!board) {
        fprintf(stderr, "dgt_open(%s) failed\n", device);
        return 1;
    }

    char fen[DGT_FEN_MAX];
    int rc = dgt_scan_fen(board, fen);
    if (rc != 0) {
        fprintf(stderr, "scan failed: %s\n", dgt_last_error(board));
        dgt_close(board);
        return 1;
    }
    printf("%s\n", fen);

    dgt_close(board);
    return 0;
}
