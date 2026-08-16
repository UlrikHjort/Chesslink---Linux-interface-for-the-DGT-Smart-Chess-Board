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

with Ada.Calendar;
with Ada.Calendar.Formatting;

package body DGT.Game is

   use Protocol;
   use Board;

   -- =========================================================
   --  Square / piece geometry helpers
   -- =========================================================

   function File_Of (Sq : Square_Index) return Natural is (Natural (Sq) mod 8);
   function Row_Of  (Sq : Square_Index) return Natural is (Natural (Sq) / 8);
   function Rank_Of (Sq : Square_Index) return Positive is (8 - Row_Of (Sq));

   function Sq_At (Row, Col : Natural) return Square_Index is
      (Square_Index (Row * 8 + Col));

   Files_Str : constant String := "abcdefgh";

   function File_Char (Sq : Square_Index) return Character is
      (Files_Str (Files_Str'First + File_Of (Sq)));
   function Rank_Char (Sq : Square_Index) return Character is
      (Character'Val (Character'Pos ('0') + Rank_Of (Sq)));

   function Opponent (C : Color) return Color is
      (if C = White then Black else White);

   -- =========================================================
   --  Piece helpers
   -- =========================================================

   function Is_Pawn  (P : Piece_Code) return Boolean is (P = WPawn or P = BPawn);
   function Is_King  (P : Piece_Code) return Boolean is (P = WKing or P = BKing);
   function Is_Knight(P : Piece_Code) return Boolean is (P = WKnight or P = BKnight);
   function Is_Bishop(P : Piece_Code) return Boolean is (P = WBishop or P = BBishop);
   function Is_Rook  (P : Piece_Code) return Boolean is (P = WRook or P = BRook);
   function Is_Queen (P : Piece_Code) return Boolean is (P = WQueen or P = BQueen);

   function Is_White_Piece (P : Piece_Code) return Boolean is
     (P = WPawn or else P = WKnight or else P = WBishop
      or else P = WRook  or else P = WQueen  or else P = WKing);

   -- =========================================================
   --  Move-detection geometry
   -- =========================================================

   function Is_Castling (Piece : Piece_Code; From, To : Square_Index) return Boolean is
      (Is_King (Piece)
       and then Row_Of (From) = Row_Of (To)
       and then abs (Integer (File_Of (To)) - Integer (File_Of (From))) = 2
       and then ((Piece = WKing and then Natural (From) = 60)   --  e1
                 or else (Piece = BKing and then Natural (From) = 4)));  --  e8

   function Is_Double_Push (Piece : Piece_Code; From, To : Square_Index)
      return Boolean is
      (Is_Pawn (Piece)
       and then File_Of (From) = File_Of (To)
       and then abs (Integer (Row_Of (From)) - Integer (Row_Of (To))) = 2);

   function Double_Push_EP_Sq (From, To : Square_Index) return Integer is
      ((Integer (Row_Of (From)) + Integer (Row_Of (To))) / 2 * 8
       + Integer (File_Of (From)));

   function Is_EP_Capture (Piece : Piece_Code; From, To : Square_Index;
                            Dest_Empty : Boolean) return Boolean is
      (Is_Pawn (Piece)
       and then abs (Integer (File_Of (From)) - Integer (File_Of (To))) = 1
       and then abs (Integer (Row_Of  (From)) - Integer (Row_Of  (To))) = 1
       and then Dest_Empty);

   function EP_Captured_Sq (Piece : Piece_Code; To : Square_Index)
      return Square_Index is
      (if Piece = WPawn
       then Sq_At (Row_Of (To) + 1, File_Of (To))
       else Sq_At (Row_Of (To) - 1, File_Of (To)));

   function Is_Promo (Piece : Piece_Code; To : Square_Index) return Boolean is
      ((Piece = WPawn and then Row_Of (To) = 0)
       or else (Piece = BPawn and then Row_Of (To) = 7));

   -- =========================================================
   --  Castling-rights update
   -- =========================================================

   procedure Kill_Castling (C : in out Castling_Rights; Sq : Square_Index) is
   begin
      case Natural (Sq) is
         when 60 => C.WK := False; C.WQ := False;   -- e1 (white king)
         when  4 => C.BK := False; C.BQ := False;   -- e8 (black king)
         when 63 => C.WK := False;                   -- h1
         when 56 => C.WQ := False;                   -- a1
         when  7 => C.BK := False;                   -- h8
         when  0 => C.BQ := False;                   -- a8
         when others => null;
      end case;
   end Kill_Castling;

   -- =========================================================
   --  Piece-attack and move-legality helpers
   -- =========================================================

   function Slide_Clear (B : Board_State; From, To : Square_Index;
                          DF, DR : Integer) return Boolean is
      F  : Integer := Integer (File_Of (From)) + DF;
      R  : Integer := Integer (Row_Of  (From)) + DR;
      TF : constant Integer := Integer (File_Of (To));
      TR : constant Integer := Integer (Row_Of  (To));
   begin
      while F /= TF or R /= TR loop
         if F < 0 or F > 7 or R < 0 or R > 7 then return False; end if;
         if B.Squares (Sq_At (R, F)) /= Empty then return False; end if;
         F := F + DF;
         R := R + DR;
      end loop;
      return True;
   end Slide_Clear;

   function Can_Attack (B : Board_State; From, To : Square_Index;
                        P : Piece_Code) return Boolean is
      DF  : constant Integer := Integer (File_Of (To)) - Integer (File_Of (From));
      DR  : constant Integer := Integer (Row_Of  (To)) - Integer (Row_Of  (From));
      ADF : constant Integer := abs DF;
      ADR : constant Integer := abs DR;
      SF  : constant Integer := (if DF > 0 then 1 elsif DF < 0 then -1 else 0);
      SR  : constant Integer := (if DR > 0 then 1 elsif DR < 0 then -1 else 0);
   begin
      if From = To then return False; end if;
      if Is_Knight (P) then
         return (ADF = 1 and then ADR = 2) or else (ADF = 2 and then ADR = 1);
      elsif Is_Bishop (P) then
         return (ADF = ADR and then ADF > 0)
            and then Slide_Clear (B, From, To, SF, SR);
      elsif Is_Rook (P) then
         return ((DF = 0) /= (DR = 0))
            and then Slide_Clear (B, From, To, SF, SR);
      elsif Is_Queen (P) then
         declare
            Diag : constant Boolean := ADF = ADR and then ADF > 0;
            Line : constant Boolean := (DF = 0) /= (DR = 0);
         begin
            return (Diag or else Line)
               and then Slide_Clear (B, From, To, SF, SR);
         end;
      elsif Is_Pawn (P) then
         --  Pawns attack diagonally forward only (no sliding, no path check).
         --  White advances toward lower row numbers (rank 8); black the opposite.
         if P = WPawn then
            return ADF = 1 and then DR = -1;
         else
            return ADF = 1 and then DR = 1;
         end if;
      elsif Is_King (P) then
         return (ADF <= 1 and then ADR <= 1) and then ADF + ADR > 0;
      end if;
      return False;
   end Can_Attack;

   function King_Square (B : Board_State; C : Color) return Square_Index is
      K : constant Piece_Code := (if C = White then WKing else BKing);
   begin
      for Sq in Square_Index loop
         if B.Squares (Sq) = K then return Sq; end if;
      end loop;
      return 0;
   end King_Square;

   --  True if any piece of color By can capture on Sq in position B.
   function Is_Attacked (B : Board_State; Sq : Square_Index; By : Color)
      return Boolean is
   begin
      for From in Square_Index loop
         declare
            P : constant Piece_Code := B.Squares (From);
         begin
            if P /= Empty
               and then Is_White_Piece (P) = (By = White)
               and then Can_Attack (B, From, Sq, P)
            then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Is_Attacked;

   function Is_In_Check (B : Board_State; C : Color) return Boolean is
      (Is_Attacked (B, King_Square (B, C), Opponent (C)));

   -- =========================================================
   --  Position hash (threefold repetition) and draw detection
   -- =========================================================

   function Compute_Hash (G : Game_State) return Position_Hash is
      H  : Position_Hash := 0;
      CR : Position_Hash := 0;
   begin
      for Sq in Square_Index loop
         H := H xor
            (Position_Hash (Piece_Code'Pos (G.Position.Squares (Sq)))
             * Position_Hash (Natural (Sq) * 1009 + 1));
      end loop;
      if G.Castling.WK then CR := CR or 1; end if;
      if G.Castling.WQ then CR := CR or 2; end if;
      if G.Castling.BK then CR := CR or 4; end if;
      if G.Castling.BQ then CR := CR or 8; end if;
      H := H xor (if G.Active = White then 16#CC55AA33# else 16#33AA55CC#);
      H := H xor (CR * 16#12345678#);
      if G.EP_Sq >= 0 then
         H := H xor (Position_Hash (G.EP_Sq) * 16#ABCDEF01#);
      end if;
      return H;
   end Compute_Hash;

   function Is_Insufficient_Material (B : Board_State) return Boolean is
      WN, WB, BN, BB_Cnt : Natural  := 0;
      Has_Power           : Boolean := False;
   begin
      for Sq in Square_Index loop
         case B.Squares (Sq) is
            when WKnight => WN := WN + 1;
            when WBishop => WB := WB + 1;
            when BKnight => BN := BN + 1;
            when BBishop => BB_Cnt := BB_Cnt + 1;
            when WPawn | BPawn | WRook | BRook | WQueen | BQueen =>
               Has_Power := True;
            when others => null;
         end case;
      end loop;
      if Has_Power then return False; end if;
      return (WN = 0 and WB = 0 and BN = 0 and BB_Cnt = 0)   -- K vs K
         or else (WN + WB = 1 and BN = 0 and BB_Cnt = 0)     -- K+minor vs K
         or else (BN + BB_Cnt = 1 and WN = 0 and WB = 0);    -- K vs K+minor
   end Is_Insufficient_Material;

   -- =========================================================
   --  Legal-move existence check (for mate/stalemate detection)
   -- =========================================================

   function Has_Legal_Move (G : Game_State) return Boolean is

      function Try (From, To : Square_Index; P : Piece_Code) return Boolean is
         Dest   : constant Piece_Code := G.Position.Squares (To);
         DF     : constant Integer    :=
            Integer (File_Of (To)) - Integer (File_Of (From));
         DR     : constant Integer    :=
            Integer (Row_Of  (To)) - Integer (Row_Of  (From));
         Fwd    : constant Integer    := (if P = WPawn then -1 else 1);
         Temp_B : Board_State         := G.Position;
      begin
         if From = To then return False; end if;
         --  Can't land on own piece
         if Dest /= Empty and then Is_White_Piece (Dest) = (G.Active = White) then
            return False;
         end if;
         if Is_Pawn (P) then
            if not (
               (DF = 0 and then DR = Fwd and then Dest = Empty)
               or else (DF = 0 and then DR = 2 * Fwd and then Dest = Empty
                        and then Row_Of (From) = (if P = WPawn then 6 else 1)
                        and then G.Position.Squares
                           (Sq_At (Row_Of (From) + Fwd, File_Of (From))) = Empty)
               or else (abs DF = 1 and then DR = Fwd
                        and then (Dest /= Empty
                                  or else (G.EP_Sq >= 0
                                           and then Integer (To) = G.EP_Sq))))
            then return False; end if;
         elsif not Can_Attack (G.Position, From, To, P) then
            return False;
         end if;
         --  Apply move and test for self-check
         Temp_B.Squares (From) := Empty;
         Temp_B.Squares (To)   := P;
         if Is_Pawn (P) and then G.EP_Sq >= 0 and then Integer (To) = G.EP_Sq then
            Temp_B.Squares (Sq_At (Row_Of (To) + (if P = WPawn then 1 else -1),
                                    File_Of (To))) := Empty;
         end if;
         return not Is_In_Check (Temp_B, G.Active);
      end Try;

   begin
      for From in Square_Index loop
         declare
            P : constant Piece_Code := G.Position.Squares (From);
         begin
            if P /= Empty and then Is_White_Piece (P) = (G.Active = White) then
               for To in Square_Index loop
                  if Try (From, To, P) then return True; end if;
               end loop;
            end if;
         end;
      end loop;
      return False;
   end Has_Legal_Move;

   -- =========================================================
   --  Commit a completed move
   -- =========================================================

   procedure Commit (G : in out Game_State; M : Move) is
      Mv : Move := M;
   begin
      Mv.Brd_Before := G.Pre_Move;
      Mv.MV_Nr      := G.Fullmove;
      Mv.MV_Color   := G.Active;
      if G.N_Moves < Max_Ply then
         --  Save undo entry before any state mutation
         G.Undo_Stack (G.N_Moves + 1) :=
            (Position => G.Pre_Move,
             Active   => G.Active,
             Castling => G.Pre_Castling,
             EP_Sq    => G.Pre_EP,
             Halfmove => G.Pre_Halfmove,
             Fullmove => G.Pre_Fullmove);
         G.N_Moves := G.N_Moves + 1;
         G.History (G.N_Moves) := Mv;
      end if;
      if G.Active = Black then
         G.Fullmove := G.Fullmove + 1;
      end if;
      G.Active := Opponent (G.Active);
      if Is_Pawn (M.Piece) or M.Captured /= Empty then
         G.Halfmove := 0;
      else
         G.Halfmove := G.Halfmove + 1;
      end if;
      if Is_Double_Push (M.Piece, M.From, M.To) then
         G.EP_Sq := Double_Push_EP_Sq (M.From, M.To);
      else
         G.EP_Sq := -1;
      end if;
      --  Check / mate / stalemate / 50-move detection
      if G.Outcome = Ongoing then
         declare
            In_Check : constant Boolean := Is_In_Check (G.Position, G.Active);
            Has_Move : constant Boolean := Has_Legal_Move (G);
         begin
            if G.N_Moves > 0 then
               G.History (G.N_Moves).Is_Check := In_Check;
               G.History (G.N_Moves).Is_Mate  := In_Check and then not Has_Move;
            end if;
            if not Has_Move then
               if In_Check then
                  G.Outcome := (if G.Active = White then Black_Wins else White_Wins);
               else
                  G.Outcome := Draw;  -- stalemate
               end if;
            elsif G.Halfmove >= 100 then
               G.Outcome := Draw;  -- 50-move rule
            elsif Is_Insufficient_Material (G.Position) then
               G.Outcome := Draw;  -- dead position
            else
               --  Threefold repetition
               declare
                  H     : constant Position_Hash := Compute_Hash (G);
                  Count : Natural := 1;
               begin
                  if G.N_Hashes < Hash_Array'Last then
                     G.N_Hashes := G.N_Hashes + 1;
                     G.Pos_Hashes (G.N_Hashes) := H;
                  end if;
                  for I in 1 .. G.N_Hashes - 1 loop
                     if G.Pos_Hashes (I) = H then Count := Count + 1; end if;
                  end loop;
                  if Count >= 3 then G.Outcome := Draw; end if;
               end;
            end if;
         end;
      end if;
   end Commit;

   -- =========================================================
   --  Update (move-detection state machine)
   -- =========================================================

   procedure Update
     (G        : in out Game_State;
      Square   : Board.Square_Index;
      Piece    : Protocol.Piece_Code;
      Complete : out Boolean;
      Illegal  : out Boolean;
      Last     : out Move)
   is
   begin
      Complete := False;
      Illegal  := False;
      Last     := (others => <>);

      if Piece = Empty then
         --  ---- LIFT event ----
         case G.Phase is

            when Idle =>
               G.Pre_Move     := G.Position;
               G.Pre_Castling := G.Castling;
               G.Pre_EP       := G.EP_Sq;
               G.Pre_Halfmove := G.Halfmove;
               G.Pre_Fullmove := G.Fullmove;
               G.Lift_From    := Square;
               G.Lift_Piece   := G.Position.Squares (Square);
               G.Position.Squares (Square) := Empty;
               G.Phase        := Holding;

            when Holding =>
               declare
                  Second : constant Piece_Code := G.Position.Squares (Square);
               begin
                  if G.Lift_Piece /= Empty
                     and then Second /= Empty
                     and then Is_White_Piece (Second) /= Is_White_Piece (G.Lift_Piece)
                  then
                     --  Some players lift the target piece before putting down the
                     --  capturing piece (common habit).  Leave the target in
                     --  G.Position so the Place handler records it as Captured.
                     --  G.Pre_Move was saved at the first lift and already holds
                     --  the correct pre-capture snapshot.
                     null;
                  else
                     --  Changed mind: restore the held piece and start fresh.
                     G.Position.Squares (G.Lift_From) := G.Lift_Piece;
                     --  Only track new lift if it is the active color's piece.
                     if Second = Empty
                        or else Is_White_Piece (Second) /= (G.Active = White)
                     then
                        G.Phase := Idle;
                        return;
                     end if;
                     G.Pre_Move     := G.Position;
                     G.Pre_Castling := G.Castling;
                     G.Pre_EP       := G.EP_Sq;
                     G.Pre_Halfmove := G.Halfmove;
                     G.Pre_Fullmove := G.Fullmove;
                     G.Lift_From    := Square;
                     G.Lift_Piece   := Second;
                     G.Position.Squares (Square) := Empty;
                  end if;
               end;

            when Castle_Rook_Lift =>
               G.Rook_From := Square;
               G.Position.Squares (Square) := Empty;
               G.Phase := Castle_Rook_Place;

            when EP_Cleanup =>
               if Square = G.EP_Cap_Sq then
                  G.Position.Squares (Square) := Empty;
                  G.Phase := Idle;
               else
                  --  Unexpected; treat as new lift
                  G.Pre_Move       := G.Position;
                  G.Lift_From        := Square;
                  G.Lift_Piece       := G.Position.Squares (Square);
                  G.Position.Squares (Square) := Empty;
                  G.Phase := Holding;
               end if;

            when Castle_Rook_Place => null;  -- shouldn't happen
         end case;

      else
         --  ---- PLACE event ----
         case G.Phase is

            when Holding =>
               declare
                  Captured : constant Piece_Code := G.Position.Squares (Square);
               begin
                  --  Ghost lift: sensor glitch or the user sliding a rejected piece
                  --  back across empty squares.  Updating G.Position here would
                  --  inject phantom pieces that corrupt Pre_Move for future moves.
                  if G.Lift_Piece = Empty then
                     G.Phase := Idle;
                     return;
                  end if;

                  --  Wrong-color piece moved: restore board and flag illegal.
                  if Is_White_Piece (G.Lift_Piece) /= (G.Active = White) then
                     G.Position := G.Pre_Move;
                     G.Castling := G.Pre_Castling;
                     G.EP_Sq    := G.Pre_EP;
                     G.Phase    := Idle;
                     Illegal    := True;
                     return;
                  end if;

                  G.Position.Squares (Square) := Piece;
                  G.Pend := (From     => G.Lift_From,
                             To       => Square,
                             Piece    => G.Lift_Piece,
                             Captured => Captured,
                             others   => <>);

                  if Is_Castling (G.Lift_Piece, G.Lift_From, Square) then
                     G.Pend.Castle_K := Integer (Square) > Integer (G.Lift_From);
                     G.Pend.Castle_Q := Integer (Square) < Integer (G.Lift_From);
                     --  Castling is illegal if:
                     --  (1) king is in check before castling,
                     --  (2) king passes through an attacked square, or
                     --  (3) king lands on an attacked square.
                     declare
                        Mid_Sq : constant Square_Index :=
                           Square_Index
                              ((Integer (G.Lift_From) + Integer (Square)) / 2);
                        Temp_B : Board_State := G.Pre_Move;
                     begin
                        Temp_B.Squares (G.Lift_From) := Empty;
                        Temp_B.Squares (Mid_Sq)      := G.Lift_Piece;
                        if Is_In_Check (G.Pre_Move, G.Active)
                           or else Is_Attacked (Temp_B, Mid_Sq, Opponent (G.Active))
                           or else Is_Attacked (G.Position, Square, Opponent (G.Active))
                        then
                           G.Position := G.Pre_Move;
                           G.Phase    := Idle;
                           Illegal    := True;
                           return;
                        end if;
                     end;
                     Kill_Castling (G.Castling, G.Lift_From);
                     G.Phase := Castle_Rook_Lift;

                  elsif Is_EP_Capture (G.Lift_Piece, G.Lift_From, Square, Captured = Empty) then
                     --  Diagonal pawn move to empty square: only legal when it matches
                     --  the current EP target square.
                     if G.EP_Sq < 0 or else Integer (Square) /= G.EP_Sq then
                        G.Position := G.Pre_Move;
                        G.Phase    := Idle;
                        Illegal    := True;
                        return;
                     end if;
                     G.Pend.Is_EP    := True;
                     G.EP_Cap_Sq     := EP_Captured_Sq (G.Lift_Piece, Square);
                     G.Pend.Captured := G.Position.Squares (G.EP_Cap_Sq);
                     --  The captured pawn is still on the board; remove it for the
                     --  check test so the position reflects the true result.
                     declare
                        Temp_B : Board_State := G.Position;
                     begin
                        Temp_B.Squares (G.EP_Cap_Sq) := Empty;
                        if Is_In_Check (Temp_B, G.Active) then
                           G.Position := G.Pre_Move;
                           G.Phase    := Idle;
                           Illegal    := True;
                           return;
                        end if;
                     end;
                     Kill_Castling (G.Castling, G.Lift_From);
                     declare M_Tmp : constant Move := G.Pend; begin Commit (G, M_Tmp); end;
                     Complete := True;
                     Last     := G.History (G.N_Moves);
                     G.Phase  := EP_Cleanup;

                  else
                     --  Geometry check: verify the piece can physically reach Square.
                     --  For pawns Can_Attack only covers diagonal captures, so the
                     --  forward-push cases are checked explicitly here.
                     declare
                        Geo_OK : Boolean;
                        DF  : constant Integer :=
                           Integer (File_Of (Square)) - Integer (File_Of (G.Lift_From));
                        DR  : constant Integer :=
                           Integer (Row_Of  (Square)) - Integer (Row_Of  (G.Lift_From));
                        Fwd : constant Integer :=
                           (if G.Lift_Piece = WPawn then -1 else 1);
                     begin
                        if Is_Pawn (G.Lift_Piece) then
                           Geo_OK :=
                              --  One-square push to empty square
                              (DF = 0 and then DR = Fwd and then Captured = Empty)
                              --  Two-square push from start rank with clear intermediate
                              or else (DF = 0 and then DR = 2 * Fwd
                                       and then Captured = Empty
                                       and then Row_Of (G.Lift_From) =
                                          (if G.Lift_Piece = WPawn then 6 else 1)
                                       and then G.Pre_Move.Squares
                                          (Sq_At (Row_Of (G.Lift_From) + Fwd,
                                                  File_Of (G.Lift_From))) = Empty)
                              --  Normal diagonal capture (non-EP, destination occupied)
                              or else (abs DF = 1 and then DR = Fwd
                                       and then Captured /= Empty);
                        else
                           Geo_OK :=
                              Can_Attack (G.Pre_Move, G.Lift_From, Square, G.Lift_Piece);
                        end if;
                        if not Geo_OK then
                           G.Position := G.Pre_Move;
                           G.Phase    := Idle;
                           Illegal    := True;
                           return;
                        end if;
                     end;
                     if Is_Promo (G.Lift_Piece, Square) then
                        G.Pend.Promo_To := Piece;  -- the placed piece IS the promoted piece
                        G.Pend.Piece    := G.Lift_Piece;
                     end if;
                     if Is_In_Check (G.Position, G.Active) then
                        G.Position := G.Pre_Move;
                        G.Phase    := Idle;
                        Illegal    := True;
                        return;
                     end if;
                     Kill_Castling (G.Castling, G.Lift_From);
                     Kill_Castling (G.Castling, Square);
                     declare M_Tmp : constant Move := G.Pend; begin Commit (G, M_Tmp); end;
                     Complete := True;
                     Last     := G.History (G.N_Moves);
                     G.Phase  := Idle;
                  end if;
               end;

            when Castle_Rook_Place =>
               G.Position.Squares (Square) := Piece;
               Kill_Castling (G.Castling, G.Rook_From);
               declare M_Tmp : constant Move := G.Pend; begin Commit (G, M_Tmp); end;
               Complete := True;
               Last     := G.History (G.N_Moves);
               G.Phase  := Idle;

            when Idle | Castle_Rook_Lift | EP_Cleanup =>
               G.Position.Squares (Square) := Piece;
         end case;
      end if;
   end Update;

   -- =========================================================
   --  SAN helpers
   -- =========================================================

   function Piece_Letter (P : Piece_Code) return Character is
   begin
      case P is
         when WKnight | BKnight => return 'N';
         when WBishop | BBishop => return 'B';
         when WRook   | BRook   => return 'R';
         when WQueen  | BQueen  => return 'Q';
         when WKing   | BKing   => return 'K';
         when others            => return ' ';
      end case;
   end Piece_Letter;

   function Promo_Letter (P : Piece_Code) return Character is
   begin
      case P is
         when WRook   | BRook   => return 'r';
         when WBishop | BBishop => return 'b';
         when WKnight | BKnight => return 'n';
         when others            => return 'q';  -- queen default
      end case;
   end Promo_Letter;

   function Move_SAN (M : Move) return String is
      B   : Board_State renames M.Brd_Before;
      Buf : String (1 .. 12) := (others => ' ');
      Pos : Natural := 0;

      procedure P (C : Character) is begin Pos := Pos + 1; Buf (Pos) := C; end P;

      procedure Add_Check is
      begin
         if M.Is_Mate then P ('#'); elsif M.Is_Check then P ('+'); end if;
      end Add_Check;

      Dest_F : constant Character := File_Char (M.To);
      Dest_R : constant Character := Rank_Char (M.To);
   begin
      if M.Castle_K then
         Buf (1 .. 3) := "O-O"; Pos := 3; Add_Check;
         return Buf (1 .. Pos);
      end if;
      if M.Castle_Q then
         Buf (1 .. 5) := "O-O-O"; Pos := 5; Add_Check;
         return Buf (1 .. Pos);
      end if;

      if Is_Pawn (M.Piece) then
         if M.Captured /= Empty or M.Is_EP then
            P (File_Char (M.From)); P ('x');
         end if;
         P (Dest_F); P (Dest_R);
         if M.Promo_To /= Empty then
            P ('='); P (Promo_Letter (M.Promo_To));
         end if;
         Add_Check;
         return Buf (1 .. Pos);
      end if;

      --  Count other pieces of same type that can also reach M.To
      P (Piece_Letter (M.Piece));
      declare
         N_Same_File : Natural := 0;
         N_Same_Rank : Natural := 0;
         N_Others    : Natural := 0;
      begin
         for Sq in Square_Index loop
            if Sq /= M.From and then B.Squares (Sq) = M.Piece
               and then Can_Attack (B, Sq, M.To, M.Piece)
            then
               N_Others := N_Others + 1;
               if File_Of (Sq) = File_Of (M.From) then N_Same_File := N_Same_File + 1; end if;
               if Row_Of  (Sq) = Row_Of  (M.From) then N_Same_Rank := N_Same_Rank + 1; end if;
            end if;
         end loop;
         if N_Others > 0 then
            if N_Same_File = 0 then
               P (File_Char (M.From));
            elsif N_Same_Rank = 0 then
               P (Rank_Char (M.From));
            else
               P (File_Char (M.From)); P (Rank_Char (M.From));
            end if;
         end if;
      end;
      if M.Captured /= Empty then P ('x'); end if;
      P (Dest_F); P (Dest_R);
      Add_Check;
      return Buf (1 .. Pos);
   end Move_SAN;

   function Move_UCI (M : Move) return String is
      S : String (1 .. 5);
   begin
      S (1) := File_Char (M.From); S (2) := Rank_Char (M.From);
      S (3) := File_Char (M.To);   S (4) := Rank_Char (M.To);
      if M.Promo_To /= Empty then
         S (5) := Promo_Letter (M.Promo_To);
         return S;
      end if;
      return S (1 .. 4);
   end Move_UCI;

   -- =========================================================
   --  Full FEN
   -- =========================================================

   function To_FEN (G : Game_State) return String is

      function Color_Ch return String is (if G.Active = White then "w" else "b");

      function Castle_Str return String is
         S : String (1 .. 4);
         N : Natural := 0;
      begin
         if G.Castling.WK then N := N + 1; S (N) := 'K'; end if;
         if G.Castling.WQ then N := N + 1; S (N) := 'Q'; end if;
         if G.Castling.BK then N := N + 1; S (N) := 'k'; end if;
         if G.Castling.BQ then N := N + 1; S (N) := 'q'; end if;
         if N = 0 then return "-"; end if;
         return S (1 .. N);
      end Castle_Str;

      function EP_Str return String is
      begin
         if G.EP_Sq < 0 then return "-"; end if;
         declare Sq : constant Square_Index := Square_Index (G.EP_Sq); begin
            return (1 => File_Char (Sq), 2 => Rank_Char (Sq));
         end;
      end EP_Str;

      HM : constant String := Natural'Image  (G.Halfmove);
      FM : constant String := Positive'Image (G.Fullmove);
   begin
      return Board.To_FEN (G.Position)
         & " " & Color_Ch
         & " " & Castle_Str
         & " " & EP_Str
         & " " & HM (2 .. HM'Last)
         & " " & FM (2 .. FM'Last);
   end To_FEN;

   -- =========================================================
   --  PGN export
   -- =========================================================

   function To_PGN (G : Game_State) return String is
      Buf : String (1 .. 16_384) := (others => ' ');
      Pos : Natural := 0;

      procedure P (S : String) is
      begin
         Buf (Pos + 1 .. Pos + S'Length) := S;
         Pos := Pos + S'Length;
      end P;

      procedure NL is begin P ((1 => ASCII.LF)); end NL;

      function Img (N : Natural) return String is
         S : constant String := Natural'Image (N);
      begin return S (2 .. S'Last); end Img;

   begin
      declare
         Res : constant String :=
            (case G.Outcome is
               when White_Wins => "1-0",
               when Black_Wins => "0-1",
               when Draw       => "1/2-1/2",
               when Ongoing    => "*");
      begin
         P ("[Event ""?""]");  NL;
         P ("[Site ""?""]");   NL;
         P ("[Date """ & G.Start_Date & """]"); NL;
         P ("[Round ""?""]");  NL;
         P ("[White """ & G.White_Name (1 .. G.White_Nlen) & """]"); NL;
         P ("[Black """ & G.Black_Name (1 .. G.Black_Nlen) & """]"); NL;
         P ("[Result """ & Res & """]"); NL;
         NL;

         for I in 1 .. G.N_Moves loop
            declare
               Mv : Move renames G.History (I);
            begin
               if Mv.MV_Color = White then
                  P (Img (Mv.MV_Nr)); P (". ");
               elsif I = 1 then
                  P (Img (Mv.MV_Nr)); P ("... ");
               end if;
               P (Move_SAN (Mv));
               if Mv.Comment_Len > 0 then
                  P (" {"); P (Mv.Comment (1 .. Mv.Comment_Len)); P ("}");
               end if;
               P (" ");
               if Pos mod 80 > 72 then NL; end if;
            end;
         end loop;
         P (Res); NL;
      end;
      return Buf (1 .. Pos);
   end To_PGN;

   -- =========================================================
   --  Constructors / accessors
   -- =========================================================

   function New_Game (B : Board.Board_State; Active : Color := White)
      return Game_State
   is
      G   : Game_State;
      Img : constant String := Ada.Calendar.Formatting.Image (Ada.Calendar.Clock);
   begin
      G.Position := B;
      G.Active   := Active;
      --  Date in PGN format YYYY.MM.DD
      G.Start_Date (1 .. 4) := Img (1 .. 4);
      G.Start_Date (5)       := '.';
      G.Start_Date (6 .. 7)  := Img (6 .. 7);
      G.Start_Date (8)        := '.';
      G.Start_Date (9 .. 10) := Img (9 .. 10);
      --  Record starting position hash
      G.N_Hashes := 1;
      G.Pos_Hashes (1) := Compute_Hash (G);
      return G;
   end New_Game;

   function Current_Board (G : Game_State) return Board.Board_State is (G.Position);
   function Active_Color  (G : Game_State) return Color               is (G.Active);
   function Move_Count    (G : Game_State) return Natural              is (G.N_Moves);
   function Game_Outcome  (G : Game_State) return Game_Result         is (G.Outcome);

   procedure Undo (G : in out Game_State) is
   begin
      if G.N_Moves = 0 then return; end if;
      declare
         U : Undo_Entry renames G.Undo_Stack (G.N_Moves);
      begin
         G.Position := U.Position;
         G.Active   := U.Active;
         G.Castling := U.Castling;
         G.EP_Sq    := U.EP_Sq;
         G.Halfmove := U.Halfmove;
         G.Fullmove := U.Fullmove;
      end;
      G.N_Moves  := G.N_Moves - 1;
      if G.N_Hashes > 0 then G.N_Hashes := G.N_Hashes - 1; end if;
      G.Outcome  := Ongoing;
      G.Phase    := Idle;
   end Undo;

   procedure Reset_Position (G : in out Game_State; B : Board.Board_State) is
   begin
      G.Position := B;
      G.Phase    := Idle;
   end Reset_Position;

   procedure Set_Outcome (G : in out Game_State; Result : Game_Result) is
   begin
      G.Outcome := Result;
   end Set_Outcome;

   procedure Set_Move_Comment (G : in out Game_State; N : Positive; S : String) is
      L : constant Natural := Natural'Min (S'Length, 80);
   begin
      if N <= G.N_Moves then
         G.History (N).Comment (1 .. L) := S (S'First .. S'First + L - 1);
         G.History (N).Comment_Len := L;
      end if;
   end Set_Move_Comment;

   procedure Set_Player (G : in out Game_State; Is_White : Boolean; Name : String) is
      L : constant Natural := Natural'Min (Name'Length, 64);
   begin
      if Is_White then
         G.White_Name (1 .. L) := Name (Name'First .. Name'First + L - 1);
         G.White_Nlen := L;
      else
         G.Black_Name (1 .. L) := Name (Name'First .. Name'First + L - 1);
         G.Black_Nlen := L;
      end if;
   end Set_Player;

   function From_FEN (Fen : String) return Game_State is
      G : Game_State;

      function Field_End (Start : Natural) return Natural is
         I : Natural := Start;
      begin
         while I <= Fen'Last and then Fen (I) /= ' ' loop
            I := I + 1;
         end loop;
         return I - 1;
      end Field_End;

      function Next_Start (After : Natural) return Natural is
         I : Natural := After + 1;
      begin
         while I <= Fen'Last and then Fen (I) = ' ' loop
            I := I + 1;
         end loop;
         return I;
      end Next_Start;

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

      function Char_To_Piece (C : Character) return Piece_Code is
      begin
         case C is
            when 'P' => return WPawn;   when 'R' => return WRook;
            when 'N' => return WKnight; when 'B' => return WBishop;
            when 'K' => return WKing;   when 'Q' => return WQueen;
            when 'p' => return BPawn;   when 'r' => return BRook;
            when 'n' => return BKnight; when 'b' => return BBishop;
            when 'k' => return BKing;   when 'q' => return BQueen;
            when others => return Empty;
         end case;
      end Char_To_Piece;

      S1 : constant Natural := Fen'First;
      E1 : constant Natural := Field_End (S1);
      S2 : constant Natural := Next_Start (E1);
      E2 : constant Natural := Field_End (S2);
      S3 : constant Natural := Next_Start (E2);
      E3 : constant Natural := Field_End (S3);
      S4 : constant Natural := Next_Start (E3);
      E4 : constant Natural := Field_End (S4);
      S5 : constant Natural := Next_Start (E4);
      E5 : constant Natural := Field_End (S5);
      S6 : constant Natural := Next_Start (E5);
      E6 : constant Natural := Field_End (S6);

   begin
      --  Field 1: piece placement (rank 8 first)
      declare
         Row : Natural := 0;
         Col : Natural := 0;
      begin
         for I in S1 .. E1 loop
            case Fen (I) is
               when '/' => Row := Row + 1; Col := 0;
               when '1' .. '8' =>
                  Col := Col + Character'Pos (Fen (I)) - Character'Pos ('0');
               when 'P'|'R'|'N'|'B'|'K'|'Q'|'p'|'r'|'n'|'b'|'k'|'q' =>
                  if Row < 8 and then Col < 8 then
                     G.Position.Squares (Board.Square_Index (Row * 8 + Col)) :=
                        Char_To_Piece (Fen (I));
                  end if;
                  Col := Col + 1;
               when others => null;
            end case;
         end loop;
      end;

      --  Field 2: active color
      G.Active := (if S2 <= E2 and then Fen (S2) = 'b' then Black else White);

      --  Field 3: castling rights
      G.Castling := (WK => False, WQ => False, BK => False, BQ => False);
      for I in S3 .. E3 loop
         case Fen (I) is
            when 'K' => G.Castling.WK := True;
            when 'Q' => G.Castling.WQ := True;
            when 'k' => G.Castling.BK := True;
            when 'q' => G.Castling.BQ := True;
            when others => null;
         end case;
      end loop;

      --  Field 4: en-passant target square
      G.EP_Sq := -1;
      if S4 <= E4 and then Fen (S4) /= '-' and then E4 - S4 >= 1 then
         declare
            F : constant Natural := Character'Pos (Fen (S4))     - Character'Pos ('a');
            R : constant Natural := Character'Pos (Fen (S4 + 1)) - Character'Pos ('1');
         begin
            if F < 8 and then R < 8 then
               G.EP_Sq := Integer ((7 - R) * 8 + F);
            end if;
         end;
      end if;

      --  Field 5: halfmove clock
      G.Halfmove := (if S5 <= E5 then Parse_Nat (Fen (S5 .. E5)) else 0);

      --  Field 6: fullmove number
      declare
         V : constant Natural := (if S6 <= E6 then Parse_Nat (Fen (S6 .. E6)) else 1);
      begin
         G.Fullmove := (if V > 0 then V else 1);
      end;

      --  Set start date
      declare
         Img : constant String := Ada.Calendar.Formatting.Image (Ada.Calendar.Clock);
      begin
         G.Start_Date (1 .. 4) := Img (1 .. 4);
         G.Start_Date (5)      := '.';
         G.Start_Date (6 .. 7) := Img (6 .. 7);
         G.Start_Date (8)      := '.';
         G.Start_Date (9 .. 10):= Img (9 .. 10);
      end;

      G.N_Hashes       := 1;
      G.Pos_Hashes (1) := Compute_Hash (G);
      return G;
   end From_FEN;

   -- =========================================================
   --  Apply UCI / SAN moves programmatically (used for !load)
   -- =========================================================

   function Apply_UCI (G : in out Game_State; UCI : String) return Boolean is
      function FN (C : Character) return Natural is
         (Character'Pos (C) - Character'Pos ('a'));
      function RN (C : Character) return Natural is
         (Character'Pos (C) - Character'Pos ('1'));
      function Sq (F, R : Natural) return Board.Square_Index is
         (Board.Square_Index ((7 - R) * 8 + F));
   begin
      if UCI'Length < 4 then return False; end if;
      declare
         I  : constant Natural := UCI'First;
         FF : constant Natural := FN (UCI (I));
         FR : constant Natural := RN (UCI (I + 1));
         TF : constant Natural := FN (UCI (I + 2));
         TR : constant Natural := RN (UCI (I + 3));
      begin
         if FF > 7 or else FR > 7 or else TF > 7 or else TR > 7 then
            return False;
         end if;
         declare
            From  : constant Board.Square_Index := Sq (FF, FR);
            To_Sq : constant Board.Square_Index := Sq (TF, TR);
            P     : constant Piece_Code         := G.Position.Squares (From);
            Promo : Piece_Code                  := Empty;
         begin
            if P = Empty then return False; end if;
            if G.Active = White
               and then P not in WPawn|WRook|WKnight|WBishop|WKing|WQueen
            then return False; end if;
            if G.Active = Black
               and then P in WPawn|WRook|WKnight|WBishop|WKing|WQueen
            then return False; end if;

            if UCI'Length >= 5 then
               case UCI (I + 4) is
                  when 'q'|'Q' => Promo := (if G.Active=White then WQueen  else BQueen);
                  when 'r'|'R' => Promo := (if G.Active=White then WRook   else BRook);
                  when 'b'|'B' => Promo := (if G.Active=White then WBishop else BBishop);
                  when 'n'|'N' => Promo := (if G.Active=White then WKnight else BKnight);
                  when others  => null;
               end case;
            end if;

            G.Pre_Move     := G.Position;
            G.Pre_Castling := G.Castling;
            G.Pre_EP       := G.EP_Sq;
            G.Pre_Halfmove := G.Halfmove;
            G.Pre_Fullmove := G.Fullmove;

            declare
               Castling : constant Boolean :=
                  P in WKing | BKing and then
                  abs (Integer (File_Of (To_Sq)) - Integer (File_Of (From))) = 2;
               Is_EP : constant Boolean :=
                  Is_Pawn (P) and then
                  File_Of (From) /= File_Of (To_Sq) and then
                  G.Position.Squares (To_Sq) = Empty;
               M : Move :=
                  (From     => From,
                   To       => To_Sq,
                   Piece    => P,
                   Captured => G.Position.Squares (To_Sq),
                   Promo_To => Promo,
                   others   => <>);
            begin
               M.Castle_K := Castling and then File_Of (To_Sq) > File_Of (From);
               M.Castle_Q := Castling and then File_Of (To_Sq) < File_Of (From);
               M.Is_EP    := Is_EP;
               if Is_EP then
                  M.Captured := (if G.Active = White then BPawn else WPawn);
               end if;

               if Castling then
                  --  Reject if king is currently in check or passes through
                  --  an attacked intermediate square (FIDE Art. 3.8.2).
                  declare
                     Mid_Sq : constant Board.Square_Index :=
                        Board.Square_Index
                           ((Integer (From) + Integer (To_Sq)) / 2);
                     Temp_B : Board_State := G.Pre_Move;
                  begin
                     Temp_B.Squares (From)   := Empty;
                     Temp_B.Squares (Mid_Sq) := P;
                     if Is_In_Check (G.Pre_Move, G.Active)
                        or else Is_Attacked (Temp_B, Mid_Sq, Opponent (G.Active))
                     then
                        G.Position := G.Pre_Move;
                        G.EP_Sq    := G.Pre_EP;
                        G.Castling := G.Pre_Castling;
                        G.Halfmove := G.Pre_Halfmove;
                        G.Fullmove := G.Pre_Fullmove;
                        return False;
                     end if;
                  end;
                  declare
                     R_Col_From : constant Natural :=
                        (if M.Castle_K then 7 else 0);
                     R_Col_To   : constant Natural :=
                        (if M.Castle_K then 5 else 3);
                     R_Row      : constant Natural := Row_Of (From);
                     R_From     : constant Board.Square_Index :=
                        Board.Square_Index (R_Row * 8 + R_Col_From);
                     R_To       : constant Board.Square_Index :=
                        Board.Square_Index (R_Row * 8 + R_Col_To);
                  begin
                     G.Position.Squares (To_Sq)  := P;
                     G.Position.Squares (From)   := Empty;
                     G.Position.Squares (R_To)   := G.Position.Squares (R_From);
                     G.Position.Squares (R_From) := Empty;
                  end;
               elsif Is_EP then
                  declare
                     Cap_Row : constant Natural :=
                        Row_Of (To_Sq) + (if G.Active = White then 1 else -1);
                  begin
                     G.Position.Squares (To_Sq) := P;
                     G.Position.Squares (From)  := Empty;
                     G.Position.Squares (Board.Square_Index (
                        Cap_Row * 8 + File_Of (To_Sq))) := Empty;
                  end;
               else
                  G.Position.Squares (To_Sq) := (if Promo /= Empty then Promo else P);
                  G.Position.Squares (From)  := Empty;
               end if;

               if Is_In_Check (G.Position, G.Active) then
                  G.Position := G.Pre_Move;
                  G.EP_Sq    := G.Pre_EP;
                  G.Castling := G.Pre_Castling;
                  G.Halfmove := G.Pre_Halfmove;
                  G.Fullmove := G.Pre_Fullmove;
                  return False;
               end if;

               Kill_Castling (G.Castling, From);
               Kill_Castling (G.Castling, To_Sq);
               Commit (G, M);
               return True;
            end;
         end;
      end;
   end Apply_UCI;

   function Apply_SAN (G : in out Game_State; SAN : String) return Boolean is
      S    : String (1 .. 16) := (others => ' ');
      Slen : Natural          := Natural'Min (SAN'Length, 16);

      function Is_File (C : Character) return Boolean is (C in 'a' .. 'h');
      function Is_Rank (C : Character) return Boolean is (C in '1' .. '8');
      function To_File (C : Character) return Natural is
         (Character'Pos (C) - Character'Pos ('a'));
      function To_Row (C : Character) return Natural is
         (7 - (Character'Pos (C) - Character'Pos ('1')));
      function Sq_Name (Sq : Board.Square_Index) return String is
         (1 => File_Char (Sq), 2 => Rank_Char (Sq));

      function Promo_UCI (C : Character) return String is
      begin
         case C is
            when 'Q'|'q' => return "q";
            when 'R'|'r' => return "r";
            when 'B'|'b' => return "b";
            when 'N'|'n' => return "n";
            when others  => return "";
         end case;
      end Promo_UCI;
   begin
      S (1 .. Slen) := SAN (SAN'First .. SAN'First + Slen - 1);
      while Slen > 0 and then S (Slen) in '+' | '#' loop
         Slen := Slen - 1;
      end loop;
      if Slen = 0 then return False; end if;

      --  Castling
      declare
         Tok : constant String := S (1 .. Slen);
         King_From : constant Board.Square_Index :=
            (if G.Active = White then 60 else 4);
      begin
         if Tok = "O-O-O" or else Tok = "0-0-0" then
            return Apply_UCI (G,
               Sq_Name (King_From) & Sq_Name (Board.Square_Index (
                  Row_Of (King_From) * 8 + 2)));
         elsif Tok = "O-O" or else Tok = "0-0" then
            return Apply_UCI (G,
               Sq_Name (King_From) & Sq_Name (Board.Square_Index (
                  Row_Of (King_From) * 8 + 6)));
         end if;
      end;

      --  Promotion suffix
      declare
         Promo_Str : String (1 .. 1) := (1 => ' ');
      begin
         if Slen >= 4 and then S (Slen - 1) = '=' then
            Promo_Str (1) := S (Slen);
            Slen := Slen - 2;
         end if;

         --  Destination (last 2 chars)
         if Slen < 2
            or else not Is_File (S (Slen - 1))
            or else not Is_Rank (S (Slen))
         then return False; end if;

         declare
            Dest_N  : constant String  := (1 => S (Slen - 1), 2 => S (Slen));
            Promo_N : constant String := Promo_UCI (Promo_Str (1));
         begin
            Slen := Slen - 2;
            if Slen >= 1 and then S (Slen) = 'x' then Slen := Slen - 1; end if;

            declare
               Piece     : Piece_Code :=
                  (if G.Active = White then WPawn else BPawn);
               Disc_File : Integer    := -1;
               Disc_Row  : Integer    := -1;
               Ptr       : Natural    := 1;
            begin
               if Slen >= 1 and then S (1) in 'A' .. 'Z' then
                  case S (1) is
                     when 'N' => Piece := (if G.Active=White then WKnight else BKnight);
                     when 'B' => Piece := (if G.Active=White then WBishop else BBishop);
                     when 'R' => Piece := (if G.Active=White then WRook   else BRook);
                     when 'Q' => Piece := (if G.Active=White then WQueen  else BQueen);
                     when 'K' => Piece := (if G.Active=White then WKing   else BKing);
                     when others => return False;
                  end case;
                  Ptr := 2;
               end if;
               if Ptr <= Slen and then Is_File (S (Ptr)) then
                  Disc_File := Integer (To_File (S (Ptr)));
                  Ptr := Ptr + 1;
               end if;
               if Ptr <= Slen and then Is_Rank (S (Ptr)) then
                  Disc_Row := Integer (To_Row (S (Ptr)));
               end if;

               for From in Board.Square_Index loop
                  if G.Position.Squares (From) = Piece
                     and then (Disc_File < 0
                                or else Integer (File_Of (From)) = Disc_File)
                     and then (Disc_Row < 0
                                or else Integer (Row_Of (From)) = Disc_Row)
                  then
                     if Apply_UCI (G, Sq_Name (From) & Dest_N & Promo_N) then
                        return True;
                     end if;
                  end if;
               end loop;
               return False;
            end;
         end;
      end;
   end Apply_SAN;

   function Get_Move (G : Game_State; I : Positive) return Move is
   begin
      if I > G.N_Moves then raise Constraint_Error with "Move index out of range"; end if;
      return G.History (I);
   end Get_Move;

   -- =========================================================
   --  Starting position detection
   -- =========================================================

   Start_Squares : constant Board_Array :=
     (0  => BRook,  1  => BKnight, 2  => BBishop, 3  => BQueen,
      4  => BKing,  5  => BBishop, 6  => BKnight, 7  => BRook,
      8  => BPawn,  9  => BPawn,  10 => BPawn,  11 => BPawn,
      12 => BPawn, 13 => BPawn,  14 => BPawn,  15 => BPawn,
      16 .. 47 => Empty,
      48 => WPawn, 49 => WPawn, 50 => WPawn, 51 => WPawn,
      52 => WPawn, 53 => WPawn, 54 => WPawn, 55 => WPawn,
      56 => WRook, 57 => WKnight, 58 => WBishop, 59 => WQueen,
      60 => WKing, 61 => WBishop, 62 => WKnight, 63 => WRook);

   function Is_Start_Position (B : Board.Board_State) return Boolean is
      (B.Squares = Start_Squares);

end DGT.Game;
