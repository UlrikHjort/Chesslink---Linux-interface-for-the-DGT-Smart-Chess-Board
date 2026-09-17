-- ***************************************************************************
--                      DGT Smart Board - DGT Protocol Types
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

package body DGT.Protocol is

   function Byte_To_Piece (B : Ada.Streams.Stream_Element) return Piece_Code is
   begin
      case B is
         when 16#00# => return Empty;
         when 16#01# => return WPawn;
         when 16#02# => return WRook;
         when 16#03# => return WKnight;
         when 16#04# => return WBishop;
         when 16#05# => return WKing;
         when 16#06# => return WQueen;
         when 16#07# => return BPawn;
         when 16#08# => return BRook;
         when 16#09# => return BKnight;
         when 16#0A# => return BBishop;
         when 16#0B# => return BKing;
         when 16#0C# => return BQueen;
         when others => return Empty;
      end case;
   end Byte_To_Piece;

   function Piece_Char (P : Piece_Code) return Character is
   begin
      case P is
         when Empty   => return '.';
         when WPawn   => return 'P';
         when WRook   => return 'R';
         when WKnight => return 'N';
         when WBishop => return 'B';
         when WKing   => return 'K';
         when WQueen  => return 'Q';
         when BPawn   => return 'p';
         when BRook   => return 'r';
         when BKnight => return 'n';
         when BBishop => return 'b';
         when BKing   => return 'k';
         when BQueen  => return 'q';
      end case;
   end Piece_Char;

   function Piece_Name (P : Piece_Code) return String is
   begin
      case P is
         when Empty   => return "empty";
         when WPawn   => return "White Pawn";
         when WRook   => return "White Rook";
         when WKnight => return "White Knight";
         when WBishop => return "White Bishop";
         when WKing   => return "White King";
         when WQueen  => return "White Queen";
         when BPawn   => return "Black Pawn";
         when BRook   => return "Black Rook";
         when BKnight => return "Black Knight";
         when BBishop => return "Black Bishop";
         when BKing   => return "Black King";
         when BQueen  => return "Black Queen";
      end case;
   end Piece_Name;

   function Piece_Symbol (P : Piece_Code) return String is
      --  White pieces U+2654-U+2659, Black pieces U+265A-U+265F (UTF-8 3 bytes each)
      function U (Code : Natural) return String is
         --  Ada's "or" is a logical operator on signed integers, not bitwise.
         --  Addition is safe here because the bit ranges never overlap:
         --  B1 bits 7-4 are fixed (1110), bits 3-0 come from Code/0x1000 (0-15).
         B1 : constant Natural := 16#E0# + (Code / 16#1000#);
         B2 : constant Natural := 16#80# + ((Code / 16#40#) mod 16#40#);
         B3 : constant Natural := 16#80# + (Code mod 16#40#);
      begin
         return (1 => Character'Val (B1),
                 2 => Character'Val (B2),
                 3 => Character'Val (B3));
      end U;
   begin
      case P is
         when Empty   => return " ";
         when WKing   => return U (16#2654#);
         when WQueen  => return U (16#2655#);
         when WRook   => return U (16#2656#);
         when WBishop => return U (16#2657#);
         when WKnight => return U (16#2658#);
         when WPawn   => return U (16#2659#);
         when BKing   => return U (16#265A#);
         when BQueen  => return U (16#265B#);
         when BRook   => return U (16#265C#);
         when BBishop => return U (16#265D#);
         when BKnight => return U (16#265E#);
         when BPawn   => return U (16#265F#);
      end case;
   end Piece_Symbol;

end DGT.Protocol;
