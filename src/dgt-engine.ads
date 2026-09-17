-- ***************************************************************************
--                      DGT Smart Board - UCI Engine Interface
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

private with GNAT.Expect;

package DGT.Engine is

   type Analysis is record
      Best_Move  : String (1 .. 5)   := (others => ' ');
      Move_Len   : Natural           := 0;
      Score_CP   : Integer           := 0;
      Is_Mate    : Boolean           := False;
      Mate_In    : Integer           := 0;
      PV         : String (1 .. 120) := (others => ' ');
      PV_Len     : Natural           := 0;
   end record;

   Max_PV : constant := 5;
   type Analysis_Array is array (1 .. Max_PV) of Analysis;

   type Engine_State is limited private;

   procedure Start (E : in out Engine_State; Path : String);
   procedure Stop  (E : in out Engine_State);

   function Engine_Name (E : Engine_State) return String;
   function Is_Running  (E : Engine_State) return Boolean;

   function Analyse
     (E            : in out Engine_State;
      FEN          : String;
      Move_Time_Ms : Positive := 1500;
      Depth        : Natural  := 0) return Analysis;

   --  Multi-PV variant: returns up to Num_PV lines (unused slots have Move_Len=0).
   function Analyse_Multi
     (E            : in out Engine_State;
      FEN          : String;
      Num_PV       : Positive := 1;
      Move_Time_Ms : Positive := 1500;
      Depth        : Natural  := 0) return Analysis_Array;

   function Format_Score (A : Analysis) return String;

private
   type Engine_State is limited record
      Pd       : GNAT.Expect.Process_Descriptor;
      Running  : Boolean         := False;
      Name     : String (1 .. 80) := (others => ' ');
      Name_Len : Natural          := 0;
   end record;
end DGT.Engine;
