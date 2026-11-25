#!/usr/bin/env python3
"""Generate src/MKBibVrs.pas (the versification tables) without Sword's tables.
Usage: genvrs.py <eng-asv.zefania.xml> <out.pas>

The 66 books: names, OSIS ids and abbreviations are written out below; the chapter count of each book and the
number of verses of each chapter are counted in a public domain Bible text with the usual (KJV) structure, the ASV
in Zefania XML from https://github.com/seven1m/open-bibles (any 66 book Bible with KJV numbering will do; the
numbers have to come to 1189 chapters and 31102 verses, which is checked).  The NRSV numbers the same way except
for two chapters, 3 John 1 (15 verses, not 14) and Revelation 12 (18, not 17).  The Apocrypha of the KJVA and
NRSVA systems are in MKBibVrA.pas (tools/genvra.py)."""
import re, sys
import xml.etree.ElementTree as ET

NAMES = """Genesis|Gen|Gen
Exodus|Exod|Exod
Leviticus|Lev|Lev
Numbers|Num|Num
Deuteronomy|Deut|Deut
Joshua|Josh|Josh
Judges|Judg|Judg
Ruth|Ruth|Ruth
I Samuel|1Sam|1Sam
II Samuel|2Sam|2Sam
I Kings|1Kgs|1Kgs
II Kings|2Kgs|2Kgs
I Chronicles|1Chr|1Chr
II Chronicles|2Chr|2Chr
Ezra|Ezra|Ezra
Nehemiah|Neh|Neh
Esther|Esth|Esth
Job|Job|Job
Psalms|Ps|Ps
Proverbs|Prov|Prov
Ecclesiastes|Eccl|Eccl
Song of Solomon|Song|Song
Isaiah|Isa|Isa
Jeremiah|Jer|Jer
Lamentations|Lam|Lam
Ezekiel|Ezek|Ezek
Daniel|Dan|Dan
Hosea|Hos|Hos
Joel|Joel|Joel
Amos|Amos|Amos
Obadiah|Obad|Obad
Jonah|Jonah|Jonah
Micah|Mic|Mic
Nahum|Nah|Nah
Habakkuk|Hab|Hab
Zephaniah|Zeph|Zeph
Haggai|Hag|Hag
Zechariah|Zech|Zech
Malachi|Mal|Mal
Matthew|Matt|Matt
Mark|Mark|Mark
Luke|Luke|Luke
John|John|John
Acts|Acts|Acts
Romans|Rom|Rom
I Corinthians|1Cor|1Cor
II Corinthians|2Cor|2Cor
Galatians|Gal|Gal
Ephesians|Eph|Eph
Philippians|Phil|Phil
Colossians|Col|Col
I Thessalonians|1Thess|1Thess
II Thessalonians|2Thess|2Thess
I Timothy|1Tim|1Tim
II Timothy|2Tim|2Tim
Titus|Titus|Titus
Philemon|Phlm|Phlm
Hebrews|Heb|Heb
James|Jas|Jas
I Peter|1Pet|1Pet
II Peter|2Pet|2Pet
I John|1John|1John
II John|2John|2John
III John|3John|3John
Jude|Jude|Jude
Revelation of John|Rev|Rev""".split("\n")
assert len(NAMES) == 66

root = ET.parse(sys.argv[1]).getroot()
chaps = []          # per book: list of verse counts
for b in root.iter('BIBLEBOOK'):
    chaps.append([max(int(v.get('vnumber')) for v in c.iter('VERS')) for c in b.iter('CHAPTER')])
assert len(chaps) == 66
vm_kjv = [n for bk in chaps for n in bk]
assert len(vm_kjv) == 1189 and sum(vm_kjv) == 31102, (len(vm_kjv), sum(vm_kjv))
canon = []
for (line, bk) in zip(NAMES, chaps):
    n, o, a = line.split("|")
    canon.append((n, o, a, len(bk)))

def index_of(osis, ch):
    i = 0
    for (n, o, a, c) in canon:
        if o == osis:
            return i + ch - 1
        i += c
