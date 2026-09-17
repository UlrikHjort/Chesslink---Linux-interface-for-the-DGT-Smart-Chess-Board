-- ***************************************************************************
--                      DGT Smart Board - Board State
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

package body DGT.Board is

   use Protocol;

   Files : constant String := "abcdefgh";

   function Square_Name (Sq : Square_Index) return String is
      F : constant Natural := Natural (Sq) mod 8;
      R : constant Natural := 8 - Natural (Sq) / 8;
   begin
      return (1 => Files (Files'First + F),
              2 => Character'Val (Character'Pos ('0') + R));
   end Square_Name;

   procedure Print_Board (B           : Board_State;
                          Flipped     : Boolean := False;
                          Use_Unicode : Boolean := False)
   is
      use Ada.Text_IO;
      ESC : constant Character := ASCII.ESC;

      function Img (N : Natural) return String is
         S : constant String := Natural'Image (N);
      begin return S (2 .. S'Last); end Img;

      procedure E (S : String) is
      begin Put (ESC & S); end E;

      File_Labels : constant String :=
         (if Flipped then "    h  g  f  e  d  c  b  a"
                     else "    a  b  c  d  e  f  g  h");
   begin
      New_Line;
      Put_Line (File_Labels);
      for Rank_Idx in 1 .. 8 loop
         declare
            Rank : constant Natural :=
               (if Flipped then Rank_Idx else 9 - Rank_Idx);
         begin
            Put (Img (Rank) & "  ");
            for File_Idx in 0 .. 7 loop
               declare
                  File  : constant Natural :=
                     (if Flipped then 7 - File_Idx else File_Idx);
                  Row   : constant Natural     := 8 - Rank;
                  Sq    : constant Square_Index := Square_Index (Row * 8 + File);
                  P     : constant Piece_Code   := B.Squares (Sq);
                  Light : constant Boolean      := (Row + File) mod 2 = 0;
               begin
                  if Light then E ("[48;5;222m"); else E ("[48;5;94m"); end if;
                  if P in WPawn | WRook | WKnight | WBishop | WKing | WQueen then
                     --  Unicode glyphs are hollow outlines - need darker strokes
                     if Use_Unicode then E ("[38;5;232m");
                     else                E ("[38;5;244m");
                     end if;
                  elsif P /= Empty then
                     E ("[38;5;16m");  --  true #000000 (black pieces)
                  end if;
                  if Use_Unicode then
                     Put (' ' & Piece_Symbol (P) & ' ');
                  else
                     declare
                        Ch : constant Character :=
                           (if P = Empty then ' ' else Piece_Char (P));
                     begin
                        Put (' '); Put (Ch); Put (' ');
                     end;
                  end if;
                  E ("[0m");
               end;
            end loop;
            Put_Line ("  " & Img (Rank));
         end;
      end loop;
      Put_Line (File_Labels);
      New_Line;
   end Print_Board;

   function To_FEN (B : Board_State) return String is
      --  Max FEN piece string: 8 ranks * (8 pieces + 1 slash) = 71 chars
      Result      : String (1 .. 72);
      Pos         : Natural := 0;
      Empty_Count : Natural;
   begin
      for Row in 0 .. 7 loop  --  row 0 = rank 8 (FEN starts at rank 8)
         if Row > 0 then
            Pos := Pos + 1;
            Result (Pos) := '/';
         end if;
         Empty_Count := 0;
         for Col in 0 .. 7 loop
            declare
               Sq : constant Square_Index := Square_Index (Row * 8 + Col);
               P  : constant Piece_Code := B.Squares (Sq);
            begin
               if P = Empty then
                  Empty_Count := Empty_Count + 1;
               else
                  if Empty_Count > 0 then
                     Pos := Pos + 1;
                     Result (Pos) :=
                        Character'Val (Character'Pos ('0') + Empty_Count);
                     Empty_Count := 0;
                  end if;
                  Pos := Pos + 1;
                  Result (Pos) := Piece_Char (P);
               end if;
            end;
         end loop;
         if Empty_Count > 0 then
            Pos := Pos + 1;
            Result (Pos) :=
               Character'Val (Character'Pos ('0') + Empty_Count);
         end if;
      end loop;
      return Result (1 .. Pos);
   end To_FEN;

end DGT.Board;
