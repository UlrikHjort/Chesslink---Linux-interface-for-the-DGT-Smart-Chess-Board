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

package body CLKB is

   function UCI_To_Move (UCI : String) return Move_12 is
      F1 : constant Natural :=
         Character'Pos (UCI (UCI'First))     - Character'Pos ('a');
      R1 : constant Natural :=
         Character'Pos (UCI (UCI'First + 1)) - Character'Pos ('1');
      F2 : constant Natural :=
         Character'Pos (UCI (UCI'First + 2)) - Character'Pos ('a');
      R2 : constant Natural :=
         Character'Pos (UCI (UCI'First + 3)) - Character'Pos ('1');
   begin
      return (F1 * 8 + R1) * 64 + (F2 * 8 + R2);
   end UCI_To_Move;

   function Move_To_UCI (M : Move_12) return String is
      Src : constant Natural := M / 64;
      Dst : constant Natural := M mod 64;
      R   : String (1 .. 4);
   begin
      R (1) := Character'Val (Character'Pos ('a') + Src / 8);
      R (2) := Character'Val (Character'Pos ('1') + Src mod 8);
      R (3) := Character'Val (Character'Pos ('a') + Dst / 8);
      R (4) := Character'Val (Character'Pos ('1') + Dst mod 8);
      return R;
   end Move_To_UCI;

   function Packed_Bytes (N : Natural) return Natural is
   begin
      return (N / 2) * 3 + (if N mod 2 = 1 then 2 else 0);
   end Packed_Bytes;

end CLKB;
