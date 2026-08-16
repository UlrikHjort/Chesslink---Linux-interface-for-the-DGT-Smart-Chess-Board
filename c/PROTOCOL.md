# DGT board wire protocol

This describes the subset of the DGT Smart Board serial protocol that
`dgtboard.c` speaks. It's not a full reference for the whole DGT
protocol family (clocks, other message types, etc.) -- just what's needed
to read board state and moves over USB serial.

## Transport

- USB serial (shows up as `/dev/ttyACM0` or similar on Linux).
- 9600 baud, 8 data bits, no parity, 1 stop bit, no flow control.
- The device is opened in raw mode (`cfmakeraw`), not canonical/line mode.

## Message framing

Every message, in both directions, starts with a 3-byte header:

```
byte 0: message ID
byte 1: length high byte
byte 2: length low byte
```

`length` is the *total* message length in bytes, including the 3 header
bytes. So a message with N bytes of payload has `length = N + 3`, and the
payload is read as `length - 3` bytes after the header.

Commands sent *to* the board are a single byte (no length, no payload) --
see below.

## Commands (host -> board)

| byte | name             | effect                                              |
|------|------------------|------------------------------------------------------|
| 0x40 | `CMD_RESET`      | reset the board (not used by this library)            |
| 0x42 | `CMD_SEND_BRD`   | request one `MSG_BOARD_DUMP` reply                     |
| 0x43 | `CMD_SEND_UPDATE`| start streaming `MSG_FIELD_UPDATE` messages as squares change |

`dgt_open()` sends `CMD_SEND_BRD` once to get the initial position, then
`CMD_SEND_UPDATE` to switch the board into streaming mode for the rest of
the session. `dgt_scan_fen()` sends `CMD_SEND_BRD` again for an on-demand
re-read, tolerating any `MSG_FIELD_UPDATE` messages that arrive interleaved
with the reply (the board doesn't stop streaming just because you asked
for a one-off dump).

## Messages (board -> host)

### `MSG_BOARD_DUMP` (0x86)

Full board snapshot. Payload is exactly 64 bytes, one per square, in
row-major order starting from the board's own top-left corner:

```
square 0  = a8
square 1  = b8
...
square 7  = h8
square 8  = a7
...
square 63 = h1
```

i.e. rank 8 first (a8..h8), then rank 7, down to rank 1 (a1..h1) last.
This happens to be exactly the order FEN's piece-placement field wants,
so `render_fen()` walks `pos[]` in a straight line with no reindexing.

Each byte is a piece code (see below).

### `MSG_FIELD_UPDATE` (0x8E)

Sent once per physical change, after `CMD_SEND_UPDATE` has been issued.
Payload is 2 bytes:

```
byte 0: square index (0-63, same 0=a8..63=h1 order as the board dump)
byte 1: piece code now on that square (0x00 if the square was just lifted/emptied)
```

A single physical move produces two of these: a lift (piece code 0x00) and
a placement (nonzero piece code) on a different square. Captures, castling
and en passant produce longer sequences -- see "Move detection" below.

## Piece codes

```
0x00  empty
0x01  white pawn      0x07  black pawn
0x02  white rook      0x08  black rook
0x03  white knight    0x09  black knight
0x04  white bishop    0x0A  black bishop
0x05  white king      0x0B  black king
0x06  white queen     0x0C  black queen
```

White and black pieces are always 6 apart, which is what
`is_white_piece()` (`p >= P_WPAWN && p <= P_WQUEEN`, i.e. 0x01-0x06) and
the black-letter lookup (`p - P_BPAWN + 1`) key off.

## Square indexing

Internally (`dgtboard.c`) squares are the board's own layout: 0=a8, 63=h1,
row-major. Helpers:

```c
file_of(sq) = sq % 8        /* 0=a .. 7=h */
row_of(sq)  = sq / 8         /* 0=rank8 .. 7=rank1 */
sq_at(row, file) = row * 8 + file
```

The public API (`dgt_square()`) uses ordinary algebraic order instead
(0=a1..63=h8) so callers don't need to know about the board's internal
layout; the conversion is a single `7 - rank` flip done at the API
boundary.

## Move detection (built on top of the raw messages)

The board only ever reports "square X went empty" or "square X now has
piece Y" -- it has no concept of a move, a capture, or castling. Those are
inferred in `dgtboard.c` by watching the *sequence* of lift/place events:

- **Quiet move**: lift `from` (piece code 0), place `to` (nonzero) with
  matching movement geometry -> `fromto`.
- **Capture**: the capturing piece is lifted first; then, before it's put
  down, the captured piece is lifted too (its square briefly reads empty)
  and the capturer is placed on the captured piece's square. The captured
  piece is *not* physically removed from the board by the player until
  after the capturing piece has landed -- so the captured piece's lift is
  recognised as "second lift while already holding something of the
  opposite colour" and the square is left alone internally until the
  placement confirms it as a capture. The reverse order (lifting the
  victim first, then the capturer) is not handled.
- **Castling**: king moves two squares on its home rank -> king's move is
  treated as the pending move, and the state machine waits for the rook to
  be lifted from its home square and placed next to the king before
  reporting the whole thing as the king's UCI move (e.g. `e1g1`).
- **En passant**: a pawn moves diagonally onto an empty square that
  matches the currently tracked en-passant target square. The move is
  committed immediately as the pawn move; the captured pawn is expected to
  be lifted off its own square afterward as a separate cleanup event.
- **Promotion**: the piece code placed on the back rank *is* the promoted
  piece (the board reports what's physically standing there), so there's
  no ambiguity -- no separate "choose a piece" step.

Only movement geometry is checked (can this piece reach that square, is
the path clear, is it that colour's turn) -- see the "Scope" section in
`README.md` for what's deliberately left out (check, pins, checkmate).

## What isn't tracked

- Halfmove clock and fullmove number: not tracked, always written as
  `0 1` in `dgt_scan_fen()` output.
- Whose turn it is, castling rights, and the en-passant target square are
  only as good as what's been observed *since* `dgt_open()` was called --
  a fresh connection always assumes the standard starting position with
  White to move, since the board has no way to report whose turn it
  actually is. Reconnecting mid-game will misreport these three FEN
  fields until enough moves have been played in the new session to
  re-derive them; piece placement itself is always read fresh off the
  wire and is unaffected.
