-- ***************************************************************************
--                      DGT Smart Board - Raw Protocol Diagnostic
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

--  Diagnostic: test DGT update mode.
--  Sends CMD_SEND_UPDATE (0x43) then reads continuously for ~15s.
--  IMPORTANT: never calls Set() after the initial configuration,
--  because Set() flushes the OS receive buffer.

with Ada.Text_IO;
with Ada.Exceptions;
with Ada.Streams;
with GNAT.Serial_Communications;

procedure Raw_Dump is
   use Ada.Text_IO;
   use Ada.Streams;
   use GNAT.Serial_Communications;

   Device : constant Port_Name (1 .. 12) := "/dev/ttyACM0";
   Port   : Serial_Port;
   Buf    : Stream_Element_Array (1 .. 1);
   Last   : Stream_Element_Offset;
   Count  : Natural := 0;

   procedure Send (B : Stream_Element) is
      Cmd : constant Stream_Element_Array (1 .. 1) := (1 => B);
   begin
      Write (Port, Cmd);
   end Send;

   procedure Hex2 (V : Natural) is
      H : constant String := "0123456789ABCDEF";
   begin
      Put (H (H'First + V / 16) & H (H'First + V mod 16));
   end Hex2;

begin
   Put_Line ("Opening " & String (Device) & "...");
   Open (Port, Device);

   --  Set once and never again -- subsequent Set() calls flush the OS buffer
   Set (Port,
        Rate      => B9600,
        Bits      => CS8,
        Stop_Bits => One,
        Parity    => None,
        Block     => False,
        Local     => True,
        Flow      => None,
        Timeout   => 0.2);

   --  Drain stale bytes
   Put ("Draining... ");
   loop
      Read (Port, Buf, Last);
      exit when Last < Buf'First;
   end loop;
   Put_Line ("done.");

   --  Reset, then start update mode
   Put_Line ("Sending RESET (0x40)...");
   Send (16#40#);

   --  Read/drain any reset response (use iterations, not delay+Set)
   for I in 1 .. 10 loop
      Read (Port, Buf, Last);
      exit when Last < Buf'First;
   end loop;

   Put_Line ("Sending CMD_SEND_UPDATE (0x43) -- full board+clock updates");
   Send (16#43#);

   Put_Line ("Lift and place pieces now. Reading for ~15s.");
   Put_Line ("Expected: 85 00 05 <square> <piece> per event");
   New_Line;

   --  Read continuously for ~15 seconds (15 / 0.2 timeout = ~75 iterations max)
   for I in 1 .. 300 loop
      Read (Port, Buf, Last);
      if Last >= Buf'First then
         Hex2 (Natural (Buf (1)));
         Put (' ');
         Count := Count + 1;
         --  Print newline every 5 bytes to group messages visually
         if Count mod 5 = 0 then
            New_Line;
         end if;
      end if;
   end loop;

   New_Line;
   Put_Line ("Total bytes:" & Natural'Image (Count));
   Close (Port);

exception
   when E : Serial_Error =>
      Put_Line ("Serial error: " & Ada.Exceptions.Exception_Message (E));
end Raw_Dump;
