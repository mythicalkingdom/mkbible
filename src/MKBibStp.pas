Unit MKBibStp;       {STEP module object (QuickVerse and other STEP publishers), read only}

{$I MKBib.Def}

{
  MKBibStp - descendant of AbsBibObj that reads STEP modules (Standard Template for Electronic
  Publishing, BSISG; used by QuickVerse, WORDsearch, e-Sword and others).

  A STEP module is a directory holding
      Book.dat        header, control word area, then the text in LZSS compressed blocks of RTF
      Viewable.idx    table of those blocks (offset, size, uncompressed size)
      Sections.idx    the section tree: one 29 byte entry per book, chapter, heading, verse and
                      footnote ("gloss"), each pointing at a block and a \stepstartlevelN marker
      Vsync.idx       per book, the (chapter, verse) -> section entry map
      Verses.idx, Concord.idx   verse and word indexes (not needed for reading)
  File names may be in any case (Windows copies have BOOK.DAT, SECTIONS.IDX ...).

  The layout is the one CrossWire's step2vpl uses (Sword utilities/step2vpl.cpp), checked against
  QuickVerse NASB, NIV and Hard Sayings of the Bible modules.

  What this reader does:
    SetBibPath(directory)   OpenBible loads the indexes (a few MB) and reads blocks on demand.
    GetRawVerse             the verse's RTF text with footnote links replaced by inline groups
                            \*\stepnote (the footnote text) and the section headings that
                            come before the verse added as \*\stephead groups.  The markup is
                            reported as bmSTEP; the markup translator reads it (italics, words of
                            Jesus = colour 6, quotes, dashes, notes, headings).
    GetIntro(bilBook)       the book title.
  Books are numbered 1..66 and the KJV verse structure is assumed (verses outside it are
  skipped and counted: GetSkippedRows).  Commentary modules (e.g. Hard Sayings of the Bible)
  open too; only the verses they have entries for have text.

  Not supported: encrypted modules (OpenBible returns bibErrUnsupported), writing STEP modules,
  the concordance and the multimedia file (MM.DAT).
}

Interface

Uses MKBibMod, MKBibAbs, MKBibVrs;

Type
  PLongArr = ^TLongArr;
  TLongArr = Array[0..0] Of LongInt;

  SecRec = Record
    Parent, Prev, Next, Block: LongInt;
    StartLevel: SmallInt;
    Level: Byte;
    NameOfs: LongInt;
  End;

  StepBibObj = Object(AbsBibObj)
  Constructor Init;
  Destructor Done; Virtual;
  Procedure SetBibPath(BP: String); Virtual;
  Function  OpenBible: Word; Virtual;
  Function  CloseBible: Word; Virtual;
  Function  BibleExists: Boolean; Virtual;
  Function  IsOpen: Boolean; Virtual;
  Function  GetName: String; Virtual;
  Function  GetDescription: String; Virtual;
  Function  GetAbout: BibStr; Virtual;
  Function  GetLang: String; Virtual;
  Function  GetVersion: String; Virtual;
  Function  GetCopyright: String; Virtual;
  Function  GetMarkup: BibMarkup; Virtual;
  Function  SetVersification(Name: String): Boolean; Virtual;
  Function  GetRawVerse: BibStr; Virtual;
  Function  GetIntro(Level, Book, Chap: Word): BibStr; Virtual;   {book titles only}
  Function  GetControlWord(Key: String): BibStr;                  {a header entry such as Title or Copyright}
  Function  GetSkippedRows: LongInt;

  Public
  PathSpec, Dir: BibStr;
  Opened: Boolean;
  BookFile: File;
  Header: BibStr;                    {control word area}
  Lang: String;
  EncType: Byte;
  ViewData: Pointer; ViewSize, ViewStart, ViewEntry, ViewCount: LongInt;
  SecData: Pointer; SecSize, SecStart, SecEntry, SecLevels, SecGloss: LongInt;
  VerseSec: PLongArr;                {by linear verse number: section entry + 1, 0 = none}
  HeadFirst, HeadNext: PLongArr;     {by section entry: first / next heading entry + 1, 0 = none}
  BookTitle: Array[1..BibBooks] Of LongInt;   {section entry + 1 of the level 1 entry}
  Skipped: LongInt;
  CBlk, GBlk: LongInt;               {block numbers held in the verse / footnote caches}
  CTxt, GTxt: BibStr;
  Function  FindFileCI(Name: String): String;
  Function  LoadAll(Const Name: String; Var P: Pointer; Var Size: LongInt): Boolean;
  Function  BlockText(N: LongInt; Gloss: Boolean): BibStr;
  Procedure ReadSec(Idx: LongInt; Var R: SecRec);
  Function  SecName(Ofs: LongInt): BibStr;
  Function  SecText(Idx: LongInt; Gloss: Boolean): BibStr;
  Function  GlossBody(Idx: LongInt): BibStr;
  Function  ExpandLinks(Const S: BibStr; Strip: Boolean): BibStr;
  Function  BuildMaps: Boolean;
  Procedure FreeAll;
  End;

