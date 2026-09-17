-- ***************************************************************************
--                  CLKB Decoder -- decompress .clkb to openings.dat
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
--
--  Usage: clkb_decode [INPUT.clkb] [OUTPUT.dat]
--  Defaults: data/openings.clkb, data/openings.dat

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Command_Line;
with Ada.Exceptions;
with CLKB;                  use CLKB;

procedure CLKB_Decode is

   In_Path  : constant String :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Ada.Command_Line.Argument (1)
      else "data/openings.clkb");
   Out_Path : constant String :=
     (if Ada.Command_Line.Argument_Count >= 2
      then Ada.Command_Line.Argument (2)
      else "data/openings.dat");

   use Ada.Streams;
   use Ada.Streams.Stream_IO;

   Bin  : Ada.Streams.Stream_IO.File_Type;
   Txt  : Ada.Text_IO.File_Type;
   Last : Stream_Element_Offset;

   function Read_Byte return Natural is
      Buf : Stream_Element_Array (1 .. 1);
   begin
      Read (Bin, Buf, Last);
      return Natural (Buf (1));
   end Read_Byte;

   function Read_U32_BE return Natural is
      B0 : constant Natural := Read_Byte;
      B1 : constant Natural := Read_Byte;
      B2 : constant Natural := Read_Byte;
      B3 : constant Natural := Read_Byte;
   begin
      return B0 * 16#1000000# + B1 * 16#10000# + B2 * 16#100# + B3;
   end Read_U32_BE;

   procedure Read_Packed (Moves : out Move_Array; Count : Natural) is
      I          : Positive := 1;
      B0, B1, B2 : Natural;
   begin
      while I <= Count loop
         if I < Count then
            B0 := Read_Byte; B1 := Read_Byte; B2 := Read_Byte;
            Moves (I)     := B0 * 16 + B1 / 16;
            Moves (I + 1) := (B1 mod 16) * 256 + B2;
            I := I + 2;
         else
            B0 := Read_Byte; B1 := Read_Byte;
            Moves (I) := B0 * 16 + B1 / 16;
            I := I + 1;
         end if;
      end loop;
   end Read_Packed;

   function Eco_To_String (Letter_Byte, Number_Byte : Natural) return String is
      Letter : constant Character :=
         Character'Val (Character'Pos ('A') + Letter_Byte);
      Tens   : constant Character :=
         Character'Val (Character'Pos ('0') + Number_Byte / 10);
      Units  : constant Character :=
         Character'Val (Character'Pos ('0') + Number_Byte mod 10);
   begin
      return (1 => Letter, 2 => Tens, 3 => Units);
   end Eco_To_String;

   procedure Read_Name (Len : Natural) is
   begin
      if Len = 0 then
         return;
      end if;
      declare
         Buf : Stream_Element_Array (1 .. Stream_Element_Offset (Len));
      begin
         Read (Bin, Buf, Last);
         for B of Buf loop
            Ada.Text_IO.Put (Txt, Character'Val (B));
         end loop;
      end;
   end Read_Name;

begin
   Open (Bin, In_File, In_Path);

   -- Verify magic
   declare
      Buf : Stream_Element_Array (1 .. 4);
   begin
      Read (Bin, Buf, Last);
      if Last /= 4
         or else Character'Val (Buf (1)) /= 'C'
         or else Character'Val (Buf (2)) /= 'L'
         or else Character'Val (Buf (3)) /= 'K'
         or else Character'Val (Buf (4)) /= 'B'
      then
         Put_Line (Standard_Error, "clkb_decode: not a CLKB file: " & In_Path);
         Ada.Command_Line.Set_Exit_Status (1);
         return;
      end if;
   end;

   declare
      Total_Entries : constant Natural := Read_U32_BE;
      Prev_Moves    : Move_Array (1 .. Max_Moves) := (others => 0);
      New_Moves     : Move_Array (1 .. Max_Moves) := (others => 0);
      Curr_Moves    : Move_Array (1 .. Max_Moves) := (others => 0);
      Shared        : Natural;
      New_Count     : Natural;
      Curr_Count    : Natural;
      Eco_Letter    : Natural;
      Eco_Number    : Natural;
      Name_Len      : Natural;
   begin
      Ada.Text_IO.Create (Txt, Ada.Text_IO.Out_File, Out_Path);
      Put_Line (Txt, "# Chesslink opening book");
      Put_Line (Txt, "# Source: lichess-org/chess-openings (CC0 licence)");
      Put_Line (Txt, "# Format: uci_moves|ECO|Name");

      for N in 1 .. Total_Entries loop
         Shared    := Read_Byte;
         New_Count := Read_Byte;

         if New_Count > 0 then
            Read_Packed (New_Moves, New_Count);
         end if;

         -- Reconstruct full move list: shared prefix + new moves
         Curr_Count := Shared + New_Count;
         Curr_Moves (1 .. Shared)              := Prev_Moves (1 .. Shared);
         Curr_Moves (Shared + 1 .. Curr_Count) := New_Moves (1 .. New_Count);

         Eco_Letter := Read_Byte;
         Eco_Number := Read_Byte;
         Name_Len   := Read_Byte;

         -- Write text line: "moves|ECO|name"
         for I in 1 .. Curr_Count loop
            if I > 1 then Ada.Text_IO.Put (Txt, " "); end if;
            Ada.Text_IO.Put (Txt, Move_To_UCI (Curr_Moves (I)));
         end loop;
         Ada.Text_IO.Put (Txt, "|" & Eco_To_String (Eco_Letter, Eco_Number) & "|");
         Read_Name (Name_Len);
         Ada.Text_IO.New_Line (Txt);

         Prev_Moves (1 .. Curr_Count) := Curr_Moves (1 .. Curr_Count);
      end loop;

      Ada.Text_IO.Close (Txt);
      Close (Bin);

      Put_Line ("Decoded" & Total_Entries'Image & " entries -> " & Out_Path);
   end;

exception
   when E : others =>
      Put_Line (Standard_Error,
                "clkb_decode: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (1);
end CLKB_Decode;
