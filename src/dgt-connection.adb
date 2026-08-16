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

with Ada.Streams;
with Ada.Real_Time;

package body DGT.Connection is

   use GNAT.Serial_Communications;
   use Ada.Streams;
   use DGT.Protocol;

   --  Read exactly Buf'Length bytes; raises DGT_Error on timeout.
   --
   --  GNAT opens serial ports with O_NONBLOCK and does not clear that flag
   --  when Block=>False is passed to Set().  With O_NONBLOCK active, a read
   --  that finds no data raises Serial_Error (EAGAIN) instead of waiting for
   --  VTIME to expire.  We therefore catch Serial_Error and retry with a short
   --  sleep, giving the same ~0.1 s effective timeout as the VTIME setting.
   procedure Read_Bytes
     (Port : in out Serial_Port;
      Buf  : out Stream_Element_Array)
   is
      use Ada.Real_Time;
      Deadline : constant Time := Clock + Milliseconds (150);
      Pos      : Stream_Element_Offset := Buf'First;
      Last     : Stream_Element_Offset;
   begin
      while Pos <= Buf'Last loop
         begin
            Read (Port, Buf (Pos .. Buf'Last), Last);
            if Last >= Pos then
               Pos := Last + 1;
            elsif Clock > Deadline then
               raise DGT_Error with "DGT read timeout";
            end if;
         exception
            when Serial_Error =>
               if Clock > Deadline then
                  raise DGT_Error with "DGT read timeout";
               end if;
               delay 0.005;
         end;
      end loop;
   end Read_Bytes;

   procedure Send_Cmd (Port : in out Serial_Port; Cmd : Stream_Element) is
      Buf : constant Stream_Element_Array (1 .. 1) := (1 => Cmd);
   begin
      Write (Port, Buf);
   end Send_Cmd;

   --  Every DGT message starts with: [msg-id, len-hi, len-lo]
   --  Length includes the 3 header bytes.
   procedure Read_Header
     (Port   : in out Serial_Port;
      Msg_ID : out Stream_Element;
      Length : out Natural)
   is
      Hdr : Stream_Element_Array (1 .. 3);
   begin
      Read_Bytes (Port, Hdr);
      Msg_ID := Hdr (1);
      Length := Natural (Hdr (2)) * 256 + Natural (Hdr (3));
   end Read_Header;

   procedure Open
     (Conn   : in out Board_Connection;
      Device : String := "/dev/ttyACM0")
   is
   begin
      Open (Conn.Port, Port_Name (Device));
      Set (Conn.Port,
           Rate      => B9600,
           Bits      => CS8,
           Stop_Bits => One,
           Parity    => None,
           Block     => False,
           Local     => True,
           Flow      => None,
           Timeout   => 0.1);
   end Open;

   procedure Close (Conn : in out Board_Connection) is
   begin
      Close (Conn.Port);
   end Close;

   procedure Drain (Port : in out Serial_Port) is
      Buf  : Stream_Element_Array (1 .. 1);
      Last : Stream_Element_Offset;
   begin
      loop
         begin
            Read (Port, Buf, Last);
            exit when Last < Buf'First;
         exception
            when Serial_Error => exit;  -- EAGAIN: buffer already empty
         end;
      end loop;
   end Drain;

   procedure Send_Reset (Conn : in out Board_Connection) is
   begin
      Send_Cmd (Conn.Port, CMD_RESET);
      Drain (Conn.Port);
   end Send_Reset;

   function Get_Version (Conn : in out Board_Connection) return String is
      Msg_ID  : Stream_Element;
      Length  : Natural;
   begin
      Send_Cmd (Conn.Port, CMD_SEND_VERSION);
      Read_Header (Conn.Port, Msg_ID, Length);
      if Length < 3 then
         raise DGT_Error with "Malformed version response";
      end if;
      declare
         Data_Len : constant Natural := Length - 3;
         Data     : Stream_Element_Array (1 .. Stream_Element_Offset (Data_Len));
      begin
         Read_Bytes (Conn.Port, Data);
         if Msg_ID = MSG_VERSION and then Data_Len = 2 then
            --  Classic DGT e-Board: major.minor bytes
            declare
               Maj : constant String := Natural'Image (Natural (Data (1)));
               Min : constant String := Natural'Image (Natural (Data (2)));
            begin
               return Maj (2 .. Maj'Last) & "." & Min (2 .. Min'Last);
            end;
         elsif Msg_ID = MSG_SMART_ID then
            --  DGT Smart Board: ASCII identifier string
            declare
               S : String (1 .. Data_Len);
            begin
               for I in Data'Range loop
                  S (Natural (I)) := Character'Val (Natural (Data (I)));
               end loop;
               return S;
            end;
         else
            raise DGT_Error with "Unknown version response 0x"
               & Stream_Element'Image (Msg_ID);
         end if;
      end;
   end Get_Version;

   function Get_Board (Conn : in out Board_Connection) return Board.Board_State is
      Msg_ID : Stream_Element;
      Length : Natural;
      Data   : Stream_Element_Array (1 .. 64);
      State  : Board.Board_State;
   begin
      Send_Cmd (Conn.Port, CMD_SEND_BRD);
      Read_Header (Conn.Port, Msg_ID, Length);
      if Msg_ID /= MSG_BOARD_DUMP then
         raise DGT_Error with "Expected MSG_BOARD_DUMP (0x86), got 0x"
            & Stream_Element'Image (Msg_ID);
      end if;
      Read_Bytes (Conn.Port, Data);
      for I in Data'Range loop
         State.Squares (Board.Square_Index (I - 1)) :=
            Protocol.Byte_To_Piece (Data (I));
      end loop;
      return State;
   end Get_Board;

   function Get_Board_During_Updates
     (Conn : in out Board_Connection) return Board.Board_State
   is
      Msg_ID : Stream_Element;
      Length : Natural;
      State  : Board.Board_State;
   begin
      Send_Cmd (Conn.Port, CMD_SEND_BRD);
      loop
         Read_Header (Conn.Port, Msg_ID, Length);
         if Msg_ID = MSG_BOARD_DUMP then
            declare
               Data : Stream_Element_Array (1 .. 64);
            begin
               Read_Bytes (Conn.Port, Data);
               for I in Data'Range loop
                  State.Squares (Board.Square_Index (I - 1)) :=
                     Protocol.Byte_To_Piece (Data (I));
               end loop;
            end;
            return State;
         elsif Length > 3 then
            declare
               Skip : Stream_Element_Array
                  (1 .. Stream_Element_Offset (Length - 3));
            begin
               Read_Bytes (Conn.Port, Skip);
            end;
         end if;
      end loop;
   end Get_Board_During_Updates;

   procedure Start_Updates (Conn : in out Board_Connection) is
   begin
      --  0x43 = CMD_SEND_UPDATE: confirmed working on DGT Smart Board.
      --  NOTE: do NOT call Set() here -- it flushes the OS receive buffer.
      Send_Cmd (Conn.Port, CMD_SEND_UPDATE);
   end Start_Updates;

   procedure Read_Field_Update
     (Conn      : in out Board_Connection;
      Square    : out Board.Square_Index;
      Piece     : out Protocol.Piece_Code;
      Got_Event : out Boolean)
   is
      Msg_ID : Stream_Element;
      Length : Natural;
      Data   : Stream_Element_Array (1 .. 2);
   begin
      Got_Event := False;
      Square    := 0;
      Piece     := Protocol.Empty;
      begin
         Read_Header (Conn.Port, Msg_ID, Length);
         if Msg_ID = MSG_FIELD_UPDATE then
            Read_Bytes (Conn.Port, Data);
            Square    := Board.Square_Index (Data (1));
            Piece     := Protocol.Byte_To_Piece (Data (2));
            Got_Event := True;
         elsif Length > 3 then
            declare
               Skip : Stream_Element_Array
                  (1 .. Stream_Element_Offset (Length - 3));
            begin
               Read_Bytes (Conn.Port, Skip);
            end;
         end if;
      exception
         --  0.1 s timeout with no data: return Got_Event = False so the main
         --  loop can service stdin commands without waiting for a board event.
         when DGT_Error => null;
      end;
   end Read_Field_Update;

end DGT.Connection;
