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

with DGT.Protocol;

package DGT.Board is

   --  DGT index mapping: 0 = a8 (top-left), 63 = h1 (bottom-right)
   --  Row 0 = rank 8, row 7 = rank 1; column 0 = file a, column 7 = file h
   type Square_Index is range 0 .. 63;
   type Board_Array  is array (Square_Index) of Protocol.Piece_Code;

   type Board_State is record
      Squares : Board_Array := (others => Protocol.Empty);
   end record;

   function  Square_Name (Sq : Square_Index) return String;
   procedure Print_Board  (B           : Board_State;
                           Flipped     : Boolean := False;
                           Use_Unicode : Boolean := False);
   function  To_FEN       (B : Board_State) return String;

end DGT.Board;
