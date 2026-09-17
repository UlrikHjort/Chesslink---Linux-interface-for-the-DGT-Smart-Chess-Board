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

with Ada.Streams;

package DGT.Protocol is

   --  Commands sent to the board (single byte each)
   CMD_RESET           : constant Ada.Streams.Stream_Element := 16#40#;
   CMD_SEND_BRD        : constant Ada.Streams.Stream_Element := 16#42#;
   CMD_SEND_UPDATE     : constant Ada.Streams.Stream_Element := 16#43#;
   CMD_SEND_SERIALNR   : constant Ada.Streams.Stream_Element := 16#44#;
   CMD_SEND_VERSION    : constant Ada.Streams.Stream_Element := 16#45#;
   CMD_SEND_UPDATE_BRD : constant Ada.Streams.Stream_Element := 16#47#;

   --  Message IDs received from the board (first byte of each message)
   MSG_BOARD_DUMP    : constant Ada.Streams.Stream_Element := 16#86#;
   MSG_FIELD_UPDATE  : constant Ada.Streams.Stream_Element := 16#8E#;
   MSG_SERIALNR      : constant Ada.Streams.Stream_Element := 16#87#;
   MSG_VERSION       : constant Ada.Streams.Stream_Element := 16#8A#;
   MSG_SMART_ID      : constant Ada.Streams.Stream_Element := 16#91#;

   --  Piece codes as sent by the board
   type Piece_Code is
     (Empty,
      WPawn, WRook, WKnight, WBishop, WKing, WQueen,
      BPawn, BRook, BKnight, BBishop, BKing, BQueen);

   for Piece_Code use
     (Empty   => 16#00#,
      WPawn   => 16#01#, WRook   => 16#02#, WKnight => 16#03#,
      WBishop => 16#04#, WKing   => 16#05#, WQueen  => 16#06#,
      BPawn   => 16#07#, BRook   => 16#08#, BKnight => 16#09#,
      BBishop => 16#0A#, BKing   => 16#0B#, BQueen  => 16#0C#);

   for Piece_Code'Size use 8;

   function Byte_To_Piece  (B : Ada.Streams.Stream_Element) return Piece_Code;
   function Piece_Char     (P : Piece_Code) return Character;
   function Piece_Name     (P : Piece_Code) return String;
   --  UTF-8 chess symbol (U+2654-U+265F); Empty returns " " (1 space).
   function Piece_Symbol   (P : Piece_Code) return String;

end DGT.Protocol;
