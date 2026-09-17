-- ***************************************************************************
--                      DGT Smart Board - Main Application
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
with Ada.Characters.Handling;
with Ada.Command_Line;
with Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with GNAT.OS_Lib;
with GNAT.Serial_Communications;
with DGT;
with DGT.Connection;
with DGT.Board;
with DGT.Protocol;
with DGT.Game;
with DGT.Engine;
with DGT.Openings;

procedure Chesslink is
   use Ada.Text_IO;
   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use type DGT.Protocol.Piece_Code;
   use type DGT.Game.Color;
   use type DGT.Board.Board_State;
   use type DGT.Board.Square_Index;
   use all type DGT.Game.Game_Result;

   Display_File_Path   : constant String := "/tmp/dgt_status.txt";
   Display_Script_Path : constant String := "tools/dgt_display.py";
   Board_Script_Path   : constant String := "tools/dgt_board.py";

   Config_Path : constant String :=
      Ada.Environment_Variables.Value ("HOME") & "/.chesslinkrc";

   --  Locate stockfish on PATH at startup; overridden by engine= in config.
   function Find_Engine_On_Path return String is
      use type GNAT.OS_Lib.String_Access;
      Result : GNAT.OS_Lib.String_Access :=
         GNAT.OS_Lib.Locate_Exec_On_Path ("stockfish");
   begin
      if Result /= null then
         declare
            S : constant String := Result.all;
         begin
            GNAT.OS_Lib.Free (Result);
            return S;
         end;
      end if;
      return "";
   end Find_Engine_On_Path;

   Engine_Path : Unbounded_String :=
      To_Unbounded_String (Find_Engine_On_Path);
   Cfg_Openings_Path  : Unbounded_String := Null_Unbounded_String;
   Cfg_Openings_SHA1  : Unbounded_String := Null_Unbounded_String;
   Cfg_Lichess_Token  : Unbounded_String := Null_Unbounded_String;
   Cfg_Device         : Unbounded_String := To_Unbounded_String ("/dev/ttyACM0");
   Cfg_Time_Ms        : Positive := 1500;
   Cfg_Depth          : Natural  := 0;
   Cfg_N_PV           : Positive := 1;
   Cfg_Unicode        : Boolean  := False;
   Cfg_Speech         : Boolean  := False;
   Cfg_TTS_Model      : Unbounded_String := Null_Unbounded_String;

   Conn   : DGT.Connection.Board_Connection;
   Engine : DGT.Engine.Engine_State;

   function Make_PGN_Path return String is
      Dir : constant String :=
         Ada.Environment_Variables.Value ("HOME") & "/games";
      TS  : String := Ada.Calendar.Formatting.Image (Ada.Calendar.Clock);
   begin
      for I in TS'Range loop
         if TS (I) = ' ' or else TS (I) = ':' then TS (I) := '_'; end if;
      end loop;
      if not Ada.Directories.Exists (Dir) then
         Ada.Directories.Create_Directory (Dir);
      end if;
      return Dir & "/" & TS & ".pgn";
   end Make_PGN_Path;

   PGN_File : Unbounded_String := To_Unbounded_String (Make_PGN_Path);

   Live_PGN_Path : constant String :=
      Ada.Environment_Variables.Value ("HOME") & "/games/live.pgn";

   procedure Save_PGN (G : DGT.Game.Game_State) is
      PGN : constant String := DGT.Game.To_PGN (G);

      procedure Write_To (Path : String) is
         F : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Path);
         Ada.Text_IO.Put (F, PGN);
         Ada.Text_IO.Close (F);
      exception
         when others =>
            Put_Line ("Warning: could not write PGN to " & Path);
      end Write_To;
   begin
      Write_To (To_String (PGN_File));
      Write_To (Live_PGN_Path);
   end Save_PGN;

   --  Decimal image without the leading space of 'Image.
   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin return (if N >= 0 then S (2 .. S'Last) else S); end Img;

   --  Write current board position to the status file without eval data.
   --  Called whenever the position changes outside of a normal move+analysis
   --  cycle (startup, !fen, !newgame, !flip) so display tools stay in sync.
   procedure Write_Position
     (G       : DGT.Game.Game_State;
      Flipped : Boolean)
   is
      F : File_Type;
   begin
      Create (F, Out_File, Display_File_Path);
      Put_Line (F, "move=");
      Put_Line (F, "move_num=0");
      Put_Line (F, "turn=" &
                (if DGT.Game.Active_Color (G) = DGT.Game.White then "White" else "Black"));
      Put_Line (F, "score_cp=0");
      Put_Line (F, "is_mate=0");
      Put_Line (F, "mate_in=0");
      Put_Line (F, "best=");
      Put_Line (F, "pv=");
      Put_Line (F, "status=");
      Put_Line (F, "opening=");
      Put_Line (F, "fen="     & DGT.Game.To_FEN (G));
      Put_Line (F, "flipped=" & (if Flipped then "1" else "0"));
      Close (F);
   exception
      --  Status file is only for the optional display tools; ignore errors.
      when others => null;
   end Write_Position;

   --  Write status fields to Display_File_Path for the Python big-display window.
   --  Score_CP is normalised to White's perspective (positive = White better).
   procedure Write_Display
     (Move_UCI : String;
      Move_Num : Positive;
      Turn     : DGT.Game.Color;
      A        : DGT.Engine.Analysis;
      Status   : String;
      Opening  : String;
      FEN      : String;
      Flipped  : Boolean)
   is
      --  Normalise: Stockfish eval is from side-to-move perspective.
      --  Flip when Black is to move so positive always means White is better.
      White_CP : constant Integer :=
         (if Turn = DGT.Game.White then A.Score_CP else -A.Score_CP);
      F : File_Type;
   begin
      Create (F, Out_File, Display_File_Path);
      Put_Line (F, "move="     & Move_UCI);
      Put_Line (F, "move_num=" & Img (Move_Num));
      Put_Line (F, "turn="     & (if Turn = DGT.Game.White then "White" else "Black"));
      Put_Line (F, "score_cp=" & Img (White_CP));
      Put_Line (F, "is_mate="  & (if A.Is_Mate then "1" else "0"));
      Put_Line (F, "mate_in="  & Img (A.Mate_In));
      Put_Line (F, "best="     & A.Best_Move (1 .. A.Move_Len));
      Put_Line (F, "pv="       & (if A.PV_Len > 0 then A.PV (1 .. A.PV_Len) else ""));
      Put_Line (F, "status="   & Status);
      Put_Line (F, "opening="  & Opening);
      Put_Line (F, "fen="      & FEN);
      Put_Line (F, "flipped="  & (if Flipped then "1" else "0"));
      Close (F);
   exception
      --  Status file is only for the optional display tools; ignore errors.
      when others => null;
   end Write_Display;

   function Format_Duration (D : Duration) return String is
      Total_Ds : constant Natural := Natural (D * 10.0);
      Secs     : constant Natural := Total_Ds / 10;
      Mins     : constant Natural := Secs / 60;
      S        : constant Natural := Secs mod 60;
      Ds       : constant Natural := Total_Ds mod 10;

      function Pad2 (N : Natural) return String is
      begin
         if N < 10 then return "0" & Img (N); else return Img (N); end if;
      end Pad2;
   begin
      if Mins > 0 then
         return Img (Mins) & ":" & Pad2 (S) & "." & Img (Ds);
      else
         return Img (S) & "." & Img (Ds) & "s";
      end if;
   end Format_Duration;

   function Moves_UCI_N (G : DGT.Game.Game_State; N : Natural) return String is
      Buf : String (1 .. 512) := (others => ' ');
      Pos : Natural := 0;
   begin
      for I in 1 .. Natural'Min (N, DGT.Game.Move_Count (G)) loop
         declare
            U : constant String := DGT.Game.Move_UCI (DGT.Game.Get_Move (G, I));
         begin
            if Pos > 0 then Pos := Pos + 1; Buf (Pos) := ' '; end if;
            Buf (Pos + 1 .. Pos + U'Length) := U;
            Pos := Pos + U'Length;
         end;
      end loop;
      return Buf (1 .. Pos);
   end Moves_UCI_N;

   function Moves_UCI (G : DGT.Game.Game_State) return String is
      Buf : String (1 .. 512) := (others => ' ');
      Pos : Natural := 0;
   begin
      for I in 1 .. DGT.Game.Move_Count (G) loop
         declare
            U : constant String := DGT.Game.Move_UCI (DGT.Game.Get_Move (G, I));
         begin
            if Pos > 0 then Pos := Pos + 1; Buf (Pos) := ' '; end if;
            Buf (Pos + 1 .. Pos + U'Length) := U;
            Pos := Pos + U'Length;
         end;
      end loop;
      return Buf (1 .. Pos);
   end Moves_UCI;

   --  Used by !resync: find the single legal move (if any) that turns the
   --  game's current position into Target.  Returns "" if none or more than
   --  one such move exists (ambiguous / not a single-move difference).
   function Find_Recovered_UCI
     (G      : DGT.Game.Game_State;
      Target : DGT.Board.Board_State) return String
   is
      Trial     : DGT.Game.Game_State := G;
      Matches   : Natural := 0;
      Found     : String (1 .. 5);
      Found_Len : Natural := 0;

      procedure Try (Cand : String) is
      begin
         if DGT.Game.Apply_UCI (Trial, Cand) then
            if DGT.Game.Current_Board (Trial) = Target then
               Matches           := Matches + 1;
               Found_Len         := Cand'Length;
               Found (1 .. Found_Len) := Cand;
            end if;
            DGT.Game.Undo (Trial);
         end if;
      end Try;

      --  Try one destination (Row/Col, 0 .. 7) reached from From, adding
      --  promotion suffixes when Row lands on the back rank.
      procedure Try_To
        (From       : DGT.Board.Square_Index;
         Row, Col    : Integer;
         Promo_Rank : Boolean)
      is
      begin
         if Row in 0 .. 7 and then Col in 0 .. 7 then
            declare
               To   : constant DGT.Board.Square_Index :=
                  DGT.Board.Square_Index (Row * 8 + Col);
               Base : constant String :=
                  DGT.Board.Square_Name (From) & DGT.Board.Square_Name (To);
            begin
               if Promo_Rank then
                  Try (Base & 'q');
                  Try (Base & 'r');
                  Try (Base & 'b');
                  Try (Base & 'n');
               else
                  Try (Base);
               end if;
            end;
         end if;
      end Try_To;
   begin
      for From in DGT.Board.Square_Index loop
         declare
            P : constant DGT.Protocol.Piece_Code :=
               DGT.Game.Current_Board (G).Squares (From);
            Is_Mine : constant Boolean :=
               (if DGT.Game.Active_Color (G) = DGT.Game.White
                then P in DGT.Protocol.WPawn | DGT.Protocol.WRook
                        | DGT.Protocol.WKnight | DGT.Protocol.WBishop
                        | DGT.Protocol.WKing | DGT.Protocol.WQueen
                else P in DGT.Protocol.BPawn | DGT.Protocol.BRook
                        | DGT.Protocol.BKnight | DGT.Protocol.BBishop
                        | DGT.Protocol.BKing | DGT.Protocol.BQueen);
         begin
            if Is_Mine
               and then P in DGT.Protocol.WPawn | DGT.Protocol.BPawn
            then
               --  Pawns: only physically reachable squares.  A blind
               --  64-square sweep can hand Apply_UCI's en-passant geometry
               --  (which assumes an adjacent diagonal) a far-away target
               --  and overflow its capture-square computation.
               declare
                  Row       : constant Integer := Integer (From) / 8;
                  Col       : constant Integer := Integer (From) mod 8;
                  Fwd       : constant Integer :=
                     (if P = DGT.Protocol.WPawn then -1 else 1);
                  Start_Row : constant Integer :=
                     (if P = DGT.Protocol.WPawn then 6 else 1);
                  One_Row   : constant Integer := Row + Fwd;
                  Promo     : constant Boolean :=
                     One_Row = 0 or else One_Row = 7;
               begin
                  Try_To (From, One_Row, Col,     Promo);
                  Try_To (From, One_Row, Col - 1, Promo);
                  Try_To (From, One_Row, Col + 1, Promo);
                  if Row = Start_Row then
                     Try_To (From, Row + 2 * Fwd, Col, False);
                  end if;
               end;
            elsif Is_Mine then
               for To in DGT.Board.Square_Index loop
                  if To /= From then
                     Try (DGT.Board.Square_Name (From)
                          & DGT.Board.Square_Name (To));
                  end if;
               end loop;
            end if;
         end;
      end loop;
      if Matches = 1 then
         return Found (1 .. Found_Len);
      else
         return "";
      end if;
   end Find_Recovered_UCI;

   procedure Print_Move_Header (M : DGT.Game.Move; MV_Num : Natural) is
      Num_Img : constant String := Natural'Image (MV_Num);
   begin
      if M.MV_Color = DGT.Game.White then
         Put (Num_Img (2 .. Num_Img'Last) & ". ");
      else
         Put (Num_Img (2 .. Num_Img'Last) & "... ");
      end if;
      Put_Line (DGT.Game.Move_SAN (M)
                & "  [" & DGT.Game.Move_UCI (M) & "]");
   end Print_Move_Header;

   --  Command summary, printed at startup and on !help.
   procedure Print_Help is
   begin
      Put_Line ("Commands:");
      Put_Line ("  Game:     !undo  !resign  !draw  !pgn  !newgame[w/b]  !comment TEXT");
      Put_Line ("            !resync  !resync force  -- re-read board, recover missed move");
      Put_Line ("  Players:  !white/!black NAME  !fen FEN");
      Put_Line ("  Board:    !flip  !unicode  !moves  !book  !display  !webdisplay  !boarddisplay");
      Put_Line ("  Engine:   !analyse/!eval  !hint  !compare  !review");
      Put_Line ("            !time N  !depth N  !multipv N");
      Put_Line ("  Clock:    !tc T+I  (T=minutes, I=increment secs)  !tc off");
      Put_Line ("  File:     !load FILE  !forward[N]  !back[N]  !save  !upload");
      Put_Line ("  Train:    !train  !train off  !train file FILE");
      Put_Line ("            !train strict [off]  -- master games only (2500+)");
      Put_Line ("            !train opening       -- list all openings in book");
      Put_Line ("            !train opening NAME  -- start from named opening");
      Put_Line ("  Toggle:   !speech  (piper/espeak-ng; also: !quiet)");
      Put_Line (String'(1 .. 55 => '-'));
   end Print_Help;

   --  Parse a natural integer (0 is valid).
   function Parse_Nat (S : String) return Natural is
      V : Natural := 0;
   begin
      for C of S loop
         if C in '0' .. '9' then
            V := V * 10 + Character'Pos (C) - Character'Pos ('0');
         end if;
      end loop;
      return V;
   end Parse_Nat;

   --  Parse a positive integer from S; return Default on failure/zero.
   function Parse_Pos (S : String; Default : Positive) return Positive is
      V : Natural := 0;
   begin
      for C of S loop
         if C in '0' .. '9' then
            V := V * 10 + Character'Pos (C) - Character'Pos ('0');
         end if;
      end loop;
      return (if V > 0 then V else Default);
   end Parse_Pos;

   procedure Print_Moves (G : DGT.Game.Game_State) is
      N : constant Natural := DGT.Game.Move_Count (G);

      function Pad (S : String; W : Natural) return String is
         R : String (1 .. W) := (others => ' ');
         L : constant Natural := Natural'Min (S'Length, W);
      begin
         R (1 .. L) := S (S'First .. S'First + L - 1);
         return R;
      end Pad;

      I : Positive := 1;
   begin
      if N = 0 then Put_Line ("No moves yet."); return; end if;
      New_Line;
      while I <= N loop
         declare
            M : constant DGT.Game.Move := DGT.Game.Get_Move (G, I);
         begin
            if M.MV_Color = DGT.Game.White then
               Put (Pad (Img (M.MV_Nr) & ".", 4) & Pad (DGT.Game.Move_SAN (M), 9));
               if I + 1 <= N then
                  Put_Line (DGT.Game.Move_SAN (DGT.Game.Get_Move (G, I + 1)));
                  I := I + 2;
               else
                  New_Line; I := I + 1;
               end if;
            else
               Put_Line (Pad (Img (M.MV_Nr) & "...", 13)
                         & DGT.Game.Move_SAN (M));
               I := I + 1;
            end if;
         end;
      end loop;
      New_Line;
   end Print_Moves;

   --  Rebuild from Start applying the first N moves of Src, return FEN.
   function FEN_At (Src       : DGT.Game.Game_State;
                    Start     : String;
                    N         : Natural) return String is
      G : DGT.Game.Game_State := DGT.Game.From_FEN (Start);
   begin
      for I in 1 .. N loop
         declare
            UCI : constant String :=
               DGT.Game.Move_UCI (DGT.Game.Get_Move (Src, I));
         begin
            if not DGT.Game.Apply_UCI (G, UCI) then exit; end if;
         end;
      end loop;
      return DGT.Game.To_FEN (G);
   end FEN_At;

   procedure Announce (Text : String) is
      use type GNAT.OS_Lib.String_Access;
      Model : constant String := To_String (Cfg_TTS_Model);
      PID   : GNAT.OS_Lib.Process_Id;
      pragma Unreferenced (PID);
   begin
      if Model'Length > 0 then
         declare
            Sh    : GNAT.OS_Lib.String_Access :=
               GNAT.OS_Lib.Locate_Exec_On_Path ("sh");
            Piper : GNAT.OS_Lib.String_Access :=
               GNAT.OS_Lib.Locate_Exec_On_Path ("piper");
         begin
            if Sh /= null and then Piper /= null then
               declare
                  Cmd  : constant String :=
                     "echo '" & Text & "' | " & Piper.all & " -m " & Model
                     & " --output-raw 2>/dev/null | aplay -r 22050 -f S16_LE -t raw - 2>/dev/null";
                  Args : GNAT.OS_Lib.Argument_List :=
                     (new String'("-c"), new String'(Cmd));
               begin
                  PID := GNAT.OS_Lib.Non_Blocking_Spawn (Sh.all, Args);
                  for A of Args loop
                     GNAT.OS_Lib.Free (A);
                  end loop;
               end;
            end if;
            GNAT.OS_Lib.Free (Sh);
            GNAT.OS_Lib.Free (Piper);
         end;
      else
         declare
            Esp : GNAT.OS_Lib.String_Access :=
               GNAT.OS_Lib.Locate_Exec_On_Path ("espeak-ng");
         begin
            if Esp = null then
               Esp := GNAT.OS_Lib.Locate_Exec_On_Path ("espeak");
            end if;
            if Esp /= null then
               declare
                  Args : GNAT.OS_Lib.Argument_List :=
                     (1 => new String'(Text));
               begin
                  PID := GNAT.OS_Lib.Non_Blocking_Spawn (Esp.all, Args);
                  for A of Args loop
                     GNAT.OS_Lib.Free (A);
                  end loop;
               end;
               GNAT.OS_Lib.Free (Esp);
            end if;
         end;
      end if;
   exception
      --  Speech is best-effort: never let TTS problems disturb the game.
      when others => null;
   end Announce;

   function SAN_To_Speech (M : DGT.Game.Move) return String is
      SAN  : constant String := DGT.Game.Move_SAN (M);
      Slen : Natural := SAN'Length;

      function Rank_Word (C : Character) return String is
      begin
         case C is
            when '1' => return "one";   when '2' => return "two";
            when '3' => return "three"; when '4' => return "four";
            when '5' => return "five";  when '6' => return "six";
            when '7' => return "seven"; when '8' => return "eight";
            when others => return "";
         end case;
      end Rank_Word;
   begin
      while Slen > 0 and then SAN (SAN'First + Slen - 1) in '+' | '#' loop
         Slen := Slen - 1;
      end loop;
      declare
         S   : constant String := SAN (SAN'First .. SAN'First + Slen - 1);
         Suf : constant String :=
            (if M.Is_Mate  then ", checkmate"
             elsif M.Is_Check then ", check"
             else "");
      begin
         if S = "O-O-O" or else S = "0-0-0" then
            return "queenside castle" & Suf;
         elsif S'Length >= 3 and then S (S'First .. S'First + 2) = "O-O" then
            return "kingside castle" & Suf;
         end if;
         declare
            Buf : String (1 .. 80) := (others => ' ');
            Pos : Natural := 0;
            I   : Natural := S'First;

            procedure Add (T : String) is
            begin
               if Pos > 0 and then Buf (Pos) /= ' ' then
                  Pos := Pos + 1; Buf (Pos) := ' ';
               end if;
               Buf (Pos + 1 .. Pos + T'Length) := T;
               Pos := Pos + T'Length;
            end Add;
         begin
            if I <= S'Last and then S (I) in 'N'|'B'|'R'|'Q'|'K' then
               case S (I) is
                  when 'N' => Add ("knight");  when 'B' => Add ("bishop");
                  when 'R' => Add ("rook");    when 'Q' => Add ("queen");
                  when 'K' => Add ("king");    when others => null;
               end case;
               I := I + 1;
            end if;
            while I <= S'Last loop
               case S (I) is
                  when 'x'      => Add ("takes");
                  when '='      => Add ("promotes to");
                  when 'a'..'h' => Add (S (I .. I));
                  when '1'..'8' => Add (Rank_Word (S (I)));
                  when 'N' => Add ("knight"); when 'B' => Add ("bishop");
                  when 'R' => Add ("rook");   when 'Q' => Add ("queen");
                  when others => null;
               end case;
               I := I + 1;
            end loop;
            if Suf'Length > 0 then Add (Suf (Suf'First + 2 .. Suf'Last)); end if;
            return Buf (1 .. Pos);
         end;
      end;
   end SAN_To_Speech;

   function Eval_Bar (A : DGT.Engine.Analysis) return String is
      Bar_W   : constant := 20;
      Full_B  : constant String (1 .. 3) :=
         (Character'Val (16#E2#), Character'Val (16#96#), Character'Val (16#88#));
      Empty_B : constant String (1 .. 3) :=
         (Character'Val (16#E2#), Character'Val (16#96#), Character'Val (16#91#));
      Filled  : Natural;
      Result  : String (1 .. Bar_W * 3 + 2);
      Pos     : Natural := 1;
   begin
      if A.Move_Len = 0 then return ""; end if;
      Result (1) := '[';
      if A.Is_Mate then
         Filled := (if A.Mate_In > 0 then Bar_W else 0);
      else
         Filled := Natural (
            Integer'Max (0, Integer'Min (Bar_W,
               (A.Score_CP + 500) * Bar_W / 1000)));
      end if;
      for I in 1 .. Bar_W loop
         if I <= Filled then Result (Pos + 1 .. Pos + 3) := Full_B;
         else                Result (Pos + 1 .. Pos + 3) := Empty_B;
         end if;
         Pos := Pos + 3;
      end loop;
      Result (Pos + 1) := ']';
      return Result (1 .. Pos + 1);
   end Eval_Bar;

   function Format_Clock (D : Duration) return String is
      S    : constant Natural := Natural (D);
      Mins : constant Natural := S / 60;
      Secs : constant Natural := S mod 60;
   begin
      return Img (Mins) & ":" & (if Secs < 10 then "0" else "") & Img (Secs);
   end Format_Clock;

   procedure Upload_To_Lichess is
      use type GNAT.OS_Lib.String_Access;
      Tmp  : constant String := "/tmp/dgt_lichess.json";
      Curl : GNAT.OS_Lib.String_Access :=
         GNAT.OS_Lib.Locate_Exec_On_Path ("curl");
      Args : constant GNAT.OS_Lib.Argument_List :=
         (new String'("-s"),
          new String'("-o"), new String'(Tmp),
          new String'("-F"),
          new String'("pgn=@" & To_String (PGN_File)),
          new String'("https://lichess.org/api/import"));
      OK   : Boolean;
   begin
      if Curl = null then
         Put_Line ("curl not found  --  install curl to use !upload");
         return;
      end if;
      Put_Line ("Uploading to Lichess...");
      GNAT.OS_Lib.Spawn (Curl.all, Args, OK);
      GNAT.OS_Lib.Free (Curl);
      if not OK then Put_Line ("curl failed."); return; end if;
      --  Parse URL from JSON response
      declare
         F   : Ada.Text_IO.File_Type;
         Buf : String (1 .. 512) := (others => ' ');
         Last : Natural := 0;
      begin
         Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Tmp);
         Ada.Text_IO.Get_Line (F, Buf, Last);
         Ada.Text_IO.Close (F);
         declare
            S       : constant String := Buf (1 .. Last);
            URL_Tag : constant String := """url"":""";
         begin
            for I in S'First .. S'Last - URL_Tag'Length + 1 loop
               if S (I .. I + URL_Tag'Length - 1) = URL_Tag then
                  declare
                     P : constant Natural := I + URL_Tag'Length;
                     E : Natural          := P;
                  begin
                     while E <= S'Last and then S (E) /= '"' loop
                        E := E + 1;
                     end loop;
                     Put_Line ("Lichess: " & S (P .. E - 1));
                     return;
                  end;
               end if;
            end loop;
            Put_Line ("Response: " & S);
         end;
      exception
         when others => Put_Line ("Could not read curl response.");
      end;
   exception
      when others => Put_Line ("Upload failed.");
   end Upload_To_Lichess;

   --  ---- Config file (~/.chesslinkrc) ----

   procedure Load_Config is
      F    : Ada.Text_IO.File_Type;
      Line : String (1 .. 256);
      Last : Natural;
   begin
      if not Ada.Directories.Exists (Config_Path) then return; end if;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Config_Path);
      while not Ada.Text_IO.End_Of_File (F) loop
         Ada.Text_IO.Get_Line (F, Line, Last);
         declare
            L          : constant String := Line (1 .. Last);
            E          : Natural         := 0;
            Is_Comment : Boolean         := False;
         begin
            --  Skip comment lines (first non-space character is '#').
            for I in L'Range loop
               if L (I) /= ' ' and then L (I) /= ASCII.HT then
                  Is_Comment := L (I) = '#';
                  exit;
               end if;
            end loop;
            if not Is_Comment then
            for I in L'Range loop
               if L (I) = '=' then E := I; exit; end if;
            end loop;
            if E > 1 then
               declare
                  Key : constant String := L (L'First .. E - 1);
                  Val : constant String := L (E + 1 .. L'Last);
               begin
                  if Key = "device" then
                     Cfg_Device := To_Unbounded_String (Val);
                  elsif Key = "openings" then
                     Cfg_Openings_Path := To_Unbounded_String (Val);
                  elsif Key = "openings_sha1" then
                     Cfg_Openings_SHA1 := To_Unbounded_String (Val);
                  elsif Key = "lichess_token" then
                     Cfg_Lichess_Token := To_Unbounded_String (Val);
                  elsif Key = "engine" then
                     declare
                        V : constant String :=
                           (if Val'Length > 0
                               and then Val (Val'Last) in ASCII.CR | ' '
                            then Val (Val'First .. Val'Last - 1)
                            else Val);
                     begin
                        Engine_Path := To_Unbounded_String (V);
                     end;
                  elsif Key = "time" then
                     Cfg_Time_Ms := Parse_Pos (Val, 1500);
                  elsif Key = "depth" then
                     Cfg_Depth := Parse_Nat (Val);
                  elsif Key = "multipv" then
                     Cfg_N_PV := Natural'Min (Parse_Pos (Val, 1), DGT.Engine.Max_PV);
                  elsif Key = "unicode" then
                     Cfg_Unicode := Val'Length > 0 and then Val (Val'First) = '1';
                  elsif Key = "speech" then
                     Cfg_Speech := Val'Length > 0 and then Val (Val'First) = '1';
                  elsif Key = "tts_model" then
                     Cfg_TTS_Model := To_Unbounded_String (Val);
                  end if;
               end;
            end if;
            end if; --  not Is_Comment
         end;
      end loop;
      Ada.Text_IO.Close (F);
   exception
      --  A missing or malformed config file is normal: defaults apply.
      when others => null;
   end Load_Config;

   procedure Save_Config
     (Time_Ms : Positive; Depth : Natural; N_PV : Positive;
      Unicode : Boolean; Speech : Boolean)
   is
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Config_Path);
      Ada.Text_IO.Put_Line (F, "device="        & To_String (Cfg_Device));
      Ada.Text_IO.Put_Line (F, "openings="      & To_String (Cfg_Openings_Path));
      Ada.Text_IO.Put_Line (F, "openings_sha1=" & To_String (Cfg_Openings_SHA1));
      Ada.Text_IO.Put_Line (F, "engine="        & To_String (Engine_Path));
      Ada.Text_IO.Put_Line (F, "lichess_token=" & To_String (Cfg_Lichess_Token));
      Ada.Text_IO.Put_Line (F, "time="    & Img (Time_Ms));
      Ada.Text_IO.Put_Line (F, "depth="   & Img (Depth));
      Ada.Text_IO.Put_Line (F, "multipv=" & Img (N_PV));
      Ada.Text_IO.Put_Line (F, "unicode=" & (if Unicode then "1" else "0"));
      Ada.Text_IO.Put_Line (F, "speech="     & (if Speech  then "1" else "0"));
      Ada.Text_IO.Put_Line (F, "tts_model=" & To_String (Cfg_TTS_Model));
      Ada.Text_IO.Close (F);
   exception
      when others =>
         Put_Line ("Warning: could not write config to " & Config_Path);
   end Save_Config;

   --  ---- Curl helper for Lichess APIs ----

   --  Runs curl with URL, optional Bearer token, returns response content.
   function Curl_Get (URL : String; Token : String := "") return String is
      use type GNAT.OS_Lib.String_Access;
      Tmp  : constant String           := "/tmp/dgt_api.json";
      Curl : GNAT.OS_Lib.String_Access := GNAT.OS_Lib.Locate_Exec_On_Path ("curl");
      OK   : Boolean;
      Buf  : String (1 .. 65536) := (others => ' ');
      Last : Natural := 0;
   begin
      if Curl = null then return ""; end if;
      declare
         Args : GNAT.OS_Lib.Argument_List :=
            (if Token'Length > 0
             then (new String'("-s"), new String'("--max-time"), new String'("8"),
                   new String'("-H"), new String'("Authorization: Bearer " & Token),
                   new String'("-o"), new String'(Tmp), new String'(URL))
             else (new String'("-s"), new String'("--max-time"), new String'("8"),
                   new String'("-o"), new String'(Tmp), new String'(URL)));
      begin
         GNAT.OS_Lib.Spawn (Curl.all, Args, OK);
         for A of Args loop
            GNAT.OS_Lib.Free (A);
         end loop;
      end;
      GNAT.OS_Lib.Free (Curl);
      if not OK then return ""; end if;
      declare
         F : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Tmp);
         Ada.Text_IO.Get_Line (F, Buf, Last);
         Ada.Text_IO.Close (F);
      exception
         --  Unreadable response file -> return ""; callers treat that
         --  as "no response".
         when others => null;
      end;
      return Buf (1 .. Last);
   end Curl_Get;

   function URL_Encode (S : String) return String is
      R   : String (1 .. S'Length * 3);
      Pos : Natural := 0;
   begin
      for C of S loop
         if C = ' ' then
            Pos := Pos + 1; R (Pos) := '%';
            Pos := Pos + 1; R (Pos) := '2';
            Pos := Pos + 1; R (Pos) := '0';
         elsif C = '/' then
            Pos := Pos + 1; R (Pos) := '%';
            Pos := Pos + 1; R (Pos) := '2';
            Pos := Pos + 1; R (Pos) := 'F';
         elsif C = '+' then
            Pos := Pos + 1; R (Pos) := '%';
            Pos := Pos + 1; R (Pos) := '2';
            Pos := Pos + 1; R (Pos) := 'B';
         else
            Pos := Pos + 1; R (Pos) := C;
         end if;
      end loop;
      return R (1 .. Pos);
   end URL_Encode;

   --  ---- Minimal JSON scanners for the Lichess API responses ----
   --
   --  Not a JSON parser: these rely on the compact fixed layout of the
   --  Lichess responses (no whitespace, no escaped quotes in the values
   --  we read).

   --  Index just after the first occurrence of Pat at or after From,
   --  or 0 if Pat does not occur (or From is 0).
   function Skip_Past
     (Resp : String; Pat : String; From : Natural) return Natural is
   begin
      if From > 0 then
         for I in From .. Resp'Last - Pat'Length + 1 loop
            if Resp (I .. I + Pat'Length - 1) = Pat then
               return I + Pat'Length;
            end if;
         end loop;
      end if;
      return 0;
   end Skip_Past;

   --  Value of the first "Key":"value" pair at or after From.  After is
   --  set just past the closing quote, or to 0 (and "" returned) if the
   --  key is not found.
   function JSON_Str
     (Resp  : String;
      Key   : String;
      From  : Natural;
      After : out Natural) return String
   is
      S : constant Natural :=
         Skip_Past (Resp, '"' & Key & """:""", From);
      E : Natural := S;
   begin
      if S = 0 then
         After := 0;
         return "";
      end if;
      while E <= Resp'Last and then Resp (E) /= '"' loop
         E := E + 1;
      end loop;
      After := E + 1;
      return Resp (S .. E - 1);
   end JSON_Str;

   --  Value of the first "Key":number pair at or after From, or 0 if the
   --  key is absent or its value is not numeric (e.g. null).
   function JSON_Num
     (Resp : String; Key : String; From : Natural) return Long_Integer
   is
      P   : Natural := Skip_Past (Resp, '"' & Key & """:", From);
      Neg : Boolean := False;
      N   : Long_Integer := 0;
   begin
      if P = 0 then
         return 0;
      end if;
      if P <= Resp'Last and then Resp (P) = '-' then
         Neg := True;
         P   := P + 1;
      end if;
      while P <= Resp'Last and then Resp (P) in '0' .. '9' loop
         N := N * 10 + Character'Pos (Resp (P)) - Character'Pos ('0');
         P := P + 1;
      end loop;
      return (if Neg then -N else N);
   end JSON_Num;

   --  ---- Loaded game (for !load / !forward / !back) ----

   Max_Loaded : constant := 512;
   type SAN_Array is array (1 .. Max_Loaded) of Unbounded_String;

   Loaded_Moves  : SAN_Array  := (others => Null_Unbounded_String);
   Loaded_Count  : Natural    := 0;
   Loaded_Pos    : Natural    := 0;
   Loaded_FEN    : Unbounded_String := Null_Unbounded_String;

   --  Parse a PGN file: extract [FEN] header and list of SAN tokens.
   procedure Load_PGN_File (Path : String) is
      F     : Ada.Text_IO.File_Type;
      Line  : String (1 .. 256);
      Last  : Natural;

      procedure Add_Move (S : String) is
      begin
         if Loaded_Count < Max_Loaded then
            Loaded_Count := Loaded_Count + 1;
            Loaded_Moves (Loaded_Count) := To_Unbounded_String (S);
         end if;
      end Add_Move;

      In_Comment : Boolean := False;

      procedure Process_Token (T : String) is
      begin
         if T'Length = 0 then return; end if;
         --  Skip move numbers (digits followed by dots)
         if T (T'First) in '0' .. '9' then return; end if;
         --  Skip result markers
         if T = "1-0" or else T = "0-1" or else T = "1/2-1/2"
            or else T = "*"
         then return; end if;
         --  Skip NAGs
         if T (T'First) = '$' then return; end if;
         Add_Move (T);
      end Process_Token;

   begin
      Loaded_Count := 0;
      Loaded_Pos   := 0;
      Loaded_FEN   := Null_Unbounded_String;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (F) loop
         Ada.Text_IO.Get_Line (F, Line, Last);
         declare
            L : constant String := Line (1 .. Last);
         begin
            --  Header lines
            if Last >= 1 and then L (L'First) = '[' then
               --  Check for [FEN "..."]
               declare
                  FEN_Tag : constant String := "[FEN """;
               begin
                  if L'Length > FEN_Tag'Length
                     and then L (L'First .. L'First + FEN_Tag'Length - 1) = FEN_Tag
                  then
                     declare
                        Start : constant Natural := L'First + FEN_Tag'Length;
                        Fin   : Natural := L'Last;
                     begin
                        while Fin >= Start and then L (Fin) /= '"' loop
                           Fin := Fin - 1;
                        end loop;
                        if Fin > Start then
                           Loaded_FEN := To_Unbounded_String (L (Start .. Fin - 1));
                        end if;
                     end;
                  end if;
               end;
            else
               --  Movetext line: tokenize and process
               declare
                  I     : Natural := L'First;
                  Start : Natural;
               begin
                  while I <= L'Last loop
                     if In_Comment then
                        if L (I) = '}' then In_Comment := False; end if;
                        I := I + 1;
                     elsif L (I) = '{' then
                        In_Comment := True; I := I + 1;
                     elsif L (I) = '(' then
                        --  Skip variation to matching ')'
                        declare Depth : Natural := 1; begin
                           I := I + 1;
                           while I <= L'Last and then Depth > 0 loop
                              if L (I) = '(' then Depth := Depth + 1;
                              elsif L (I) = ')' then Depth := Depth - 1;
                              end if;
                              I := I + 1;
                           end loop;
                        end;
                     elsif L (I) = ' ' or else L (I) = ASCII.HT then
                        I := I + 1;
                     else
                        Start := I;
                        while I <= L'Last
                           and then L (I) /= ' '
                           and then L (I) /= ASCII.HT
                           and then L (I) /= '{'
                           and then L (I) /= '('
                        loop I := I + 1; end loop;
                        Process_Token (L (Start .. I - 1));
                     end if;
                  end loop;
               end;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (F);
   exception
      --  Truncated/odd PGN just yields fewer moves; callers report
      --  "no moves found" when Loaded_Count stays 0.
      when others => null;
   end Load_PGN_File;

   --  ---- Interactive command channel (stdin reader task) ----

   protected Pending_Cmd is
      entry     Wait_Ready;
      procedure Enable;
      procedure Set   (S : String);
      procedure Poll  (S : out String; L : out Natural; Found : out Boolean);
   private
      Buf     : String (1 .. 256) := (others => ' ');
      Len     : Natural  := 0;
      Ready   : Boolean  := False;
      --  Gate: Stdin_Reader blocks here until main task finishes initial prompts
      Go      : Boolean  := False;
   end Pending_Cmd;

   protected body Pending_Cmd is
      entry Wait_Ready when Go is
      begin null; end Wait_Ready;
      procedure Enable is begin Go := True; end Enable;
      procedure Set (S : String) is
         N : constant Natural := Natural'Min (S'Length, Buf'Length);
      begin
         Buf (1 .. N) := S (S'First .. S'First + N - 1);
         Len   := N;
         Ready := True;
      end Set;
      procedure Poll (S : out String; L : out Natural; Found : out Boolean) is
      begin
         Found := Ready;
         if Ready then
            L := Natural'Min (Len, S'Length);
            S (S'First .. S'First + L - 1) := Buf (1 .. L);
            Ready := False;
            Len   := 0;
         else
            L := 0;
         end if;
      end Poll;
   end Pending_Cmd;

   task Stdin_Reader;
   task body Stdin_Reader is
      Line : String (1 .. 256);
      Last : Natural;
   begin
      --  Wait until main task has finished all blocking prompts (e.g. "Whose
      --  turn?") before competing for stdin.
      Pending_Cmd.Wait_Ready;
      loop
         Ada.Text_IO.Get_Line (Line, Last);
         Pending_Cmd.Set (Line (1 .. Last));
      end loop;
   exception
      when Ada.IO_Exceptions.End_Error | Ada.IO_Exceptions.Status_Error => null;
      --  A task must not propagate: any other failure just ends command input.
      when others => null;
   end Stdin_Reader;

begin
   --  ---- Connect to board ----
   Load_Config;
   if Length (Cfg_Openings_Path) > 0 then
      DGT.Openings.Load (To_String (Cfg_Openings_Path));
      declare
         Actual   : constant String := DGT.Openings.Hash_File (To_String (Cfg_Openings_Path));
         Expected : constant String := To_String (Cfg_Openings_SHA1);
      begin
         if Expected'Length = 0 then
            Put_Line ("Warning: opening book loaded but SHA-1 not configured.");
            Put_Line ("  Add to ~/.chesslinkrc:  openings_sha1=" & Actual);
         elsif Actual /= Expected then
            Put_Line ("Warning: opening book SHA-1 mismatch  --  file may have been modified!");
            Put_Line ("  Expected: " & Expected);
            Put_Line ("  Got:      " & Actual);
         else
            Put_Line ("Opening book verified OK.");
         end if;
      end;
   end if;
   --  Command-line argument overrides config: chesslink [device]
   if Ada.Command_Line.Argument_Count >= 1 then
      Cfg_Device := To_Unbounded_String (Ada.Command_Line.Argument (1));
   end if;

   if Ada.Directories.Exists (Display_File_Path) then
      Ada.Directories.Delete_File (Display_File_Path);
   end if;
   Put_Line ("Connecting to DGT board on " & To_String (Cfg_Device) & "...");
   DGT.Connection.Open (Conn, To_String (Cfg_Device));
   Put_Line ("Port open. Resetting...");
   DGT.Connection.Send_Reset (Conn);

   Put ("Firmware: ");
   Put_Line (DGT.Connection.Get_Version (Conn));

   --  ---- Read initial board position ----
   Put_Line ("Reading board...");
   declare
      B      : constant DGT.Board.Board_State := DGT.Connection.Get_Board (Conn);
      Active : DGT.Game.Color := DGT.Game.White;
      Game   : DGT.Game.Game_State := DGT.Game.New_Game (B, Active);
      White_Elapsed   : Duration          := 0.0;
      Black_Elapsed   : Duration          := 0.0;
      Last_Move_Clock : Ada.Calendar.Time := Ada.Calendar.Clock;
      Board_Flipped   : Boolean           := False;
      Engine_Time_Ms  : Positive          := Cfg_Time_Ms;
      Engine_Depth    : Natural           := Cfg_Depth;
      Engine_N_PV     : Positive          := Cfg_N_PV;
      Announce_On     : Boolean           := Cfg_Speech;
      Use_Unicode     : Boolean           := Cfg_Unicode;
      Training_Mode   : Boolean           := False;
      Training_File   : Boolean           := False;
      Training_Strict : Boolean           := False;
      Start_FEN       : Unbounded_String  :=
         To_Unbounded_String (DGT.Game.To_FEN (Game));
      TC_Base_Secs    : Natural           := 0;
      TC_Incr_Secs    : Natural           := 0;
      White_Remaining : Duration          := 0.0;
      Black_Remaining : Duration          := 0.0;

      --  Opening browser state
      type Browse_Rec is record
         ECO   : Unbounded_String;
         Name  : Unbounded_String;
         Moves : Unbounded_String;
      end record;
      package Browse_Vectors is new Ada.Containers.Vectors
        (Index_Type   => Positive,
         Element_Type => Browse_Rec);
      Browse_Vec    : Browse_Vectors.Vector;
      Browse_Mode   : Boolean          := False;
      Browse_Page   : Positive         := 1;
      Browse_Filter : Unbounded_String := Null_Unbounded_String;

      Browse_Page_Size : constant Positive := 20;

      procedure Setup_Opening_From_UCI (UCI_Mvs : String; Label : String) is
         Setup_G : DGT.Game.Game_State :=
            DGT.Game.New_Game
              (DGT.Connection.Get_Board_During_Updates (Conn),
               DGT.Game.White);
         Pos : Natural := UCI_Mvs'First;
      begin
         while Pos <= UCI_Mvs'Last loop
            declare
               Next : Natural := Pos;
            begin
               while Next <= UCI_Mvs'Last
                  and then UCI_Mvs (Next) /= ' '
               loop Next := Next + 1; end loop;
               if not DGT.Game.Apply_UCI
                  (Setup_G, UCI_Mvs (Pos .. Next - 1))
               then exit; end if;
               Pos := Next + 1;
            end;
         end loop;
         Game          := Setup_G;
         Start_FEN     := To_Unbounded_String (DGT.Game.To_FEN (Game));
         Training_Mode := True;
         Training_File := False;
         New_Line;
         Put_Line ("=== Opening: " & Label & " ===");
         DGT.Board.Print_Board
           (DGT.Game.Current_Board (Game), Board_Flipped, Use_Unicode);
         Put_Line ("FEN: " & DGT.Game.To_FEN (Game));
         Put_Line ("Set up this position on the board, then play on.");
         Browse_Mode := False;
      end Setup_Opening_From_UCI;

      procedure Populate_Browse (Filter : String) is
         procedure Collect (ECO : String; Name : String; Moves : String) is
         begin
            Browse_Vec.Append (Browse_Rec'(
               ECO   => To_Unbounded_String (ECO),
               Name  => To_Unbounded_String (Name),
               Moves => To_Unbounded_String (Moves)));
         end Collect;
      begin
         Browse_Vec.Clear;
         DGT.Openings.For_Each_Opening_Full (Collect'Access, Filter);
      end Populate_Browse;

      procedure Print_Browse_Page is
         use Ada.Containers;
         Total : constant Natural  := Natural (Browse_Vec.Length);
         Pages : constant Positive :=
            Positive'Max (1, (Total + Browse_Page_Size - 1) / Browse_Page_Size);
         First : constant Natural  := (Browse_Page - 1) * Browse_Page_Size + 1;
         Last  : constant Natural  :=
            Natural'Min (First + Browse_Page_Size - 1, Total);
      begin
         New_Line;
         Put ("Openings - page " & Img (Browse_Page) & "/" & Img (Pages)
            & "  (" & Img (Total) & " entries)");
         if Length (Browse_Filter) > 0 then
            Put ("  [filter: """ & To_String (Browse_Filter) & """]");
         end if;
         New_Line;
         for I in First .. Last loop
            declare
               E   : constant Browse_Rec := Browse_Vec.Element (I);
               Num : constant String     := Img (I - First + 1);
            begin
               Put_Line ((if Num'Length = 1 then "  " else " ") & Num & ". "
                  & To_String (E.ECO) & "  " & To_String (E.Name));
            end;
         end loop;
         Put_Line ("  > number=select  n=next  p=prev  q=quit"
            & "  or text=filter");
      end Print_Browse_Page;

   begin
      DGT.Board.Print_Board (B, Board_Flipped, Use_Unicode);
      Put_Line ("FEN: " & DGT.Game.To_FEN (Game));

      if DGT.Game.Is_Start_Position (B) then
         Put_Line ("Standard starting position detected -- White to move.");
      else
         Put ("Whose turn is it? [w/b]: ");
         declare
            Input : constant String := Get_Line;
         begin
            if Input'Length > 0 and then Input (Input'First) = 'b' then
               Active := DGT.Game.Black;
               Game   := DGT.Game.New_Game (B, Active);
            end if;
         end;
      end if;
      --  All blocking stdin prompts done - let Stdin_Reader take over stdin.
      Pending_Cmd.Enable;

      Write_Position (Game, Board_Flipped);

      --  ---- Start UCI engine ----
      Put ("Starting engine... ");
      if not Ada.Directories.Exists (To_String (Engine_Path)) then
         Put_Line ("not found.");
         Put_Line ("  Engine path: " & To_String (Engine_Path));
         Put_Line ("  Set 'engine=/path/to/engine' in " & Config_Path);
      else
         DGT.Engine.Start (Engine, To_String (Engine_Path));
         if DGT.Engine.Is_Running (Engine) then
            Put_Line (DGT.Engine.Engine_Name (Engine) & " ready.");
         else
            Put_Line ("failed to start.");
            Put_Line ("  Engine path: " & To_String (Engine_Path));
         end if;
      end if;

      --  Initial analysis so the board display has a best-move arrow right away.
      declare
         A : constant DGT.Engine.Analysis :=
            DGT.Engine.Analyse (Engine, DGT.Game.To_FEN (Game),
                                Engine_Time_Ms, Engine_Depth);
      begin
         if A.Move_Len > 0 then
            Write_Display ("", 1, DGT.Game.Active_Color (Game), A,
                           "", "", DGT.Game.To_FEN (Game), Board_Flipped);
         end if;
      end;

      --  ---- Enter update mode ----
      New_Line;
      Put_Line ("Board ready. Move pieces to play. Type !help for commands. Ctrl+C to exit.");
      Print_Help;
      Last_Move_Clock := Ada.Calendar.Clock;
      DGT.Connection.Start_Updates (Conn);

      --  ---- Main event loop ----
      loop
         declare
            Square    : DGT.Board.Square_Index;
            Piece     : DGT.Protocol.Piece_Code;
            Got_Event : Boolean;
            Complete  : Boolean := False;
            Illegal   : Boolean := False;
            Last      : DGT.Game.Move;
         begin
            DGT.Connection.Read_Field_Update (Conn, Square, Piece, Got_Event);

            if Got_Event then
               DGT.Game.Update (Game, Square, Piece, Complete, Illegal, Last);

               if Piece = DGT.Protocol.Empty then
                  Put_Line ("  lifted from " & DGT.Board.Square_Name (Square));
               end if;

               if Illegal then
                  New_Line;
                  Put_Line ("*** Illegal move  --  restore pieces and try again. ***");
                  DGT.Board.Print_Board (DGT.Game.Current_Board (Game), Board_Flipped, Use_Unicode);
                  Put_Line (String'(1 .. 55 => '-'));
               end if;

            if Complete then
               declare
                  Now      : constant Ada.Calendar.Time := Ada.Calendar.Clock;
                  Elapsed  : constant Duration := Now - Last_Move_Clock;
                  Move_N   : constant Positive := DGT.Game.Move_Count (Game);
                  Opening  : Unbounded_String  := Null_Unbounded_String;
               begin
                  Last_Move_Clock := Now;
                  if Last.MV_Color = DGT.Game.White then
                     White_Elapsed := White_Elapsed + Elapsed;
                  else
                     Black_Elapsed := Black_Elapsed + Elapsed;
                  end if;

                  New_Line;
                  Print_Move_Header (Last, Last.MV_Nr);

                  --  Time control deduction
                  if TC_Base_Secs > 0 then
                     if Last.MV_Color = DGT.Game.White then
                        White_Remaining :=
                           Duration'Max (0.0, White_Remaining - Elapsed)
                           + Duration (TC_Incr_Secs);
                     else
                        Black_Remaining :=
                           Duration'Max (0.0, Black_Remaining - Elapsed)
                           + Duration (TC_Incr_Secs);
                     end if;
                     Put ("  TC W:" & Format_Clock (White_Remaining)
                          & "  B:" & Format_Clock (Black_Remaining));
                     if White_Remaining <= 0.0 then
                        Put ("  *** WHITE FLAG ***");
                        if Announce_On then Announce ("White flag"); end if;
                     elsif White_Remaining < 60.0 then
                        Put ("  (W low)");
                     end if;
                     if Black_Remaining <= 0.0 then
                        Put ("  *** BLACK FLAG ***");
                        if Announce_On then Announce ("Black flag"); end if;
                     elsif Black_Remaining < 60.0 then
                        Put ("  (B low)");
                     end if;
                     New_Line;
                  else
                     Put_Line ("  Time: " & Format_Duration (Elapsed)
                               & "   W: " & Format_Duration (White_Elapsed)
                               & "   B: " & Format_Duration (Black_Elapsed));
                  end if;

                  if Announce_On then Announce (SAN_To_Speech (Last)); end if;

                  DGT.Board.Print_Board (DGT.Game.Current_Board (Game), Board_Flipped, Use_Unicode);
                  Put_Line ("FEN: " & DGT.Game.To_FEN (Game));

                  --  Opening name
                  declare
                     Name : constant String := DGT.Openings.Lookup (Moves_UCI (Game));
                  begin
                     if Name'Length > 0 then
                        Opening := To_Unbounded_String (Name);
                        Put_Line ("Opening: " & Name);
                     end if;
                  end;

                  --  Stockfish analysis (skip if game over)
                  declare
                     Move_UCI : constant String :=
                        DGT.Board.Square_Name (Last.From)
                        & DGT.Board.Square_Name (Last.To)
                        & (if Last.Promo_To /= DGT.Protocol.Empty
                           then (1 => Ada.Characters.Handling.To_Lower
                                         (DGT.Protocol.Piece_Char (Last.Promo_To)))
                           else "");
                     Game_Status : constant String :=
                        (if Last.Is_Mate  then "Checkmate"
                         elsif Last.Is_Check then "Check"
                         else "Playing");
                  begin
                     if DGT.Game.Game_Outcome (Game) = Ongoing then
                        if Engine_N_PV > 1 then
                           declare
                              RA : constant DGT.Engine.Analysis_Array :=
                                 DGT.Engine.Analyse_Multi
                                    (Engine, DGT.Game.To_FEN (Game),
                                     Engine_N_PV, Engine_Time_Ms, Engine_Depth);
                           begin
                              declare
                                 Got : Natural := 0;
                              begin
                                 for I in 1 .. Engine_N_PV loop
                                    if RA (I).Move_Len > 0 then
                                       Got := Got + 1;
                                       Put_Line ((if I = 1 then "Eval: " else "  PV" & Img (I) & ": ")
                                          & DGT.Engine.Format_Score (RA (I))
                                          & " " & Eval_Bar (RA (I))
                                          & "  " & RA (I).Best_Move (1 .. RA (I).Move_Len));
                                    end if;
                                 end loop;
                                 if Got > 0 and then Got < Engine_N_PV then
                                    Put_Line ("  (engine returned "
                                       & Img (Got) & " of "
                                       & Img (Engine_N_PV)
                                       & " PV lines; MultiPV may not be supported)");
                                 end if;
                              end;
                              if RA (1).Move_Len > 0 then
                                 DGT.Game.Set_Move_Comment
                                   (Game, Move_N,
                                    DGT.Engine.Format_Score (RA (1))
                                    & " " & RA (1).Best_Move (1 .. RA (1).Move_Len)
                                    & " " & Format_Duration (Elapsed));
                                 Write_Display (Move_UCI, Last.MV_Nr,
                                    DGT.Game.Active_Color (Game), RA (1),
                                    Game_Status, To_String (Opening),
                                    DGT.Game.To_FEN (Game), Board_Flipped);
                              end if;
                           end;
                        else
                           declare
                              A : constant DGT.Engine.Analysis :=
                                 DGT.Engine.Analyse (Engine, DGT.Game.To_FEN (Game),
                                                     Engine_Time_Ms, Engine_Depth);
                           begin
                              if A.Move_Len > 0 then
                                 Put_Line ("Eval: " & DGT.Engine.Format_Score (A)
                                           & " " & Eval_Bar (A)
                                           & "  Best: " & A.Best_Move (1 .. A.Move_Len));
                                 if A.PV_Len > 0 then
                                    Put_Line ("  PV: " & A.PV (1 .. A.PV_Len));
                                 end if;
                                 DGT.Game.Set_Move_Comment
                                   (Game, Move_N,
                                    DGT.Engine.Format_Score (A)
                                    & " " & A.Best_Move (1 .. A.Move_Len)
                                    & " " & Format_Duration (Elapsed));
                                 Write_Display (Move_UCI, Last.MV_Nr,
                                    DGT.Game.Active_Color (Game), A,
                                    Game_Status, To_String (Opening),
                                    DGT.Game.To_FEN (Game), Board_Flipped);
                              end if;
                           end;
                        end if;
                     end if;
                  end;

                  --  Tablebase query (<= 7 pieces)
                  declare
                     PC : Natural := 0;
                  begin
                     for Sq in DGT.Board.Square_Index loop
                        if DGT.Game.Current_Board (Game).Squares (Sq)
                           /= DGT.Protocol.Empty
                        then PC := PC + 1; end if;
                     end loop;
                     if PC <= 7 and then DGT.Game.Game_Outcome (Game) = Ongoing then
                        declare
                           Resp  : constant String := Curl_Get (
                              "https://tablebase.lichess.ovh/standard?fen="
                              & URL_Encode (DGT.Game.To_FEN (Game)));
                           After : Natural;
                           Cat   : constant String :=
                              JSON_Str (Resp, "category", Resp'First, After);
                        begin
                           if Cat'Length > 0 then
                              declare
                                 DTM : constant Long_Integer :=
                                    JSON_Num (Resp, "dtm", Resp'First);
                                 DTM_Str : constant String :=
                                    (if DTM > 0
                                     then " in " & Img (Integer (DTM))
                                     else "");
                              begin
                                 if Cat = "win" then
                                    Put_Line ("TB: Win" & DTM_Str);
                                 elsif Cat = "loss" then
                                    Put_Line ("TB: Loss" & DTM_Str);
                                 elsif Cat = "draw" or else Cat = "cursed-win"
                                    or else Cat = "blessed-loss"
                                 then
                                    Put_Line ("TB: Draw (" & Cat & ")");
                                 else
                                    Put_Line ("TB: " & Cat);
                                 end if;
                              end;
                           end if;
                        end;
                     end if;
                  end;

                  --  Opening trainer feedback (file-based)
                  if Training_Mode and then Training_File then
                     declare
                        Next_Pos : constant Natural := Loaded_Pos + 1;
                     begin
                        if Next_Pos > Loaded_Count then
                           Put_Line ("Training: end of repertoire.");
                           Training_Mode := False;
                        else
                           declare
                              Expected_SAN : constant String :=
                                 To_String (Loaded_Moves (Next_Pos));
                              --  Accept if the played UCI matches the SAN
                              --  (simplistic: compare SAN of played move)
                              Played_SAN : constant String :=
                                 DGT.Game.Move_SAN
                                   (DGT.Game.Get_Move
                                     (Game, DGT.Game.Move_Count (Game)));
                           begin
                              if Played_SAN = Expected_SAN then
                                 Loaded_Pos := Next_Pos;
                                 Put_Line ("Training: correct! ("
                                    & Img (Loaded_Pos) & "/"
                                    & Img (Loaded_Count) & ")");
                                 if Loaded_Pos = Loaded_Count then
                                    Put_Line ("Training: repertoire complete!");
                                    Training_Mode := False;
                                 end if;
                              else
                                 Put_Line ("Training: expected "
                                    & Expected_SAN & ", played "
                                    & Played_SAN);
                              end if;
                           end;
                        end if;
                     end;
                  end if;

                  --  Opening trainer feedback (Lichess-based)
                  if Training_Mode and then not Training_File then
                     declare
                        Played : constant String :=
                           DGT.Game.Move_UCI (DGT.Game.Get_Move
                              (Game, DGT.Game.Move_Count (Game)));
                        --  Query explorer with moves UP TO the parent position
                        Parent_UCI : constant String :=
                           (if DGT.Game.Move_Count (Game) > 1
                            then Moves_UCI_N (Game, DGT.Game.Move_Count (Game) - 1)
                            else "");
                        URL  : constant String :=
                           "https://explorer.lichess.ovh/lichess"
                           & "?topGames=0&recentGames=0"
                           & (if Training_Strict
                              then "&speeds=classical&ratings=2500"
                              else "")
                           & (if Parent_UCI'Length > 0
                              then "&play=" & Parent_UCI
                              else "");
                        Resp : constant String := Curl_Get (URL, To_String (Cfg_Lichess_Token));
                        In_Book   : Boolean := False;
                        No_Moves  : Boolean := True;
                        Hint_Buf  : String (1 .. 200) := (others => ' ');
                        Hint_Len  : Natural := 0;

                        procedure Add_Hint (S : String) is
                        begin
                           if Hint_Len > 0 then
                              Hint_Buf (Hint_Len + 1) := ' ';
                              Hint_Len := Hint_Len + 1;
                           end if;
                           if Hint_Len + S'Length <= Hint_Buf'Length then
                              Hint_Buf (Hint_Len + 1 .. Hint_Len + S'Length) := S;
                              Hint_Len := Hint_Len + S'Length;
                           end if;
                        end Add_Hint;
                     begin
                        if Resp'Length > 0 then
                           declare
                              P : Natural :=
                                 Skip_Past (Resp, """moves"":[", Resp'First);
                           begin
                              --  Still in book iff the moves array is
                              --  present and non-empty.
                              if P > 0 and then P <= Resp'Last
                                 and then Resp (P) /= ']'
                              then
                                 No_Moves := False;
                              end if;
                              --  Walk the move objects; the empty topGames/
                              --  recentGames arrays contain no uci keys, so
                              --  the scan stops at the end of moves.
                              while P > 0 loop
                                 declare
                                    After : Natural;
                                    UCI_V : constant String :=
                                       JSON_Str (Resp, "uci", P, After);
                                 begin
                                    exit when After = 0;
                                    if UCI_V = Played then
                                       In_Book := True;
                                    end if;
                                    declare
                                       San_After : Natural;
                                       San_V     : constant String :=
                                          JSON_Str (Resp, "san",
                                                    After, San_After);
                                    begin
                                       if San_After > 0 then
                                          Add_Hint (San_V);
                                       end if;
                                    end;
                                    P := After;
                                 end;
                              end loop;
                           end;
                        end if;
                        if No_Moves then
                           Put_Line ("Training: out of book after"
                              & Natural'Image (DGT.Game.Move_Count (Game))
                              & " moves.");
                           Training_Mode := False;
                        elsif In_Book then
                           Put_Line ("Training: good move! ("
                              & DGT.Openings.Lookup (Moves_UCI (Game)) & ")");
                        else
                           Put_Line ("Training: not a main line move.");
                           if Hint_Len > 0 then
                              Put_Line ("  Book moves here: "
                                 & Hint_Buf (1 .. Hint_Len));
                           end if;
                        end if;
                     end;
                  end if;

                  Save_PGN (Game);
                  Put_Line (String'(1 .. 55 => '-'));

                  --  Game-over announcement
                  case DGT.Game.Game_Outcome (Game) is
                     when DGT.Game.White_Wins =>
                        Put_Line ("Checkmate! White wins. (1-0)");
                        if Announce_On then Announce ("Checkmate. White wins."); end if;
                        Put_Line ("PGN saved to " & To_String (PGN_File));
                        exit;
                     when DGT.Game.Black_Wins =>
                        Put_Line ("Checkmate! Black wins. (0-1)");
                        if Announce_On then Announce ("Checkmate. Black wins."); end if;
                        Put_Line ("PGN saved to " & To_String (PGN_File));
                        exit;
                     when DGT.Game.Draw =>
                        Put_Line ("Game drawn. (1/2-1/2)");
                        if Announce_On then Announce ("Draw."); end if;
                        Put_Line ("PGN saved to " & To_String (PGN_File));
                        exit;
                     when DGT.Game.Ongoing => null;
                  end case;
               end;
            end if;
            end if;  --  Got_Event

            --  Check for interactive commands typed on stdin
            declare
               Cmd_Buf   : String (1 .. 256);
               Cmd_Len   : Natural;
               Cmd_Found : Boolean;
            begin
               Pending_Cmd.Poll (Cmd_Buf, Cmd_Len, Cmd_Found);
               if Cmd_Found then
                  declare
                     Cmd : constant String := Cmd_Buf (1 .. Cmd_Len);
                  begin
                     if Browse_Mode then
                        if Cmd = "n" or else Cmd = "next" then
                           declare
                              use Ada.Containers;
                              Pages : constant Positive :=
                                 Positive'Max (1,
                                   (Natural (Browse_Vec.Length)
                                    + Browse_Page_Size - 1) / Browse_Page_Size);
                           begin
                              if Browse_Page < Pages then
                                 Browse_Page := Browse_Page + 1;
                              end if;
                           end;
                           Print_Browse_Page;
                        elsif Cmd = "p" or else Cmd = "prev" then
                           if Browse_Page > 1 then
                              Browse_Page := Browse_Page - 1;
                           end if;
                           Print_Browse_Page;
                        elsif Cmd = "q" or else Cmd = "quit" then
                           Browse_Mode := False;
                           Put_Line ("Browse cancelled.");
                        else
                           --  Try number -> select entry on current page
                           declare
                              Num   : Natural := 0;
                              Valid : Boolean := Cmd'Length > 0;
                           begin
                              for C of Cmd loop
                                 if C in '0' .. '9' then
                                    Num := Num * 10
                                       + (Character'Pos (C) - 48);
                                 else
                                    Valid := False; exit;
                                 end if;
                              end loop;
                              if Valid and then Num >= 1 then
                                 declare
                                    First : constant Natural :=
                                       (Browse_Page - 1) * Browse_Page_Size + 1;
                                    Idx   : constant Natural := First + Num - 1;
                                 begin
                                    if Idx <= Natural (Browse_Vec.Length) then
                                       declare
                                          E : constant Browse_Rec :=
                                             Browse_Vec.Element (Idx);
                                       begin
                                          Setup_Opening_From_UCI
                                            (To_String (E.Moves),
                                             To_String (E.ECO) & "  "
                                             & To_String (E.Name));
                                       end;
                                    else
                                       Put_Line ("No entry " & Img (Num)
                                          & " on this page.");
                                       Print_Browse_Page;
                                    end if;
                                 end;
                              else
                                 --  Treat as filter -> rebuild list
                                 Browse_Filter := To_Unbounded_String (Cmd);
                                 Browse_Page   := 1;
                                 Populate_Browse (Cmd);
                                 if Browse_Vec.Is_Empty then
                                    Put_Line ("No openings match """
                                       & Cmd & """.");
                                    Browse_Mode := False;
                                 else
                                    Print_Browse_Page;
                                 end if;
                              end if;
                           end;
                        end if;

                     elsif Cmd = "!undo" then
                        if DGT.Game.Move_Count (Game) > 0 then
                           DGT.Game.Undo (Game);
                           New_Line;
                           Put_Line ("*** Undo: restore pieces to match the board below. ***");
                           DGT.Board.Print_Board (DGT.Game.Current_Board (Game), Board_Flipped, Use_Unicode);
                           Put_Line ("FEN: " & DGT.Game.To_FEN (Game));
                           Put_Line (String'(1 .. 55 => '-'));
                        else
                           Put_Line ("Nothing to undo.");
                        end if;
                     elsif Cmd = "!resign" then
                        New_Line;
                        if DGT.Game.Active_Color (Game) = DGT.Game.White then
                           DGT.Game.Set_Outcome (Game, DGT.Game.Black_Wins);
                           Put_Line ("White resigns. Black wins. (0-1)");
                        else
                           DGT.Game.Set_Outcome (Game, DGT.Game.White_Wins);
                           Put_Line ("Black resigns. White wins. (1-0)");
                        end if;
                        Save_PGN (Game);
                        Put_Line ("PGN saved to " & To_String (PGN_File));
                        exit;
                     elsif Cmd = "!draw" then
                        New_Line;
                        DGT.Game.Set_Outcome (Game, DGT.Game.Draw);
                        Put_Line ("Draw agreed. (1/2-1/2)");
                        Save_PGN (Game);
                        Put_Line ("PGN saved to " & To_String (PGN_File));
                        exit;
                     elsif Cmd = "!pgn" then
                        New_Line;
                        Put_Line (DGT.Game.To_PGN (Game));
                        Put_Line (String'(1 .. 55 => '-'));
                     elsif Cmd_Len >= 8
                        and then Cmd (1 .. 6) = "!white"
                        and then Cmd (7) = ' '
                     then
                        DGT.Game.Set_Player (Game, True, Cmd (8 .. Cmd_Len));
                        Put_Line ("White: " & Cmd (8 .. Cmd_Len));
                     elsif Cmd_Len >= 8
                        and then Cmd (1 .. 6) = "!black"
                        and then Cmd (7) = ' '
                     then
                        DGT.Game.Set_Player (Game, False, Cmd (8 .. Cmd_Len));
                        Put_Line ("Black: " & Cmd (8 .. Cmd_Len));
                     elsif Cmd_Len >= 6
                        and then Cmd (1 .. 4) = "!fen"
                        and then Cmd (5) = ' '
                     then
                        begin
                           Game            := DGT.Game.From_FEN (Cmd (6 .. Cmd_Len));
                           PGN_File        := To_Unbounded_String (Make_PGN_Path);
                           Start_FEN       := To_Unbounded_String (DGT.Game.To_FEN (Game));
                           Training_Mode   := False;
                           White_Elapsed   := 0.0;
                           Black_Elapsed   := 0.0;
                           Last_Move_Clock := Ada.Calendar.Clock;
                           New_Line;
                           Put_Line ("=== Position from FEN ===");
                           DGT.Board.Print_Board (DGT.Game.Current_Board (Game), Board_Flipped, Use_Unicode);
                           Put_Line ("FEN: " & DGT.Game.To_FEN (Game));
                           Put_Line ("(Adjust physical pieces to match if playing on.)");
                           Put_Line (String'(1 .. 55 => '-'));
                           declare
                              A : constant DGT.Engine.Analysis :=
                                 DGT.Engine.Analyse (Engine, DGT.Game.To_FEN (Game),
                                                     Engine_Time_Ms, Engine_Depth);
                           begin
                              if A.Move_Len > 0 then
                                 Write_Display ("", 1, DGT.Game.Active_Color (Game), A,
                                                "", "", DGT.Game.To_FEN (Game), Board_Flipped);
                              else
                                 Write_Position (Game, Board_Flipped);
                              end if;
                           end;
                        exception
                           when others => Put_Line ("Invalid FEN string.");
                        end;
                     elsif Cmd = "!flip" then
                        Board_Flipped := not Board_Flipped;
                        New_Line;
                        Put_Line ("Board: "
                                  & (if Board_Flipped then "Black" else "White")
                                  & "'s perspective");
                        DGT.Board.Print_Board
                           (DGT.Game.Current_Board (Game), Board_Flipped, Use_Unicode);
                        Put_Line (String'(1 .. 55 => '-'));
                        Write_Position (Game, Board_Flipped);
                     elsif Cmd = "!moves" then
                        Print_Moves (Game);
                        Put_Line ("FEN: " & DGT.Game.To_FEN (Game));
                     elsif Cmd_Len >= 6
                        and then Cmd (1 .. 5) = "!time"
                        and then Cmd (6) = ' '
                     then
                        Engine_Time_Ms := Parse_Pos (Cmd (7 .. Cmd_Len), 1500);
                        Engine_Depth   := 0;
                        Put_Line ("Analysis: movetime"
                                  & Positive'Image (Engine_Time_Ms) & " ms");
                     elsif Cmd_Len >= 7
                        and then Cmd (1 .. 6) = "!depth"
                        and then Cmd (7) = ' '
                     then
                        Engine_Depth := Parse_Pos (Cmd (8 .. Cmd_Len), 15);
                        Put_Line ("Analysis: depth"
                                  & Natural'Image (Engine_Depth));
                     elsif Cmd = "!speech" or else Cmd = "!quiet" then
                        Announce_On := not Announce_On;
                        Put_Line ("Speech: "
                                  & (if Announce_On then "on" else "off"));
                        declare
                           use type GNAT.OS_Lib.String_Access;
                           Model : constant String :=
                              To_String (Cfg_TTS_Model);
                           Pip   : GNAT.OS_Lib.String_Access :=
                              GNAT.OS_Lib.Locate_Exec_On_Path ("piper");
                           Esp   : GNAT.OS_Lib.String_Access :=
                              GNAT.OS_Lib.Locate_Exec_On_Path ("espeak-ng");
                        begin
                           if Model'Length > 0 then
                              Put_Line ("  model:  " & Model);
                              Put_Line ("  piper:  "
                                 & (if Pip /= null then Pip.all
                                    else "(not found on PATH)"));
                           else
                              Put_Line ("  engine: "
                                 & (if Esp /= null then Esp.all
                                    else "(espeak-ng not found)"));
                           end if;
                           GNAT.OS_Lib.Free (Pip);
                           GNAT.OS_Lib.Free (Esp);
                        end;
                     elsif Cmd = "!unicode" then
                        Use_Unicode := not Use_Unicode;
                        Put_Line ("Pieces: "
                                  & (if Use_Unicode then "unicode symbols" else "letters"));
                        DGT.Board.Print_Board (DGT.Game.Current_Board (Game),
                                               Board_Flipped, Use_Unicode);
                     elsif Cmd_Len >= 9
                        and then Cmd (1 .. 8) = "!multipv"
                        and then Cmd (9) = ' '
                     then
                        Engine_N_PV := Natural'Min
                           (Parse_Pos (Cmd (10 .. Cmd_Len), 1), DGT.Engine.Max_PV);
                        Put_Line ("Multi-PV: " & Img (Engine_N_PV) & " lines"
                           & (if Engine_N_PV = DGT.Engine.Max_PV
                              then " (max)" else ""));
                     elsif Cmd_Len >= 4
                        and then Cmd (1 .. 3) = "!tc"
                        and then Cmd (4) = ' '
                     then
                        declare
                           Spec : constant String := Cmd (5 .. Cmd_Len);
                        begin
                           if Spec = "off" then
                              TC_Base_Secs := 0; TC_Incr_Secs := 0;
                              Put_Line ("Time control off.");
                           else
                              declare
                                 Plus : Natural := 0;
                              begin
                                 for I in Spec'Range loop
                                    if Spec (I) = '+' then Plus := I; exit; end if;
                                 end loop;
                                 TC_Base_Secs := Parse_Pos (
                                    (if Plus > 0
                                     then Spec (Spec'First .. Plus - 1)
                                     else Spec), 5) * 60;
                                 TC_Incr_Secs :=
                                    (if Plus > 0
                                     then Parse_Nat (Spec (Plus + 1 .. Spec'Last))
                                     else 0);
                              end;
                              White_Remaining := Duration (TC_Base_Secs);
                              Black_Remaining := Duration (TC_Base_Secs);
                              Put_Line ("TC: " & Img (TC_Base_Secs / 60)
                                        & "m + " & Img (TC_Incr_Secs) & "s");
                           end if;
                        end;
                     elsif Cmd = "!save" then
                        Save_Config (Engine_Time_Ms, Engine_Depth, Engine_N_PV,
                                     Use_Unicode, Announce_On);
                        Put_Line ("Config saved to " & Config_Path);
                     elsif Cmd_Len >= 6
                        and then Cmd (1 .. 5) = "!load"
                        and then Cmd (6) = ' '
                     then
                        declare
                           Path : constant String := Cmd (7 .. Cmd_Len);
                        begin
                           if Ada.Directories.Exists (Path) then
                              Load_PGN_File (Path);
                              if Loaded_Count = 0 then
                                 Put_Line ("No moves found in " & Path);
                              else
                                 --  Reset to start position
                                 if Length (Loaded_FEN) > 0 then
                                    Game := DGT.Game.From_FEN (To_String (Loaded_FEN));
                                 else
                                    Game := DGT.Game.New_Game (
                                       DGT.Connection.Get_Board_During_Updates (Conn),
                                       DGT.Game.White);
                                 end if;
                                 Loaded_Pos    := 0;
                                 Start_FEN     := To_Unbounded_String (DGT.Game.To_FEN (Game));
                                 Training_Mode := False;
                                 New_Line;
                                 Put_Line ("Loaded " & Img (Loaded_Count)
                                           & " moves from " & Path);
                                 Put_Line ("Use !forward / !back to navigate.");
                                 DGT.Board.Print_Board (DGT.Game.Current_Board (Game), Board_Flipped, Use_Unicode);
                                 Put_Line (String'(1 .. 55 => '-'));
                              end if;
                           else
                              Put_Line ("File not found: " & Path);
                           end if;
                        end;
                     elsif Cmd = "!forward"
                        or else (Cmd_Len >= 9
                                 and then Cmd (1 .. 8) = "!forward"
                                 and then Cmd (9) = ' ')
                     then
                        if Loaded_Count = 0 then
                           Put_Line ("No game loaded. Use !load FILENAME first.");
                        else
                           declare
                              Steps : constant Positive :=
                                 (if Cmd_Len >= 10
                                  then Parse_Pos (Cmd (10 .. Cmd_Len), 1)
                                  else 1);
                              Applied : Natural := 0;
                           begin
                              for K in 1 .. Steps loop
                                 if Loaded_Pos < Loaded_Count then
                                    Loaded_Pos := Loaded_Pos + 1;
                                    if not DGT.Game.Apply_SAN (
                                       Game, To_String (Loaded_Moves (Loaded_Pos)))
                                    then
                                       Put_Line ("Could not apply: "
                                                 & To_String (Loaded_Moves (Loaded_Pos)));
                                       Loaded_Pos := Loaded_Pos - 1;
                                       exit;
                                    end if;
                                    Applied := Applied + 1;
                                 end if;
                              end loop;
                              if Applied > 0 then
                                 New_Line;
                                 declare
                                    N : constant Natural := DGT.Game.Move_Count (Game);
                                 begin
                                    if N > 0 then
                                       Print_Move_Header (DGT.Game.Get_Move (Game, N), N);
                                    end if;
                                 end;
                                 DGT.Board.Print_Board (DGT.Game.Current_Board (Game), Board_Flipped, Use_Unicode);
                                 Put_Line ("FEN: " & DGT.Game.To_FEN (Game));
                                 Put_Line ("Move " & Img (Loaded_Pos)
                                           & " of " & Img (Loaded_Count));
                                 Put_Line (String'(1 .. 55 => '-'));
                              else
                                 Put_Line ("Already at end of game.");
                              end if;
                           end;
                        end if;
                     elsif Cmd = "!back"
                        or else (Cmd_Len >= 6
                                 and then Cmd (1 .. 5) = "!back"
                                 and then Cmd (6) = ' ')
                     then
                        if Loaded_Count = 0 then
                           Put_Line ("No game loaded.");
                        else
                           declare
                              Steps : constant Positive :=
                                 (if Cmd_Len >= 7
                                  then Parse_Pos (Cmd (7 .. Cmd_Len), 1)
                                  else 1);
                              Backed : Natural := 0;
                           begin
                              for K in 1 .. Steps loop
                                 if Loaded_Pos > 0 then
                                    DGT.Game.Undo (Game);
                                    Loaded_Pos := Loaded_Pos - 1;
                                    Backed := Backed + 1;
                                 end if;
                              end loop;
                              if Backed > 0 then
                                 New_Line;
                                 DGT.Board.Print_Board (DGT.Game.Current_Board (Game), Board_Flipped, Use_Unicode);
                                 Put_Line ("Move " & Img (Loaded_Pos)
                                           & " of " & Img (Loaded_Count));
                                 Put_Line (String'(1 .. 55 => '-'));
                              else
                                 Put_Line ("Already at start.");
                              end if;
                           end;
                        end if;
                     elsif Cmd = "!book" then
                        declare
                           Token  : constant String := To_String (Cfg_Lichess_Token);
                           UCI    : constant String := Moves_UCI (Game);
                           URL    : constant String :=
                              "https://explorer.lichess.ovh/lichess?topGames=0&recentGames=0"
                              & (if UCI'Length > 0 then "&play=" & UCI else "");
                        begin
                           New_Line;
                           if Token'Length = 0 then
                              Put_Line ("Book: Lichess API token required.");
                              Put_Line ("  Get one at https://lichess.org/account/oauth/token");
                              Put_Line ("  Add to ~/.chesslinkrc:  lichess_token=YOUR_TOKEN");
                           else
                              declare
                                 Resp : constant String := Curl_Get (URL, Token);
                                 P    : Natural :=
                                    Skip_Past (Resp, """moves"":[", Resp'First);
                                 Cnt  : Natural := 0;

                                 function LI (N : Long_Integer) return String is
                                    S : constant String := Long_Integer'Image (N);
                                 begin return S (S'First + 1 .. S'Last); end LI;
                              begin
                                 if Resp'Length = 0 then
                                    Put_Line ("Book: no response.");
                                 else
                                    --  Print up to 3 moves with W/D/B stats
                                    while P > 0 and then Cnt < 3 loop
                                       declare
                                          After : Natural;
                                          San_V : constant String :=
                                             JSON_Str (Resp, "san", P, After);
                                       begin
                                          exit when After = 0;
                                          declare
                                             W : constant Long_Integer :=
                                                JSON_Num (Resp, "white", After);
                                             D : constant Long_Integer :=
                                                JSON_Num (Resp, "draws", After);
                                             B : constant Long_Integer :=
                                                JSON_Num (Resp, "black", After);
                                             Total : constant Long_Integer := W + D + B;
                                             Pct   : constant String :=
                                                (if Total > 0
                                                 then Img (Natural (W * 100 / Total)) & "% W"
                                                 else "?");
                                          begin
                                             Put_Line ("Book: " & San_V
                                                & "  " & Pct
                                                & "  (" & LI (W) & "/" & LI (D) & "/" & LI (B) & ")");
                                          end;
                                          Cnt := Cnt + 1;
                                          P   := After;
                                       end;
                                    end loop;
                                    if Cnt = 0 then
                                       Put_Line ("Book: position not in database.");
                                    end if;
                                 end if;
                              end;
                           end if;
                           Put_Line (String'(1 .. 55 => '-'));
                        end;
                     elsif Cmd = "!upload" then
                        if DGT.Game.Move_Count (Game) > 0 then
                           Save_PGN (Game);
                           Upload_To_Lichess;
                        else
                           Put_Line ("No moves to upload yet.");
                        end if;
                     elsif Cmd = "!analyse" or else Cmd = "!eval" then
                        New_Line;
                        if not DGT.Engine.Is_Running (Engine) then
                           Put_Line ("No engine running -- set 'engine=/path/to/engine' in "
                              & Config_Path & " and restart.");
                        else
                        Put_Line ("Analysing...");
                        if Engine_N_PV > 1 then
                           declare
                              RA : constant DGT.Engine.Analysis_Array :=
                                 DGT.Engine.Analyse_Multi
                                    (Engine, DGT.Game.To_FEN (Game),
                                     Engine_N_PV, Engine_Time_Ms, Engine_Depth);
                           begin
                              declare
                                 Got : Natural := 0;
                              begin
                                 for I in 1 .. Engine_N_PV loop
                                    if RA (I).Move_Len > 0 then
                                       Got := Got + 1;
                                       Put_Line ((if I = 1 then "Eval: " else "  PV" & Img (I) & ": ")
                                          & DGT.Engine.Format_Score (RA (I))
                                          & " " & Eval_Bar (RA (I))
                                          & "  " & RA (I).Best_Move (1 .. RA (I).Move_Len));
                                       if I = 1 and then RA (1).PV_Len > 0 then
                                          Put_Line ("  PV: " & RA (1).PV (1 .. RA (1).PV_Len));
                                       end if;
                                    end if;
                                 end loop;
                                 if Got = 0 then
                                    Put_Line ("No analysis available.");
                                 elsif Got < Engine_N_PV then
                                    Put_Line ("  (engine returned "
                                       & Img (Got) & " of "
                                       & Img (Engine_N_PV)
                                       & " PV lines; MultiPV may not be supported)");
                                 end if;
                              end;
                           end;
                        else
                           declare
                              A : constant DGT.Engine.Analysis :=
                                 DGT.Engine.Analyse (Engine, DGT.Game.To_FEN (Game),
                                                  Engine_Time_Ms, Engine_Depth);
                           begin
                              if A.Move_Len > 0 then
                                 Put_Line ("Eval: " & DGT.Engine.Format_Score (A)
                                           & "  Best: " & A.Best_Move (1 .. A.Move_Len));
                                 if A.PV_Len > 0 then
                                    Put_Line ("  PV: " & A.PV (1 .. A.PV_Len));
                                 end if;
                              else
                                 Put_Line ("No analysis available.");
                              end if;
                           end;
                        end if;
                        end if;
                        Put_Line (String'(1 .. 55 => '-'));

                     --  ---- !hint ------------------------------------------------
                     elsif Cmd = "!hint" then
                        New_Line;
                        if not DGT.Engine.Is_Running (Engine) then
                           Put_Line ("No engine running -- set 'engine=/path/to/engine' in "
                              & Config_Path & " and restart.");
                        else
                        declare
                           A : constant DGT.Engine.Analysis :=
                              DGT.Engine.Analyse (Engine, DGT.Game.To_FEN (Game),
                                                  Engine_Time_Ms, Engine_Depth);
                        begin
                           if A.Move_Len >= 2 then
                              declare
                                 From_File : constant Character :=
                                    A.Best_Move (1);
                                 From_Rank : constant Character :=
                                    A.Best_Move (2);
                                 F_Idx : constant Natural :=
                                    Character'Pos (From_File)
                                    - Character'Pos ('a');
                                 R_Idx : constant Natural :=
                                    Character'Pos (From_Rank)
                                    - Character'Pos ('1');
                                 Row   : constant Natural := 7 - R_Idx;
                                 Sq    : constant DGT.Board.Square_Index :=
                                    DGT.Board.Square_Index (Row * 8 + F_Idx);
                                 P     : constant DGT.Protocol.Piece_Code :=
                                    DGT.Game.Current_Board (Game).Squares (Sq);
                              begin
                                 Put_Line ("Hint: consider moving your "
                                    & DGT.Protocol.Piece_Name (P)
                                    & " on " & (From_File, From_Rank));
                              end;
                           else
                              Put_Line ("No hint available.");
                           end if;
                        end;
                        end if;
                        Put_Line (String'(1 .. 55 => '-'));

                     --  ---- !compare ---------------------------------------------
                     elsif Cmd = "!compare" then
                        New_Line;
                        if not DGT.Engine.Is_Running (Engine) then
                           Put_Line ("No engine running -- set 'engine=/path/to/engine' in "
                              & Config_Path & " and restart.");
                        else
                        declare
                           N : constant Natural := DGT.Game.Move_Count (Game);
                        begin
                           if N = 0 then
                              Put_Line ("No moves played yet.");
                           else
                              declare
                                 Pre_FEN  : constant String :=
                                    FEN_At (Game, To_String (Start_FEN), N - 1);
                                 A_Pre    : constant DGT.Engine.Analysis :=
                                    DGT.Engine.Analyse (Engine, Pre_FEN,
                                                        Engine_Time_Ms,
                                                        Engine_Depth);
                                 Last_M   : constant DGT.Game.Move :=
                                    DGT.Game.Get_Move (Game, N);
                                 Played   : constant String :=
                                    DGT.Game.Move_UCI (Last_M);
                                 Best     : constant String :=
                                    A_Pre.Best_Move (1 .. A_Pre.Move_Len);
                              begin
                                 Put_Line ("Last move:  " & DGT.Game.Move_SAN (Last_M)
                                    & "  [" & Played & "]");
                                 if A_Pre.Move_Len > 0 then
                                    if Played = Best then
                                       Put_Line ("Best move! Stockfish agrees: "
                                          & Best & "  "
                                          & DGT.Engine.Format_Score (A_Pre));
                                    else
                                       Put_Line ("Stockfish preferred: " & Best
                                          & "  " & DGT.Engine.Format_Score (A_Pre));
                                       --  Eval after played move (already computed)
                                       declare
                                          A_After : constant DGT.Engine.Analysis :=
                                             DGT.Engine.Analyse
                                               (Engine, DGT.Game.To_FEN (Game),
                                                Engine_Time_Ms, Engine_Depth);
                                          Loss : constant Integer :=
                                             A_Pre.Score_CP + A_After.Score_CP;
                                       begin
                                          if A_After.Move_Len > 0 then
                                             Put_Line ("After played move:  "
                                                & DGT.Engine.Format_Score (A_After)
                                                & "  (loss: "
                                                & (if Loss > 0 then "+" else "")
                                                & Img (abs Loss) & " cp)");
                                          end if;
                                       end;
                                    end if;
                                 end if;
                              end;
                           end if;
                        end;
                        end if;
                        Put_Line (String'(1 .. 55 => '-'));

                     --  ---- !review ----------------------------------------------
                     elsif Cmd = "!review" then
                        New_Line;
                        if not DGT.Engine.Is_Running (Engine) then
                           Put_Line ("No engine running -- set 'engine=/path/to/engine' in "
                              & Config_Path & " and restart.");
                        else
                        declare
                           N : constant Natural := DGT.Game.Move_Count (Game);
                        begin
                           if N = 0 then
                              Put_Line ("No moves to review.");
                           else
                              Put_Line ("Reviewing " & Img (N) & " moves...");
                              declare
                                 Review_Time : constant Positive := 500;
                                 W_Best, W_Inaccuracy,
                                 W_Mistake, W_Blunder : Natural := 0;
                                 B_Best, B_Inaccuracy,
                                 B_Mistake, B_Blunder : Natural := 0;
                              begin
                                 for I in 1 .. N loop
                                    declare
                                       M        : constant DGT.Game.Move :=
                                          DGT.Game.Get_Move (Game, I);
                                       Pre_FEN  : constant String :=
                                          FEN_At (Game,
                                             To_String (Start_FEN), I - 1);
                                       Post_FEN : constant String :=
                                          FEN_At (Game,
                                             To_String (Start_FEN), I);
                                       A_Pre    : constant DGT.Engine.Analysis :=
                                          DGT.Engine.Analyse (Engine, Pre_FEN,
                                             Review_Time, 0);
                                       A_Post   : constant DGT.Engine.Analysis :=
                                          DGT.Engine.Analyse (Engine, Post_FEN,
                                             Review_Time, 0);
                                       --  Both scores are from the side-to-move's
                                       --  perspective (positive = good for mover).
                                       --  After a perfect move S_pre + S_post = 0;
                                       --  a blunder of N cp gives Loss = +N.
                                       Loss     : constant Integer :=
                                          A_Pre.Score_CP + A_Post.Score_CP;
                                       Is_White : constant Boolean :=
                                          M.MV_Color = DGT.Game.White;

                                       function Classify return String is
                                       begin
                                          if Loss <= 20  then return "best";
                                          elsif Loss <= 50  then return "good";
                                          elsif Loss <= 100 then return "inaccuracy";
                                          elsif Loss <= 300 then return "mistake";
                                          else                   return "blunder";
                                          end if;
                                       end Classify;

                                       Label : constant String := Classify;
                                    begin
                                       if Label /= "best" and then
                                          Label /= "good"
                                       then
                                          declare
                                             Nr_Img : constant String :=
                                                Natural'Image (M.MV_Nr);
                                          begin
                                             Put (Nr_Img (2 .. Nr_Img'Last));
                                             if Is_White then Put (". ");
                                             else Put ("... ");
                                             end if;
                                             Put_Line (DGT.Game.Move_SAN (M)
                                                & "  " & Label
                                                & "  (+"  & Img (abs Loss)
                                                & " cp)"
                                                & (if A_Pre.Move_Len > 0
                                                   then "  better: "
                                                   & A_Pre.Best_Move
                                                     (1 .. A_Pre.Move_Len)
                                                   else ""));
                                          end;
                                       end if;
                                       --  Accumulate stats
                                       if Is_White then
                                          if    Label = "best"
                                             or else Label = "good"       then W_Best := W_Best + 1;
                                          elsif Label = "inaccuracy"      then W_Inaccuracy := W_Inaccuracy + 1;
                                          elsif Label = "mistake"         then W_Mistake := W_Mistake + 1;
                                          else                                 W_Blunder := W_Blunder + 1;
                                          end if;
                                       else
                                          if    Label = "best"
                                             or else Label = "good"       then B_Best := B_Best + 1;
                                          elsif Label = "inaccuracy"      then B_Inaccuracy := B_Inaccuracy + 1;
                                          elsif Label = "mistake"         then B_Mistake := B_Mistake + 1;
                                          else                                 B_Blunder := B_Blunder + 1;
                                          end if;
                                       end if;
                                    end;
                                 end loop;
                                 New_Line;
                                 Put_Line ("=== Review Summary ===");
                                 Put_Line ("White: "
                                    & Img (W_Best) & " good  "
                                    & Img (W_Inaccuracy) & " inaccuracy  "
                                    & Img (W_Mistake) & " mistake  "
                                    & Img (W_Blunder) & " blunder");
                                 Put_Line ("Black: "
                                    & Img (B_Best) & " good  "
                                    & Img (B_Inaccuracy) & " inaccuracy  "
                                    & Img (B_Mistake) & " mistake  "
                                    & Img (B_Blunder) & " blunder");
                              end;
                           end if;
                        end;
                        end if;
                        Put_Line (String'(1 .. 55 => '-'));

                     --  ---- !comment TEXT ----------------------------------------
                     elsif Cmd_Len >= 9
                        and then Cmd (1 .. 8) = "!comment"
                        and then Cmd (9) = ' '
                     then
                        if DGT.Game.Move_Count (Game) > 0 then
                           DGT.Game.Set_Move_Comment
                             (Game, DGT.Game.Move_Count (Game),
                              Cmd (10 .. Cmd_Len));
                           Save_PGN (Game);
                           Put_Line ("Comment added.");
                        else
                           Put_Line ("No moves yet.");
                        end if;

                     --  ---- !train -----------------------------------------------
                     elsif Cmd = "!train" then
                        Training_Mode  := True;
                        Training_File  := False;
                        Put_Line ("Training mode on (Lichess). Play moves on the board.");
                        Put_Line ("  !train off        --  stop");
                        Put_Line ("  !train strict      --  master games only (classical, 2500+)");
                        Put_Line ("  !train file FILE   --  use repertoire PGN");
                        Put_Line ("  !train opening       --  list all openings in book");
                        Put_Line ("  !train opening NAME  --  start from named opening");
                     elsif Cmd = "!train off" then
                        Training_Mode   := False;
                        Training_Strict := False;
                        Put_Line ("Training mode off.");
                     elsif Cmd = "!train strict" then
                        Training_Mode   := True;
                        Training_File   := False;
                        Training_Strict := True;
                        Put_Line ("Training mode on (Lichess, strict: "
                           & "classical games by 2500+ players only).");
                     elsif Cmd = "!train strict off" then
                        Training_Strict := False;
                        if Training_Mode and then not Training_File then
                           Put_Line ("Strict filter off (training continues "
                              & "against all Lichess games).");
                        else
                           Put_Line ("Strict filter off.");
                        end if;
                     elsif Cmd_Len >= 12
                        and then Cmd (1 .. 11) = "!train file"
                        and then Cmd (12) = ' '
                     then
                        declare
                           Path : constant String := Cmd (13 .. Cmd_Len);
                        begin
                           if Ada.Directories.Exists (Path) then
                              Load_PGN_File (Path);
                              if Loaded_Count = 0 then
                                 Put_Line ("No moves found in " & Path);
                              else
                                 Loaded_Pos    := 0;
                                 Training_Mode := True;
                                 Training_File := True;
                                 Put_Line ("Training: loaded " & Img (Loaded_Count)
                                    & " moves from " & Path);
                              end if;
                           else
                              Put_Line ("File not found: " & Path);
                           end if;
                        end;
                     elsif Cmd = "!train opening" then
                        Browse_Filter := Null_Unbounded_String;
                        Browse_Page   := 1;
                        Populate_Browse ("");
                        Browse_Mode := True;
                        Print_Browse_Page;

                     elsif Cmd_Len >= 16
                        and then Cmd (1 .. 15) = "!train opening "
                     then
                        declare
                           Name     : constant String := Cmd (16 .. Cmd_Len);
                           UCI_Mvs  : constant String :=
                              DGT.Openings.Find_Moves (Name);
                        begin
                           if UCI_Mvs'Length = 0 then
                              Put_Line ("Opening not found: " & Name);
                              declare
                                 Found : Natural := 0;
                                 procedure Print_Match (ECO : String; MName : String) is
                                 begin
                                    if Found = 0 then
                                       Put_Line ("  Similar entries:");
                                    end if;
                                    Put_Line ("    " & ECO & "  " & MName);
                                    Found := Found + 1;
                                 end Print_Match;
                              begin
                                 DGT.Openings.For_Each_Opening
                                   (Print_Match'Access, Name);
                                 if Found = 0 then
                                    Put_Line ("  No matches. Use !train opening"
                                       & " to browse all openings.");
                                 end if;
                              end;
                           else
                              Setup_Opening_From_UCI (UCI_Mvs, Name);
                           end if;
                        end;

                     elsif Cmd_Len >= 8
                        and then Cmd (1 .. 8) = "!newgame"
                     then
                        declare
                           New_Color : DGT.Game.Color := DGT.Game.White;
                           New_Board : DGT.Board.Board_State;
                        begin
                           if Cmd_Len >= 10
                              and then (Cmd (10) = 'b' or else Cmd (10) = 'B')
                           then
                              New_Color := DGT.Game.Black;
                           end if;
                           New_Board := DGT.Connection.Get_Board_During_Updates (Conn);
                           Game            := DGT.Game.New_Game (New_Board, New_Color);
                           PGN_File        := To_Unbounded_String (Make_PGN_Path);
                           Start_FEN       := To_Unbounded_String (DGT.Game.To_FEN (Game));
                           Training_Mode   := False;
                           White_Elapsed   := 0.0;
                           Black_Elapsed   := 0.0;
                           Last_Move_Clock := Ada.Calendar.Clock;
                           if TC_Base_Secs > 0 then
                              White_Remaining := Duration (TC_Base_Secs);
                              Black_Remaining := Duration (TC_Base_Secs);
                           end if;
                           New_Line;
                           Put_Line ("=== New Game ("
                              & (if New_Color = DGT.Game.White
                                 then "White" else "Black")
                              & " to move) ===");
                           DGT.Board.Print_Board (New_Board, Board_Flipped, Use_Unicode);
                           Put_Line ("FEN: " & DGT.Game.To_FEN (Game));
                           Put_Line (String'(1 .. 55 => '-'));
                           declare
                              A : constant DGT.Engine.Analysis :=
                                 DGT.Engine.Analyse (Engine, DGT.Game.To_FEN (Game),
                                                     Engine_Time_Ms, Engine_Depth);
                           begin
                              if A.Move_Len > 0 then
                                 Write_Display ("", 1, DGT.Game.Active_Color (Game), A,
                                                "", "", DGT.Game.To_FEN (Game), Board_Flipped);
                              else
                                 Write_Position (Game, Board_Flipped);
                              end if;
                           end;
                        end;

                     --  ---- !resync -------------------------------------------
                     elsif Cmd = "!resync" or else Cmd = "!resync force" then
                        declare
                           Force     : constant Boolean := Cmd = "!resync force";
                           New_Board : constant DGT.Board.Board_State :=
                              DGT.Connection.Get_Board_During_Updates (Conn);
                           Cur       : constant DGT.Board.Board_State :=
                              DGT.Game.Current_Board (Game);
                        begin
                           New_Line;
                           if New_Board = Cur then
                              DGT.Game.Reset_Position (Game, New_Board);
                              Put_Line ("Board in sync with game state. No changes.");
                           else
                              declare
                                 UCI : constant String :=
                                    Find_Recovered_UCI (Game, New_Board);
                              begin
                                 if UCI'Length > 0
                                    and then DGT.Game.Apply_UCI (Game, UCI)
                                 then
                                    DGT.Game.Reset_Position
                                      (Game, DGT.Game.Current_Board (Game));
                                    Put_Line ("Recovered missed move: "
                                       & DGT.Game.Move_SAN
                                          (DGT.Game.Get_Move
                                             (Game, DGT.Game.Move_Count (Game)))
                                       & "  [" & UCI & "]");
                                    Save_PGN (Game);
                                 elsif Force then
                                    DGT.Game.Reset_Position (Game, New_Board);
                                    Put_Line ("Board adopted as-is (forced). Move "
                                       & "history may now be out of sync with the");
                                    Put_Line ("physical position -- verify with "
                                       & "!moves / !fen.");
                                    Save_PGN (Game);
                                 else
                                    DGT.Game.Reset_Position
                                      (Game, DGT.Game.Current_Board (Game));
                                    Put_Line ("Board does not match a single legal "
                                       & "move from the current position.");
                                    Put_Line ("Differences (expected -> actual):");
                                    declare
                                       N : Natural := 0;
                                    begin
                                       for Sq in DGT.Board.Square_Index loop
                                          if Cur.Squares (Sq)
                                             /= New_Board.Squares (Sq)
                                          then
                                             N := N + 1;
                                             Put_Line ("  "
                                                & DGT.Board.Square_Name (Sq) & ": "
                                                & DGT.Protocol.Piece_Name
                                                   (Cur.Squares (Sq))
                                                & " -> "
                                                & DGT.Protocol.Piece_Name
                                                   (New_Board.Squares (Sq)));
                                          end if;
                                       end loop;
                                       if N = 0 then Put_Line ("  (none?)"); end if;
                                    end;
                                    Put_Line ("Fix the physical pieces and try "
                                       & "!resync again, or use '!resync force'");
                                    Put_Line ("to adopt the board as-is (breaks "
                                       & "PGN continuity).");
                                 end if;
                              end;
                           end if;
                           DGT.Board.Print_Board
                             (DGT.Game.Current_Board (Game), Board_Flipped, Use_Unicode);
                           Put_Line ("FEN: " & DGT.Game.To_FEN (Game));
                           Put_Line (String'(1 .. 55 => '-'));
                           Write_Position (Game, Board_Flipped);
                        end;
                     elsif Cmd = "!display" then
                        declare
                           use type GNAT.OS_Lib.String_Access;
                           use type GNAT.OS_Lib.Process_Id;
                           Py3 : GNAT.OS_Lib.String_Access :=
                              GNAT.OS_Lib.Locate_Exec_On_Path ("python3");
                           PID : GNAT.OS_Lib.Process_Id;
                        begin
                           if Py3 /= null then
                              if not Ada.Directories.Exists (Display_Script_Path) then
                                 Put_Line ("Display: " & Display_Script_Path
                                    & " not found -- run chesslink from the "
                                    & "project root.");
                                 GNAT.OS_Lib.Free (Py3);
                              else
                                 declare
                                    Args : constant GNAT.OS_Lib.Argument_List :=
                                       (1 => new String'(Display_Script_Path));
                                 begin
                                    PID := GNAT.OS_Lib.Non_Blocking_Spawn (Py3.all, Args);
                                    GNAT.OS_Lib.Free (Py3);
                                    if PID = GNAT.OS_Lib.Invalid_Pid then
                                       Put_Line ("Display: failed to launch.");
                                    else
                                       Put_Line ("Display window opened.");
                                    end if;
                                 end;
                              end if;
                           else
                              Put_Line ("Display: python3 not found on PATH.");
                           end if;
                        end;

                     elsif Cmd = "!webdisplay" then
                        declare
                           use type GNAT.OS_Lib.String_Access;
                           use type GNAT.OS_Lib.Process_Id;
                           Web_Script : constant String := "tools/dgt_webdisplay.py";
                           Py3 : GNAT.OS_Lib.String_Access :=
                              GNAT.OS_Lib.Locate_Exec_On_Path ("python3");
                           PID : GNAT.OS_Lib.Process_Id;
                        begin
                           if Py3 /= null then
                              if not Ada.Directories.Exists (Web_Script) then
                                 Put_Line ("Web display: " & Web_Script
                                    & " not found -- run chesslink from the "
                                    & "project root.");
                                 GNAT.OS_Lib.Free (Py3);
                              else
                              declare
                                 Args : constant GNAT.OS_Lib.Argument_List :=
                                    (1 => new String'(Web_Script));
                              begin
                                 PID := GNAT.OS_Lib.Non_Blocking_Spawn (Py3.all, Args);
                                 GNAT.OS_Lib.Free (Py3);
                                 if PID = GNAT.OS_Lib.Invalid_Pid then
                                    Put_Line ("Web display: failed to launch.");
                                 else
                                    Put_Line ("Web display started at http://localhost:8080/");
                                 end if;
                              end;
                              end if;
                           else
                              Put_Line ("Web display: python3 not found on PATH.");
                           end if;
                        end;

                     elsif Cmd = "!boarddisplay" then
                        declare
                           use type GNAT.OS_Lib.String_Access;
                           use type GNAT.OS_Lib.Process_Id;
                           Py3 : GNAT.OS_Lib.String_Access :=
                              GNAT.OS_Lib.Locate_Exec_On_Path ("python3");
                           PID : GNAT.OS_Lib.Process_Id;
                        begin
                           if Py3 /= null then
                              if not Ada.Directories.Exists (Board_Script_Path) then
                                 Put_Line ("Board display: " & Board_Script_Path
                                    & " not found -- run chesslink from the "
                                    & "project root.");
                                 GNAT.OS_Lib.Free (Py3);
                              else
                                 declare
                                    Args : constant GNAT.OS_Lib.Argument_List :=
                                       (1 => new String'(Board_Script_Path));
                                 begin
                                    PID := GNAT.OS_Lib.Non_Blocking_Spawn (Py3.all, Args);
                                    GNAT.OS_Lib.Free (Py3);
                                    if PID = GNAT.OS_Lib.Invalid_Pid then
                                       Put_Line ("Board display: failed to launch.");
                                    else
                                       Put_Line ("Board display window opened.");
                                    end if;
                                 end;
                              end if;
                           else
                              Put_Line ("Board display: python3 not found on PATH.");
                           end if;
                        end;

                     elsif Cmd = "!help" then
                        New_Line;
                        Print_Help;
                     else
                        Put_Line ("Unknown command. Type !help for a list of commands.");
                     end if;
                  end;
               end if;
            end;
         end;
      end loop;

   exception
      when DGT.DGT_Error | GNAT.Serial_Communications.Serial_Error =>
         New_Line;
         Put_Line ("Board disconnected or timeout.");
         if DGT.Game.Move_Count (Game) > 0 then
            Save_PGN (Game);
            Put_Line ("PGN saved to " & To_String (PGN_File));
         end if;
      when E : others =>
         New_Line;
         Put_Line ("Error: " & Ada.Exceptions.Exception_Information (E));
         if DGT.Game.Move_Count (Game) > 0 then
            Save_PGN (Game);
            Put_Line ("PGN saved to " & To_String (PGN_File));
         end if;
   end;

   DGT.Engine.Stop (Engine);
   DGT.Connection.Close (Conn);

exception
   when E : DGT.DGT_Error =>
      Put_Line ("DGT error: " & Ada.Exceptions.Exception_Message (E));
   when E : GNAT.Serial_Communications.Serial_Error =>
      Put_Line ("Serial error: " & Ada.Exceptions.Exception_Message (E));
end Chesslink;
