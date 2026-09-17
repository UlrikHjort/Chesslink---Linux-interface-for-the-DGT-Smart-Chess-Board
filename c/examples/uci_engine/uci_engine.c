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
 * Connects a DGT board to any UCI chess engine (Stockfish, for example):
 * every move played on the board is fed to the engine, which replies with
 * its top suggestion for the resulting position.
 *
 * Like dgtboard.h itself, this assumes the game starts from the standard
 * position when the board connects -- play from move 1 with the board
 * already connected.
 *
 *   ./dgt_uci_engine <board-device> <path-to-engine> [movetime_ms]
 *
 * e.g. ./dgt_uci_engine /dev/ttyACM0 /usr/bin/stockfish
 */

#define _POSIX_C_SOURCE 200809L /* fdopen() */

#include "dgtboard.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct {
    pid_t pid;
    FILE *in;  /* write to the engine's stdin */
    FILE *out; /* read from the engine's stdout */
} engine_t;

static engine_t engine_start(const char *path) {
    int to_engine[2], from_engine[2];
    if (pipe(to_engine) != 0 || pipe(from_engine) != 0) {
        perror("pipe");
        exit(1);
    }

    pid_t pid = fork();
    if (pid < 0) {
        perror("fork");
        exit(1);
    }

    if (pid == 0) {
        dup2(to_engine[0], STDIN_FILENO);
        dup2(from_engine[1], STDOUT_FILENO);
        close(to_engine[0]);
        close(to_engine[1]);
        close(from_engine[0]);
        close(from_engine[1]);
        execl(path, path, (char *) NULL);
        perror("execl");
        _exit(127);
    }

    close(to_engine[0]);
    close(from_engine[1]);

    engine_t e;
    e.pid = pid;
    e.in = fdopen(to_engine[1], "w");
    e.out = fdopen(from_engine[0], "r");
    if (!e.in || !e.out) {
        perror("fdopen");
        exit(1);
    }
    return e;
}

static void engine_send(engine_t *e, const char *cmd) {
    fprintf(e->in, "%s\n", cmd);
    fflush(e->in);
}

/* Reads engine stdout lines, discarding them, until one starting with
 * `prefix` shows up; returns that line (without its trailing newline). */
static void engine_wait_for(engine_t *e, const char *prefix, char *line, size_t len) {
    while (fgets(line, (int) len, e->out)) {
        size_t n = strlen(line);
        if (n && line[n - 1] == '\n') line[n - 1] = '\0';
        if (strncmp(line, prefix, strlen(prefix)) == 0) return;
    }
    line[0] = '\0';
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <board-device> <path-to-engine> [movetime_ms]\n", argv[0]);
        return 1;
    }
    const char *device = argv[1];
    const char *engine_path = argv[2];
    const char *movetime = argc > 3 ? argv[3] : "1000";

    engine_t engine = engine_start(engine_path);
    char line[4096];
    engine_send(&engine, "uci");
    engine_wait_for(&engine, "uciok", line, sizeof line);
    engine_send(&engine, "isready");
    engine_wait_for(&engine, "readyok", line, sizeof line);
    engine_send(&engine, "ucinewgame");

    dgt_board_t *board = dgt_open(device);
    if (!board) {
        fprintf(stderr, "dgt_open(%s) failed\n", device);
        return 1;
    }
    printf("Connected to %s and %s.\n"
           "Assuming a fresh game from the standard starting position --\n"
           "play a move on the board...\n", device, engine_path);
    fflush(stdout);

    char moves[8192] = "";
    char uci[6];
    for (;;) {
        int rc = dgt_next_move(board, uci);
        if (rc == 1) {
            fprintf(stderr, "ignored: %s\n", dgt_last_error(board));
            continue;
        }
        if (rc != 0) {
            fprintf(stderr, "board disconnected: %s\n", dgt_last_error(board));
            break;
        }

        printf("move: %s\n", uci);
        if (moves[0]) strncat(moves, " ", sizeof(moves) - strlen(moves) - 1);
        strncat(moves, uci, sizeof(moves) - strlen(moves) - 1);

        char cmd[8300];
        snprintf(cmd, sizeof cmd, "position startpos moves %s", moves);
        engine_send(&engine, cmd);

        snprintf(cmd, sizeof cmd, "go movetime %s", movetime);
        engine_send(&engine, cmd);

        engine_wait_for(&engine, "bestmove", line, sizeof line);
        char best[16] = {0};
        sscanf(line, "bestmove %15s", best);
        printf("%s suggests: %s\n\n", engine_path, best);
        fflush(stdout);
    }

    dgt_close(board);
    engine_send(&engine, "quit");
    fclose(engine.in);
    fclose(engine.out);
    waitpid(engine.pid, NULL, 0);
    return 0;
}
