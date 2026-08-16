# Manual Test Procedure -- DGT Smart Board

Work through the sections in order. Each step lists what to do and what to expect.
Check the box mentally (or on paper) when the step passes.

---

## 1. Build

```
make clean && make
```

**Expected:** No errors. `bin/chesslink`, `bin/raw_dump`, `bin/tests`,
`bin/clkb_encode`, `bin/clkb_decode` all present.

```
make test
```

**Expected:** All tests T01-T38 print `PASS`. Exit code 0.

---

## 2. Startup -- engine auto-detection

Make sure Stockfish is installed (`which stockfish` returns a path) and the board
is **not** plugged in yet.

```
./bin/chesslink
```

**Expected output (engine line):**
```
Starting engine... Stockfish <version> ready.
```

Engine name comes from the UCI handshake -- any UCI engine installed as `stockfish`
will show its own name here.

---

## 3. Startup -- missing engine

Temporarily break the engine path:

```
echo "engine=/nonexistent/path" >> ~/.chesslinkrc
./bin/chesslink
```

**Expected:**
```
Starting engine... not found.
  Engine path: /nonexistent/path
  Set 'engine=/path/to/engine' in ~/.chesslinkrc
```

With no engine running, try the engine-dependent commands:

```
!analyse
!eval
!hint
!compare
!review
```

**Expected:** Each prints
```
No engine running -- set 'engine=/path/to/engine' in /home/<user>/.chesslinkrc and restart.
```
instead of silently showing `No analysis available.` / `No hint available.`.

Remove that line from `~/.chesslinkrc` afterwards (or use `!save` after a good run
to overwrite it).

---

## 4. Config file -- comments

Add a comment line to `~/.chesslinkrc`:

```
# This is a comment
time=1500
```

**Expected:** Program starts without error or complaint; the comment line is silently
ignored.

---

## 5. Serial device

### 5a. Default device

Plug in the board on `/dev/ttyACM0` and run:

```
./bin/chesslink
```

**Expected:** Connects, shows board version and initial position.

### 5b. Command-line override

If the board is on `/dev/ttyACM1`:

```
./bin/chesslink /dev/ttyACM1
```

**Expected:** Connects on the specified device.

### 5c. Config file device

```
echo "device=/dev/ttyACM1" >> ~/.chesslinkrc
./bin/chesslink
```

**Expected:** Connects on `/dev/ttyACM1` without the command-line argument.

Clean up the extra line afterwards.

---

## 6. Startup prompt -- colour selection

With board connected, run the program.

**Expected prompts:**
```
White plays from which side? (w=bottom / b=top):
```

Answer `w`. Board displays with white at the bottom.

---

## 7. Basic move tracking

Place the pieces in the starting position. Make the following moves on the board:

1. e2-e4
2. e7-e5
3. g1-f3

**Expected after each move:**
- ASCII board updates correctly
- Move printed in SAN notation: `e4`, `e5`, `Nf3`
- Opening name appears: after move 1 `King's Pawn Game`, after move 3 something
  in the King's Knight family

---

## 8. Engine analysis

After the three moves above, type:

```
!analyse
```

**Expected:** Score line printed (e.g. `+0.20`) with best move and PV.

```
!hint
```

**Expected:** Prints the piece Stockfish wants to move (not the destination square).

```
!eval
```

**Expected:** Same as `!analyse`.

---

## 9. Multi-PV

```
!multipv 3
!analyse
```

**Expected:** Three numbered PV lines printed.

```
!multipv 10
```

**Expected:** `Multi-PV: 5 lines (max)` -- clamped to 5, no crash.

```
!multipv 1
```

Reset.

---

## 10. Time and depth control

```
!time 500
!analyse
```

**Expected:** Analysis finishes faster (~0.5 s).

```
!depth 8
!analyse
```

**Expected:** Analysis stops at depth 8.

```
!time 1500
!depth 0
```

Reset.

---

## 11. Undo

Make one more move on the board (e.g. f8-c5), then type:

```
!undo
```

**Expected:** Board reverts; bishop back on f8; move list shortened by one.

---

## 12. Player names and PGN

```
!white Alice
!black Bob
!pgn
```

**Expected:** PGN header shows `[White "Alice"]` and `[Black "Bob"]`.

---

## 13. Comment

```
!comment Interesting pawn sacrifice
!pgn
```

**Expected:** Last move in PGN includes `{ Interesting pawn sacrifice }`.

---

## 14. Flip

