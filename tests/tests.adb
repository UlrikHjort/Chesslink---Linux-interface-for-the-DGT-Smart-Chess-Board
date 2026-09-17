-- ***************************************************************************
--                      DGT Smart Board - Test Suite
--
--           Copyright (C) 2026 By Ulrik Hørlyk Hjort
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- ***************************************************************************

with Ada.Text_IO;
with Ada.Directories;
with Ada.Sequential_IO;
with Ada.Strings.Fixed;
with Ada.Command_Line;
with DGT.Game;
with DGT.Board;
with DGT.Protocol;
with DGT.Openings;
with CLKB;

procedure Tests is

   use Ada.Text_IO;
   use DGT.Game;
   use DGT.Board;
   use DGT.Protocol;

   Pass_N : Natural := 0;
   Fail_N : Natural := 0;

   procedure Check (Label : String; Cond : Boolean) is
   begin
      if Cond then
         Put_Line ("[PASS] " & Label);
         Pass_N := Pass_N + 1;
      else
         Put_Line ("[FAIL] " & Label);
         Fail_N := Fail_N + 1;
      end if;
   end Check;

   --  Ada.Strings.Fixed.Move conflicts with DGT.Game.Move - use full name.
   function Has (S, Sub : String) return Boolean is
     (Ada.Strings.Fixed.Index (S, Sub) > 0);

   Start_FEN : constant String :=
      "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

