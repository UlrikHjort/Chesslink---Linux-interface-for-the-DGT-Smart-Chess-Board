-- ***************************************************************************
--                  CLKB Encoder -- compress openings.dat to .clkb
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
--  Usage: clkb_encode [INPUT.dat] [OUTPUT.clkb]
--  Defaults: data/openings.dat, data/openings.clkb

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with CLKB;                  use CLKB;

procedure CLKB_Encode is

   In_Path  : constant String :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Ada.Command_Line.Argument (1)
      else "data/openings.dat");
   Out_Path : constant String :=
     (if Ada.Command_Line.Argument_Count >= 2
      then Ada.Command_Line.Argument (2)
      else "data/openings.clkb");

   use Ada.Streams;
   use Ada.Streams.Stream_IO;

   Txt         : Ada.Text_IO.File_Type;
   Bin         : Ada.Streams.Stream_IO.File_Type;
   Prev_Moves  : Move_Array (1 .. Max_Moves) := (others => 0);
   Prev_Count  : Natural := 0;
   Entry_Count : Natural := 0;
   Comp_Size   : Long_Integer := 0;

   procedure Write_Byte (B : Natural) is
      Buf : Stream_Element_Array (1 .. 1);
   begin
      Buf (1) := Stream_Element (B);
      Write (Bin, Buf);
   end Write_Byte;

   procedure Write_U32_BE (V : Natural) is
      Buf : Stream_Element_Array (1 .. 4);
   begin
      Buf (1) := Stream_Element (V / 16#1000000#);
      Buf (2) := Stream_Element ((V / 16#10000#) mod 16#100#);
      Buf (3) := Stream_Element ((V / 16#100#)   mod 16#100#);
      Buf (4) := Stream_Element (V               mod 16#100#);
      Write (Bin, Buf);
   end Write_U32_BE;

   procedure Write_Packed (Moves : Move_Array) is
      I : Positive := Moves'First;
   begin
      while I <= Moves'Last loop
         if I < Moves'Last then
            declare
               M1  : constant Natural := Moves (I);
               M2  : constant Natural := Moves (I + 1);
               Buf : Stream_Element_Array (1 .. 3);
            begin
               Buf (1) := Stream_Element (M1 / 16);
               Buf (2) := Stream_Element ((M1 mod 16) * 16 + M2 / 256);
               Buf (3) := Stream_Element (M2 mod 256);
               Write (Bin, Buf);
            end;
            I := I + 2;
         else
            declare
               M1  : constant Natural := Moves (I);
               Buf : Stream_Element_Array (1 .. 2);
            begin
               Buf (1) := Stream_Element (M1 / 16);
               Buf (2) := Stream_Element ((M1 mod 16) * 16);
               Write (Bin, Buf);
            end;
            I := I + 1;
         end if;
      end loop;
   end Write_Packed;

   procedure Process_Line (Line : String) is
      use Ada.Strings.Fixed;
      P1         : constant Natural := Index (Line, "|");
      P2         : Natural;
      Curr_Moves : Move_Array (1 .. Max_Moves) := (others => 0);
      Curr_Count : Natural := 0;
      Shared     : Natural := 0;
      New_Count  : Natural;
      Eco_Letter : Natural;
      Eco_Number : Natural;
   begin
      if Line'Length = 0 or else Line (Line'First) = '#' or else P1 = 0 then
         return;
      end if;

      P2 := Index (Line, "|", P1 + 1);

      declare
         Moves_Str : constant String := Line (Line'First .. P1 - 1);
         Eco_Str   : constant String := Line (P1 + 1 .. P2 - 1);
         Name_Str  : constant String := Line (P2 + 1 .. Line'Last);
         Start     : Positive        := Moves_Str'First;
         Sp        : Natural;
      begin
         -- Parse space-separated UCI moves
         loop
            Sp := Index (Moves_Str, " ", Start);
            if Sp = 0 then
               if Start <= Moves_Str'Last then
                  Curr_Count := Curr_Count + 1;
                  Curr_Moves (Curr_Count) :=
                     UCI_To_Move (Moves_Str (Start .. Moves_Str'Last));
               end if;
               exit;
            end if;
            Curr_Count := Curr_Count + 1;
            Curr_Moves (Curr_Count) := UCI_To_Move (Moves_Str (Start .. Sp - 1));
            Start := Sp + 1;
         end loop;

         -- Longest shared prefix with previous entry
         while Shared < Prev_Count and then Shared < Curr_Count and then
               Prev_Moves (Shared + 1) = Curr_Moves (Shared + 1)
         loop
            Shared := Shared + 1;
         end loop;
         New_Count := Curr_Count - Shared;

         -- ECO letter stored as 0..4, number as 0..99
         Eco_Letter :=
            Character'Pos (Eco_Str (Eco_Str'First)) - Character'Pos ('A');
         Eco_Number :=
            Integer'Value (Eco_Str (Eco_Str'First + 1 .. Eco_Str'First + 2));

         -- Write entry bytes
         Write_Byte (Shared);
         Write_Byte (New_Count);
         if New_Count > 0 then
            Write_Packed (Curr_Moves (Shared + 1 .. Curr_Count));
         end if;
         Write_Byte (Eco_Letter);
         Write_Byte (Eco_Number);
         Write_Byte (Name_Str'Length);
         if Name_Str'Length > 0 then
            declare
               Buf : Stream_Element_Array
                 (1 .. Stream_Element_Offset (Name_Str'Length));
            begin
               for I in Name_Str'Range loop
                  Buf (Stream_Element_Offset (I - Name_Str'First + 1)) :=
                     Stream_Element (Character'Pos (Name_Str (I)));
               end loop;
               Write (Bin, Buf);
            end;
         end if;
      end;

      Prev_Moves (1 .. Curr_Count) := Curr_Moves (1 .. Curr_Count);
      Prev_Count  := Curr_Count;
      Entry_Count := Entry_Count + 1;
   end Process_Line;

begin
   Ada.Text_IO.Open (Txt, Ada.Text_IO.In_File, In_Path);
   Create (Bin, Out_File, Out_Path);

   -- Magic bytes + placeholder entry count (filled in after all entries)
   declare
      Buf : Stream_Element_Array (1 .. 4);
   begin
      for I in 1 .. 4 loop
         Buf (Stream_Element_Offset (I)) :=
            Stream_Element (Character'Pos (Magic (I)));
      end loop;
      Write (Bin, Buf);
   end;
   Write_U32_BE (0);

   while not Ada.Text_IO.End_Of_File (Txt) loop
      Process_Line (Ada.Text_IO.Get_Line (Txt));
   end loop;
   Ada.Text_IO.Close (Txt);

   -- Save compressed size then seek back to write the real entry count
   Comp_Size := Long_Integer (Index (Bin)) - 1;
   Set_Index (Bin, 5);
   Write_U32_BE (Entry_Count);
   Close (Bin);

   declare
      Orig  : constant Long_Integer :=
         Long_Integer (Ada.Directories.Size (In_Path));
      Ratio : constant Natural :=
         Natural ((Comp_Size * 100) / Orig);
   begin
      Put_Line ("Entries    :" & Entry_Count'Image);
      Put_Line ("Original   :" & Orig'Image & " bytes");
      Put_Line ("Compressed :" & Comp_Size'Image & " bytes  (" &
                Integer'Image (100 - Ratio) & "% reduction)");
      Put_Line ("Output     : " & Out_Path);
   end;

exception
   when E : others =>
      Put_Line (Standard_Error,
                "clkb_encode: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (1);
end CLKB_Encode;