```
!flip
```

**Expected:** ASCII board re-drawn with black at the bottom (ranks reversed,
files reversed).

```
!flip
```

Flip back.

---

## 15. Unicode toggle

```
!unicode
```

**Expected:** Board re-drawn with Unicode piece symbols ((K Q R B N P)).

```
!unicode
```

Toggle back.

---

## 16. FEN position

```
!fen r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4
```

**Expected:** Board set to the Italian Game position (4 moves in).
Engine analyses the new position immediately; graphical board (if open) updates.

---

## 17. New game

```
!newgame
```

**Expected:** Board resets to starting position; move counter resets.

```
!newgameb
```

**Expected:** New game, black to move first.

```
!newgame
```

Reset to white.

---

## 18. Castling

Set up a position where white can castle kingside:

```
!fen r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 0 5
```

On the board, move the king e1-g1.

**Expected:** Program detects castling; SAN shows `O-O`; rook jumps to f1 automatically.

---

## 19. En passant

```
!fen rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3
```

On the board, move the pawn e5-f6 (capturing the f5 pawn).

**Expected:** En passant capture detected; f5 pawn removed from the board display;
SAN shows `exf6`.

---

## 20. Promotion

```
!fen 8/P7/8/8/8/8/8/4K1k1 w - - 0 1
```

On the board, advance the a7 pawn to a8.

**Expected:** Program prompts for promotion piece. Type `q`.

**Expected:** Queen appears on a8; SAN shows `a8=Q`.

---

## 21. Draw conditions

### 21a. Resign

```
!resign
```

**Expected:** Game ends; result printed as `0-1` (or `1-0` if black resigns).

### 21b. Agreed draw

```
!newgame
!draw
```

**Expected:** Game ends with `1/2-1/2`.

---

## 22. Opening book

Start a new game and play 1. e4 e5 2. Nf3 Nc6 3. Bb5.

**Expected:** Opening name `Ruy Lopez` shown automatically.

```
!book
```

**Expected:** Up to 3 book moves printed with win percentage and W/D/B counts
(requires internet and `lichess_token` in `~/.chesslinkrc`).

**Regression check (fixed hang):** set up a deep position with fewer than 3
book moves and run `!book` again:

```
!fen r1bqk2r/2p1bppp/p1np1n2/1p2p3/3PP3/1B3N2/PPP2PPP/RNBQR1K1 b kq - 0 8
!book
```

**Expected:** Prints however many book moves exist (possibly 1-2, or
`Book: position not in database.`) and returns to the prompt. Must **not**
hang -- older versions spun forever when fewer than 3 moves came back.

---

## 23. Time control

```
!tc 5+3
```

**Expected:** Clock starts; each move shows remaining time; 3-second increment
added after each move.

Make a couple of moves, verify clock counts down.

```
!tc off
```

**Expected:** Clock disabled.

---

## 24. Game review

Play a short game (or load one), then:

```
!review
```

**Expected:** Each move classified as Best / Inaccuracy / Mistake / Blunder with
a score delta. Summary printed at the end.

---

## 25. Compare

After any move:

```
!compare
```

**Expected:** Prints your move alongside Stockfish's suggestion and the score
difference.

---

## 26. PGN auto-save

After a game ends, check:

```
ls ~/games/*.pgn
```

**Expected:** A timestamped PGN file exists. Also `~/games/live.pgn` contains the
current game.

---

## 27. Load PGN and navigate

```
!load ~/games/live.pgn
!forward
!forward
!back
```

**Expected:** Board steps through moves; `!forward` / `!back` move one step at a
time.

```
!forward 5
```

**Expected:** Board jumps 5 moves ahead.

---

## 28. Save config

```
!time 1200
!save
cat ~/.chesslinkrc
```

**Expected:** `time=1200` (and all other current settings) present in the file.

---

## 29. Big-text display

```
!display
```

**Expected:** A Tk window opens showing the last move at large size, eval bar,
best move, and PV. Make a move on the board; window updates within 0.5 s.

---

## 30. Graphical board

```
!boarddisplay
```

**Expected:** A graphical chess board window opens showing the current position.

- White pieces are solid white; black pieces are solid dark
- Last move squares highlighted in yellow-green
- Best-move arrow drawn in cyan
- Click **Flip board** -> board orientation mirrors
- Uncheck **Best move arrow** -> arrow disappears
- Check **Coordinates** -> rank numbers and file letters appear inside squares
- Make a move on the physical board -> graphical board updates within 0.5 s

