#!/usr/bin/env python3
# ***************************************************************************
#                      DGT Smart Board - Big Display (Tk helper)
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

"""Big-text display window for DGT Smart Board.

Reads /tmp/dgt_status.txt (written by the main Ada program) and shows
the last move, eval, and PV in large text suitable for reading from a
distance. Launch manually or via the '!display' command in the board app.

Usage: python3 dgt_display.py [/path/to/status/file]
"""

import tkinter as tk
import os
import sys

STATUS_FILE = "/tmp/dgt_status.txt"
POLL_MS     = 400

# Catppuccin-inspired dark palette
BG          = "#1e1e2e"
FG_MOVE     = "#cdd6f4"
FG_GOOD     = "#a6e3a1"   # positive eval (White better)
FG_BAD      = "#f38ba8"   # negative eval (Black better)
FG_EVEN     = "#f9e2af"   # near-zero eval
FG_DIM      = "#6c7086"
FG_PV       = "#89b4fa"
FG_STATUS   = "#fab387"
FG_OPENING  = "#cba6f7"

BAR_WHITE   = "#dce0e8"   # light side of eval bar
BAR_BLACK   = "#11111b"   # dark side of eval bar
BAR_DIVIDER = "#45475a"   # centre reference line

FONT_MONO   = "DejaVu Sans Mono"
FONT_SANS   = "DejaVu Sans"


def eval_color(score_cp: int) -> str:
    if abs(score_cp) < 25:
        return FG_EVEN
    return FG_GOOD if score_cp > 0 else FG_BAD


class EvalBar(tk.Canvas):
    """Horizontal eval bar: white side grows from centre leftward, black rightward."""

    BAR_H = 52

    def __init__(self, parent: tk.Widget, **kwargs) -> None:
        super().__init__(parent, height=self.BAR_H, bg=BG,
                         highlightthickness=0, **kwargs)
        self._score_cp = 0
        self._is_mate  = False
        self._mate_in  = 0
        self.bind("<Configure>", lambda _e: self._draw())

    def update(self, score_cp: int, is_mate: bool = False, mate_in: int = 0) -> None:
        self._score_cp = score_cp
        self._is_mate  = is_mate
        self._mate_in  = mate_in
        self._draw()

    def _ratio(self) -> float:
        """Return White's share [0, 1]; 0.5 = equal."""
        if self._is_mate:
            return 1.0 if self._mate_in > 0 else 0.0
        clamped = max(-500, min(500, self._score_cp))
        return (clamped + 500) / 1000.0

    def _score_text(self) -> str:
        if self._is_mate:
            n = self._mate_in
            if n > 0:
                return f"Mate in {n}"
            elif n < 0:
                return f"Mated in {-n}"
            return "Mate"
        cp   = self._score_cp
        sign = "+" if cp >= 0 else ""
        return f"{sign}{cp / 100:.2f}"

    def _draw(self) -> None:
        self.delete("all")
        w = self.winfo_width()
        h = self.winfo_height()
        if w < 4 or h < 4:
            return

        ratio = self._ratio()
        split = max(2, min(w - 2, int(w * ratio)))

        # White advantage - left of split
        self.create_rectangle(0, 0, split, h, fill=BAR_WHITE, outline="")
        # Black advantage - right of split
        self.create_rectangle(split, 0, w, h, fill=BAR_BLACK, outline="")

        # Centre reference tick
        mid = w // 2
        self.create_line(mid, 0, mid, h, fill=BAR_DIVIDER, width=2)

        # Score label - placed on whichever half is wider, for contrast
        text  = self._score_text()
        pad   = 12
        if ratio >= 0.5:
            tx    = max(pad, split - pad * 4)
            tfill = "#111111"
        else:
            tx    = min(w - pad, split + pad * 4)
            tfill = "#eeeeee"
        self.create_text(tx, h // 2, text=text,
                         font=(FONT_MONO, 18, "bold"), fill=tfill, anchor="center")


