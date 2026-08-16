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

with GNAT.OS_Lib;

package body DGT.Engine is

   use GNAT.Expect;

   --  =========================================================
   --  String helpers
   --  =========================================================

   --  Find the first occurrence of Sub in S; return index or 0.
   function Find (S, Sub : String) return Natural is
   begin
      if Sub'Length = 0 or Sub'Length > S'Length then return 0; end if;
      for I in S'First .. S'Last - Sub'Length + 1 loop
         if S (I .. I + Sub'Length - 1) = Sub then return I; end if;
      end loop;
      return 0;
   end Find;

   --  Parse the integer starting at S (I), skip leading spaces.
   function Parse_Int (S : String; Start : Natural) return Integer is
      I     : Natural := Start;
      Neg   : Boolean := False;
      Value : Integer := 0;
   begin
      while I <= S'Last and S (I) = ' ' loop I := I + 1; end loop;
      if I <= S'Last and S (I) = '-' then Neg := True; I := I + 1; end if;
      while I <= S'Last and S (I) in '0' .. '9' loop
         Value := Value * 10 + (Character'Pos (S (I)) - Character'Pos ('0'));
         I := I + 1;
      end loop;
      return (if Neg then -Value else Value);
   end Parse_Int;

   --  Like Find but returns the LAST match position.
   function Find_Last (S, Sub : String) return Natural is
      Last : Natural := 0;
   begin
      if Sub'Length = 0 or else Sub'Length > S'Length then return 0; end if;
      for I in S'First .. S'Last - Sub'Length + 1 loop
         if S (I .. I + Sub'Length - 1) = Sub then Last := I; end if;
      end loop;
      return Last;
   end Find_Last;

   --  Parse score from a Stockfish "info ... score cp N ..." line.
   procedure Parse_Score (Output : String; A : in out Analysis) is
      CP_Tag   : constant String := " score cp ";
      Mate_Tag : constant String := " score mate ";
      P        : Natural;
   begin
      P := Find (Output, Mate_Tag);
      if P > 0 then
         A.Is_Mate := True;
         A.Mate_In := Parse_Int (Output, P + Mate_Tag'Length);
         return;
      end if;
      P := Find (Output, CP_Tag);
      if P > 0 then
         A.Score_CP := Parse_Int (Output, P + CP_Tag'Length);
      end if;
   end Parse_Score;

   --  Capture the full PV text from the last "pv " tag to end of its line.
   procedure Parse_PV (Output : String; A : in out Analysis) is
      Tag : constant String := " pv ";
      P   : constant Natural := Find_Last (Output, Tag);
      I   : Natural;
      E   : Natural;
   begin
      if P = 0 then return; end if;
      I := P + Tag'Length;
      E := I;
      while E <= Output'Last and then Output (E) /= ASCII.LF
                              and then Output (E) /= ASCII.CR loop
         E := E + 1;
      end loop;
      A.PV_Len := Natural'Min (A.PV'Length, E - I);
      A.PV (1 .. A.PV_Len) := Output (I .. I + A.PV_Len - 1);
   end Parse_PV;

   --  Extract the best move from "bestmove e2e4 ..."
   procedure Parse_Best_Move (Output : String; A : in out Analysis) is
      Tag : constant String := "bestmove ";
      P   : constant Natural := Find (Output, Tag);
      I   : Natural;
   begin
      if P = 0 then return; end if;
      I := P + Tag'Length;
      A.Move_Len := 0;
      while I <= Output'Last and A.Move_Len < 5 loop
         exit when Output (I) = ' ' or Output (I) = ASCII.LF or Output (I) = ASCII.CR;
         A.Move_Len := A.Move_Len + 1;
         A.Best_Move (A.Move_Len) := Output (I);
         I := I + 1;
      end loop;
   end Parse_Best_Move;

   --  =========================================================
   --  Returns " multipv N " for integer N (no leading space in N).
   function PV_Tag_Str (N : Positive) return String is
      S : constant String := Positive'Image (N);
   begin
      return " multipv " & S (2 .. S'Last) & " ";
   end PV_Tag_Str;

   --  Extract score and first pv move from the last "multipv N" info line.
   procedure Parse_PV_Line
     (Output : String; PV_N : Positive; A : in out Analysis)
   is
      Tag : constant String  := PV_Tag_Str (PV_N);
      P   : constant Natural := Find_Last (Output, Tag);
   begin
      if P = 0 then return; end if;
      declare
         E : Natural := P;
      begin
         while E <= Output'Last and then Output (E) /= ASCII.LF loop
            E := E + 1;
         end loop;
         declare
            Line : constant String := Output (P .. E - 1);
            PV_P : constant Natural := Find (Line, " pv ");
            I    : Natural;
         begin
            Parse_Score (Line, A);
            if PV_P > 0 then
               I := PV_P + 4;
               A.Move_Len := 0;
               while I <= Line'Last and then A.Move_Len < 5 loop
                  exit when Line (I) in ' ' | ASCII.LF | ASCII.CR;
                  A.Move_Len := A.Move_Len + 1;
                  A.Best_Move (A.Move_Len) := Line (I);
                  I := I + 1;
               end loop;
               --  Full PV text
               declare
                  PV_Start : constant Natural := PV_P + 4;
                  PV_End   : Natural := PV_Start;
               begin
                  while PV_End <= Line'Last
                     and then Line (PV_End) /= ASCII.LF
                     and then Line (PV_End) /= ASCII.CR
                  loop PV_End := PV_End + 1; end loop;
                  A.PV_Len := Natural'Min (A.PV'Length, PV_End - PV_Start);
                  A.PV (1 .. A.PV_Len) :=
                     Line (PV_Start .. PV_Start + A.PV_Len - 1);
               end;
            end if;
         end;
      end;
   end Parse_PV_Line;

   --  Public API
   --  =========================================================

   procedure Start (E : in out Engine_State; Path : String) is
      Empty_Args : constant GNAT.OS_Lib.Argument_List (1 .. 0) :=
         (others => null);
      Match      : Expect_Match;
   begin
      Non_Blocking_Spawn (E.Pd, Path, Empty_Args, Err_To_Out => True);
      Send (E.Pd, "uci");
      Expect (E.Pd, Match, "uciok", Timeout => 5_000);

      --  Parse "id name <engine name>" from the uci handshake output.
      declare
         Output : constant String := Expect_Out (E.Pd);
         Tag    : constant String := "id name ";
         P      : Natural         := Find (Output, Tag);
      begin
         if P > 0 then
            P := P + Tag'Length;
            declare
               Fin : Natural := P;
            begin
               while Fin <= Output'Last
                  and then Output (Fin) /= ASCII.LF
                  and then Output (Fin) /= ASCII.CR
               loop
                  Fin := Fin + 1;
               end loop;
               E.Name_Len := Natural'Min (E.Name'Length, Fin - P);
               E.Name (1 .. E.Name_Len) := Output (P .. P + E.Name_Len - 1);
            end;
         end if;
      end;

      Send (E.Pd, "setoption name Threads value 1");
      Send (E.Pd, "isready");
      Expect (E.Pd, Match, "readyok", Timeout => 5_000);
      E.Running := True;
   exception
      when others =>
         E.Running := False;
   end Start;

   function Engine_Name (E : Engine_State) return String is
   begin
      return E.Name (1 .. E.Name_Len);
   end Engine_Name;

   function Is_Running (E : Engine_State) return Boolean is
   begin
      return E.Running;
   end Is_Running;

   procedure Stop (E : in out Engine_State) is
   begin
      if E.Running then
         Send (E.Pd, "quit");
         Close (E.Pd);
         E.Running := False;
      end if;
   end Stop;

   function Analyse
     (E            : in out Engine_State;
      FEN          : String;
      Move_Time_Ms : Positive := 1500;
      Depth        : Natural  := 0) return Analysis
   is
      A       : Analysis;
      Match   : Expect_Match;
      Timeout : constant Integer :=
         (if Depth > 0 then 60_000 else Move_Time_Ms + 5_000);
   begin
      if not E.Running then return A; end if;

      Send (E.Pd, "position fen " & FEN);
      if Depth > 0 then
         Send (E.Pd, "go depth" & Natural'Image (Depth));
      else
         Send (E.Pd, "go movetime" & Positive'Image (Move_Time_Ms));
      end if;

      --  Read all output until "bestmove" arrives
      Expect (E.Pd, Match, "bestmove [a-h][1-8][a-h][1-8]",
              Timeout => Timeout);

      if Match = Expect_Timeout then return A; end if;  --  timed out

      declare
         Output : constant String := Expect_Out (E.Pd);
      begin
         Parse_Score     (Output, A);
         Parse_Best_Move (Output, A);
         Parse_PV        (Output, A);
      end;

      --  Send "stop" to be safe (engine should have finished, but just in case)
      Send (E.Pd, "stop");

      return A;
   exception
      when Process_Died =>
         E.Running := False;
         return A;
   end Analyse;

   function Analyse_Multi
     (E            : in out Engine_State;
      FEN          : String;
      Num_PV       : Positive := 1;
      Move_Time_Ms : Positive := 1500;
      Depth        : Natural  := 0) return Analysis_Array
   is
      Results : Analysis_Array;
      Match   : Expect_Match;
      Timeout : constant Integer :=
         (if Depth > 0 then 60_000 else Move_Time_Ms + 5_000);
      NP_Img  : constant String := Positive'Image (Num_PV);
   begin
      if not E.Running then return Results; end if;

      Send (E.Pd, "setoption name MultiPV value" & NP_Img);
      Send (E.Pd, "position fen " & FEN);
      if Depth > 0 then
         Send (E.Pd, "go depth" & Natural'Image (Depth));
      else
         Send (E.Pd, "go movetime" & Positive'Image (Move_Time_Ms));
      end if;

      Expect (E.Pd, Match, "bestmove [a-h][1-8][a-h][1-8]",
              Timeout => Timeout);

      if Match /= Expect_Timeout then
         declare
            Output : constant String := Expect_Out (E.Pd);
         begin
            for I in 1 .. Num_PV loop
               Parse_PV_Line (Output, I, Results (I));
            end loop;
            --  Fallback for PV 1 when multipv tag is absent (single-pv engine)
            if Results (1).Move_Len = 0 then
               Parse_Best_Move (Output, Results (1));
               Parse_Score (Output, Results (1));
            end if;
         end;
      end if;

      Send (E.Pd, "setoption name MultiPV value 1");
      Send (E.Pd, "stop");
      return Results;
   exception
      when Process_Died =>
         E.Running := False;
         return Results;
   end Analyse_Multi;

   function Format_Score (A : Analysis) return String is
   begin
      if A.Move_Len = 0 then return "(no analysis)"; end if;
      if A.Is_Mate then
         if A.Mate_In > 0 then
            return "Mate in" & Integer'Image (A.Mate_In);
         else
            return "Mated in" & Integer'Image (-A.Mate_In);
         end if;
      end if;
      declare
         Abs_CP  : constant Natural := abs A.Score_CP;
         Pawns   : constant Natural := Abs_CP / 100;
         Cents   : constant Natural := Abs_CP mod 100;
         Sign    : constant String  := (if A.Score_CP >= 0 then "+" else "-");
         P_Img   : constant String  := Natural'Image (Pawns);
         C_Str   : constant String  := (if Cents < 10 then "0" else "")
                                       & Natural'Image (Cents);
         C_Img   : constant String  := C_Str (C_Str'Last - 1 .. C_Str'Last);
      begin
         return Sign & P_Img (2 .. P_Img'Last) & "." & C_Img;
      end;
   end Format_Score;

end DGT.Engine;