---

## 31. Web display

```
!webdisplay
```

Open `http://localhost:8080/` in a browser.

**Expected:** Page shows current position with move, eval, and PV.
Make a move; page updates within 0.5 s without manual refresh.

Open the same URL on a phone on the same network using the machine's LAN IP.

**Expected:** Page loads and updates on the phone too.

---

## 32. Tablebase

Set up a simple endgame with <= 7 pieces:

```
!fen 8/8/8/8/8/4K3/4Q3/4k3 w - - 0 1
```

Make a move.

**Expected:** Tablebase result printed automatically (DTZ and WDL).

---

## 33. Training -- Lichess

```
!newgame
!train
```

Play 1. e4.

**Expected:** `Training: good move! (...)` with the opening name.

Play a deliberately bad but legal move as black (e.g. 1... a6, then 2. h4).

**Expected:** In-book moves report `good move!`; non-book moves report
`not a main line move.` followed by `Book moves here:` with SAN hints.

**Regression check (out-of-book end):** keep playing junk moves (e.g.
shuffle rook pawns and rooks) until the position leaves the database.

**Expected:** `Training: out of book after N moves.` printed and training
mode ends automatically. Older versions never detected this and reported
`not a main line move` forever.

```
!train off
```

---

## 34. Training -- named opening

Each of the following forms must set up the opening position and enable
training:

```
!train opening Sicilian Defense
!train opening B90
!train opening E93  King's Indian Defense: Petrosian Variation, Keres Defense
```

**Expected:** For each: board diagram of the opening's final position, its
FEN, and `Set up this position on the board, then play on.` Name matching is
case-insensitive; an ECO code alone and a pasted `ECO  Name` line from the
browser both work.

```
!train opening Xyzzy Gambit
```

**Expected:** `Opening not found: Xyzzy Gambit`.

---

## 34b. Opening browser

```
!train opening
```

**Expected:** Paginated list, 20 entries per page, header like
`Openings -- page 1/N  (M entries)` and a prompt line
`> number=select  n=next  p=prev  q=quit  or text=filter`.

- Type `n` -> next page; `p` -> previous page; `p` on page 1 stays put
- Type `sicilian` -> list filtered (header shows `[filter: "sicilian"]`)
- Type `3` -> opening number 3 on the current page is set up for training
  (same output as section 34)
- Re-enter with `!train opening`, type `q` -> `Browse cancelled.`,
  normal commands work again

---

## 35. Opening book compression

```
make compress-book
make decompress-book
diff data/openings.dat data/openings_rt.dat
```

(Adjust filenames to match your Makefile targets.)

**Expected:** Round-trip produces identical file; encoder reports ~44% compression.

---

## 36. Raw dump (diagnostics)

With board connected:

```
./bin/raw_dump
```

Move a piece.

**Expected:** Raw hex bytes printed to stdout for every board event.

---

## 37. Board reconnect

While the program is running, unplug the USB cable and replug it.

**Expected:** Program detects disconnect; reconnects automatically; board continues
working without restart.

---

## 38. Speech announcements

### 38a. espeak-ng fallback

With `tts_model` **not** set in `~/.chesslinkrc` and `espeak-ng` (or
`espeak`) installed:

```
!speech
```

**Expected:** Speech toggled on; diagnostic line names the espeak binary in
use. Make a move -> move announced by voice (e.g. "knight g one to f three").
`!quiet` is an alias for `!speech`.

### 38b. Piper neural TTS

Add to `~/.chesslinkrc` (adjust to your model path):

```
tts_model=~/.local/share/piper/en_US-lessac-medium.onnx
```

`piper` must be on PATH. Restart, then:

```
!speech
```

**Expected:** Diagnostic shows the model path and `piper: <full path>`.
Make a move -> announced in the piper voice, **with no piper/aplay debug
output** in the terminal.

### 38c. Piper missing

Keep `tts_model` set but temporarily rename or remove `piper` from PATH.

**Expected:** `!speech` diagnostic shows `piper: (not found on PATH)`;
moves are silent but the program keeps working normally.

---

## 39. Training -- strict mode

```
!newgame
!train strict
```

**Expected:** `Training mode on (Lichess, strict: classical games by 2500+
players only).`

Play 1. e4 e5 2. Nf3.

**Expected:** Main-line moves still report `good move!`. The book is much
smaller: rare-but-playable sidelines that pass in normal `!train` report
`not a main line move` or run out of book earlier.

