-- ***************************************************************************
--                        CLKB Opening Book Format
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
--
--  Binary opening book format for Chesslink.
--
--  File layout:
--    Header  : "CLKB" (4 bytes) + entry_count (4 bytes, big-endian unsigned)
--    Entries : one record per opening line
--      shared_count  (1 byte)  moves shared with the previous entry's prefix
--      new_count     (1 byte)  new moves appended after the shared prefix
--      packed_moves  N bytes   12-bit moves packed in pairs (see Packed_Bytes)
--      eco_letter    (1 byte)  'A'..'E' encoded as 0..4
--      eco_number    (1 byte)  0..99
--      name_len      (1 byte)  byte length of the opening name string
--      name          N bytes   raw ASCII
--
--  Move encoding (12 bits each):
--    sq      = file * 8 + rank   (file: 'a'=0..'h'=7, rank: '1'=0..'8'=7)
--    move_12 = src_sq * 64 + dst_sq   (0 .. 4095)
--
--  Packing two moves M1, M2 into 3 bytes:
--    byte0 = M1 >> 4
--    byte1 = ((M1 and 0xF) << 4) or (M2 >> 8)
--    byte2 = M2 and 0xFF
--  An odd trailing move packs into 2 bytes with a zero low nibble in byte1.

package CLKB is

   subtype Move_12 is Natural range 0 .. 4095;
   type Move_Array is array (Positive range <>) of Move_12;

   Magic     : constant String  := "CLKB";
   Max_Moves : constant Natural := 255;

   --  Encode a 4-character UCI move string (e.g. "e2e4") to a 12-bit value.
   function UCI_To_Move (UCI : String) return Move_12;

   --  Decode a 12-bit move value back to a 4-character UCI move string.
   function Move_To_UCI (M : Move_12) return String;

   --  Return the number of bytes required to store N packed 12-bit moves.
   function Packed_Bytes (N : Natural) return Natural;

end CLKB;
