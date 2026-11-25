Unit MKBibCom;       {Abstract Commentary Object (interface only so far)}

{$I MKBib.Def}

{
  MKBibCom - AbsComObj: commentaries.  A commentary is a Bible whose text comes in entries, each
  covering a verse range (a verse, a passage, a whole chapter), possibly with a title.  It descends
  from AbsBibObj so that positioning, reference parsing and GetRawVerse work as for a Bible:
  GetRawVerse gives the first entry that covers the current verse.

  Only the interface exists; a descendant for a format (theWord .cmt.twm, Sword zCom / RawCom, MySword
  .cmt.mybible, STEP commentaries) is still to be written.  An entry is addressed by its number
  1..GetEntryCount in the order the module keeps them.
}

Interface

Uses MKBibMod, MKBibAbs;

Type
  AbsComObj = Object(AbsBibObj)
  Function  GetEntryCount: LongInt; Virtual;
  Procedure GetEntryRange(Idx: LongInt; Var FromRef, ToRef: BibRef); Virtual;
  Function  GetEntryTitle(Idx: LongInt): BibStr; Virtual;
  Function  GetEntryAt(Idx: LongInt): BibStr; Virtual; {text, markup as stored}
  Function  FindEntryForVerse(Book, Chap, Verse: Word; After: LongInt): LongInt; Virtual;
    {the first entry after entry number After that covers the verse, 0 = none (After = 0: from the start)}
  Function  PutEntry(Const FromRef, ToRef: BibRef; Const Title, Txt: BibStr): Boolean; Virtual;
  Function  GetRawVerse: BibStr; Virtual;     {the first entry covering the current verse}
  End;

Type AbsComPtr = ^AbsComObj;

Implementation

Function AbsComObj.GetEntryCount: LongInt;
  Begin
  GetEntryCount := 0;
  End;

Procedure AbsComObj.GetEntryRange(Idx: LongInt; Var FromRef, ToRef: BibRef);
  Begin
  FillChar(FromRef, SizeOf(FromRef), 0);
  FillChar(ToRef, SizeOf(ToRef), 0);
  End;

Function AbsComObj.GetEntryTitle(Idx: LongInt): BibStr;
  Begin
  GetEntryTitle := '';
  End;

Function AbsComObj.GetEntryAt(Idx: LongInt): BibStr;
  Begin
  GetEntryAt := '';
  End;

Function AbsComObj.FindEntryForVerse(Book, Chap, Verse: Word; After: LongInt): LongInt;
  Var
    i: LongInt;
    A, B: BibRef;
    L, LA, LB: LongInt;
  Begin
  FindEntryForVerse := 0;
  L := (LongInt(Book) * 1000 + Chap) * 1000 + Verse;
  For i := After + 1 To GetEntryCount Do
    Begin
    GetEntryRange(i, A, B);
    LA := (LongInt(A.Book) * 1000 + A.Chapter) * 1000 + A.Verse;
    LB := (LongInt(B.Book) * 1000 + B.Chapter) * 1000 + B.Verse;
    If (L >= LA) And (L <= LB) Then
      Begin
      FindEntryForVerse := i;
      Exit;
      End;
    End;
  End;

Function AbsComObj.PutEntry(Const FromRef, ToRef: BibRef; Const Title, Txt: BibStr): Boolean;
  Begin
  PutEntry := False;
  End;

Function AbsComObj.GetRawVerse: BibStr;
  Var I: LongInt;
  Begin
  GetRawVerse := '';
  If Not Found Then Exit;
  I := FindEntryForVerse(CurRef.Book, CurRef.Chapter, CurRef.Verse, 0);
  If I > 0 Then GetRawVerse := GetEntryAt(I);
  End;

End.
