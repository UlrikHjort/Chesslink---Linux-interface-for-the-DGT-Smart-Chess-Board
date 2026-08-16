# dgtboard - minimal DGT Smart Board library (C)

A small, dependency-free C library for Linux that talks to a [DGT Smart Chess Board](https://www.digitalgametechnology.com/products/home-use-e-boards/smart-board-with-indices) over its USB serial port and turns physical piece movements
into UCI move strings ("e2e4", "e7e8q", "e1g1" for castling, ...).


## Scope

- Only piece-movement geometry is validated (can this piece physically
  reach that square, is the path blocked, is en passant/castling
  structurally sane). **Check, pins and checkmate are not validated** --
  this is a board-to-UCI translator, not a chess legality engine. Feed
  the result through a real move validator (or a UCI engine) if you
  need that guarantee.
- No PGN, clocks, undo, or game-outcome tracking -- see the parent
  project if you want that.
- Assumes the board starts in the standard starting position with White
  to move; there's no way to ask the hardware who is to move.

## Layout

```
lib/       dgtboard.h / dgtboard.c -- the library itself, no other deps
examples/  small standalone programs built against lib/
tests/     unit tests for the move-detection state machine (no hardware needed)
```

## Build

```
make          # builds libdgtboard.a and every example into bin/
make test     # runs the move-detection/FEN unit tests (no hardware needed)
```

Built executables land in `bin/` (`bin/dgt_example`, `bin/dgt_scan`,
`bin/dgt_uci_engine`).

## Usage

```c
#include "dgtboard.h"

dgt_board_t *board = dgt_open("/dev/ttyACM0");
char uci[6];
while (dgt_next_move(board, uci) == 0) {
    printf("%s\n", uci);
}
dgt_close(board);
```

See `examples/basic/example.c` for a complete runnable version, and
`lib/dgtboard.h` for the full API (five functions plus an error
accessor). See [`PROTOCOL.md`](PROTOCOL.md) for the wire protocol and
move-detection logic this library implements.

### Scanning the whole board as a FEN

`dgt_scan_fen()` re-reads every square over the wire (rather than relying
on the tracked position) and renders it as a FEN string. Handy for an
initial sync, or to recover if a move was ever missed:

```c
char fen[DGT_FEN_MAX];
if (dgt_scan_fen(board, fen) == 0) puts(fen);
```

Halfmove/fullmove counters aren't tracked by this minimal library and
are always written as `0 1`. Also built as a standalone command:

```
./bin/dgt_scan [/dev/ttyACM0]
```

### Getting suggestions from a UCI engine

`examples/uci_engine/dgt_uci_engine` feeds every board move to any UCI
engine (Stockfish, for example) and prints its top suggestion for the
resulting position. Point it at your engine binary:

```
./bin/dgt_uci_engine /dev/ttyACM0 /path/to/stockfish [movetime_ms]
```

Any engine that speaks plain UCI over stdin/stdout works, not just
Stockfish. Like the library itself, it assumes the game starts from the
standard position when it connects -- have the board connected before
move 1.

## Finding the board's serial device

`/dev/ttyACM0` is the common default, but it's not guaranteed -- it
depends on connection order and what else is plugged in. Confirm it
rather than assuming it:

```
ls /dev/ttyACM*                  # candidates
dmesg | tail -20                 # shows which one appeared when you plugged the board in
```

`dmesg` also logs the USB product name right next to the `ttyACM`
assignment, which is the easiest way to confirm you've got the right
device and not some other USB-serial gadget:

```
dmesg | grep -iE "tty|dgt|hitachi"
```

Look for "DGT" in the product string -- the manufacturer may show up as
"Hitachi, Ltd" (that's the board's USB-serial chip, not a different
device), immediately followed by a line assigning it a `ttyACMn` name.

You may also need to be in the `dialout` group to access the serial port:

```
sudo usermod -aG dialout $USER
```