begin

   Put_Line ("=== DGT Chesslink Test Suite ===");
   New_Line;

   -- ================================================================
   --  Group 1: FEN parsing and round-trip
   -- ================================================================

   -- T1
   declare
      G : constant Game_State := From_FEN (Start_FEN);
   begin
      Check ("T01 FEN round-trip: starting position", To_FEN (G) = Start_FEN);
   end;

   -- T2: after 1.e4, To_FEN includes the en-passant square "e3"
   declare
      G  : Game_State := From_FEN (Start_FEN);
      OK : constant Boolean := Apply_UCI (G, "e2e4");
   begin
      Check ("T02 FEN after 1.e4 contains EP square 'e3'",
             OK and then Has (To_FEN (G), "e3"));
   end;

   -- T3: From_FEN sets the active colour correctly
   declare
      G : constant Game_State := From_FEN (
         "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1");
   begin
      Check ("T03 From_FEN sets active colour Black",
             Active_Color (G) = Black);
   end;

   -- ================================================================
   --  Group 2: Basic move application
   -- ================================================================

   -- T4
   declare
      G  : Game_State := From_FEN (Start_FEN);
      OK : constant Boolean := Apply_UCI (G, "e2e4");
   begin
      Check ("T04 Apply_UCI increments move count to 1",
             OK and then Move_Count (G) = 1);
   end;

   -- T5
   declare
      G   : Game_State := From_FEN (Start_FEN);
      OK1 : constant Boolean := Apply_UCI (G, "e2e4");
      OK2 : constant Boolean := Apply_UCI (G, "e7e5");
   begin
      Check ("T05 Two UCI moves: count=2, White to move",
             OK1 and OK2
             and Move_Count (G) = 2
             and Active_Color (G) = White);
   end;

   -- T6: a Black piece cannot move when it is White's turn
   declare
      G  : Game_State := From_FEN (Start_FEN);
      OK : constant Boolean := Apply_UCI (G, "e7e5");
   begin
      Check ("T06 Wrong-colour move is rejected", not OK);
   end;

   -- T7: a move from an empty square is rejected
   declare
      G  : Game_State := From_FEN (Start_FEN);
      OK : constant Boolean := Apply_UCI (G, "a3a4");
   begin
      Check ("T07 Move from empty square is rejected", not OK);
   end;

   -- T8
   declare
      G  : Game_State := From_FEN (Start_FEN);
      OK : constant Boolean := Apply_SAN (G, "e4");
   begin
      Check ("T08 Apply_SAN 'e4' succeeds", OK and Move_Count (G) = 1);
   end;

   -- ================================================================
   --  Group 3: Move record - UCI and SAN strings
   -- ================================================================

   -- T9
   declare
      G  : Game_State := From_FEN (Start_FEN);
      OK : constant Boolean := Apply_UCI (G, "e2e4");
      M  : constant Move    := Get_Move (G, 1);
   begin
      Check ("T09 Move_UCI = 'e2e4'", OK and Move_UCI (M) = "e2e4");
   end;

   -- T10
   declare
      G  : Game_State := From_FEN (Start_FEN);
      OK : constant Boolean := Apply_UCI (G, "e2e4");
      M  : constant Move    := Get_Move (G, 1);
   begin
      Check ("T10 Move_SAN 1.e4 = 'e4'", OK and Move_SAN (M) = "e4");
   end;

   -- T11
   declare
      G  : Game_State := From_FEN (Start_FEN);
      OK : constant Boolean := Apply_UCI (G, "g1f3");
      M  : constant Move    := Get_Move (G, 1);
   begin
      Check ("T11 Move_SAN 1.Nf3 = 'Nf3'", OK and Move_SAN (M) = "Nf3");
   end;

   -- ================================================================
   --  Group 4: Castling
   -- ================================================================

   -- T12: kingside O-O
   declare
      G  : Game_State := From_FEN (
         "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1");
      OK : constant Boolean := Apply_SAN (G, "O-O");
      M  : constant Move    := Get_Move (G, 1);
   begin
      Check ("T12 Kingside O-O accepted, SAN = 'O-O'",
             OK and Move_SAN (M) = "O-O");
   end;

   -- T13: queenside O-O-O
   declare
      G  : Game_State := From_FEN (
         "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1");
      OK : constant Boolean := Apply_SAN (G, "O-O-O");
      M  : constant Move    := Get_Move (G, 1);
   begin
      Check ("T13 Queenside O-O-O accepted, SAN = 'O-O-O'",
             OK and Move_SAN (M) = "O-O-O");
   end;

   -- ================================================================
   --  Group 5: En passant
   -- ================================================================

   -- T14 + T15: White pawn on e5, Black just double-pushed to d5 (EP sq d6)
   declare
      G  : Game_State := From_FEN (
         "rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3");
      OK : constant Boolean := Apply_UCI (G, "e5d6");
      M  : constant Move    := Get_Move (G, 1);
   begin
      Check ("T14 EP capture: Is_EP = True",  OK and M.Is_EP);
      Check ("T15 EP capture: Captured = BPawn", M.Captured = BPawn);
   end;

   -- ================================================================
   --  Group 6: Promotion
   -- ================================================================

   -- T16 + T17: White pawn on e7 promotes to queen
   declare
      G  : Game_State := From_FEN ("4k3/4P3/8/8/8/8/8/4K3 w - - 0 1");
      OK : constant Boolean := Apply_UCI (G, "e7e8q");
      M  : constant Move    := Get_Move (G, 1);
   begin
      Check ("T16 Promotion SAN contains '=q'",
             OK and Has (Move_SAN (M), "=q"));
      Check ("T17 Promotion: WQueen on e8",
             Current_Board (G).Squares (Square_Index (4)) = WQueen);
   end;

   -- ================================================================
   --  Group 7: Checkmate (Scholar's mate)
   --   1.e4 e5 2.Bc4 Nc6 3.Qh5 Nf6 4.Qxf7#
   -- ================================================================

   -- T18 + T19
   declare
      G : Game_State := From_FEN (Start_FEN);

      procedure Play (UCI : String) is
         OK : constant Boolean := Apply_UCI (G, UCI);
      begin
         if not OK then
            Put_Line ("  warning: move rejected: " & UCI);
         end if;
      end Play;

   begin
      Play ("e2e4"); Play ("e7e5");
      Play ("f1c4"); Play ("b8c6");
      Play ("d1h5"); Play ("g8f6");
      Play ("h5f7");
      declare
         S : constant String := Move_SAN (Get_Move (G, 7));
      begin
         Check ("T18 Scholar's mate: outcome = White_Wins",
                Game_Outcome (G) = White_Wins);
         Check ("T19 Checkmate move SAN ends '#'", S (S'Last) = '#');
      end;
   end;

   -- ================================================================
   --  Group 8: Stalemate
   --   BKing a8, WKing c8, WQueen c6 -> Qc6-b6 stalemates Black
   -- ================================================================

   -- T20
   declare
      G  : Game_State := From_FEN ("k1K5/8/2Q5/8/8/8/8/8 w - - 0 1");
      OK : constant Boolean := Apply_UCI (G, "c6b6");
   begin
      Check ("T20 Stalemate: outcome = Draw",
             OK and Game_Outcome (G) = Draw);
   end;

   -- ================================================================
   --  Group 9: Draw by insufficient material
   -- ================================================================

   -- T21: K vs K
   declare
      G  : Game_State := From_FEN ("K7/8/8/8/8/8/8/7k w - - 0 1");
      OK : constant Boolean := Apply_UCI (G, "a8b8");
   begin
      Check ("T21 K vs K: outcome = Draw (insufficient material)",
             OK and Game_Outcome (G) = Draw);
   end;

   -- ================================================================
   --  Group 10: Undo
   -- ================================================================

   -- T22 + T23
   declare
      G  : Game_State := From_FEN (Start_FEN);
      OK : constant Boolean := Apply_UCI (G, "e2e4");
   begin
      Check ("T22 e4 was applied successfully", OK);
      Undo (G);
      Check ("T23 Undo restores starting FEN", To_FEN (G) = Start_FEN);
   end;

   -- ================================================================
   --  Group 11: Opening book
   -- ================================================================

   -- T24
   Check ("T24 Ruy Lopez lookup contains 'Ruy'",
          Has (DGT.Openings.Lookup (
             "e2e4 e7e5 g1f3 b8c6 f1b5"), "Ruy"));

   -- T25
   Check ("T25 Unknown moves return empty string",
          DGT.Openings.Lookup ("h2h4 a7a5") = "");

   -- T26
   Check ("T26 Find_Moves 'Sicilian' is non-empty",
          DGT.Openings.Find_Moves ("Sicilian") /= "");

   -- T27-T28: SHA-1 NIST FIPS test vectors (written as raw binary via Sequential_IO
   --  so Ada.Text_IO does not append a line terminator).
   declare
      package CIO is new Ada.Sequential_IO (Character);

      procedure Write_Raw (Path : String; Content : String) is
         F : CIO.File_Type;
      begin
         CIO.Create (F, CIO.Out_File, Path);
         for C of Content loop CIO.Write (F, C); end loop;
         CIO.Close (F);
      end Write_Raw;
   begin
      Write_Raw ("/tmp/dgt_sha1_a.bin", "a");
      Check ("T27 Hash_File: SHA-1 of 'a' matches FIPS vector",
             DGT.Openings.Hash_File ("/tmp/dgt_sha1_a.bin") =
                "86f7e437faa5a7fce15d1ddcb9eaeaea377667b8");

      Write_Raw ("/tmp/dgt_sha1_abc.bin", "abc");
      Check ("T28 Hash_File: SHA-1 of 'abc' matches FIPS vector",
             DGT.Openings.Hash_File ("/tmp/dgt_sha1_abc.bin") =
                "a9993e364706816aba3e25717850c26c9cd0d89d");
   end;

   -- T29: Hash_File on the real openings.dat matches sha1sum (if present).
   declare
      Path : constant String :=
         "../data/openings.dat";
   begin
      if Ada.Directories.Exists (Path) then
         Check ("T29 Hash_File: openings.dat matches sha1sum reference",
                DGT.Openings.Hash_File (Path) =
                   "40ad6b70cd3bad7481b86c0ea41075c4dcbf72ae");
      end if;
   end;

   -- ================================================================
   --  Group 12: Check and pin geometry
   -- ================================================================

   -- T30: a rook pinned on the e-file (Re2 shields Ke1 from Re8) may
   --  not step off that file - the move must be rejected.
   declare
      G  : Game_State := From_FEN ("4r3/8/8/8/8/8/4R3/4K3 w - - 0 1");
      OK : constant Boolean := Apply_UCI (G, "e2d2");
   begin
      Check ("T30 Pinned rook move is rejected (exposes king to Re8)", not OK);
   end;

   -- ================================================================
   --  Group 13: Castling restrictions
   -- ================================================================

   -- T31: king may not castle through an attacked square (f1 covered by Rf8)
   declare
      G  : Game_State := From_FEN ("5r2/8/8/8/8/8/8/4K2R w K - 0 1");
      OK : constant Boolean := Apply_SAN (G, "O-O");
   begin
      Check ("T31 Cannot castle kingside through check (f1 attacked)", not OK);
   end;

   -- T32: king may not castle into check (g1 covered by Rg8)
   declare
      G  : Game_State := From_FEN ("6r1/8/8/8/8/8/8/4K2R w K - 0 1");
      OK : constant Boolean := Apply_SAN (G, "O-O");
   begin
      Check ("T32 Cannot castle kingside into check (g1 attacked)", not OK);
   end;

   -- ================================================================
   --  Group 14: Draw conditions
   -- ================================================================

   -- T33: 50-move rule - halfmove clock at 99, one quiet king move
   --  brings it to 100 and triggers the draw.
   declare
      G  : Game_State := From_FEN ("k7/8/8/8/8/8/8/7K w - - 99 1");
      OK : constant Boolean := Apply_UCI (G, "h1g1");
   begin
      Check ("T33 50-move rule: outcome = Draw after clock reaches 100",
             OK and Game_Outcome (G) = Draw);
   end;

   -- T34: threefold repetition - shuffle Ra1<->b1 and Kh8<->g8.
   --  The position after Ra1-b1 (P1) first appears on half-move 1,
   --  again on half-move 5, and a third time on half-move 9 -> Draw.
   declare
      G      : Game_State := From_FEN ("7k/8/8/8/8/8/8/R6K w - - 0 1");
      Ignore : Boolean := False;
      procedure Play (UCI : String) is
      begin Ignore := Apply_UCI (G, UCI); end Play;
   begin
      Play ("a1b1"); Play ("h8g8");   --  half-moves 1-2: P1, P2
      Play ("b1a1"); Play ("g8h8");   --  half-moves 3-4: P3, P0 (stored)
      Play ("a1b1"); Play ("h8g8");   --  half-moves 5-6: P1x2, P2x2
      Play ("b1a1"); Play ("g8h8");   --  half-moves 7-8: P3x2, P0x2
      Play ("a1b1");                  --  half-move  9:   P1x3 -> Draw
      Check ("T34 Threefold repetition: outcome = Draw", Game_Outcome (G) = Draw);
   end;

   -- ================================================================
   --  Group 15: Insufficient material (additional cases)
   -- ================================================================

   -- T35: K + bishop vs lone K is a dead position.
   declare
      G  : Game_State := From_FEN ("k7/8/8/8/8/8/8/BK6 w - - 0 1");
      OK : constant Boolean := Apply_UCI (G, "b1c1");
   begin
      Check ("T35 K+B vs K: outcome = Draw (insufficient material)",
             OK and Game_Outcome (G) = Draw);
   end;

   -- T36: K + knight vs lone K is also a dead position.
   declare
      G  : Game_State := From_FEN ("k7/8/8/8/8/8/8/NK6 w - - 0 1");
      OK : constant Boolean := Apply_UCI (G, "b1c1");
   begin
      Check ("T36 K+N vs K: outcome = Draw (insufficient material)",
             OK and Game_Outcome (G) = Draw);
   end;

   -- ================================================================
   --  Group 16: CLKB compression library
   -- ================================================================

   -- T37: encoding a UCI move to 12 bits and back must be lossless.
   declare
      use CLKB;
   begin
      Check ("T37 CLKB UCI_To_Move/Move_To_UCI round-trip (e2e4, g1f3, d7d5)",
             Move_To_UCI (UCI_To_Move ("e2e4")) = "e2e4" and
             Move_To_UCI (UCI_To_Move ("g1f3")) = "g1f3" and
             Move_To_UCI (UCI_To_Move ("d7d5")) = "d7d5");
   end;

   -- T38: byte-count formula for packed 12-bit move arrays.
   declare
      use CLKB;
   begin
      Check ("T38 CLKB Packed_Bytes: 0->0, 1->2, 2->3, 3->5, 4->6",
             Packed_Bytes (0) = 0 and Packed_Bytes (1) = 2 and
             Packed_Bytes (2) = 3 and Packed_Bytes (3) = 5 and
             Packed_Bytes (4) = 6);
   end;

   -- ================================================================
   --  Summary
   -- ================================================================

   New_Line;
   Put_Line (Natural'Image (Pass_N) & " passed,"
             & Natural'Image (Fail_N) & " failed  ("
             & Natural'Image (Pass_N + Fail_N) & " total).");

   if Fail_N > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;

end Tests;
