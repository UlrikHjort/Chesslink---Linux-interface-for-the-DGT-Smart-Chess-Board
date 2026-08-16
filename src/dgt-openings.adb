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

with Ada.Text_IO;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces;
with Sha1; use Sha1;

package body DGT.Openings is

   --  Each line: "uci_moves|ECO|Name", separated by ASCII.LF.
   --  Builtin_Data is the compiled-in fallback.
   --  Loaded_Data holds a file-loaded book when Load has been called.
   Builtin_Data : constant String :=
      --  ================================================================
      --  A00  Irregular / Flank
      --  ================================================================
      "b2b4|A00|Polish Opening" & ASCII.LF &
      "b2b4 e7e5|A00|Polish: King's Gambit" & ASCII.LF &
      "b2b4 e7e5 c1b2|A00|Polish: Birmingham Gambit" & ASCII.LF &
      "b2b4 d7d5|A00|Polish: ...d5" & ASCII.LF &
      "b2b3|A01|Nimzo-Larsen Attack" & ASCII.LF &
      "b2b3 e7e5|A01|Nimzo-Larsen: Classical" & ASCII.LF &
      "b2b3 e7e5 c1b2 b8c6|A01|Nimzo-Larsen: ...Nc6" & ASCII.LF &
      "b2b3 d7d5 c1b2|A01|Nimzo-Larsen: ...d5" & ASCII.LF &
      "g2g3|A00|King's Fianchetto Opening" & ASCII.LF &
      "g2g4|A00|Grob's Attack" & ASCII.LF &
      "g2g4 d7d5|A00|Grob: ...d5" & ASCII.LF &
      "e2e3|A00|Van't Kruijs Opening" & ASCII.LF &
      "b1a3|A00|Durkin Opening" & ASCII.LF &
      "h2h3|A00|Clemenz Opening" & ASCII.LF &
      "f2f4|A02|Bird's Opening" & ASCII.LF &
      "f2f4 e7e5|A02|Bird's: From Gambit" & ASCII.LF &
      "f2f4 d7d5|A03|Bird's: ...d5" & ASCII.LF &
      "f2f4 d7d5 g1f3|A03|Bird's: Schlechter" & ASCII.LF &
      --  ================================================================
      --  A04-A09  Reti / KIA
      --  ================================================================
      "g1f3|A04|Reti Opening" & ASCII.LF &
      "g1f3 c7c5|A04|Reti: ...c5" & ASCII.LF &
      "g1f3 f7f5|A04|Reti: ...f5" & ASCII.LF &
      "g1f3 g7g6|A04|Reti: ...g6" & ASCII.LF &
      "g1f3 d7d5|A05|Reti: ...d5" & ASCII.LF &
      "g1f3 d7d5 c2c4|A09|Reti: ...d5 c4" & ASCII.LF &
      "g1f3 d7d5 g2g3|A07|Reti: King's Indian Attack" & ASCII.LF &
      "g1f3 d7d5 g2g3 g8f6 f1g2|A07|KIA: Nf6" & ASCII.LF &
      "g1f3 d7d5 g2g3 g8f6 f1g2 c7c5|A07|KIA: ...c5" & ASCII.LF &
      "g1f3 d7d5 g2g3 g8f6 f1g2 g7g6|A07|KIA: ...g6" & ASCII.LF &
      "g1f3 d7d5 g2g3 g8f6 f1g2 e7e6 e1g1|A07|KIA: main" & ASCII.LF &
      "g1f3 e7e5|A04|Reti: ...e5" & ASCII.LF &
      "g1f3 g8f6 c2c4|A15|English: Anglo-Indian" & ASCII.LF &
      --  ================================================================
      --  A10-A39  English Opening
      --  ================================================================
      "c2c4|A10|English Opening" & ASCII.LF &
      "c2c4 e7e5|A20|English: King's English" & ASCII.LF &
      "c2c4 e7e5 g1f3|A22|English: Three Knights" & ASCII.LF &
      "c2c4 e7e5 g1f3 b8c6|A22|English: Three Knights Nc6" & ASCII.LF &
      "c2c4 e7e5 g1f3 b8c6 b1c3|A25|English: Four Knights" & ASCII.LF &
      "c2c4 e7e5 g1f3 b8c6 b1c3 f8b4|A28|English: Four Knights Spanish" & ASCII.LF &
      "c2c4 e7e5 g1f3 b8c6 b1c3 g8f6|A26|English: Four Knights" & ASCII.LF &
      "c2c4 e7e5 b1c3|A25|English: King's English Closed" & ASCII.LF &
      "c2c4 e7e5 b1c3 g8f6|A26|English: Botvinnik System" & ASCII.LF &
      "c2c4 e7e5 b1c3 g8f6 g2g3|A29|English: Bremen/Reverse Dragon" & ASCII.LF &
      "c2c4 e7e5 b1c3 g8f6 g2g3 d7d5|A29|English: Bremen ...d5" & ASCII.LF &
      "c2c4 c7c5|A30|English: Symmetrical" & ASCII.LF &
      "c2c4 c7c5 g1f3|A30|English: Symmetrical Nf3" & ASCII.LF &
      "c2c4 c7c5 g1f3 g8f6 b1c3|A34|English: Symmetrical Four Knights" & ASCII.LF &
      "c2c4 c7c5 g1f3 g8f6 b1c3 d7d5|A34|English: Symmetrical ...d5" & ASCII.LF &
      "c2c4 c7c5 b1c3|A30|English: Symmetrical Nc3" & ASCII.LF &
      "c2c4 g8f6|A16|English: Anglo-Indian" & ASCII.LF &
      "c2c4 g8f6 b1c3 d7d5|A17|English: ...d5" & ASCII.LF &
      "c2c4 g8f6 b1c3 e7e6|A18|English: Mikenas-Carls" & ASCII.LF &
      "c2c4 g8f6 g1f3 g7g6|A16|English: Anglo-Indian Fianchetto" & ASCII.LF &
      "c2c4 d7d6|A10|English: Old Indian" & ASCII.LF &
      "c2c4 b8c6|A22|English: ...Nc6" & ASCII.LF &
      "c2c4 g7g6|A10|English: ...g6" & ASCII.LF &
      --  ================================================================
      --  A40-A44  Queen's Pawn / Misc
      --  ================================================================
      "d2d4|A40|Queen's Pawn Game" & ASCII.LF &
      "d2d4 e7e5|A40|Englund Gambit" & ASCII.LF &
      "d2d4 e7e5 d4e5 b8c6|A40|Englund: Felbecker" & ASCII.LF &
      "d2d4 g8f6 e2e3|A40|Colle System" & ASCII.LF &
      "d2d4 d7d5 e2e3|A46|Colle: ...d5" & ASCII.LF &
      "d2d4 d7d5 e2e3 g8f6 f1d3|D05|Colle System" & ASCII.LF &
      "d2d4 g8f6 g1f3 e7e6 e2e3|A46|Torre: ...e6 Colle" & ASCII.LF &
      --  ================================================================
      --  A45-A49  Trompowsky / Torre / others
      --  ================================================================
      "d2d4 g8f6 c1g5|A45|Trompowsky Attack" & ASCII.LF &
      "d2d4 g8f6 c1g5 e7e6|A45|Trompowsky: ...e6" & ASCII.LF &
      "d2d4 g8f6 c1g5 d7d5|A45|Trompowsky: ...d5" & ASCII.LF &
      "d2d4 g8f6 c1g5 g7g6|A45|Trompowsky: ...g6" & ASCII.LF &
      "d2d4 g8f6 g1f3|A46|Queen's Pawn: Torre Attack" & ASCII.LF &
      "d2d4 g8f6 g1f3 e7e6 c1g5|A46|Torre Attack: ...e6" & ASCII.LF &
      "d2d4 g8f6 g1f3 e7e6 c1f4|A46|London System: ...e6" & ASCII.LF &
      "d2d4 g8f6 g1f3 d7d5 c1f4|D02|London System" & ASCII.LF &
      "d2d4 g8f6 g1f3 d7d5 c1f4 e7e6|D02|London: ...e6" & ASCII.LF &
      "d2d4 g8f6 g1f3 d7d5 c1f4 c7c5|D02|London: ...c5" & ASCII.LF &
      "d2d4 d7d5 g1f3 g8f6 c1f4|D02|London System: ...Nf6" & ASCII.LF &
      "d2d4 d7d5 g1f3 g8f6 c1f4 e7e6 e2e3|D02|London: main" & ASCII.LF &
      "d2d4 d7d5 g1f3 g8f6 c1f4 c7c6 e2e3|D02|London: Slav setup" & ASCII.LF &
      --  ================================================================
      --  A50-A79  Indian Defences (general)
      --  ================================================================
      "d2d4 g8f6 c2c4 c7c5 d4d5|A56|Benoni: Czech" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6|A60|King's Indian Setup" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 f8g7|E60|King's Indian Defence" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 f8g7 e2e4|E60|King's Indian: Main Line" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 f8g7 e2e4 d7d6|E70|King's Indian: ...d6" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 f8g7 e2e4 d7d6 g1f3 e8g8|E90|King's Indian: Classical" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 f8g7 e2e4 d7d6 g1f3 e8g8 f1e2 e7e5|E91|KID: Classical ...e5" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 f8g7 e2e4 d7d6 g1f3 e8g8 f1e2 e7e5 e1g1|E91|KID: Classical 0-0" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 f8g7 e2e4 d7d6 g1f3 e8g8 f1e2 e7e5 d4d5|E92|KID: Petrosian" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 f8g7 e2e4 d7d6 g1f3 e8g8 f1e2 e7e5 e1g1 b8c6|E91|KID: Classical Nc6" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 f8g7 e2e4 d7d6 f2f3|E70|KID: Samisch" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 f8g7 e2e4 d7d6 f2f4|E70|KID: Four Pawns Attack" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 f8g7 e2e4 d7d6 c1e3|E73|KID: Averbakh" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 f8g7 e2e4 d7d6 g1e2|E70|KID: Gligoric" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 g1f3 f8g7|A53|Old Indian" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 g2g3|A53|KID: Fianchetto" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 g2g3 f8g7 f1g2|E60|KID: Fianchetto main" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 g2g3 f8g7 f1g2 e8g8|E60|KID: Fianchetto 0-0" & ASCII.LF &
      --  ================================================================
      --  A80-A99  Dutch Defence
      --  ================================================================
      "d2d4 f7f5|A80|Dutch Defence" & ASCII.LF &
      "d2d4 f7f5 g2g3|A81|Dutch: Leningrad" & ASCII.LF &
      "d2d4 f7f5 g2g3 g8f6 f1g2 g7g6|A81|Dutch: Leningrad Main" & ASCII.LF &
      "d2d4 f7f5 g2g3 g8f6 f1g2 g7g6 g1f3 f8g7 e1g1 e8g8|A89|Dutch: Leningrad 0-0" & ASCII.LF &
      "d2d4 f7f5 c2c4|A85|Dutch: ...c4" & ASCII.LF &
      "d2d4 f7f5 c2c4 g8f6 b1c3 e7e6|A90|Dutch: Classical" & ASCII.LF &
      "d2d4 f7f5 c2c4 g8f6 b1c3 e7e6 g2g3|A92|Dutch: Classical Fianchetto" & ASCII.LF &
      "d2d4 f7f5 c2c4 g8f6 g2g3 e7e6 f1g2 f8e7|A97|Dutch: Ilyin-Zhenevsky" & ASCII.LF &
      "d2d4 e7e6 c2c4 f7f5|A99|Dutch: Classical (via e6)" & ASCII.LF &
      "d2d4 f7f5 b1c3|A80|Dutch: Hein-Gambit setup" & ASCII.LF &
      --  ================================================================
      --  D80-D89  Grunfeld Defence
      --  ================================================================
      "d2d4 g8f6 c2c4 g7g6 b1c3 d7d5|D80|Grunfeld Defence" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 d7d5 c1f4|D82|Grunfeld: Four Pawns" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 d7d5 g1f3|D80|Grunfeld: Russian" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 d7d5 d1b3|D81|Grunfeld: Hungarian" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 d7d5 c4d5 f6d5|D82|Grunfeld: Exchange" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 d7d5 c4d5 f6d5 e2e4 d5c3 b2c3 f8g7|D85|Grunfeld: Exchange Main" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 d7d5 c4d5 f6d5 e2e4 d5c3 b2c3 f8g7 f1c4|D86|Grunfeld: Classical" & ASCII.LF &
      "d2d4 g8f6 c2c4 g7g6 b1c3 d7d5 c4d5 f6d5 e2e4 d5c3 b2c3 f8g7 f1c4 c7c5|D87|Grunfeld: Spassky" & ASCII.LF &
      --  ================================================================
      --  A56-A79  Benoni
      --  ================================================================
      "d2d4 g8f6 c2c4 c7c5|A56|Benoni Defence" & ASCII.LF &
      "d2d4 g8f6 c2c4 c7c5 d4d5|A61|Modern Benoni" & ASCII.LF &
      "d2d4 g8f6 c2c4 c7c5 d4d5 e7e6 b1c3|A64|Modern Benoni: Nc3" & ASCII.LF &
      "d2d4 g8f6 c2c4 c7c5 d4d5 e7e6 b1c3 e6d5 c4d5 d7d6|A65|Modern Benoni: Main" & ASCII.LF &
      "d2d4 g8f6 c2c4 c7c5 d4d5 e7e6 b1c3 e6d5 c4d5 d7d6 e2e4|A66|Modern Benoni: ...e4" & ASCII.LF &
      "d2d4 g8f6 c2c4 c7c5 d4d5 b7b5|A57|Benko Gambit" & ASCII.LF &
      "d2d4 g8f6 c2c4 c7c5 d4d5 b7b5 c4b5 a7a6|A58|Benko Gambit Accepted" & ASCII.LF &
      "d2d4 g8f6 c2c4 c7c5 d4d5 b7b5 c4b5 a7a6 b5a6 c8a6|A59|Benko: Full Benko" & ASCII.LF &
      --  ================================================================
      --  E15-E19  Queen's Indian
      --  ================================================================
      "d2d4 g8f6 c2c4 e7e6 g1f3 b7b6|E15|Queen's Indian Defence" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 g1f3 b7b6 g2g3|E15|QID: Fianchetto" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 g1f3 b7b6 g2g3 c8b7 f1g2|E15|QID: Fianchetto Main" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 g1f3 b7b6 b1c3|E16|QID: Kasparov" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 g1f3 b7b6 c1g5|E14|QID: Active" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 g1f3 b7b6 e2e3|E13|QID: ...e3" & ASCII.LF &
      --  ================================================================
      --  E20-E59  Nimzo-Indian
      --  ================================================================
      "d2d4 g8f6 c2c4 e7e6 b1c3 f8b4|E20|Nimzo-Indian Defence" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 b1c3 f8b4 d1c2|E21|Nimzo-Indian: Classical" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 b1c3 f8b4 d1c2 e8g8|E21|NID: Classical 0-0" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 b1c3 f8b4 d1c2 d7d5|E21|NID: Classical ...d5" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 b1c3 f8b4 d1c2 b8c6|E21|NID: Classical Nc6" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 b1c3 f8b4 e2e3|E40|Nimzo-Indian: Rubinstein" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 b1c3 f8b4 e2e3 b7b6|E43|NID: Fischer" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 b1c3 f8b4 e2e3 c7c5|E41|NID: Huebner" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 b1c3 f8b4 e2e3 e8g8 f1d3|E44|NID: ...Bd3" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 b1c3 f8b4 f2f3|E20|Nimzo-Indian: Samisch" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 b1c3 f8b4 a2a3|E26|NID: Samisch ...a3" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 b1c3 f8b4 g1f3|E21|NID: Three Knights" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 b1c3 f8b4 g1e2|E22|NID: Spielmann" & ASCII.LF &
      --  ================================================================
      --  D00-D09  Queen's Gambit setup
      --  ================================================================
      "d2d4 d7d5|D00|Queen's Pawn: Closed" & ASCII.LF &
      "d2d4 d7d5 c2c4|D06|Queen's Gambit" & ASCII.LF &
      "d2d4 d7d5 c2c4 d5c4|D20|Queen's Gambit Accepted" & ASCII.LF &
      "d2d4 d7d5 c2c4 d5c4 g1f3|D20|QGA: Nf3" & ASCII.LF &
      "d2d4 d7d5 c2c4 d5c4 g1f3 g8f6 e2e3|D21|QGA: ...e3" & ASCII.LF &
      "d2d4 d7d5 c2c4 d5c4 e2e4|D22|QGA: Central" & ASCII.LF &
      "d2d4 d7d5 c2c4 d5c4 e2e3 g8f6|D23|QGA: ...e3 Nf6" & ASCII.LF &
      "d2d4 d7d5 c2c4 d5c4 b1c3|D20|QGA: Nc3" & ASCII.LF &
      --  ================================================================
      --  D10-D19  Slav Defence
      --  ================================================================
      "d2d4 d7d5 c2c4 c7c6|D10|Slav Defence" & ASCII.LF &
      "d2d4 d7d5 c2c4 c7c6 g1f3|D11|Slav: ...Nf3" & ASCII.LF &
      "d2d4 d7d5 c2c4 c7c6 g1f3 g8f6|D11|Slav: ...Nf6" & ASCII.LF &
      "d2d4 d7d5 c2c4 c7c6 g1f3 g8f6 b1c3|D45|Semi-Slav Defence" & ASCII.LF &
      "d2d4 d7d5 c2c4 c7c6 g1f3 g8f6 b1c3 e7e6|D45|Semi-Slav: ...e6" & ASCII.LF &
      "d2d4 d7d5 c2c4 c7c6 g1f3 g8f6 b1c3 e7e6 c1g5|D43|Semi-Slav: Anti-Moscow" & ASCII.LF &
      "d2d4 d7d5 c2c4 c7c6 g1f3 g8f6 b1c3 e7e6 e2e3|D46|Semi-Slav: Meran" & ASCII.LF &
      "d2d4 d7d5 c2c4 c7c6 g1f3 g8f6 b1c3 e7e6 e2e3 b8d7 f1d3 d5c4 d3c4|D47|Semi-Slav: Meran main" & ASCII.LF &
      "d2d4 d7d5 c2c4 c7c6 g1f3 g8f6 b1c3 a7a6|D15|Slav: Chebanenko" & ASCII.LF &
      "d2d4 d7d5 c2c4 c7c6 b1c3 g8f6 g1f3|D13|Slav: Exchange" & ASCII.LF &
      "d2d4 d7d5 c2c4 c7c6 b1c3 d5c4|D12|Slav: Accepted" & ASCII.LF &
      --  ================================================================
      --  D30-D69  QGD
      --  ================================================================
      "d2d4 d7d5 c2c4 e7e6|D30|Queen's Gambit Declined" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 b1c3|D30|QGD: Nc3" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 b1c3 g8f6|D40|QGD: ...Nf6" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 b1c3 g8f6 c1g5|D50|QGD: ...Bg5" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 b1c3 g8f6 c1g5 f8e7|D50|QGD: Classical" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 b1c3 g8f6 c1g5 f8e7 e2e3 e8g8|D58|QGD: Tartakower 0-0" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 b1c3 g8f6 c1g5 f8e7 e2e3 e8g8 g1f3 b7b6|D59|QGD: Tartakower" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 b1c3 g8f6 c1g5 b8d7|D51|QGD: ...Nd7" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 b1c3 g8f6 c1g5 b8d7 g1f3|D51|QGD: Lasker" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 b1c3 g8f6 g1f3 c7c6 c1g5|D43|QGD: Cambridge Springs" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 b1c3 g8f6 g1f3 f8b4|D35|QGD: ...Bb4" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 b1c3 g8f6 g1f3 c7c6|D46|QGD: Semi-Meran" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 g1f3 g8f6 b1c3 c7c6 c1g5|D43|QGD: Anti-Moscow" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 g1f3 g8f6 b1c3 f8b4|D30|QGD: ...Bb4 Nf3" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 b1c3 c7c5|D32|QGD: Tarrasch defence" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 b1c3 c7c5 c4d5|D32|Tarrasch: ...cd5" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 b1c3 c7c5 g1f3|D34|Tarrasch: Nf3" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 b1c3 c7c5 g1f3 c5d4|D34|Tarrasch: Main" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 b1c3 c7c5 g1f3 g8f6|D34|Tarrasch: ...Nf6" & ASCII.LF &
      --  ================================================================
      --  D70-D79  Neo-Grunfeld / Exchange
      --  ================================================================
      "d2d4 d7d5 c2c4 d5c4 b1c3 g8f6 g1f3 e7e6 e2e4|D37|QGD: ...e4" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 b1c3 g8f6 g1f3 c7c5 c4d5 e6d5 g2g3|D30|Tarrasch: ...g3" & ASCII.LF &
      --  ================================================================
      --  E00-E09  Catalan
      --  ================================================================
      "d2d4 d7d5 c2c4 e7e6 g1f3 g8f6 g2g3|E01|Catalan Opening" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 g1f3 g8f6 g2g3 f8e7 f1g2|E04|Catalan: Open" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 g1f3 g8f6 g2g3 f8e7 f1g2 e8g8|E04|Catalan: 0-0" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 g1f3 g8f6 g2g3 d5c4|E00|Catalan: Accepted" & ASCII.LF &
      "d2d4 d7d5 c2c4 e7e6 g1f3 g8f6 g2g3 d5c4 f1g2 b7b5|E06|Catalan: Accepted ...b5" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 g2g3|E00|Catalan: Nf6 g3" & ASCII.LF &
      "d2d4 g8f6 c2c4 e7e6 g1f3 d7d5 g2g3|E01|Catalan: via Nf3" & ASCII.LF &
      --  ================================================================
      --  B00-B09  Semi-open (not 1.e4 e5)
      --  ================================================================
      "e2e4 b8c6|B00|Nimzowitsch Defence" & ASCII.LF &
      "e2e4 b8c6 d2d4 e7e5|B00|Nimzowitsch: ...e5" & ASCII.LF &
      "e2e4 d7d5|B01|Scandinavian Defence" & ASCII.LF &
      "e2e4 d7d5 e4d5|B01|Scandinavian: Accepted" & ASCII.LF &
      "e2e4 d7d5 e4d5 d8d5 b1c3|B01|Scandinavian: Mieses-Kotroc" & ASCII.LF &
      "e2e4 d7d5 e4d5 d8d5 b1c3 d8a5|B01|Scandinavian: Anderssen" & ASCII.LF &
      "e2e4 d7d5 e4d5 d8d5 b1c3 d8d6|B01|Scandinavian: ...Qd6" & ASCII.LF &
      "e2e4 d7d5 e4d5 g8f6|B01|Scandinavian: Modern" & ASCII.LF &
      "e2e4 d7d5 e4d5 g8f6 d2d4 g7g6|B01|Scandinavian: ...g6" & ASCII.LF &
      "e2e4 d7d5 b1c3|B01|Scandinavian: Nc3" & ASCII.LF &
      "e2e4 g8f6|B02|Alekhine's Defence" & ASCII.LF &
      "e2e4 g8f6 e4e5 g8d5|B03|Alekhine: Modern" & ASCII.LF &
      "e2e4 g8f6 e4e5 g8d5 d2d4 d7d6|B04|Alekhine: Modern ...d6" & ASCII.LF &
      "e2e4 g8f6 e4e5 g8d5 d2d4 d7d6 g1f3|B04|Alekhine: Nf3" & ASCII.LF &
      "e2e4 g8f6 e4e5 g8d5 d2d4 d7d6 e5d6|B05|Alekhine: Exchange" & ASCII.LF &
      "e2e4 g7g6|B06|Modern Defence" & ASCII.LF &
      "e2e4 g7g6 d2d4 f8g7|B06|Modern: ...Bg7" & ASCII.LF &
      "e2e4 g7g6 d2d4 f8g7 b1c3|B06|Modern: Nc3" & ASCII.LF &
      "e2e4 d7d6 d2d4 g8f6 b1c3 g7g6|B07|Pirc Defence" & ASCII.LF &
      "e2e4 d7d6 d2d4 g8f6 b1c3 g7g6 f1e2 f8g7|B08|Pirc: Classical" & ASCII.LF &
      "e2e4 d7d6 d2d4 g8f6 b1c3 g7g6 f1e2 f8g7 g1f3 e8g8|B08|Pirc: Classical 0-0" & ASCII.LF &
      "e2e4 d7d6 d2d4 g8f6 b1c3 g7g6 f2f4|B09|Pirc: Austrian Attack" & ASCII.LF &
      "e2e4 d7d6 d2d4 g8f6 b1c3 g7g6 f2f4 f8g7 g1f3|B09|Pirc: Austrian main" & ASCII.LF &
      --  ================================================================
      --  B10-B19  Caro-Kann Defence
      --  ================================================================
      "e2e4 c7c6|B10|Caro-Kann Defence" & ASCII.LF &
      "e2e4 c7c6 d2d4 d7d5|B13|Caro-Kann: Main Line" & ASCII.LF &
      "e2e4 c7c6 d2d4 d7d5 b1c3|B15|Caro-Kann: Classical" & ASCII.LF &
      "e2e4 c7c6 d2d4 d7d5 b1c3 c8f5|B16|Caro-Kann: Bronstein-Larsen" & ASCII.LF &
      "e2e4 c7c6 d2d4 d7d5 b1c3 c8f5 b1c3 e7e6|B16|CK: Bronstein main" & ASCII.LF &
      "e2e4 c7c6 d2d4 d7d5 b1c3 g8f6|B15|Caro-Kann: ...Nf6" & ASCII.LF &
      "e2e4 c7c6 d2d4 d7d5 b1d2|B10|Caro-Kann: Tartakower" & ASCII.LF &
      "e2e4 c7c6 d2d4 d7d5 b1d2 g8f6|B14|Caro-Kann: Tartakower Nf6" & ASCII.LF &
      "e2e4 c7c6 d2d4 d7d5 e4e5|B12|Caro-Kann: Advance" & ASCII.LF &
      "e2e4 c7c6 d2d4 d7d5 e4e5 c8f5|B12|Caro-Kann: Advance ...Bf5" & ASCII.LF &
      "e2e4 c7c6 d2d4 d7d5 e4e5 c8f5 g1f3|B12|CK: Advance Nf3" & ASCII.LF &
      "e2e4 c7c6 d2d4 d7d5 e4d5|B13|Caro-Kann: Exchange" & ASCII.LF &
      "e2e4 c7c6 d2d4 d7d5 e4d5 c6d5 c2c4|B14|Caro-Kann: Panov Attack" & ASCII.LF &
      "e2e4 c7c6 d2d4 d7d5 e4d5 c6d5 c2c4 g8f6 b1c3|B14|Panov: ...Nf6 Nc3" & ASCII.LF &
      "e2e4 c7c6 b1c3|B10|Caro-Kann: Two Knights" & ASCII.LF &
      "e2e4 c7c6 b1c3 d7d5 d2d4|B10|CK: Two Knights ...d4" & ASCII.LF &
      --  ================================================================
      --  B20-B99  Sicilian Defence
      --  ================================================================
      "e2e4 c7c5|B20|Sicilian Defence" & ASCII.LF &
      "e2e4 c7c5 b1c3|B23|Sicilian: Closed" & ASCII.LF &
      "e2e4 c7c5 b1c3 b8c6|B23|Sicilian: Closed Nc6" & ASCII.LF &
      "e2e4 c7c5 b1c3 b8c6 g2g3|B24|Sicilian: Closed g3" & ASCII.LF &
      "e2e4 c7c5 c2c3|B22|Sicilian: Alapin" & ASCII.LF &
      "e2e4 c7c5 c2c3 d7d5 e4d5|B22|Sicilian: Alapin Accepted" & ASCII.LF &
      "e2e4 c7c5 c2c3 g8f6 e4e5|B22|Sicilian: Alapin Anti-Nf6" & ASCII.LF &
      "e2e4 c7c5 c2c3 g8f6 e4e5 f6d5|B22|Sicilian: Alapin ...Nd5" & ASCII.LF &
      "e2e4 c7c5 c2c3 e7e6|B22|Sicilian: Alapin ...e6" & ASCII.LF &
      "e2e4 c7c5 d2d4 c5d4 c2c3|B21|Sicilian: Smith-Morra Gambit" & ASCII.LF &
      "e2e4 c7c5 d2d4 c5d4 c2c3 d4c3|B21|Morra Gambit: Accepted" & ASCII.LF &
      "e2e4 c7c5 d2d4 c5d4 c2c3 d4c3 b1c3|B21|Morra: main" & ASCII.LF &
      "e2e4 c7c5 f2f4|B21|Sicilian: Grand Prix Attack" & ASCII.LF &
      "e2e4 c7c5 f2f4 b8c6|B21|Grand Prix: Nc6" & ASCII.LF &
      "e2e4 c7c5 f2f4 b8c6 g1f3|B21|Grand Prix: Nf3" & ASCII.LF &
      "e2e4 c7c5 g1f3|B30|Sicilian: Open" & ASCII.LF &
      "e2e4 c7c5 g1f3 b8c6|B30|Sicilian: ...Nc6" & ASCII.LF &
      "e2e4 c7c5 g1f3 b8c6 d2d4 c5d4 f3d4|B40|Sicilian: Open Nc6" & ASCII.LF &
      "e2e4 c7c5 g1f3 b8c6 f1b5|B30|Sicilian: Rossolimo" & ASCII.LF &
      "e2e4 c7c5 g1f3 b8c6 f1b5 g7g6|B31|Sicilian: Rossolimo ...g6" & ASCII.LF &
      "e2e4 c7c5 g1f3 b8c6 f1b5 e7e6|B30|Sicilian: Rossolimo ...e6" & ASCII.LF &
      "e2e4 c7c5 g1f3 b8c6 f1b5 d7d6|B30|Sicilian: Rossolimo ...d6" & ASCII.LF &
      "e2e4 c7c5 g1f3 e7e6|B40|Sicilian: ...e6" & ASCII.LF &
      "e2e4 c7c5 g1f3 e7e6 d2d4 c5d4 f3d4|B40|Sicilian: Taimanov" & ASCII.LF &
      "e2e4 c7c5 g1f3 e7e6 d2d4 c5d4 f3d4 b8c6|B46|Sicilian: Taimanov Nc6" & ASCII.LF &
      "e2e4 c7c5 g1f3 e7e6 d2d4 c5d4 f3d4 g8f6 b1c3|B41|Sicilian: Kan" & ASCII.LF &
      "e2e4 c7c5 g1f3 e7e6 d2d4 c5d4 f3d4 a7a6|B41|Sicilian: Kan (Polugaevsky)" & ASCII.LF &
      "e2e4 c7c5 g1f3 e7e6 d2d4 c5d4 f3d4 a7a6 b1c3|B41|Sicilian: Kan Nc3" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6|B50|Sicilian: ...d6" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4|B50|Sicilian: Open d6" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 a7a6|B90|Sicilian: Najdorf" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 a7a6 c1g5|B99|Sicilian: Najdorf English" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 a7a6 c1e3|B90|Sicilian: Najdorf English Attack" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 a7a6 f2f4|B93|Sicilian: Najdorf f4" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 a7a6 f1e2|B92|Sicilian: Najdorf Be2" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 a7a6 f1c4|B90|Sicilian: Najdorf Bc4" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 b8c6|B56|Sicilian: Classical" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 e7e6|B80|Sicilian: Scheveningen" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 e7e6 f2f4|B84|Sicilian: Scheveningen Keres" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 e7e6 c1e3|B83|Sicilian: Scheveningen Classical" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 g7g6|B70|Sicilian: Dragon" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 g7g6 f1e2 f8g7|B70|Sicilian: Dragon Be2" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 g7g6 f1e2 f8g7 e1g1 e8g8|B72|Sicilian: Dragon 0-0" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 g7g6 c1e3|B72|Sicilian: Dragon Yugoslav" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 g7g6 c1e3 f8g7 f2f3|B76|Sicilian: Dragon Yugoslav ...f3" & ASCII.LF &
      "e2e4 c7c5 g1f3 b8c6 d2d4 c5d4 f3d4 g7g6|B35|Sicilian: Accelerated Dragon" & ASCII.LF &
      "e2e4 c7c5 g1f3 b8c6 d2d4 c5d4 f3d4 g7g6 b1c3 f8g7|B36|Sic: Accelerated Dragon Nc3" & ASCII.LF &
      "e2e4 c7c5 g1f3 b8c6 d2d4 c5d4 f3d4 g8f6 b1c3 e7e5|B33|Sicilian: Sveshnikov/Pelikan" & ASCII.LF &
      "e2e4 c7c5 g1f3 b8c6 d2d4 c5d4 f3d4 g8f6 b1c3 e7e5 f4b5|B33|Sicilian: Sveshnikov main" & ASCII.LF &
      "e2e4 c7c5 g1f3 b8c6 d2d4 c5d4 f3d4 g8f6 b1c3 d7d5|B55|Sicilian: Sveshnikov d5" & ASCII.LF &
      "e2e4 c7c5 g1f3 b8c6 d2d4 c5d4 f3d4 g8f6 b1c3 c8b4|B34|Sicilian: ...Bb4" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 b8c6 b1c3|B56|Sicilian: Classical Nc3" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 b8c6 b1c3 g7g6|B72|Sicilian: Dragon via d6" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 b8c6 b1c3 c8f5|B58|Sicilian: ...Bf5" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 g7g6 c1e3 f8g7 f2f3 b8c6|B76|Sicilian: Dragon f3 Nc6" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 f1b5|B51|Sicilian: Moscow" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 f1b5 b8d7|B51|Sicilian: Moscow ...Nd7" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 f1b5 c8d7|B52|Sicilian: Moscow ...Bd7" & ASCII.LF &
      --  Sicilian: Richter-Rauzer
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 b8c6 c1g5|B60|Sicilian: Richter-Rauzer" & ASCII.LF &
      "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 b8c6 c1g5 e7e6|B61|Sicilian: Richter-Rauzer ...e6" & ASCII.LF &
      "e2e4 c7c5 g1f3 b8c6 d2d4 c5d4 f3d4 g8f6 b1c3 d7d6 c1g5|B60|Sicilian: Rauzer via Nc6" & ASCII.LF &
      --  ================================================================
      --  C00-C19  French Defence
      --  ================================================================
      "e2e4 e7e6|C00|French Defence" & ASCII.LF &
      "e2e4 e7e6 d2d4|C00|French: ...d4" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5|C01|French: Main Line" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 e4e5|C02|French: Advance" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 e4e5 c7c5|C02|French: Advance ...c5" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 e4e5 c7c5 c2c3|C02|French: Advance Main" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 e4e5 c7c5 c2c3 b8c6|C02|French: Advance ...Nc6" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 e4d5|C01|French: Exchange" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 e4d5 e6d5|C01|French: Exchange ...exd5" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 b1c3|C10|French: Three Knights" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 b1c3 g8f6|C11|French: Classical" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 b1c3 g8f6 c1g5|C13|French: Classical ...Bg5" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 b1c3 g8f6 c1g5 f8e7|C13|French: MacCutcheon" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 b1c3 g8f6 c1g5 d5e4|C15|French: Burn" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 b1c3 g8f6 e4e5|C11|French: Steinitz" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 b1c3 f8b4|C15|French: Winawer" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 b1c3 f8b4 e4e5|C16|French: Winawer ...e5" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 b1c3 f8b4 a2a3|C17|French: Winawer ...a3" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 b1c3 f8b4 a2a3 f8c3 b2c3|C17|French: Winawer Poisoned Pawn" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 b1c3 f8b4 g1e2|C15|French: Winawer Ne2" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 b1d2|C03|French: Tarrasch" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 b1d2 c7c5|C05|French: Tarrasch Open" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 b1d2 g8f6|C06|French: Tarrasch ...Nf6" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 b1d2 g8f6 e4e5|C07|French: Tarrasch Advance" & ASCII.LF &
      "e2e4 e7e6 d2d4 d7d5 b1d2 c7c5 g1f3|C05|French: Tarrasch ...Nf3" & ASCII.LF &
      --  ================================================================
      --  C20-C29  Open Games (e4 e5, rare)
      --  ================================================================
      "e2e4 e7e5|C20|King's Pawn Game" & ASCII.LF &
      "e2e4 e7e5 f1c4|C23|Bishop's Opening" & ASCII.LF &
      "e2e4 e7e5 f1c4 g8f6|C24|Bishop's: Berlin Defence" & ASCII.LF &
      "e2e4 e7e5 f1c4 f8c5|C23|Bishop's: ...Bc5" & ASCII.LF &
      "e2e4 e7e5 b1c3|C25|Vienna Game" & ASCII.LF &
      "e2e4 e7e5 b1c3 g8f6|C26|Vienna: ...Nf6" & ASCII.LF &
      "e2e4 e7e5 b1c3 g8f6 f2f4|C26|Vienna Gambit" & ASCII.LF &
      "e2e4 e7e5 b1c3 f8c5|C23|Vienna: ...Bc5" & ASCII.LF &
      "e2e4 e7e5 b1c3 b8c6|C25|Vienna: ...Nc6" & ASCII.LF &
      "e2e4 e7e5 b1c3 b8c6 f2f4|C25|Vienna: Hampe-Allgaier" & ASCII.LF &
      "e2e4 e7e5 f2f4|C30|King's Gambit" & ASCII.LF &
      "e2e4 e7e5 f2f4 e5f4|C33|King's Gambit Accepted" & ASCII.LF &
      "e2e4 e7e5 f2f4 e5f4 g1f3|C34|KGA: Schallop" & ASCII.LF &
      "e2e4 e7e5 f2f4 e5f4 g1f3 g7g5|C34|KGA: Fischer Defence" & ASCII.LF &
      "e2e4 e7e5 f2f4 e5f4 g1f3 d7d5|C33|KGA: ...d5" & ASCII.LF &
      "e2e4 e7e5 f2f4 e5f4 f1c4|C37|KGA: Muzio Gambit" & ASCII.LF &
      "e2e4 e7e5 f2f4 f8c5|C30|KGD: Classical" & ASCII.LF &
      "e2e4 e7e5 f2f4 d7d5|C31|KGD: Falkbeer" & ASCII.LF &
      "e2e4 e7e5 f2f4 d7d5 e4d5 e5e4|C31|Falkbeer Countergambit" & ASCII.LF &
      "e2e4 e7e5 d2d4 e5d4|C21|Centre Game" & ASCII.LF &
      "e2e4 e7e5 d2d4 e5d4 d1d4|C22|Centre Game: ...Qd4" & ASCII.LF &
      --  ================================================================
      --  C40-C49  Open Games (e4 e5 Nf3)
      --  ================================================================
      "e2e4 e7e5 g1f3 d7d6|C41|Philidor Defence" & ASCII.LF &
      "e2e4 e7e5 g1f3 d7d6 d2d4|C41|Philidor: ...d4" & ASCII.LF &
      "e2e4 e7e5 g1f3 d7d6 d2d4 g8f6|C41|Philidor: Hanham" & ASCII.LF &
      "e2e4 e7e5 g1f3 d7d6 d2d4 e5d4 g1f3 g8f6|C41|Philidor: Nimzowitsch" & ASCII.LF &
      "e2e4 e7e5 g1f3 g8f6|C42|Petrov Defence" & ASCII.LF &
      "e2e4 e7e5 g1f3 g8f6 f3e5|C42|Petrov: ...Ne5" & ASCII.LF &
      "e2e4 e7e5 g1f3 g8f6 f3e5 d7d6|C42|Petrov: Classical" & ASCII.LF &
      "e2e4 e7e5 g1f3 g8f6 f3e5 d7d6 e5f3 f6e4|C43|Petrov: Three Knights" & ASCII.LF &
      "e2e4 e7e5 g1f3 g8f6 f3e5 f6e4 d2d4|C42|Petrov: ...d4" & ASCII.LF &
      "e2e4 e7e5 g1f3 g8f6 b1c3|C46|Four Knights Game" & ASCII.LF &
      "e2e4 e7e5 g1f3 g8f6 b1c3 b8c6|C46|Four Knights: Symmetrical" & ASCII.LF &
      "e2e4 e7e5 g1f3 g8f6 b1c3 f8b4|C47|Four Knights: Spanish" & ASCII.LF &
      "e2e4 e7e5 g1f3 g8f6 b1c3 f8b4 f1b5|C48|Four Knights: Spanish main" & ASCII.LF &
      "e2e4 e7e5 g1f3 g8f6 b1c3 b8c6 f1b5|C49|Four Knights: Double Spanish" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 d2d4|C44|Scotch Opening" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 d2d4 e5d4|C45|Scotch Game" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 d2d4 e5d4 f3d4|C45|Scotch: Main Line" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 d2d4 e5d4 f3d4 f8c5|C45|Scotch: Classical" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 d2d4 e5d4 f3d4 g8f6|C45|Scotch: ...Nf6" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 d2d4 e5d4 f3d4 b8c6|C45|Scotch: ...Nc6" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 d2d4 e5d4 f3d4 d8h4|C44|Scotch Gambit: Steinitz" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1c4 f8c5 b2b4|C51|Evans Gambit" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1c4 f8c5 b2b4 c5b4|C52|Evans Gambit Accepted" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6|C55|Two Knights Defence" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 d2d4|C55|Two Knights: ...d4" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 f3g5|C57|Two Knights: Fried Liver" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 f3g5 d7d5|C57|Two Knights: ...d5" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 f3g5 d7d5 e4d5|C57|Two Knights: Main" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1c4 f8c5|C50|Giuoco Piano" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1c4 f8c5 c2c3|C54|Giuoco Piano: Main" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1c4 f8c5 c2c3 g8f6|C54|Giuoco Piano: ...Nf6" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1c4 f8c5 c2c3 d7d5|C54|Giuoco Piano: ...d5" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1c4 f8c5 d2d3|C53|Giuoco Pianissimo" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1c4 f8c5 b1c3|C50|Hungarian Defence" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1c4|C50|Italian Game" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1c4 f7f5|C50|Italian: ...f5" & ASCII.LF &
      --  ================================================================
      --  C60-C99  Ruy Lopez
      --  ================================================================
      "e2e4 e7e5 g1f3 b8c6 f1b5|C60|Ruy Lopez" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6|C60|Ruy Lopez: Morphy Defence" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5a4|C64|Ruy Lopez: a4" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5c6|C69|Ruy Lopez: Exchange" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5c6 d7c6 e1g1|C69|RL: Exchange 0-0" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5a4 g8f6|C70|Ruy Lopez: Open" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5a4 g8f6 e1g1|C77|Ruy Lopez: Morphy" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5a4 g8f6 e1g1 f8e7|C78|Ruy Lopez: Closed" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5a4 g8f6 e1g1 f8e7 h1e1|C79|RL: Open Defence" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5a4 g8f6 e1g1 f8e7 d1e2|C80|Ruy Lopez: Open" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5a4 g8f6 e1g1 f8e7 h1e1 b7b5 a4b3|C84|RL: Closed" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5a4 g8f6 e1g1 f8e7 h1e1 b7b5 a4b3 d7d6 c2c3 e8g8|C84|RL: Closed Main" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5a4 g8f6 e1g1 f8e7 h1e1 b7b5 a4b3 e8g8 c2c3 d7d5|C88|Ruy Lopez: Marshall Attack" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5a4 g8f6 e1g1 f8e7 h1e1 b7b5 a4b3 e8g8 c2c3 d7d6 h2h3|C90|RL: Chigorin" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5a4 g8f6 e1g1 f8e7 h1e1 b7b5 a4b3 e8g8 c2c3 d7d6 h2h3 b8a6|C91|RL: Breyer" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5a4 g8f6 e1g1 f8e7 h1e1 b7b5 a4b3 e8g8 c2c3 d7d6 h2h3 b8d7|C95|RL: ...Nd7" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 g8f6|C65|Ruy Lopez: Berlin Defence" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 g8f6 e1g1|C66|RL: Berlin 0-0" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 g8f6 e1g1 f6e4|C67|Ruy Lopez: Berlin Endgame" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 g8f6 e1g1 f6e4 d1e1|C67|Berlin: ...Qe1" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 f7f5|C63|Ruy Lopez: Schliemann" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 d7d6|C61|Ruy Lopez: ...d6" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 c8c6|C62|Ruy Lopez: Old Steinitz" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 f1b5 f8c5|C60|Ruy Lopez: Classical" & ASCII.LF &
      --  ================================================================
      --  Misc open
      --  ================================================================
      "e2e4 e7e5 g1f3 b8c6 b1c3 g8f6 f1b5|C47|Four Knights: Yugoslav" & ASCII.LF &
      "e2e4 e7e5 g1f3 b8c6 d2d3|C55|King's Indian Attack (vs e5)" & ASCII.LF;

   Loaded_Data : Unbounded_String := Null_Unbounded_String;

   function Active_Data return String is
   begin
      if Length (Loaded_Data) > 0 then
         return To_String (Loaded_Data);
      else
         return Builtin_Data;
      end if;
   end Active_Data;

   --  Case-insensitive contains check.
   function Contains_CI (Haystack, Needle : String) return Boolean is
      function Lo (C : Character) return Character is
      begin
         if C in 'A' .. 'Z' then
            return Character'Val (Character'Pos (C) + 32);
         end if;
         return C;
      end Lo;
   begin
      if Needle'Length = 0 or else Needle'Length > Haystack'Length then
         return Needle'Length = 0;
      end if;
      for I in Haystack'First .. Haystack'Last - Needle'Length + 1 loop
         declare
            Match : Boolean := True;
         begin
            for J in Needle'Range loop
               if Lo (Haystack (I + J - Needle'First)) /= Lo (Needle (J)) then
                  Match := False; exit;
               end if;
            end loop;
            if Match then return True; end if;
         end;
      end loop;
      return False;
   end Contains_CI;

   function Find_Moves (Name : String) return String is
      Data : constant String  := Active_Data;
      I    : Natural          := Data'First;
   begin
      while I <= Data'Last loop
         declare
            Line_End : Natural := I;
         begin
            while Line_End <= Data'Last
               and then Data (Line_End) /= ASCII.LF
            loop Line_End := Line_End + 1; end loop;
            declare
               Line : constant String := Data (I .. Line_End - 1);
               Sep1 : Natural := 0;
               Sep2 : Natural := 0;
            begin
               for J in Line'Range loop
                  if Line (J) = '|' then
                     if Sep1 = 0 then Sep1 := J;
                     elsif Sep2 = 0 then Sep2 := J;
                     end if;
                  end if;
               end loop;
               if Sep1 > 0 and then Sep2 > Sep1 then
                  declare
                     Entry_ECO  : constant String := Line (Sep1 + 1 .. Sep2 - 1);
                     Entry_Name : constant String := Line (Sep2 + 1 .. Line'Last);
                  begin
                     if Contains_CI (Entry_Name, Name)
                        or else Contains_CI (Entry_ECO, Name)
                        or else Contains_CI (Entry_ECO & "  " & Entry_Name, Name)
                     then
                        return Line (Line'First .. Sep1 - 1);
                     end if;
                  end;
               end if;
            end;
            I := Line_End + 1;
         end;
      end loop;
      return "";
   end Find_Moves;

   procedure For_Each_Opening
     (Action : not null access procedure (ECO : String; Name : String);
      Filter : String := "")
   is
      Data : constant String := Active_Data;
      I    : Natural         := Data'First;
   begin
      while I <= Data'Last loop
         declare
            Line_End : Natural := I;
         begin
            while Line_End <= Data'Last
               and then Data (Line_End) /= ASCII.LF
            loop Line_End := Line_End + 1; end loop;
            declare
               Line : constant String := Data (I .. Line_End - 1);
               Sep1 : Natural := 0;
               Sep2 : Natural := 0;
            begin
               for J in Line'Range loop
                  if Line (J) = '|' then
                     if Sep1 = 0 then Sep1 := J;
                     elsif Sep2 = 0 then Sep2 := J;
                     end if;
                  end if;
               end loop;
               if Sep1 > 0 and then Sep2 > Sep1 then
                  declare
                     ECO  : constant String := Line (Sep1 + 1 .. Sep2 - 1);
                     Name : constant String := Line (Sep2 + 1 .. Line'Last);
                  begin
                     if Filter'Length = 0 or else Contains_CI (Name, Filter) then
                        Action (ECO, Name);
                     end if;
                  end;
               end if;
            end;
            I := Line_End + 1;
         end;
      end loop;
   end For_Each_Opening;

   procedure For_Each_Opening_Full
     (Action : not null access procedure
        (ECO : String; Name : String; Moves : String);
      Filter : String := "")
   is
      Data : constant String := Active_Data;
      I    : Natural         := Data'First;
   begin
      while I <= Data'Last loop
         declare
            Line_End : Natural := I;
         begin
            while Line_End <= Data'Last
               and then Data (Line_End) /= ASCII.LF
            loop Line_End := Line_End + 1; end loop;
            declare
               Line : constant String := Data (I .. Line_End - 1);
               Sep1 : Natural := 0;
               Sep2 : Natural := 0;
            begin
               for J in Line'Range loop
                  if Line (J) = '|' then
                     if Sep1 = 0 then Sep1 := J;
                     elsif Sep2 = 0 then Sep2 := J;
                     end if;
                  end if;
               end loop;
               if Sep1 > 0 and then Sep2 > Sep1 then
                  declare
                     ECO   : constant String := Line (Sep1 + 1 .. Sep2 - 1);
                     Name  : constant String := Line (Sep2 + 1 .. Line'Last);
                     Moves : constant String := Line (Line'First .. Sep1 - 1);
                  begin
                     if Filter'Length = 0
                        or else Contains_CI (Name, Filter)
                        or else Contains_CI (ECO, Filter)
                     then
                        Action (ECO, Name, Moves);
                     end if;
                  end;
               end if;
            end;
            I := Line_End + 1;
         end;
      end loop;
   end For_Each_Opening_Full;

   function Lookup (Moves_UCI : String) return String is
      Data      : constant String  := Active_Data;
      Best_Len  : Natural := 0;
      Best_Code : String (1 .. 3)  := "   ";
      Best_Name : String (1 .. 60) := (others => ' ');
      Best_Nlen : Natural := 0;

      I : Natural := Data'First;
   begin
      while I <= Data'Last loop
         --  Find end of this line
         declare
            Line_End : Natural := I;
         begin
            while Line_End <= Data'Last and then Data (Line_End) /= ASCII.LF loop
               Line_End := Line_End + 1;
            end loop;
            --  Parse "moves|code|name"
            declare
               Line  : constant String := Data (I .. Line_End - 1);
               Sep1  : Natural := 0;
               Sep2  : Natural := 0;
            begin
               for J in Line'Range loop
                  if Line (J) = '|' then
                     if Sep1 = 0 then Sep1 := J;
                     elsif Sep2 = 0 then Sep2 := J;
                     end if;
                  end if;
               end loop;
               if Sep1 > 0 and then Sep2 > Sep1 then
                  declare
                     Mvs  : constant String := Line (Line'First .. Sep1 - 1);
                     Code : constant String := Line (Sep1 + 1 .. Sep2 - 1);
                     Name : constant String := Line (Sep2 + 1 .. Line'Last);
                     Mlen : constant Natural := Mvs'Length;
                  begin
                     --  Match if Moves_UCI starts with Mvs (exact or followed by space)
                     if Mlen <= Moves_UCI'Length
                        and then Moves_UCI (Moves_UCI'First
                                            .. Moves_UCI'First + Mlen - 1) = Mvs
                        and then (Mlen = Moves_UCI'Length
                                  or else Moves_UCI (Moves_UCI'First + Mlen) = ' ')
                        and then Mlen > Best_Len
                     then
                        Best_Len := Mlen;
                        Best_Code (1 .. Code'Length) := Code;
                        Best_Name (1 .. Name'Length) := Name;
                        Best_Nlen := Name'Length;
                     end if;
                  end;
               end if;
            end;
            I := Line_End + 1;
         end;
      end loop;

      if Best_Len = 0 then return ""; end if;
      return Best_Code (1 .. 3) & "  " & Best_Name (1 .. Best_Nlen);
   end Lookup;

   function Hash_File (Path : String) return String is
      use Ada.Streams;
      use Ada.Streams.Stream_IO;
      F       : File_Type;
      Buf     : Stream_Element_Array (1 .. 4096);
      Last    : Stream_Element_Offset;
      Sha_Buf : Sha1.Unsigned_8_Array_T (1 .. 4096);
      Count   : Natural;
      Ctx     : Sha1.Context_T;
      Ok      : Boolean;
      Hex     : constant String := "0123456789abcdef";
      Res     : String (1 .. 40);
      Pos     : Positive := 1;
   begin
      Sha1.Init (Ctx);
      Open (F, In_File, Path);
      loop
         Read (F, Buf, Last);
         exit when Last < Buf'First;
         Count := Natural (Last - Buf'First + 1);
         for I in Stream_Element_Offset range Buf'First .. Last loop
            Sha_Buf (Natural (I - Buf'First) + 1) :=
               Interfaces.Unsigned_8 (Buf (I));
         end loop;
         Sha1.Input (Ctx, Sha_Buf (1 .. Count));
      end loop;
      Close (F);
      Sha1.Result (Ctx, Ok);
      if not Ok then return ""; end if;
      for W of Ctx.Message_Digest loop
         for S in reverse 0 .. 7 loop
            declare
               Shift  : constant Sha1.Unsigned_32 := Sha1.Unsigned_32 (16) ** S;
               Nibble : constant Natural := Natural ((W / Shift) and 15);
            begin
               Res (Pos) := Hex (Hex'First + Nibble);
               Pos := Pos + 1;
            end;
         end loop;
      end loop;
      return Res;
   exception
      when others => return "";
   end Hash_File;

   procedure Load (Path : String) is
      F    : Ada.Text_IO.File_Type;
      Line : String (1 .. 512);
      Last : Natural;
      Buf  : Unbounded_String := Null_Unbounded_String;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (F) loop
         Ada.Text_IO.Get_Line (F, Line, Last);
         if Last >= 1 and then Line (1) /= '#' then
            Append (Buf, Line (1 .. Last));
            Append (Buf, ASCII.LF);
         end if;
      end loop;
      Ada.Text_IO.Close (F);
      Loaded_Data := Buf;
   exception
      when others => null;
   end Load;

end DGT.Openings;
