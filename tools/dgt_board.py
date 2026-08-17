#!/usr/bin/env python3
# ***************************************************************************
#                  DGT Smart Board - Graphical Board Display
#
#           Copyright (C) 2026 By Ulrik Hørlyk Hjort
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
# ***************************************************************************

"""Graphical chess board display for DGT Smart Board.

Reads /tmp/dgt_status.txt (written by the main Ada program after every move)
and renders the current position as a coloured board using the Lichess
"cburnett" piece set (assets/pieces/cburnett/, GPLv2+ -- see the LICENSE.md
next to those SVGs). Also shows the last move, eval score, and opening name
below the board.

Requires the 'cairosvg' and 'Pillow' packages (pip install cairosvg pillow)
to rasterise the piece SVGs.

Launch via '!boarddisplay' in the board app, or directly:
    python3 tools/dgt_board.py [/path/to/status/file]
"""

import io
import os
import sys
import tkinter as tk

import cairosvg
from PIL import Image, ImageTk

STATUS_FILE = "/tmp/dgt_status.txt"
POLL_MS     = 400
PIECE_DIR   = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "assets", "pieces", "cburnett")

# Colour palette
BG          = "#1e1e2e"
LIGHT_SQ    = "#f0d9b5"   # cream
DARK_SQ     = "#b58863"   # brown
LAST_LIGHT  = "#cdd26a"   # highlight on light square
LAST_DARK   = "#aaa23a"   # highlight on dark square
COORD_FG    = "#6c7086"
LABEL_FG    = "#cdd6f4"
OPENING_FG  = "#cba6f7"
EVAL_POS    = "#a6e3a1"
EVAL_NEG    = "#f38ba8"
EVAL_EVEN   = "#f9e2af"
ARROW_CLR   = "#89dceb"   # cyan - visible on both light and dark squares
FONT_MONO   = "DejaVu Sans Mono"
FONT_SANS   = "DejaVu Sans"

# FEN piece letter -> cburnett SVG filename (w/b + King/Queen/Rook/Bishop/Knight/Pawn)
PIECE_FILE: dict[str, str] = {
    "K": "wK", "Q": "wQ", "R": "wR", "B": "wB", "N": "wN", "P": "wP",
    "k": "bK", "q": "bQ", "r": "bR", "b": "bB", "n": "bN", "p": "bP",
}


def _load_piece_svgs() -> dict[str, bytes]:
    """Read each cburnett SVG once; rasterisation happens later, per size."""
    svgs = {}
    for letter, name in PIECE_FILE.items():
        with open(os.path.join(PIECE_DIR, f"{name}.svg"), "rb") as f:
            svgs[letter] = f.read()
    return svgs


PIECE_SVG = _load_piece_svgs()


def parse_fen_board(fen: str) -> list[list[str]]:
    """Return an 8×8 grid [rank0..rank7][file0..file7] from a FEN string.

    rank0 = rank 8 (top of FEN), rank7 = rank 1 (bottom of FEN).
    """
    board = [[""] * 8 for _ in range(8)]
    ranks = fen.split("/")
    for r, rank_str in enumerate(ranks):
        f = 0
        for ch in rank_str:
            if ch.isdigit():
                f += int(ch)
            else:
                board[r][f] = ch
                f += 1
    return board


def uci_to_squares(uci: str) -> tuple[tuple[int, int], tuple[int, int]] | None:
    """Convert a UCI move string to (from_rank, from_file), (to_rank, to_file)
    in board-grid coordinates (rank 0 = rank 8)."""
    if not uci or len(uci) < 4:
        return None
    try:
        ff = ord(uci[0]) - ord("a")
        fr = 8 - int(uci[1])
        tf = ord(uci[2]) - ord("a")
        tr = 8 - int(uci[3])
        return (fr, ff), (tr, tf)
    except (ValueError, IndexError):
        return None


def eval_color(score_cp: int) -> str:
    if abs(score_cp) < 25:
        return EVAL_EVEN
    return EVAL_POS if score_cp > 0 else EVAL_NEG