vm_nrsv = list(vm_kjv)
vm_nrsv[index_of('3John', 1)] = 15
vm_nrsv[index_of('Rev', 12)] = 18

def lit(s): return "'" + s.replace("'", "''") + "'"
def recs(bs): return ",\n".join("    (Name: %s; OSIS: %s; Abbrev: %s; Chaps: %d)" % (lit(n), lit(o), lit(a), c) for n, o, a, c in bs)
def arr(name, v, per=16):
    return ("  %s: Array[0..%d] Of Byte = (\n" % (name, len(v) - 1)) + ",\n".join("    " + ", ".join(map(str, v[i:i+per])) for i in range(0, len(v), per)) + ");\n"

TEMPLATE = """
Function VrsFind(Name: String; Var Sys: VrsSystem): Boolean;
  {Sword Versification= name -> system (KJV, KJVA, NRSV, NRSVA); False if not supported}
Function VrsName(Sys: VrsSystem): String;
Function VrsHasApoc(Sys: VrsSystem): Boolean;
Function VrsBookCount(Sys: VrsSystem; Apoc: Boolean): Word;
Function VrsBook(Sys: VrsSystem; Book: Word): BookNameRec;
Function VrsInNT(Book: Word): Boolean;                  {books 40..66; apocrypha live in the OT file}
Function VrsChapters(Sys: VrsSystem; Book: Word): Word;
Function VrsVerses(Sys: VrsSystem; Book, Chap: Word): Word;
Function VrsValid(Sys: VrsSystem; Book, Chap, Verse: Word): Boolean;
Function VrsLinear(Sys: VrsSystem; Book, Chap, Verse: Word): LongInt;   {1.. in book number order; 0 = invalid}
Function VrsTotal(Sys: VrsSystem; Apoc: Boolean): LongInt;
Procedure VrsFromLinear(Sys: VrsSystem; L: LongInt; Var Book, Chap, Verse: Word);
Function VrsTestOffset(Sys: VrsSystem; Book, Chap, Verse: Word): LongInt;
  {Sword index of a verse inside its testament file (0 = module heading, 1 = testament
   heading, then book/chapter headings interleaved).  Chap 0 gives the book heading.}

Implementation

Type
  TabRec = Record
    NBooks: Word;                                    {canon + apocrypha}
    ChapMax: Array[1..BibMaxBooks, 1..BibMaxChap] Of Byte;
    ChapOff: Array[1..BibMaxBooks, 1..BibMaxChap] Of LongInt; {test. offset of chapter heading}
    ChapLin: Array[1..BibMaxBooks, 1..BibMaxChap] Of LongInt;
    BookLin: Array[1..BibMaxBooks + 1] Of LongInt;   {linear index before book}
    NApoc: Word;
    TotCanon, TotAll: LongInt;
  End;

Var
  Tab: Array[VrsSystem] Of TabRec;

Function UpStr(S: String): String;
  Var i: Word;
  Begin
  For i := 1 To Length(S) Do S[i] := UpCase(S[i]);
  UpStr := S;
  End;

Function VrsFind(Name: String; Var Sys: VrsSystem): Boolean;
  Begin
  Name := UpStr(Name);
  VrsFind := True;
  If (Name = '') Or (Name = 'KJV') Then Sys := vsKJV
  Else If Name = 'KJVA' Then Sys := vsKJVA
  Else If Name = 'NRSV' Then Sys := vsNRSV
  Else If Name = 'NRSVA' Then Sys := vsNRSVA
  Else VrsFind := False;
  End;

Function VrsName(Sys: VrsSystem): String;
  Begin
  Case Sys Of
    vsKJV: VrsName := 'KJV';
    vsKJVA: VrsName := 'KJVA';
    vsNRSV: VrsName := 'NRSV';
    Else VrsName := 'NRSVA';
    End;
  End;

Function VrsHasApoc(Sys: VrsSystem): Boolean;
  Begin
  VrsHasApoc := Tab[Sys].NApoc > 0;
  End;

Function VrsBookCount(Sys: VrsSystem; Apoc: Boolean): Word;
  Begin
  If Apoc Then VrsBookCount := Tab[Sys].NBooks Else VrsBookCount := BibBooks;
  End;

Function VrsBook(Sys: VrsSystem; Book: Word): BookNameRec;
  Var Empty: BookNameRec; A: ApocBookRec;
  Begin
  FillChar(Empty, SizeOf(Empty), 0);
  If (Book >= 1) And (Book <= BibBooks) Then VrsBook := BookInfo[Book]
  Else If (Book > BibBooks) And (Book <= Tab[Sys].NBooks) Then
    Begin
    If Sys = vsKJVA Then A := ApocKJVA[Book - BibBooks] Else A := ApocNRSVA[Book - BibBooks];
    Empty.Name := A.Name; Empty.OSIS := A.OSIS; Empty.Abbrev := A.Abbrev; Empty.Chaps := A.Chaps;
    VrsBook := Empty;
    End
  Else VrsBook := Empty;
  End;

Function VrsInNT(Book: Word): Boolean;
  Begin
  VrsInNT := (Book > BibOTBooks) And (Book <= BibBooks);
  End;

Function VrsChapters(Sys: VrsSystem; Book: Word): Word;
  Begin
  If (Book < 1) Or (Book > Tab[Sys].NBooks) Then VrsChapters := 0
  Else VrsChapters := VrsBook(Sys, Book).Chaps;
  End;

Function VrsVerses(Sys: VrsSystem; Book, Chap: Word): Word;
  Begin
  If (Chap < 1) Or (Chap > VrsChapters(Sys, Book)) Then VrsVerses := 0
  Else VrsVerses := Tab[Sys].ChapMax[Book, Chap];
  End;

Function VrsValid(Sys: VrsSystem; Book, Chap, Verse: Word): Boolean;
  Begin
  VrsValid := (Verse >= 1) And (Verse <= VrsVerses(Sys, Book, Chap));
  End;

Function VrsTotal(Sys: VrsSystem; Apoc: Boolean): LongInt;
  Begin
  If Apoc Then VrsTotal := Tab[Sys].TotAll Else VrsTotal := Tab[Sys].TotCanon;
  End;

Function VrsLinear(Sys: VrsSystem; Book, Chap, Verse: Word): LongInt;
  Begin
  If Not VrsValid(Sys, Book, Chap, Verse) Then VrsLinear := 0
  Else VrsLinear := Tab[Sys].ChapLin[Book, Chap] + Verse;
  End;

Procedure VrsFromLinear(Sys: VrsSystem; L: LongInt; Var Book, Chap, Verse: Word);
  Var B, C: Word;
  Begin
  Book := 0; Chap := 0; Verse := 0;
  If (L < 1) Or (L > Tab[Sys].TotAll) Then Exit;
  B := 1;
  While Tab[Sys].BookLin[B + 1] < L Do Inc(B);
  C := 1;
  While (C < VrsChapters(Sys, B)) And (Tab[Sys].ChapLin[B, C + 1] < L) Do Inc(C);
  Book := B; Chap := C; Verse := L - Tab[Sys].ChapLin[B, C];
  End;

Function VrsTestOffset(Sys: VrsSystem; Book, Chap, Verse: Word): LongInt;
  Begin
  If (Book < 1) Or (Book > Tab[Sys].NBooks) Then VrsTestOffset := 0
  Else If Chap = 0 Then VrsTestOffset := Tab[Sys].ChapOff[Book, 1] - 1   {book heading}
  Else VrsTestOffset := Tab[Sys].ChapOff[Book, Chap] + Verse;
  End;

Procedure BuildTables;
  Var
    S: VrsSystem;
    B, C, P, Q, NB, NAp: Word;
    N: Word;
    Off, Lin: LongInt;
    Order: Array[1..BibMaxBooks] Of Word;     {book numbers in Sword file order: OT, apocrypha, NT}
    K: Word;
  Begin
  For S := vsKJV To vsNRSVA Do
    Begin
    If S = vsKJVA Then NAp := NApocKJVA Else If S = vsNRSVA Then NAp := NApocNRSVA Else NAp := 0;
    NB := BibBooks + NAp;
    Tab[S].NBooks := NB;
    Tab[S].NApoc := NAp;
    {chapter maxima: canon from the base array (KJVA shares KJV's, NRSVA NRSV's), then apocrypha}
    P := 0; Q := 0;
    For B := 1 To NB Do
      Begin
      For C := 1 To VrsChapters(S, B) Do
        Begin
        If B <= BibBooks Then
          Begin
          If S In [vsKJV, vsKJVA] Then N := VerseMaxKJV[P] Else N := VerseMaxNRSV[P];
          Inc(P);
          End
        Else
          Begin
          If S = vsKJVA Then N := ApocVMKJVA[Q] Else N := ApocVMNRSVA[Q];
          Inc(Q);
          End;
        Tab[S].ChapMax[B, C] := N;
        End;
      End;
    {linear index in book number order}
    Lin := 0;
    For B := 1 To NB Do
      Begin
      Tab[S].BookLin[B] := Lin;
      For C := 1 To VrsChapters(S, B) Do
        Begin
        Tab[S].ChapLin[B, C] := Lin;
        Inc(Lin, Tab[S].ChapMax[B, C]);
        End;
      If B = BibBooks Then Tab[S].TotCanon := Lin;
      End;
    Tab[S].BookLin[NB + 1] := Lin;
    Tab[S].TotAll := Lin;
    {testament file offsets: OT file = books 1-39 then the apocrypha, NT file = 40-66}
    K := 0;
    For B := 1 To BibOTBooks Do Begin Inc(K); Order[K] := B; End;
    For B := BibBooks + 1 To NB Do Begin Inc(K); Order[K] := B; End;
    Off := 1;                                  {module heading 0, testament heading 1}
    For P := 1 To K Do
      Begin
      B := Order[P];
      Inc(Off);                                {book heading}
      For C := 1 To VrsChapters(S, B) Do
        Begin
        Inc(Off);                              {chapter heading}
        Tab[S].ChapOff[B, C] := Off;
        Inc(Off, Tab[S].ChapMax[B, C]);
        End;
      End;
    Off := 1;                                  {NT file restarts}
    For B := BibOTBooks + 1 To BibBooks Do
      Begin
      Inc(Off);
      For C := 1 To VrsChapters(S, B) Do
        Begin
        Inc(Off);
        Tab[S].ChapOff[B, C] := Off;
        Inc(Off, Tab[S].ChapMax[B, C]);
        End;
      End;
    End;
  End;

Begin
BuildTables;
End.
"""

o = []
o.append("Unit MKBibVrs;       {Versification tables - GENERATED by tools/genvrs.py}\n")
o.append("{ The 66 book tables are counted in a public domain Bible text; the Apocrypha tables are in MKBibVrA. }\n")
o.append("{$I MKBib.Def}\n\nInterface\n\nUses MKBibVrA;\n")
o.append("""Const
  BibBooks = 66;           {canonical books: 1-39 OT, 40-66 NT}
  BibOTBooks = 39;
  BibMaxBooks = 66 + MaxApocBooks;        {canon + the longest Apocrypha}
  BibMaxChap = 150;
  BibTotalVerses = %d;     {canonical verses (KJV)}

Type
  BookNameRec = Record Name, OSIS, Abbrev: String[24]; Chaps: Byte; End;
  VrsSystem = (vsKJV, vsKJVA, vsNRSV, vsNRSVA);

Const
  BookInfo: Array[1..66] Of BookNameRec = (
%s);
""" % (sum(vm_kjv), recs(canon)))
o.append("Const\n" + arr("VerseMaxKJV", vm_kjv) + arr("VerseMaxNRSV", vm_nrsv))
o.append(TEMPLATE)
open(sys.argv[2], 'w').write("\n".join(o))
