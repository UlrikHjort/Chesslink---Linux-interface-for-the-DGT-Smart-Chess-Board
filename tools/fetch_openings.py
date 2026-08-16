#!/usr/bin/env python3
# ***************************************************************************
#                 DGT Smart Board - Opening Book Fetcher/Converter
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

"""Download and convert the lichess opening book to chesslink's format.

Source: https://github.com/lichess-org/chess-openings  (CC0 licence)
Input TSV columns: eco  name  pgn
Output format (one line per entry): uci_moves|ECO|Name

Requires python-chess:
    pip install chess

Usage:
    python3 tools/fetch_openings.py [output_path]

Output defaults to data/openings.dat.
Add this line to ~/.chesslinkrc to use it:
    openings=/path/to/data/openings.dat
"""

import sys
import os
import io
import urllib.request

try:
    import chess
    import chess.pgn
except ImportError:
    print("python-chess is required:  pip install chess")
    sys.exit(1)

OUTPUT  = sys.argv[1] if len(sys.argv) > 1 else "data/openings.dat"
BASE    = "https://raw.githubusercontent.com/lichess-org/chess-openings/master"
LETTERS = list("abcde")


def pgn_to_uci(pgn_str: str) -> str:
    """Convert a PGN move string (e.g. '1. e4 e5 2. Nf3') to UCI moves."""
    try:
        game = chess.pgn.read_game(io.StringIO(pgn_str))
        board = game.board()
        uci = []
        for move in game.mainline_moves():
            uci.append(move.uci())
        return " ".join(uci)
    except Exception:
        return ""


def fetch(letter: str) -> list[tuple[str, str, str]]:
    """Return list of (uci_moves, eco, name) for one TSV file."""
    url = f"{BASE}/{letter}.tsv"
    print(f"  {url} ...", end=" ", flush=True)
    with urllib.request.urlopen(url, timeout=15) as r:
        text = r.read().decode("utf-8")
    rows = []
    for line in text.splitlines()[1:]:      # skip header row
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        eco, name, pgn = parts[0].strip(), parts[1].strip(), parts[2].strip()
        if not pgn:
            continue
        uci = pgn_to_uci(pgn)
        if uci:
            rows.append((uci, eco, name))
    print(f"{len(rows)} entries")
    return rows


def main() -> None:
    out_dir = os.path.dirname(OUTPUT)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    all_entries: list[tuple[str, str, str]] = []
    for letter in LETTERS:
        all_entries.extend(fetch(letter))

    with open(OUTPUT, "w", encoding="utf-8") as f:
        f.write("# Chesslink opening book\n")
        f.write("# Source: lichess-org/chess-openings (CC0 licence)\n")
        f.write("# Format: uci_moves|ECO|Name\n")
        for uci, eco, name in all_entries:
            f.write(f"{uci}|{eco}|{name}\n")

    print(f"\nWrote {len(all_entries)} entries to {OUTPUT}")
    print(f"Add this line to ~/.chesslinkrc:\n  openings={os.path.abspath(OUTPUT)}")


if __name__ == "__main__":
    main()
