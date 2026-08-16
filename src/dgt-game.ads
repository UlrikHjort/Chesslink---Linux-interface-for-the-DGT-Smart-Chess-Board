-- ***************************************************************************
--                      DGT Smart Board - Game State and Move Detection
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

with DGT.Board;
with DGT.Protocol;

package DGT.Game is

   type Color is (White, Black);
   function Opponent (C : Color) return Color;

   --  A fully-described chess move as detected from the board sensors
   type Move is record
      From      : Board.Square_Index   := 0;
      To        : Board.Square_Index   := 0;
      Piece     : Protocol.Piece_Code := Protocol.Empty;  -- piece that moved
      Captured  : Protocol.Piece_Code := Protocol.Empty;  -- piece taken (Empty = none)
      Castle_K  : Boolean             := False;
      Castle_Q  : Boolean             := False;
      Is_EP     : Boolean             := False;
      Promo_To  : Protocol.Piece_Code := Protocol.Empty;  -- Empty = no promotion
      Brd_Before : Board.Board_State;                      -- position before move
      MV_Nr     : Positive            := 1;               -- fullmove number
      MV_Color  : Color               := White;
      Is_Check  : Boolean             := False;           -- move gives check
      Is_Mate   : Boolean             := False;           -- move is checkmate
      Comment     : String (1 .. 80)  := (others => ' '); -- PGN annotation
      Comment_Len : Natural           := 0;
   end record;

   type Game_Result is (Ongoing, White_Wins, Black_Wins, Draw);

   type Game_State is private;

   function  New_Game
     (B      : Board.Board_State;
      Active : Color := White) return Game_State;

   function  Current_Board  (G : Game_State) return Board.Board_State;
   function  Active_Color   (G : Game_State) return Color;
   function  Move_Count     (G : Game_State) return Natural;
   function  Get_Move       (G : Game_State; I : Positive) return Move;

   --  Process one field event from the board.
   --  Complete = True when a full move is detected; Last carries it.
   procedure Update
     (G        : in out Game_State;
      Square   : Board.Square_Index;
      Piece    : Protocol.Piece_Code;
      Complete : out Boolean;
      Illegal  : out Boolean;
      Last     : out Move);

   function To_FEN  (G : Game_State) return String;  -- full FEN (6 fields)
   function To_PGN  (G : Game_State) return String;
   function Move_SAN (M : Move) return String;       -- uses M.Brd_Before
   function Move_UCI (M : Move) return String;       -- e.g. "e2e4", "e7e8q"

   function Is_Start_Position (B : Board.Board_State) return Boolean;
   function Game_Outcome (G : Game_State) return Game_Result;

   procedure Undo          (G : in out Game_State);
   procedure Reset_Position (G : in out Game_State; B : Board.Board_State);
   procedure Set_Outcome      (G : in out Game_State; Result : Game_Result);
   procedure Set_Move_Comment (G : in out Game_State; N : Positive; S : String);
   procedure Set_Player       (G : in out Game_State; Is_White : Boolean; Name : String);

   function From_FEN   (Fen : String) return Game_State;
   function Apply_UCI  (G : in out Game_State; UCI : String) return Boolean;
   function Apply_SAN  (G : in out Game_State; SAN : String) return Boolean;

private

   type Detect_Phase is
     (Idle,
      Holding,            --  piece lifted, waiting for placement
      Castle_Rook_Lift,   --  king placed (castling), waiting for rook lift
      Castle_Rook_Place,  --  rook lifted, waiting for rook placement
      EP_Cleanup);        --  EP pawn placed, waiting for captured pawn removal

   type Castling_Rights is record
      WK, WQ, BK, BQ : Boolean := True;
   end record;

   Max_Ply : constant := 512;
   type Move_Array is array (1 .. Max_Ply) of Move;

   type Position_Hash is mod 2**32;
   type Hash_Array    is array (1 .. Max_Ply + 1) of Position_Hash;

   type Undo_Entry is record
      Position : Board.Board_State;
      Active   : Color            := White;
      Castling : Castling_Rights;
      EP_Sq    : Integer          := -1;
      Halfmove : Natural          := 0;
      Fullmove : Positive         := 1;
   end record;
   type Undo_Array is array (1 .. Max_Ply) of Undo_Entry;

   type Game_State is record
      Position : Board.Board_State;              -- current board position
      Active   : Color           := White;
      Castling : Castling_Rights;
      EP_Sq    : Integer         := -1;          -- en-passant target (-1 = none)
      Halfmove : Natural         := 0;
      Fullmove : Positive        := 1;
      History  : Move_Array;
      N_Moves  : Natural         := 0;
      --  Detection state
      Phase      : Detect_Phase         := Idle;
      Lift_From  : Board.Square_Index   := 0;
      Lift_Piece : Protocol.Piece_Code := Protocol.Empty;
      Pend       : Move;
      Pre_Move      : Board.Board_State;
      Pre_Castling  : Castling_Rights;
      Pre_EP        : Integer  := -1;
      Pre_Halfmove  : Natural  := 0;
      Pre_Fullmove  : Positive := 1;
      EP_Cap_Sq  : Board.Square_Index   := 0;
      Rook_From  : Board.Square_Index   := 0;
      Outcome    : Game_Result          := Ongoing;
      Start_Date : String (1 .. 10)     := "????.??.??";
      Pos_Hashes : Hash_Array           := (others => 0);
      N_Hashes   : Natural              := 0;
      Undo_Stack : Undo_Array;
      White_Name : String (1 .. 64)     := (1 => '?', others => ' ');
      White_Nlen : Natural              := 1;
      Black_Name : String (1 .. 64)     := (1 => '?', others => ' ');
      Black_Nlen : Natural              := 1;
   end record;

end DGT.Game;