```
!train strict off
```

**Expected:** `Strict filter off (training continues against all Lichess
games).`

```
!train off
!train
```

**Expected:** Plain training again (strict does not stick after `!train off`).

Also verify: `!train strict` followed by `!train opening NAME` keeps the
strict filter while training that opening.

---

## 40. Training -- PGN repertoire file

Save a short PGN (e.g. `~/rep.pgn` containing `1. e4 e5 2. Nf3 Nc6`), then:

```
!newgame
!train file ~/rep.pgn
```

**Expected:** `Training: loaded 4 moves from ~/rep.pgn`.

Play 1. e4 on the board -> `Training: correct! (1/4)`.
Play a wrong second move (e.g. 1... d5) -> `Training: expected e5, played d5`.
Play through all four correct moves -> `Training: repertoire complete!`

```
!train file /no/such/file.pgn
```

**Expected:** `File not found: /no/such/file.pgn`.

---

## 41. Score sheet and Lichess upload

```
!moves
```

**Expected:** Two-column score sheet of all moves played so far, with move
times.

With `lichess_token` configured and at least one move played:

```
!upload
```

**Expected:** Game imported; Lichess URL printed. (Optional -- publishes the
game to your Lichess account.)

---

## 42. Resync (missed move recovery)

### 42a. Already in sync

With no pending physical change, run:

```
!resync
```

**Expected:** `Board in sync with game state. No changes.` Board and FEN
reprinted; game state (move history, PGN) unaffected.

### 42b. Recovering a missed move

Play a move on the board as normal, but during setup deliberately
interrupt detection so it doesn't register (e.g. briefly disconnect the
USB cable while the piece is in the air, or use `!fen` to desync the
program's position from the board without moving pieces, then move a
single legal piece on the physical board to match). Once the board
again shows a single legal move away from the program's position, run:

```
!resync
```

**Expected:** `Recovered missed move: <SAN>  [<uci>]` printed; move
appears in `!moves`; PGN file updated (check with `!pgn`); board/FEN
reprinted normally.

### 42c. Unrecoverable difference

Desync the position so more than one physical change is needed to
reconcile (e.g. `!fen` to an unrelated position while leaving the
physical board as it was), then run:

```
!resync
```

**Expected:** `Board does not match a single legal move from the
current position.` followed by a square-by-square
`<square>: <expected> -> <actual>` diff, and a suggestion to fix the
pieces or use `!resync force`. Game state unchanged.

Then run:

```
!resync force
```

**Expected:** `Board adopted as-is (forced).` warning about PGN
continuity; board/FEN now match the physical board; PGN file updated.

---

## Summary checklist

| # | Area                        | Pass |
|---|-----------------------------|------|
| 1 | Build + automated tests     |      |
| 2 | Engine auto-detected        |      |
| 3 | Missing engine error (startup + !analyse etc.) |      |
| 4 | Config # comments           |      |
| 5 | Serial device (default/arg/config) |  |
| 6 | Colour selection prompt     |      |
| 7 | Move tracking + openings    |      |
| 8 | !analyse / !eval / !hint    |      |
| 9 | !multipv                    |      |
|10 | !time / !depth              |      |
|11 | !undo                       |      |
|12 | Player names + !pgn         |      |
|13 | !comment                    |      |
|14 | !flip                       |      |
|15 | !unicode                    |      |
|16 | !fen                        |      |
|17 | !newgame / !newgameb        |      |
|18 | Castling                    |      |
|19 | En passant                  |      |
|20 | Promotion                   |      |
|21 | Resign / draw               |      |
|22 | Opening book + !book        |      |
|23 | Time control                |      |
|24 | !review                     |      |
|25 | !compare                    |      |
|26 | PGN auto-save               |      |
|27 | !load + !forward / !back    |      |
|28 | !save                       |      |
|29 | !display                    |      |
|30 | !boarddisplay               |      |
|31 | !webdisplay                 |      |
|32 | Tablebase                   |      |
|33 | !train (Lichess) + out-of-book end |  |
|34 | !train opening (name/ECO/paste) |  |
|34b| Opening browser             |      |
|35 | CLKB compress/decompress    |      |
|36 | raw_dump                    |      |
|37 | Board reconnect             |      |
|38 | Speech (espeak-ng / piper)  |      |
|39 | !train strict               |      |
|40 | !train file                 |      |
|41 | !moves + !upload            |      |
|42 | !resync (sync/recover/force)|      |