Type StepBibPtr = ^StepBibObj;

Implementation

Uses SysUtils, MKBibZ;

Function GetU16(P: Pointer; Ofs: LongInt): Word;
  Begin
  GetU16 := LEtoN(PWord(PByte(P) + Ofs)^);
  End;

Function GetS16(P: Pointer; Ofs: LongInt): SmallInt;
  Begin
  GetS16 := SmallInt(LEtoN(PWord(PByte(P) + Ofs)^));
  End;

Function GetU32(P: Pointer; Ofs: LongInt): LongWord;
  Begin
  GetU32 := LEtoN(PLongWord(PByte(P) + Ofs)^);
  End;

Function GetS32(P: Pointer; Ofs: LongInt): LongInt;
  Begin
  GetS32 := LongInt(LEtoN(PLongWord(PByte(P) + Ofs)^));
  End;


Constructor StepBibObj.Init;
  Begin
  AbsBibObj.Init;
  PathSpec := ''; Dir := '';
  Opened := False;
  Header := ''; Lang := '';
  ViewData := Nil; SecData := Nil; VerseSec := Nil; HeadFirst := Nil; HeadNext := Nil;
  CBlk := -1; GBlk := -1; CTxt := ''; GTxt := '';
  Skipped := 0;
  MetaMarkup := bmSTEP;
  End;

Destructor StepBibObj.Done;
  Begin
  If Opened Then CloseBible;
  AbsBibObj.Done;
  End;

Procedure StepBibObj.SetBibPath(BP: String);
  Begin
  If Opened Then CloseBible;
  PathSpec := BP;
  End;

Function StepBibObj.FindFileCI(Name: String): String;
  Var
    SR: TSearchRec;
    D: AnsiString;
  Begin
  FindFileCI := '';
  D := PathSpec;
  If (D <> '') And (D[Length(D)] <> '/') Then D := D + '/';
  If FindFirst(D + '*', faAnyFile, SR) = 0 Then
    Begin
    Repeat
      If LowerCase(SR.Name) = LowerCase(Name) Then
        Begin
        FindFileCI := D + SR.Name;
        Break;
        End;
    Until FindNext(SR) <> 0;
    FindClose(SR);
    End;
  End;

Function StepBibObj.BibleExists: Boolean;
  Begin
  BibleExists := Opened Or ((PathSpec <> '') And DirectoryExists(PathSpec) And (FindFileCI('Book.dat') <> ''));
  End;

Function StepBibObj.IsOpen: Boolean;
  Begin
  IsOpen := Opened;
  End;

Function StepBibObj.LoadAll(Const Name: String; Var P: Pointer; Var Size: LongInt): Boolean;
  Var
    F: File;
    N: String;
    SaveMode: Byte;
  Begin
  LoadAll := False;
  P := Nil; Size := 0;
  N := FindFileCI(Name);
  If N = '' Then Exit;
  SaveMode := FileMode;
  FileMode := 0;
  Assign(F, N);
  Reset(F, 1);
  FileMode := SaveMode;
  If IOResult <> 0 Then Exit;
  Size := FileSize(F);
  If Size > 0 Then
    Begin
    GetMem(P, Size);
    BlockRead(F, P^, Size);
    If IOResult <> 0 Then
      Begin
      FreeMem(P, Size);
      P := Nil;
      Close(F);
      Exit;
      End;
    End;
  Close(F);
  LoadAll := True;
  End;

