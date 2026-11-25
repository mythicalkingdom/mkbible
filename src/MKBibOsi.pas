Unit MKBibOsi;       {OSIS XML Bible object (.osis.xml)}

{$I MKBib.Def}

{
  MKBibOsi - descendant of MemBibObj for OSIS XML Bible files, such as the public domain texts of
  the open-bibles collection.  Verses are found as

      <verse osisID="Gen.1.1" sID="Gen.1.1.seID.2"/> text <verse eID="Gen.1.1.seID.2"/>      (milestones)
      <verse osisID="Gen.1.1">text</verse>                                                     (container)

  and the text between the tags (reported as bmOSIS, so w / note / hi / transChange / q / l ... are all
  kept) is the verse.  Markup between two verses (<p>, <lg>, <l>, <title>) is carried at the front of
  the verse that follows, back to the last chapter start, so paragraphs, poetry lines and headings
  survive.  A verse with several ids (a range) is stored at its first.  Apocrypha and the like (books
  that are not one of the 66) are counted, not stored.

  Module information: the <work> element of the header (title, identifier, language, rights,
  description).  Writing makes <dir>/<Name>.osis.xml with container verses, in UTF-8.
}

Interface

Uses MKBibMod, MKBibAbs, MKBibVrs, MKBibMem;

Type
  OsisBibObj = Object(MemBibObj)
  Constructor Init;
  Function  LoadSource: Boolean; Virtual;
  Function  BuildOutput: Word; Virtual;
  End;

Type OsisBibPtr = ^OsisBibObj;

Implementation

Uses SysUtils, StrUtils, MKBibMkp;

Constructor OsisBibObj.Init;
  Begin
  MemBibObj.Init;
  FileMarkup := bmOSIS;
  MetaMarkup := bmOSIS;
  OutExt := '.osis.xml';
  OutIsDir := False;
  End;

{ the text of the gap from the last chapter start on }
Function GapAfterChapter(Const Gap: BibStr): BibStr;
  Var
    L: BibStr;
    P, Q, Best: LongInt;
  Begin
  L := LowerCase(Gap);
  Best := 0;
  P := 0;
  Repeat
    Q := PosEx('<chapter', L, P + 1);
    If Q = 0 Then Break;
    P := Q;
    Best := Q;
  Until False;
  If Best > 0 Then
    Begin
    Q := PosEx('>', Gap, Best);
    If Q > 0 Then GapAfterChapter := Copy(Gap, Q + 1, Length(Gap)) Else GapAfterChapter := '';
    End
  Else GapAfterChapter := Gap;
  End;

Function OsisBookNumber(Const Id: BibStr; Obj: MemBibPtr): Word;
  Begin
  OsisBookNumber := Obj^.BookOfName(Id);
  End;

