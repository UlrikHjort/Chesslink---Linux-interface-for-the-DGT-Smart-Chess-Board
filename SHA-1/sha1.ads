-- ***************************************************************************
--                            SHA-1 Hash Library
--
--           Copyright (C) 1997 By Ulrik Hørlyk Hjort
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

-- Implemented according to FIPS PUB 180-1
-- https://www.itl.nist.gov/fipspubs/fip180-1.htm

with Interfaces;

package Sha1 is

   type Unsigned_32 is mod (2 ** 32); -- According to the spec

   type Unsigned_32_Array_T is array(Positive range <>) of Unsigned_32;
   type Unsigned_8_Array_T is array(Positive range <>) of Interfaces.Unsigned_8;

   type Context_T is
      record
         Message_Digest      : Unsigned_32_Array_T(1..5);
         Length_Low          : Unsigned_32;
         Length_High         : Unsigned_32;
         Message_Block       : Unsigned_8_Array_T(1..64);
         Message_Block_Index : Positive;
         Computed            : Boolean;
         Corrupted           : Boolean;
      end record;



   ---------------------------------------------
   --
   -- Reset and initialize buffers and indexes
   --
   ---------------------------------------------
   procedure Init (Context : in out Context_T);


   --------------------------------------------------------
   --
   -- Calculate and returns the 160 bit message digest in
   -- Context.Message_Digest.
   --
   -- Returns True in Result_Ok on success otherwise False
   --
   --------------------------------------------------------
   procedure Result(Context : in out Context_T; Result_Ok : out Boolean);


   -----------------------------------------------
   --
   -- Takes a message as an unsigned_8 array and
   -- update the SHA-1 context
   --
   -----------------------------------------------
   procedure Input(Context : in out Context_T;
                   Message : in     Unsigned_8_Array_T);


End Sha1;

