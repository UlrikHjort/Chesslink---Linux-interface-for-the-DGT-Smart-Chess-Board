-- ***************************************************************************
--                      DGT Smart Board - ECO Opening Book
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

package DGT.Openings is

   --  Load opening book from a file (one "uci_moves|ECO|Name" line per entry).
   --  If not called, or if the file cannot be read, the built-in book is used.
   procedure Load (Path : String);

   --  Compute the SHA-1 digest of a file and return it as a 40-character
   --  lowercase hex string.  Returns "" on any I/O or computation error.
   function Hash_File (Path : String) return String;

   --  Given space-separated UCI moves (e.g. "e2e4 e7e5 g1f3"), returns
   --  "CODE  Name" for the most specific recognised opening, or "" if unknown.
   function Lookup (Moves_UCI : String) return String;

   --  Case-insensitive substring search by name.  Returns the UCI move
   --  sequence for the first matching entry, or "" if not found.
   function Find_Moves (Name : String) return String;

   --  Call Action for every entry in the book, passing ECO code and name.
   --  Optional Filter: if non-empty, only entries whose name contains Filter
   --  (case-insensitive) are passed to Action.
   procedure For_Each_Opening
     (Action : not null access procedure (ECO : String; Name : String);
      Filter : String := "");

   --  Same as For_Each_Opening but also passes the UCI move sequence.
   procedure For_Each_Opening_Full
     (Action : not null access procedure
        (ECO : String; Name : String; Moves : String);
      Filter : String := "");

end DGT.Openings;