class BoardApp:
    MIN_SQ  = 48
    PAD     = 6     # border around board

    def __init__(self, root: tk.Tk, status_path: str) -> None:
        self._path       = status_path
        self._last_mtime: float | None = None
        self._root       = root
        self._flipped    = False
        self._board      = parse_fen_board("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR")
        self._last_move: tuple[tuple[int, int], tuple[int, int]] | None = None
        self._best_move: tuple[tuple[int, int], tuple[int, int]] | None = None
        self._show_arrow  = tk.BooleanVar(value=True)
        self._show_coords = tk.BooleanVar(value=True)
        self._sq_size    = self.MIN_SQ
        self._piece_images: dict[tuple[str, int], ImageTk.PhotoImage] = {}

        root.title("DGT Board")
        root.configure(bg=BG)
        root.geometry("520x620")
        root.resizable(True, True)

        # Canvas fills the top portion
        self._canvas = tk.Canvas(root, bg=BG, highlightthickness=0)
        self._canvas.pack(fill="both", expand=True)
        self._canvas.bind("<Configure>", self._on_resize)

        # Info strip below the board
        info_frame = tk.Frame(root, bg=BG)
        info_frame.pack(fill="x", padx=8, pady=(2, 6))

        self._lbl_move = tk.Label(
            info_frame, text="", font=(FONT_MONO, 15, "bold"),
            bg=BG, fg=LABEL_FG, anchor="w")
        self._lbl_move.pack(side="left")

        self._lbl_eval = tk.Label(
            info_frame, text="", font=(FONT_MONO, 15),
            bg=BG, fg=EVAL_EVEN, anchor="e")
        self._lbl_eval.pack(side="right")

        self._lbl_opening = tk.Label(
            root, text="", font=(FONT_SANS, 12, "italic"),
            bg=BG, fg=OPENING_FG, anchor="center")
        self._lbl_opening.pack(fill="x", padx=8, pady=(0, 6))

        # Button row
        btn_frame = tk.Frame(root, bg=BG)
        btn_frame.pack(pady=(0, 8))

        tk.Button(
            btn_frame, text="Flip board", font=(FONT_SANS, 11),
            bg="#313244", fg=LABEL_FG, activebackground="#45475a",
            relief="flat", bd=0, padx=10, pady=4,
            command=self._flip).pack(side="left", padx=6)

        tk.Checkbutton(
            btn_frame, text="Best move arrow", font=(FONT_SANS, 11),
            variable=self._show_arrow, command=self._draw,
            bg=BG, fg=LABEL_FG, selectcolor="#313244",
            activebackground=BG, activeforeground=LABEL_FG,
            relief="flat", bd=0).pack(side="left", padx=6)

        tk.Checkbutton(
            btn_frame, text="Coordinates", font=(FONT_SANS, 11),
            variable=self._show_coords, command=self._draw,
            bg=BG, fg=LABEL_FG, selectcolor="#313244",
            activebackground=BG, activeforeground=LABEL_FG,
            relief="flat", bd=0).pack(side="left", padx=6)

        self._poll()

    # ------------------------------------------------------------------
    def _flip(self) -> None:
        self._flipped = not self._flipped
        self._draw()

    def _on_resize(self, _event: tk.Event) -> None:
        self._draw()

    # ------------------------------------------------------------------
    def _sq_size_from_canvas(self) -> int:
        w = self._canvas.winfo_width()
        h = self._canvas.winfo_height()
        available = min(w, h) - 2 * self.PAD
        return max(self.MIN_SQ, available // 8)

    def _board_offset(self, sq: int) -> tuple[int, int]:
        """Canvas pixel origin (x, y) of the board's top-left corner."""
        w = self._canvas.winfo_width()
        h = self._canvas.winfo_height()
        board_px = sq * 8
        x0 = (w - board_px) // 2
        y0 = (h - board_px) // 2
        return x0, y0

    def _piece_image(self, letter: str, px: int) -> ImageTk.PhotoImage:
        """Rasterise (and cache) a cburnett piece SVG at `px` pixels square."""
        key = (letter, px)
        img = self._piece_images.get(key)
        if img is None:
            png_bytes = cairosvg.svg2png(
                bytestring=PIECE_SVG[letter], output_width=px, output_height=px)
            img = ImageTk.PhotoImage(Image.open(io.BytesIO(png_bytes)))
            self._piece_images[key] = img
        return img

    def _draw_arrow(
        self,
        move: tuple[tuple[int, int], tuple[int, int]],
        sq: int,
        x0: int,
        y0: int,
    ) -> None:
        (fr, ff), (tr, tf) = move

        # Map board coordinates through flip
        if self._flipped:
            vfr, vff = 7 - fr, 7 - ff
            vtr, vtf = 7 - tr, 7 - tf
        else:
            vfr, vff = fr, ff
            vtr, vtf = tr, tf

        cx1 = x0 + vff * sq + sq // 2
        cy1 = y0 + vfr * sq + sq // 2
        cx2 = x0 + vtf * sq + sq // 2
        cy2 = y0 + vtr * sq + sq // 2

        w      = max(3, sq // 9)
        ahead  = max(sq // 4, 10)
        awidth = max(sq // 6, 7)

        # Dark outline for contrast
        self._canvas.create_line(
            cx1, cy1, cx2, cy2,
            fill="#1e1e2e", width=w + 4,
            arrow=tk.LAST, arrowshape=(ahead + 4, ahead + 4, awidth + 3),
            capstyle=tk.ROUND)
        # Coloured arrow on top
        self._canvas.create_line(
            cx1, cy1, cx2, cy2,
            fill=ARROW_CLR, width=w,
            arrow=tk.LAST, arrowshape=(ahead, ahead, awidth),
            capstyle=tk.ROUND)

    # ------------------------------------------------------------------
    def _draw(self) -> None:
        c      = self._canvas
        c.delete("all")
        sq     = self._sq_size_from_canvas()
        x0, y0 = self._board_offset(sq)

        if sq != self._sq_size:
            self._sq_size = sq
            self._piece_images.clear()  # drop the previous size's rasters

        last_sqs: set[tuple[int, int]] = set()
        if self._last_move:
            last_sqs = {self._last_move[0], self._last_move[1]}

        for rank in range(8):
            for file in range(8):
                # Flip maps: visually top-left is rank8/a1 (normal) or rank1/h8 (flipped)
                board_rank = (7 - rank) if self._flipped else rank
                board_file = (7 - file) if self._flipped else file

                light = (rank + file) % 2 == 0
                highlighted = (board_rank, board_file) in last_sqs

                if highlighted:
                    fill = LAST_LIGHT if light else LAST_DARK
                else:
                    fill = LIGHT_SQ if light else DARK_SQ

                px = x0 + file * sq
                py = y0 + rank * sq
                c.create_rectangle(px, py, px + sq, py + sq,
                                   fill=fill, outline="")

                piece = self._board[board_rank][board_file]
                if piece:
                    img = self._piece_image(piece, sq)
                    c.create_image(px + sq // 2, py + sq // 2,
                                    image=img, anchor="center")

        # Rank numbers and file letters drawn inside the border squares
        # so they are never clipped by the canvas edge.
        if self._show_coords.get():
            coord_font = (FONT_MONO, max(7, sq // 6))
            for rank in range(8):
                label_rank = (rank + 1) if self._flipped else (8 - rank)
                # top-left corner of each left-edge square
                light = (rank + 0) % 2 == 0
                fg = DARK_SQ if light else LIGHT_SQ
                c.create_text(x0 + 2, y0 + rank * sq + 2,
                              text=str(label_rank),
                              font=coord_font, fill=fg, anchor="nw")
            for file in range(8):
                label_file = chr(ord("h") - file) if self._flipped else chr(ord("a") + file)
                # bottom-right corner of each bottom-edge square
                light = (7 + file) % 2 == 0
                fg = DARK_SQ if light else LIGHT_SQ
                c.create_text(x0 + file * sq + sq - 2, y0 + 8 * sq - 2,
                              text=label_file,
                              font=coord_font, fill=fg, anchor="se")

        # Best-move arrow (drawn last so it sits on top of everything)
        if self._show_arrow.get() and self._best_move:
            self._draw_arrow(self._best_move, sq, x0, y0)

    # ------------------------------------------------------------------
    def _poll(self) -> None:
        try:
            mtime = os.path.getmtime(self._path)
            if mtime != self._last_mtime:
                self._last_mtime = mtime
                self._reload()
        except OSError:
            pass
        self._canvas.after(POLL_MS, self._poll)

    def _reload(self) -> None:
        data: dict[str, str] = {}
        try:
            with open(self._path, encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if "=" in line:
                        k, _, v = line.partition("=")
                        data[k.strip()] = v.strip()
        except OSError:
            return

        fen     = data.get("fen", "")
        move    = data.get("move", "")
        best    = data.get("best", "")
        flipped = data.get("flipped", "0") == "1"

        if fen:
            board_part = fen.split()[0]
            self._board = parse_fen_board(board_part)

        self._last_move = uci_to_squares(move)
        self._best_move = uci_to_squares(best)
        self._flipped   = flipped

        # Eval label
        try:
            cp      = int(data.get("score_cp", "0"))
            is_mate = data.get("is_mate", "0") == "1"
            mate_n  = int(data.get("mate_in", "0"))
            if is_mate:
                eval_txt = f"Mate in {mate_n}" if mate_n > 0 else f"Mated in {-mate_n}"
                eval_fg  = EVAL_POS if mate_n > 0 else EVAL_NEG
            else:
                sign     = "+" if cp >= 0 else ""
                eval_txt = f"{sign}{cp / 100:.2f}"
                eval_fg  = eval_color(cp)
        except ValueError:
            eval_txt = ""
            eval_fg  = EVAL_EVEN

        # Move label: "e2e4" -> "e2-e4" for readability
        if move and len(move) >= 4:
            move_txt = move[:2] + "–" + move[2:4]
        else:
            move_txt = ""

        move_num = data.get("move_num", "")
        turn     = data.get("turn", "")
        if move_num and turn:
            move_txt = f"{move_num}. {move_txt}  ({turn} to move)"

        self._lbl_move.config(text=move_txt)
        self._lbl_eval.config(text=eval_txt, fg=eval_fg)
        self._lbl_opening.config(text=data.get("opening", ""))

        self._draw()


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else STATUS_FILE
    root = tk.Tk()
    BoardApp(root, path)
    root.mainloop()


if __name__ == "__main__":
    main()