class DisplayApp:
    def __init__(self, root: tk.Tk, status_path: str) -> None:
        self._path       = status_path
        self._last_mtime: float | None = None
        self._root       = root

        root.title("DGT Board Display")
        root.configure(bg=BG)
        root.geometry("860x560")
        root.resizable(True, True)
        root.bind("<Configure>", self._on_resize)

        # Last move - very large
        self.lbl_move = tk.Label(
            root, text="—",
            font=(FONT_SANS, 108, "bold"),
            bg=BG, fg=FG_MOVE, anchor="center")
        self.lbl_move.pack(fill="x", pady=(18, 0))

        # Move number + whose turn
        self.lbl_turn = tk.Label(
            root, text="",
            font=(FONT_SANS, 22),
            bg=BG, fg=FG_DIM, anchor="center")
        self.lbl_turn.pack(fill="x")

        # Best move + PV
        self.lbl_eval = tk.Label(
            root, text="",
            font=(FONT_MONO, 26, "bold"),
            bg=BG, fg=FG_GOOD, anchor="center")
        self.lbl_eval.pack(fill="x", pady=(10, 0))

        self.lbl_pv = tk.Label(
            root, text="",
            font=(FONT_MONO, 18),
            bg=BG, fg=FG_PV, anchor="center",
            wraplength=820, justify="center")
        self.lbl_pv.pack(fill="x", pady=(3, 0))

        # Status / opening - push to fill remaining vertical space
        self.lbl_status = tk.Label(
            root, text="Waiting for board...",
            font=(FONT_SANS, 17),
            bg=BG, fg=FG_STATUS, anchor="center")
        self.lbl_status.pack(fill="x", pady=(5, 0))

        self.lbl_opening = tk.Label(
            root, text="",
            font=(FONT_SANS, 15, "italic"),
            bg=BG, fg=FG_OPENING, anchor="center")
        self.lbl_opening.pack(fill="x", pady=(2, 0))

        # Eval bar anchored to the bottom
        self.eval_bar = EvalBar(root)
        self.eval_bar.pack(fill="x", side="bottom", padx=0, pady=0)

        self._poll()

    def _on_resize(self, event: tk.Event) -> None:
        if event.widget is self._root:
            self.lbl_pv.config(wraplength=event.width - 40)

    def _poll(self) -> None:
        try:
            mtime = os.path.getmtime(self._path)
            if mtime != self._last_mtime:
                self._last_mtime = mtime
                self._reload()
        except OSError:
            pass
        self.lbl_move.after(POLL_MS, self._poll)

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

        move     = data.get("move", "")
        move_num = data.get("move_num", "")
        turn     = data.get("turn", "")
        score_cp = data.get("score_cp", "")
        is_mate  = data.get("is_mate", "0") == "1"
        mate_in  = data.get("mate_in", "0")
        best     = data.get("best", "")
        pv       = data.get("pv", "")
        status   = data.get("status", "")
        opening  = data.get("opening", "")

        # Move
        self.lbl_move.config(text=move if move else "—")

        # Turn line
        parts = []
        if move_num:
            parts.append(f"Move {move_num}")
        if turn:
            parts.append(f"{turn} to move")
        self.lbl_turn.config(text="  •  ".join(parts))

        # Eval bar + numeric label
        cp_int = 0
        try:
            cp_int = int(score_cp) if score_cp else 0
        except ValueError:
            pass
        try:
            mate_n = int(mate_in)
        except ValueError:
            mate_n = 0
        self.eval_bar.update(cp_int, is_mate, mate_n)

        # Best move line
        fg = eval_color(cp_int) if not is_mate else (FG_GOOD if mate_n > 0 else FG_BAD)
        eval_text = f"Best: {best}" if best else ""
        self.lbl_eval.config(text=eval_text, fg=fg)

        # PV
        self.lbl_pv.config(text=f"PV: {pv}" if pv else "")

        # Status / opening
        self.lbl_status.config(text=status)
        self.lbl_opening.config(text=opening)


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else STATUS_FILE
    root = tk.Tk()
    DisplayApp(root, path)
    root.mainloop()


if __name__ == "__main__":
    main()