Procedure StepBibObj.FreeAll;
  Begin
  If ViewData <> Nil Then FreeMem(ViewData, ViewSize);
  If SecData <> Nil Then FreeMem(SecData, SecSize);
  If VerseSec <> Nil Then FreeMem(VerseSec);
  If HeadFirst <> Nil Then FreeMem(HeadFirst);
  If HeadNext <> Nil Then FreeMem(HeadNext);
  ViewData := Nil; SecData := Nil; VerseSec := Nil; HeadFirst := Nil; HeadNext := Nil;
  CBlk := -1; GBlk := -1; CTxt := ''; GTxt := '';
  End;


{ Text of block N of Viewable.idx: read from Book.dat and LZSS expanded }
Function StepBibObj.BlockText(N: LongInt; Gloss: Boolean): BibStr;
  Var
    Ofs, USize, CSize: LongWord;
    Comp: Pointer;
    Got: LongInt;
    ULen: LongWord;
    R: BibStr;
    P: LongInt;
  Begin
  BlockText := '';
  If (N < 0) Or (N >= ViewCount) Then Exit;
  If Gloss Then
    Begin
    If GBlk = N Then Begin BlockText := GTxt; Exit; End;
    End
  Else If CBlk = N Then Begin BlockText := CTxt; Exit; End;
  Ofs := GetU32(ViewData, ViewStart + N * ViewEntry);
  USize := GetU32(ViewData, ViewStart + N * ViewEntry + 4);
  CSize := GetU32(ViewData, ViewStart + N * ViewEntry + 8);
  If (CSize = 0) Or (USize = 0) Or (USize > 32 * 1024 * 1024) Then Exit;
  GetMem(Comp, CSize);
  Seek(BookFile, Ofs);
  BlockRead(BookFile, Comp^, CSize, Got);
  If (IOResult <> 0) Or (Got <> LongInt(CSize)) Then
    Begin
    FreeMem(Comp, CSize);
    Exit;
    End;
  SetLength(R, USize + 18);
  ULen := USize + 18;
  If LzssUncompress(Comp, CSize, @R[1], ULen) <> 0 Then ULen := 0;
  FreeMem(Comp, CSize);
  SetLength(R, ULen);
  P := Pos(#0, R);                    {the text is a C string}
  If P > 0 Then SetLength(R, P - 1);
  If Gloss Then Begin GBlk := N; GTxt := R; End
  Else Begin CBlk := N; CTxt := R; End;
  BlockText := R;
  End;

Procedure StepBibObj.ReadSec(Idx: LongInt; Var R: SecRec);
  Var O: LongInt;
  Begin
  FillChar(R, SizeOf(R), 0);
  If (Idx < 0) Or (Idx >= SecLevels + SecGloss) Then Exit;
  O := SecStart + Idx * SecEntry;
  If O + 29 > SecSize Then Exit;
  R.Parent := GetS32(SecData, O);
  R.Prev := GetS32(SecData, O + 4);
  R.Next := GetS32(SecData, O + 8);
  R.Block := GetS32(SecData, O + 12);
  R.StartLevel := GetS16(SecData, O + 16);
  R.Level := (PByte(SecData) + O + 18)^;
  R.NameOfs := GetS32(SecData, O + 19);
  End;

Function StepBibObj.SecName(Ofs: LongInt): BibStr;
  Var
    N: Word;
    R: BibStr;
  Begin
  SecName := '';
  If (Ofs < 0) Or (Ofs + 2 > SecSize) Then Exit;
  N := GetU16(SecData, Ofs);
  If Ofs + 2 + N > SecSize Then Exit;
  SetLength(R, N);
  If N > 0 Then Move((PByte(SecData) + Ofs + 2)^, R[1], N);
  SecName := R;
  End;

{ The RTF of one section entry: the part of its block from \stepstartlevelN up to the next
  \stepstartlevel marker (the whole block for entries without a start level) }
Function StepBibObj.SecText(Idx: LongInt; Gloss: Boolean): BibStr;
  Const Mark = '\stepstartlevel';
  Var
    R: SecRec;
    T, Tok: BibStr;
    P, E, L: LongInt;
  Begin
  SecText := '';
  ReadSec(Idx, R);
  If R.Level = 0 Then Gloss := True;
  T := BlockText(R.Block, Gloss);
  If T = '' Then Exit;
  Str(R.StartLevel, Tok);
  Tok := Mark + Tok;
  L := Length(Tok);
  P := Pos(Tok, T);
  While (P > 0) And (P + L <= Length(T)) And (T[P + L] In ['0'..'9']) Do
    Begin
    E := Pos(Tok, Copy(T, P + 1, Length(T)));         {a longer number that starts the same way}
    If E = 0 Then Begin P := 0; Break; End;
    P := P + E;
    End;
  If P = 0 Then
    Begin
    If R.StartLevel <= 0 Then SecText := T;       {no marker: footnote blocks hold one entry each}
    Exit;
    End;
  Inc(P, L);
  E := Pos(Mark, Copy(T, P, Length(T)));
  If E = 0 Then SecText := Copy(T, P, Length(T))
  Else SecText := Copy(T, P, E - 1);
  End;

(* A footnote entry reads: steplink, a link back to the verse (steplinkto4), then the body.
   The body is what follows that link. *)
Function StepBibObj.GlossBody(Idx: LongInt): BibStr;
  Var
    T: BibStr;
    P, E: LongInt;
  Begin
  T := SecText(Idx, True);
  GlossBody := T;
  P := Pos('\steplink', T);
  If P = 0 Then Exit;
  E := Pos('{\*\steplinkto', Copy(T, P, Length(T)));
  If E = 0 Then Exit;
  P := P + E - 1;
  E := Pos('}', Copy(T, P, Length(T)));
  If E = 0 Then Exit;
  GlossBody := Copy(T, P + E, Length(T));
  End;

(* Replace every footnote link (from steplink to the steplinkto1 group) by the footnote it points
   to, written as a stepnote group.  Strip: just remove the links. *)
Function StepBibObj.ExpandLinks(Const S: BibStr; Strip: Boolean): BibStr;
  Var
    R, Rest, Num, Body: BibStr;
    P, Q, E, Typ, Code: LongInt;
    N: LongInt;
    NextCh: Char;
  Begin
  If Pos('\steplink', S) = 0 Then
    Begin
    ExpandLinks := S;
    Exit;
    End;
  R := '';
  Rest := S;
  Repeat
    P := Pos('\steplink', Rest);
    If P > 0 Then
      Begin
      NextCh := #0;
      If P + 9 <= Length(Rest) Then NextCh := Rest[P + 9];
      If NextCh In ['a'..'z', 'A'..'Z'] Then       {\steplinkto..., not a link start}
        Begin
        R := R + Copy(Rest, 1, P + 8);
        Rest := Copy(Rest, P + 9, Length(Rest));
        Continue;
        End;
      Q := Pos('{\*\steplinkto', Copy(Rest, P, Length(Rest)));
      If Q = 0 Then
        Begin
        R := R + Rest;
        Rest := '';
        Break;
        End;
      Q := P + Q - 1;
      E := Pos('}', Copy(Rest, Q, Length(Rest)));
      If E = 0 Then
        Begin
        R := R + Rest;
        Rest := '';
        Break;
        End;
      E := Q + E - 1;
      { the group holds the link type digit and the target }
      Num := Copy(Rest, Q + 14, E - Q - 14);
      Typ := 0;
      If (Num <> '') And (Num[1] In ['0'..'9']) Then Typ := Ord(Num[1]) - Ord('0');
      Num := Trim(Copy(Num, 2, Length(Num)));
      R := R + Copy(Rest, 1, P - 1);
      If Typ = 1 Then
        Begin
        { a footnote marker: the text between the link start and the target is a hidden glyph }
        If Not Strip Then
          Begin
          Val(Num, N, Code);
          If (Code = 0) And (N >= SecLevels) And (N < SecLevels + SecGloss) Then
            Begin
            Body := ExpandLinks(GlossBody(N), True);
            R := R + '{\*\stepnote ' + Body + '}';
            End;
          End;
        End
      Else
        { a link to a passage: its anchor text is real text and stays, only the link goes }
        R := R + Copy(Rest, P + 9, Q - P - 9);
      Rest := Copy(Rest, E + 1, Length(Rest));
      End
    Else
      Begin
      R := R + Rest;
      Rest := '';
      End;
  Until Rest = '';
  ExpandLinks := R;
  End;


Function StepBibObj.GetControlWord(Key: String): BibStr;
  Var
    P, Depth, E: LongInt;
    Tok: BibStr;
  Begin
  GetControlWord := '';
  Tok := '{\' + Key + ':';
  P := Pos(Tok, Header);
  If P = 0 Then Exit;
  Inc(P, Length(Tok));
  E := P;
  Depth := 1;
  While (E <= Length(Header)) And (Depth > 0) Do
    Begin
    If Header[E] = '{' Then Inc(Depth)
    Else If Header[E] = '}' Then Dec(Depth);
    Inc(E);
    End;
  GetControlWord := Latin1ToUtf8(Trim(Copy(Header, P, E - P - 1)));     {the header is Windows-1252, the verses UTF-8}
  End;

Function StepBibObj.SetVersification(Name: String): Boolean;
  Begin
  SetVersification := AbsBibObj.SetVersification(Name) And (VSys = vsKJV);
  VSys := vsKJV;
  End;


{ The tables built after the indexes are loaded: verse -> section entry, headings -> next verse,
  book titles }
Function StepBibObj.BuildMaps: Boolean;
  Var
    VS: Pointer;
    VSz: LongInt;
    O, B, C, V, BOfs, Cnt, K, L, SB, EB: LongInt;
    Idx: LongInt;
    R: SecRec;
    Pending, PendLast, I, BNo: LongInt;
    NameS: BibStr;
    VSyncHdr, EntSz, BEnt: LongInt;
    SzRec: Word;
  Begin
  BuildMaps := False;
  If Not LoadAll('Vsync.idx', VS, VSz) Then Exit;
  SzRec := GetU16(VS, 0);                          {version record}
  O := SzRec;
  VSyncHdr := GetU16(VS, O);
  SB := GetS16(VS, O + 2);
  EB := GetS16(VS, O + 4);
  BEnt := GetU16(VS, O + 6);
  EntSz := GetU16(VS, O + 8);
  O := O + VSyncHdr;                               {the per book table}
  GetMem(VerseSec, (BibTotalVerses + 1) * SizeOf(LongInt));
  FillChar(VerseSec^, (BibTotalVerses + 1) * SizeOf(LongInt), 0);
  Skipped := 0;
  For B := SB To EB Do
    Begin
    BOfs := GetS32(VS, O + (B - SB) * BEnt);
    Cnt := GetU16(VS, O + (B - SB) * BEnt + 4);
    For K := 0 To Cnt - 1 Do
      Begin
      C := GetS16(VS, BOfs + K * EntSz);
      V := GetS16(VS, BOfs + K * EntSz + 2);
      Idx := GetS32(VS, BOfs + K * EntSz + 4);
      L := 0;
      If (B >= 1) And (B <= BibBooks) And (V >= 1) Then L := VrsLinear(vsKJV, B, C, V);
      If (L > 0) And (Idx >= 0) And (Idx < SecLevels) Then VerseSec^[L] := Idx + 1
      Else Inc(Skipped);
      End;
    End;
  FreeMem(VS, VSz);

  { walk the section tree in order: headings (level 2 with a start level) belong to the verse that
    follows them; level 1 entries are the book titles }
  GetMem(HeadFirst, (SecLevels + 1) * SizeOf(LongInt));
  GetMem(HeadNext, (SecLevels + 1) * SizeOf(LongInt));
  FillChar(HeadFirst^, (SecLevels + 1) * SizeOf(LongInt), 0);
  FillChar(HeadNext^, (SecLevels + 1) * SizeOf(LongInt), 0);
  FillChar(BookTitle, SizeOf(BookTitle), 0);
  Pending := 0; PendLast := 0;
  For I := 0 To SecLevels - 1 Do
    Begin
    ReadSec(I, R);
    If R.Level = 3 Then
      Begin
      If Pending > 0 Then
        Begin
        HeadFirst^[I] := Pending;
        Pending := 0; PendLast := 0;
        End;
      End
    Else If (R.Level = 2) And (R.StartLevel > 0) Then
      Begin
      If Pending = 0 Then Pending := I + 1 Else HeadNext^[PendLast - 1] := I + 1;
      PendLast := I + 1;
      End
    Else
      Begin
      Pending := 0; PendLast := 0;
      If R.Level = 1 Then
        Begin
        NameS := SecName(R.NameOfs);
        BNo := FindBook(NameS);
        If (BNo >= 1) And (BNo <= BibBooks) And (BookTitle[BNo] = 0) Then BookTitle[BNo] := I + 1;
        End;
      End;
    End;
  BuildMaps := True;
  End;


Function StepBibObj.OpenBible: Word;
  Var
    N: String;
    SaveMode: Byte;
    HdrSize, O, L: LongInt;
    Buf: Pointer;
    Ver: Word;
    Fs: LongInt;
    Txt: BibStr;
    P, Q: LongInt;
    LCID: LongInt;
    Code: LongInt;
  Begin
  If Opened Then CloseBible;
  If PathSpec = '' Then
    Begin
    OpenBible := bibErrNoPath;
    Exit;
    End;
  If (Not DirectoryExists(PathSpec)) Or (FindFileCI('Book.dat') = '') Then
    Begin
    OpenBible := bibErrNotFound;
    Exit;
    End;
  { Book.dat: version record, then the control word area }
  N := FindFileCI('Book.dat');
  SaveMode := FileMode;
  FileMode := 0;
  Assign(BookFile, N);
  Reset(BookFile, 1);
  FileMode := SaveMode;
  If IOResult <> 0 Then
    Begin
    OpenBible := bibErrIO;
    Exit;
    End;
  GetMem(Buf, 64);
  BlockRead(BookFile, Buf^, 18, Fs);
  If Fs < 18 Then
    Begin
    FreeMem(Buf, 64);
    Close(BookFile);
    OpenBible := bibErrBadConf;
    Exit;
    End;
  Ver := GetU16(Buf, 0);                              {version record size}
  EncType := (PByte(Buf) + 12)^;
  FreeMem(Buf, 64);
  If EncType <> 0 Then
    Begin
    Close(BookFile);
    OpenBible := bibErrUnsupported;                   {encrypted: needs the publisher's key}
    Exit;
    End;
  Seek(BookFile, Ver);
  GetMem(Buf, 4);
  BlockRead(BookFile, Buf^, 4, Fs);
  HdrSize := GetS32(Buf, 0);
  FreeMem(Buf, 4);
  If (Fs < 4) Or (HdrSize < 0) Or (HdrSize > 1024 * 1024) Then
    Begin
    Close(BookFile);
    OpenBible := bibErrBadConf;
    Exit;
    End;
  SetLength(Header, HdrSize);
  If HdrSize > 0 Then BlockRead(BookFile, Header[1], HdrSize);
  { Viewable.idx }
  If Not LoadAll('Viewable.idx', ViewData, ViewSize) Then
    Begin
    Close(BookFile);
    OpenBible := bibErrNotFound;
    Exit;
    End;
  O := GetU16(ViewData, 0);                           {version record}
  ViewCount := GetS32(ViewData, O + 2);               {blocks, gloss blocks included}
  If (PByte(ViewData) + O + 10)^ <> 1 Then                {compression type: 1 = LZSS}
    Begin
    FreeAll;
    Close(BookFile);
    OpenBible := bibErrUnsupported;
    Exit;
    End;
  ViewEntry := GetU16(ViewData, O + 12);
  ViewStart := O + GetU16(ViewData, O);
  { Sections.idx }
  If Not LoadAll('Sections.idx', SecData, SecSize) Then
    Begin
    FreeAll;
    Close(BookFile);
    OpenBible := bibErrNotFound;
    Exit;
    End;
  O := GetU16(SecData, 0);
  SecLevels := GetS32(SecData, O + 2);
  SecGloss := GetS32(SecData, O + 6);
  SecEntry := GetU16(SecData, O + 10);
  SecStart := O + GetU16(SecData, O);
  If (SecEntry < 29) Or (ViewEntry < 12) Then
    Begin
    FreeAll;
    Close(BookFile);
    OpenBible := bibErrBadConf;
    Exit;
    End;
  If Not BuildMaps Then
    Begin
    FreeAll;
    Close(BookFile);
    OpenBible := bibErrNotFound;
    Exit;
    End;
  { language: the first \steplang code (Windows locale id) }
  Lang := '';
  For L := 1 To BibTotalVerses Do
    If VerseSec^[L] > 0 Then
      Begin
      Txt := SecText(VerseSec^[L] - 1, False);
      P := Pos('\steplang', Txt);
      If P > 0 Then
        Begin
        Q := P + 9;
        While (Q <= Length(Txt)) And (Txt[Q] In ['0'..'9']) Do Inc(Q);
        Val(Copy(Txt, P + 9, Q - P - 9), LCID, Code);
        Case LCID And $3FF Of
          9: Lang := 'en';
          12: Lang := 'fr';
          7: Lang := 'de';
          10: Lang := 'es';
          16: Lang := 'it';
          19: Lang := 'nl';
          25: Lang := 'ru';
          8: Lang := 'el';
          13: Lang := 'he';
          22: Lang := 'pt';
          29: Lang := 'sv';
          Else Lang := '';
          End;
        End;
      Break;
      End;
  VSys := vsKJV;
  UseApoc := False;
  Opened := True;
  SeekFirst;
  OpenBible := bibOk;
  End;

Function StepBibObj.CloseBible: Word;
  Begin
  If Opened Then Close(BookFile);
  FreeAll;
  Opened := False;
  CloseBible := bibOk;
  End;

Function StepBibObj.GetName: String;
  Var S: BibStr;
  Begin
  S := GetControlWord('Translation');
  If S = '' Then S := GetControlWord('Title');
  GetName := S;
  End;

Function StepBibObj.GetDescription: String;
  Begin
  GetDescription := GetControlWord('Title');
  End;

Function StepBibObj.GetAbout: BibStr;
  Var S: BibStr;
  Begin
  S := GetControlWord('Acknowledgments');
  If S = '' Then S := GetControlWord('OtherInfo');
  GetAbout := S;
  End;

Function StepBibObj.GetLang: String;
  Begin
  GetLang := Lang;
  End;

Function StepBibObj.GetVersion: String;
  Begin
  GetVersion := GetControlWord('Edition');
  End;

Function StepBibObj.GetCopyright: String;
  Begin
  GetCopyright := GetControlWord('Copyright');
  End;

Function StepBibObj.GetMarkup: BibMarkup;
  Begin
  GetMarkup := bmSTEP;
  End;

Function StepBibObj.GetSkippedRows: LongInt;
  Begin
  GetSkippedRows := Skipped;
  End;

Function StepBibObj.GetRawVerse: BibStr;
  Var
    L, Sec, H: LongInt;
    Heads: BibStr;
  Begin
  GetRawVerse := '';
  If (Not Opened) Or (Not Found) Then Exit;
  L := VrsLinear(vsKJV, GetBook, GetChapter, GetVerse);
  If L < 1 Then Exit;
  Sec := VerseSec^[L] - 1;
  If Sec < 0 Then Exit;
  Heads := '';
  H := HeadFirst^[Sec];
  While H > 0 Do
    Begin
    Heads := Heads + '{\*\stephead ' + SecText(H - 1, False) + '}';
    H := HeadNext^[H - 1];
    End;
  GetRawVerse := Heads + ExpandLinks(SecText(Sec, False), False);
  End;

Function StepBibObj.GetIntro(Level, Book, Chap: Word): BibStr;
  Begin
  GetIntro := '';
  If (Not Opened) Or (Level <> bilBook) Or (Book < 1) Or (Book > BibBooks) Then Exit;
  { the title block is bold text; as a heading group it becomes a heading in the other markups }
  If BookTitle[Book] > 0 Then GetIntro := '{\*\stephead ' + SecText(BookTitle[Book] - 1, False) + '}';
  End;

End.