Function OsisBibObj.LoadSource: Boolean;
  Var
    T, L, Tag, Id, SId, Txt, Gap, First, Wk: BibStr;
    P, E, Q, GapFrom, N, Code, Bk: LongInt;
    Ch, Vs: LongInt;
    Parts: Array[1..3] Of BibStr;
    i, Np, Dot, Sp: LongInt;
  Begin
  LoadSource := False;
  If Not ReadWholeFile(PathSpec, T) Then Exit;
  L := LowerCase(T);
  If Pos('<osis', L) = 0 Then Exit;
  P := Pos('<work', L);
  If P > 0 Then
    Begin
    E := PosEx('</work>', L, P);
    If E = 0 Then E := Length(T);
    Wk := Copy(T, P, E - P);
    Q := PosEx('>', Wk, 1);
    Id := XmlAttrOf(Copy(Wk, 1, Q), 'osisWork');
    SetInfo(Id, XmlFirst(Wk, 'title'), XmlFirst(Wk, 'language'), XmlFirst(Wk, 'rights'), XmlFirst(Wk, 'description'),
            XmlFirst(Wk, 'date'));
    End;
  P := 1;
  GapFrom := 1;
  While True Do
    Begin
    P := PosEx('<verse ', L, P);
    If P = 0 Then Break;
    E := PosEx('>', T, P);
    If E = 0 Then Break;
    Tag := Copy(T, P, E - P + 1);
    If XmlAttrOf(Tag, 'eID') <> '' Then
      Begin
      GapFrom := E + 1;
      P := E;
      Continue;
      End;
    Id := XmlAttrOf(Tag, 'osisID');
    If Id = '' Then Id := XmlAttrOf(Tag, 'osisRef');
    SId := XmlAttrOf(Tag, 'sID');
    Gap := GapAfterChapter(Copy(T, GapFrom, P - GapFrom));
    { the first of several ids; Book.Chapter.Verse }
    First := Id;
    Sp := Pos(' ', First);
    If Sp > 0 Then First := Copy(First, 1, Sp - 1);
    Dot := Pos('-', First);
    If Dot > 0 Then First := Copy(First, 1, Dot - 1);
    Np := 0;
    For i := 1 To 3 Do Parts[i] := '';
    While (First <> '') And (Np < 3) Do
      Begin
      Inc(Np);
      Dot := Pos('.', First);
      If Dot = 0 Then
        Begin
        Parts[Np] := First;
        First := '';
        End
      Else
        Begin
        Parts[Np] := Copy(First, 1, Dot - 1);
        First := Copy(First, Dot + 1, Length(First));
        End;
      End;
    If Np = 3 Then Bk := OsisBookNumber(Parts[1], @Self) Else Bk := 0;
    Val(Parts[2], Ch, Code);
    If Code <> 0 Then Ch := 0;
    Val(Parts[3], Vs, Code);
    If Code <> 0 Then Vs := 0;
    If T[E - 1] = '/' Then
      Begin
      If SId <> '' Then
        Begin
        { milestone: the verse runs to the matching end milestone }
        Q := PosEx('eID="' + SId + '"', T, E);
        If Q = 0 Then Q := PosEx('eID=''' + SId + '''', T, E);
        If Q = 0 Then Q := Length(T)
        Else
          Begin
          While (Q > 1) And (T[Q] <> '<') Do Dec(Q);       {back to the < of <verse eID=...}
          End;
        Txt := Copy(T, E + 1, Q - E - 1);
        Q := PosEx('>', T, Q);
        If Q = 0 Then Q := Length(T);
        End
      Else
        Begin
        Txt := '';
        Q := E;
        End;
      End
    Else
      Begin
      Q := PosEx('</verse>', L, E);
      If Q = 0 Then Q := Length(T);
      Txt := Copy(T, E + 1, Q - E - 1);
      Q := Q + 7;
      End;
    If Trim(Gap) <> '' Then Txt := Gap + Txt;
    If (Bk > 0) And (Ch > 0) And (Vs > 0) Then StoreVerse(Bk, Ch, Vs, Txt) Else Inc(Skipped);
    GapFrom := Q + 1;
    P := Q;
    End;
  LoadSource := True;
  End;

Function OsisBibObj.BuildOutput: Word;
  Var
    O, Nm, Lang, Id: BibStr;
    B, C, V: Word;
    L: LongInt;
    Any: Boolean;
  Begin
  Nm := MetaName;
  Lang := MetaLang;
  If Lang = '' Then Lang := 'en';
  O := '<?xml version="1.0" encoding="UTF-8"?>'#10 +
       '<osis xmlns="http://www.bibletechnologies.net/2003/OSIS/namespace" ' +
       'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
       'xsi:schemaLocation="http://www.bibletechnologies.net/2003/OSIS/namespace http://www.bibletechnologies.net/osisCore.2.1.1.xsd">'#10 +
       '<osisText osisIDWork="' + XmlEsc(Nm) + '" osisRefWork="Bible" xml:lang="' + XmlEsc(Lang) + '" canonical="true">'#10 +
       '<header>'#10 +
       '  <work osisWork="' + XmlEsc(Nm) + '">'#10 +
       '    <title>' + XmlEsc(GetDescription) + '</title>'#10 +
       '    <date>' + XmlEsc(MetaVer) + '</date>'#10 +
       '    <identifier type="OSIS">Bible.' + XmlEsc(Nm) + '</identifier>'#10 +
       '    <description>' + XmlEsc(MetaAbout) + '</description>'#10 +
       '    <rights>' + XmlEsc(MetaCopy) + '</rights>'#10 +
       '    <language>' + XmlEsc(Lang) + '</language>'#10 +
       '    <refSystem>Bible.KJV</refSystem>'#10 +
       '  </work>'#10 +
       '  <work osisWork="defaultReferenceScheme"><refSystem>Bible.KJV</refSystem></work>'#10 +
       '</header>'#10;
  For B := 1 To BibBooks Do
    Begin
    Any := False;
    For C := 1 To VrsChapters(vsKJV, B) Do
      For V := 1 To VrsVerses(vsKJV, B, C) Do
        If Lines^[VrsLinear(vsKJV, B, C, V)] <> '' Then Any := True;
    If Not Any Then Continue;
    Id := BookInfo[B].OSIS;
    O := O + '<div type="book" osisID="' + Id + '">'#10;
    For C := 1 To VrsChapters(vsKJV, B) Do
      Begin
      O := O + '<chapter osisID="' + Id + '.' + IntToStr(C) + '">'#10;
      For V := 1 To VrsVerses(vsKJV, B, C) Do
        Begin
        L := VrsLinear(vsKJV, B, C, V);
        If Lines^[L] <> '' Then
          O := O + '<verse osisID="' + Id + '.' + IntToStr(C) + '.' + IntToStr(V) + '">' + MkpTranslate(Lines^[L], mfOSIS, mfOSIS) + '</verse>'#10;
        End;
      O := O + '</chapter>'#10;
      End;
    O := O + '</div>'#10;
    End;
  O := O + '</osisText>'#10'</osis>'#10;
  If WriteWholeFile(FileName, O) Then BuildOutput := bibOk Else BuildOutput := bibErrIO;
  End;

End.
