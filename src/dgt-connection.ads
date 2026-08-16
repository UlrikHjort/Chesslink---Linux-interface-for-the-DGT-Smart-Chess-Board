-- ***************************************************************************
--                      DGT Smart Board - Board Connection
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
private with GNAT.Serial_Communications;

package DGT.Connection is

   type Board_Connection is limited private;

   procedure Open
     (Conn   : in out Board_Connection;
      Device : String := "/dev/ttyACM0");

   procedure Close (Conn : in out Board_Connection);

   procedure Send_Reset (Conn : in out Board_Connection);

   function Get_Version (Conn : in out Board_Connection) return String;

   function Get_Board (Conn : in out Board_Connection) return Board.Board_State;

   --  Like Get_Board, safe to call while update mode is active.
   --  Skips queued field-update messages until the board dump arrives.
   function Get_Board_During_Updates
     (Conn : in out Board_Connection) return Board.Board_State;

   --  Start streaming field-update messages on every piece lift/place
   procedure Start_Updates (Conn : in out Board_Connection);

   --  Return the next field-update message if one is available within the
   --  port timeout (~0.1 s).  Got_Event = False means no event this call.
   procedure Read_Field_Update
     (Conn      : in out Board_Connection;
      Square    : out Board.Square_Index;
      Piece     : out Protocol.Piece_Code;
      Got_Event : out Boolean);

private

   type Board_Connection is limited record
      Port : GNAT.Serial_Communications.Serial_Port;
   end record;

end DGT.Connection;
