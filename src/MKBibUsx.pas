Unit MKBibUsx;       {USX Bible object (a folder of .usx book files, or a .zip of them)}

{$I MKBib.Def}

{
  MKBibUsx - descendant of MemBibObj for USX (the XML form of USFM used by Paratext and the Digital Bible
  Library), versions 2 and 3: one file per book,

      <usx version="2.0"><book code="GEN" style="id">name</book>
        <chapter number="1" style="c"/>
        <para style="p"><verse number="1" style="v"/>text <char style="wj">..</char></para> ...

  SetBibPath takes a folder of .usx files, one such file, or a .zip of them (unpacked to a temporary folder
  while it is read).  The book is the code of its <book> element.  A verse is the text after <verse number=..>
  up to the next verse or chapter (USX 2), or up to <verse eid=..> (USX 3); it is kept as USX markup (bmUSX:
  char styles w, wj, add, it, bd, notes, refs, and the para styles of USFM).  Paragraphs, poetry lines and
  headings that come between two verses lead the verse that follows them.  Books that are not one of the 66
  are counted, not stored.

  Writing makes the folder <dir>/<Name>_usx with files NN-ABC.usx; Ver = 3 (the default) writes USX 3 with
  verse and chapter start / end milestones, Ver = 2 the older form.
}

Interface

Uses MKBibMod, MKBibAbs, MKBibVrs, MKBibMem, MKBibUfx;

Type
  UsxBibObj = Object(MemBibObj)
  Constructor Init;
  Function  LoadSource: Boolean; Virtual;
  Function  BuildOutput: Word; Virtual;
  Function  LoadFile(Const Path: String): Boolean;
  Function  LoadFolder(Const Dir: String): Boolean;

  Public
  Ver: Word;                 {2 or 3: the version written}
  End;

Type UsxBibPtr = ^UsxBibObj;

Implementation

Uses SysUtils, StrUtils, MKBibMkp, MKBibZip;

Constructor UsxBibObj.Init;
  Begin
  MemBibObj.Init;
  FileMarkup := bmUSX;
  MetaMarkup := bmUSX;
  OutExt := '_usx';
  OutIsDir := True;
  Ver := 3;
  End;

{ paragraph styles whose text is a heading or a header line, not verse text }
Function SkipStyle(Const S: String): Boolean;
  Var L: String;
  Begin
  L := LowerCase(S);
  SkipStyle := (L <> 'd') And ((Copy(L, 1, 1) = 's') And (L <> 'sc') Or (Copy(L, 1, 2) = 'ms') Or (L = 'mr') Or (L = 'r') Or
               (L = 'sr') Or (L = 'sp') Or (L = 'qa') Or (Copy(L, 1, 3) = 'toc') Or (Copy(L, 1, 2) = 'mt') Or (L = 'h') Or
               (Copy(L, 1, 1) = 'h') And (Length(L) = 2) Or (L = 'cl') Or (L = 'cd') Or (L = 'cp') Or (L = 'rem') Or
               (Copy(L, 1, 1) = 'i') And (L <> 'it') And (L <> 'ior') And (L <> 'iex'));
  End;

{ Where the part of a verse region that belongs to the next verse begins: the markup after the last text of
  the verse, from the first paragraph tag on (closing tags of char and note stay with the verse).  The text of
  heading and header paragraphs does not count as verse text. }
Function TailStart(Const R: BibStr): LongInt;
  Var
    i, j, Last, CutFrom: LongInt;
    Q: Char;
    Tag, Nm, Sty: BibStr;
    InSkip: Boolean;
    TextEnd: LongInt;
    Closing: Boolean;
  Begin
  TextEnd := 0;
  InSkip := False;
  i := 1;
  While i <= Length(R) Do
    Begin
    If R[i] = '<' Then
      Begin
      j := i + 1;
      Q := #0;
      While j <= Length(R) Do
        Begin
        If Q <> #0 Then
          Begin If R[j] = Q Then Q := #0; End
        Else If (R[j] = '"') Or (R[j] = '''') Then Q := R[j]
        Else If R[j] = '>' Then Break;
        Inc(j);
        End;
      Tag := Copy(R, i + 1, j - i - 1);
      Closing := (Tag <> '') And (Tag[1] = '/');
      Nm := Tag;
      If Closing Then Delete(Nm, 1, 1);
      Last := Pos(' ', Nm);
      If Last > 0 Then Nm := Copy(Nm, 1, Last - 1);
      If Nm <> '' Then If Nm[Length(Nm)] = '/' Then Delete(Nm, Length(Nm), 1);
      If Nm = 'para' Then
        Begin
        If Closing Then InSkip := False
        Else
          Begin
          Sty := XmlAttrOf(Tag, 'style');
          { a psalm title (d) before the next verse is not text of the verse above it either }
          InSkip := (SkipStyle(Sty) Or (LowerCase(Sty) = 'd')) And (Tag[Length(Tag)] <> '/');
          End;
        End;
      i := j + 1;
      End
    Else
      Begin
      j := i;
      While (j <= Length(R)) And (R[j] <> '<') Do Inc(j);
      If (Not InSkip) And (Trim(Copy(R, i, j - i)) <> '') Then TextEnd := j - 1;
      i := j;
      End;
    End;
  If TextEnd = 0 Then
    Begin
    TailStart := 1;                         {no verse text at all: everything leads the next verse}
    Exit;
    End;
  { after the last text: keep the closing char / note tags with the verse }
  CutFrom := TextEnd + 1;
  While CutFrom <= Length(R) Do
    Begin
    If Copy(R, CutFrom, 7) = '</char>' Then Inc(CutFrom, 7)
    Else If Copy(R, CutFrom, 7) = '</note>' Then Inc(CutFrom, 7)
    Else If Copy(R, CutFrom, 6) = '</ref>' Then Inc(CutFrom, 6)
    Else Break;
    End;
  TailStart := CutFrom;
  End;

Function UsxBibObj.LoadFile(Const Path: String): Boolean;
  Var
    T, Tag, VStr, Carry, Lead, Desc: BibStr;
    P, E, A, Bk, Ch, VNum, Code, N, GapFrom, VStart, NextCh, NextV: LongInt;
    InVerse: Boolean;

  Procedure Finish(EndAt: LongInt; Split: Boolean);
    { the open verse's text is T[VStart .. EndAt - 1]; Split: what trails the last text goes to the next verse }
    Var
      Reg: BibStr;
      CutAt: LongInt;
    Begin
    If Not InVerse Then Exit;
    Reg := Copy(T, VStart, EndAt - VStart);
    If Split Then
      Begin
      CutAt := TailStart(Reg);
      Carry := Copy(Reg, CutAt, Length(Reg));
      Reg := Copy(Reg, 1, CutAt - 1);
      End
    Else Carry := '';
    Reg := Lead + Reg;
    If (Bk > 0) And (Ch > 0) And (VNum > 0) Then StoreVerse(Bk, Ch, VNum, Reg) Else Inc(Skipped);
    InVerse := False;
    Lead := '';
    End;

  Begin
  LoadFile := False;
  If Not ReadWholeFile(Path, T) Then Exit;
  P := Pos('<book ', T);
  If P = 0 Then Exit;
  E := PosEx('>', T, P);
  Tag := Copy(T, P, E - P + 1);
  Bk := UsfmBookNumber(XmlAttrOf(Tag, 'code'));
  If (IDesc = '') And (Bk > 0) Then
    Begin
    Desc := XmlFirst(Copy(T, P, 2000), 'book');
    If Desc <> '' Then SetInfo('', Desc, '', '', '', '');
    End;
  Ch := 0; VNum := 0; InVerse := False; Carry := ''; Lead := ''; GapFrom := 0;
  P := E + 1;
  While True Do
    Begin
    NextCh := PosEx('<chapter ', T, P);
    NextV := PosEx('<verse ', T, P);
    If (NextCh = 0) And (NextV = 0) Then Break;
    If (NextCh > 0) And ((NextV = 0) Or (NextCh < NextV)) Then A := NextCh Else A := NextV;
    E := PosEx('>', T, A);
    If E = 0 Then Break;
    Tag := Copy(T, A, E - A + 1);
    If A = NextCh Then
      Begin
      If XmlAttrOf(Tag, 'eid') = '' Then
        Begin
        Finish(A, True);                      {a chapter start: USX 2 ends the last verse here}
        VStr := XmlAttrOf(Tag, 'number');
        Val(VStr, Ch, Code);
        If Code <> 0 Then Ch := 0;
        Carry := '';
        End
      Else Finish(A, False);
      GapFrom := E + 1;
      End
    Else If XmlAttrOf(Tag, 'eid') <> '' Then
      Begin
      Finish(A, False);                       {USX 3: the verse ends exactly here}
      GapFrom := E + 1;
      End
    Else
      Begin
      Finish(A, True);                        {a verse starts; in USX 2 that ends the one before}
      VStr := XmlAttrOf(Tag, 'number');
      N := 1;
      While (N <= Length(VStr)) And (VStr[N] In ['0'..'9']) Do Inc(N);
      If N = 1 Then VNum := 0 Else Val(Copy(VStr, 1, N - 1), VNum, Code);
      Lead := Carry;
      If (GapFrom > 0) And (GapFrom < A) Then Lead := Lead + Copy(T, GapFrom, A - GapFrom);
      Carry := '';
      VStart := E + 1;
      InVerse := True;
      GapFrom := 0;
      End;
    P := E + 1;
    End;
  Finish(Length(T) + 1, False);
  LoadFile := True;
  End;

Function UsxBibObj.LoadFolder(Const Dir: String): Boolean;
  Var
    SR: TSearchRec;
    D, Ext: String;
    Names: Array Of String;
    N, i, j: LongInt;
    Tmp: String;
  Begin
  LoadFolder := False;
  D := IncludeTrailingPathDelimiter(Dir);
  N := 0;
  SetLength(Names, 0);
  If FindFirst(D + '*', faAnyFile, SR) = 0 Then
    Begin
    Repeat
      Ext := LowerCase(ExtractFileExt(SR.Name));
      If ((SR.Attr And faDirectory) = 0) And (Ext = '.usx') Then
        Begin
        SetLength(Names, N + 1);
        Names[N] := SR.Name;
        Inc(N);
        End;
    Until FindNext(SR) <> 0;
    FindClose(SR);
    End;
  If N = 0 Then Exit;
  For i := 0 To N - 2 Do
    For j := i + 1 To N - 1 Do
      If Names[j] < Names[i] Then Begin Tmp := Names[i]; Names[i] := Names[j]; Names[j] := Tmp; End;
  For i := 0 To N - 1 Do LoadFile(D + Names[i]);
  LoadFolder := True;
  End;

Function UsxBibObj.LoadSource: Boolean;
  Var
    Tmp: String;
    Ok: Boolean;
  Begin
  LoadSource := False;
  If DirectoryExists(PathSpec) Then LoadSource := LoadFolder(PathSpec)
  Else If LowerCase(ExtractFileExt(PathSpec)) = '.zip' Then
    Begin
    Tmp := GetTempDir + 'mkbible-usx-' + IntToStr(GetProcessID) + '/';
    Ok := UnzipTo(PathSpec, Tmp) And LoadFolder(Tmp);
    RemoveTree(Tmp);
    LoadSource := Ok;
    End
  Else LoadSource := LoadFile(PathSpec);
  End;

{ the paragraph, poetry and heading blocks a translated verse starts with belong before its verse marker }
Function LeadingBlocks(Var Frag: BibStr): BibStr;
  Const
    ParaP = '</para><para style="p">';
    ParaQ = '</para><para style="q1">';
    HeadS = '</para><para style="s1">';
  Var
    R: BibStr;
    E: LongInt;
    Again: Boolean;
  Begin
  R := '';
  Repeat
    Again := False;
    If Copy(Frag, 1, Length(ParaP)) = ParaP Then
      Begin R := R + ParaP; Delete(Frag, 1, Length(ParaP)); Again := True; End
    Else If Copy(Frag, 1, Length(ParaQ)) = ParaQ Then
      Begin R := R + ParaQ; Delete(Frag, 1, Length(ParaQ)); Again := True; End
    Else If Copy(Frag, 1, Length(HeadS)) = HeadS Then
      Begin
      E := Pos(ParaP, Frag);
      If E > 0 Then
        Begin
        R := R + Copy(Frag, 1, E + Length(ParaP) - 1);
        Delete(Frag, 1, E + Length(ParaP) - 1);
        Again := True;
        End;
      End;
  Until Not Again;
  LeadingBlocks := R;
  End;

{ USX 2's schema has no strong= / x-morph= on <char>; they are written for USX 3 only }
Function DropWordAttrs(Const S: BibStr): BibStr;
  Var
    R: BibStr;
    P, E: LongInt;
    Keys: Array[1..2] Of String;
    k: Integer;
  Begin
  R := S;
  Keys[1] := ' strong="';
  Keys[2] := ' x-morph="';
  For k := 1 To 2 Do
    Repeat
      P := Pos(Keys[k], R);
      If P = 0 Then Break;
      E := P + Length(Keys[k]);
      While (E <= Length(R)) And (R[E] <> '"') Do Inc(E);
      Delete(R, P, E - P + 1);
    Until False;
  DropWordAttrs := R;
  End;

Function UsxBibObj.BuildOutput: Word;
  Var
    Dir, O, Nm, Desc, FName, Id, Frag, Lead: BibStr;
    B, C, V: Word;
    L: LongInt;
    Any: Boolean;
    Num: Word;
  Begin
  BuildOutput := bibOk;
  If Not ForceDirectories(FileName) Then
    Begin
    BuildOutput := bibErrIO;
    Exit;
    End;
  Dir := IncludeTrailingPathDelimiter(FileName);
  Desc := GetDescription;
  If Desc = '' Then Desc := MetaName;
  For B := 1 To BibBooks Do
    Begin
    Any := False;
    For C := 1 To VrsChapters(vsKJV, B) Do
      For V := 1 To VrsVerses(vsKJV, B, C) Do
        If Lines^[VrsLinear(vsKJV, B, C, V)] <> '' Then Any := True;
    If Not Any Then Continue;
    Nm := BookInfo[B].Name;
    Id := UsfmBookIds[B];
    O := '<?xml version="1.0" encoding="utf-8"?>'#10;
    If Ver >= 3 Then O := O + '<usx version="3.0">'#10 Else O := O + '<usx version="2.0">'#10;
    O := O + '  <book code="' + Id + '" style="id">' + XmlEsc(Desc) + '</book>'#10 +
         '  <para style="h">' + XmlEsc(Nm) + '</para>'#10 +
         '  <para style="toc1">' + XmlEsc(Nm) + '</para>'#10 +
         '  <para style="mt1">' + XmlEsc(Nm) + '</para>'#10;
    For C := 1 To VrsChapters(vsKJV, B) Do
      Begin
      If Ver >= 3 Then O := O + '  <chapter number="' + IntToStr(C) + '" style="c" sid="' + Id + ' ' + IntToStr(C) + '"/>'#10
      Else O := O + '  <chapter number="' + IntToStr(C) + '" style="c"/>'#10;
      O := O + '  <para style="p">';
      For V := 1 To VrsVerses(vsKJV, B, C) Do
        Begin
        L := VrsLinear(vsKJV, B, C, V);
        If Lines^[L] = '' Then Continue;
        Frag := MkpTranslate(Lines^[L], mfUSX, mfUSX);
        If Ver < 3 Then Frag := DropWordAttrs(Frag);
        Lead := LeadingBlocks(Frag);
        If Ver >= 3 Then
          O := O + Lead + '<verse number="' + IntToStr(V) + '" style="v" sid="' + Id + ' ' + IntToStr(C) + ':' + IntToStr(V) + '"/>' +
               Frag + '<verse eid="' + Id + ' ' + IntToStr(C) + ':' + IntToStr(V) + '"/>'
        Else
          O := O + Lead + '<verse number="' + IntToStr(V) + '" style="v"/>' + Frag + ' ';
        End;
      O := O + '</para>'#10;
      If Ver >= 3 Then O := O + '  <chapter eid="' + Id + ' ' + IntToStr(C) + '"/>'#10;
      End;
    O := O + '</usx>'#10;
    If B <= BibOTBooks Then Num := B Else Num := B + 1;
    FName := Dir + Copy('0' + IntToStr(Num), Length(IntToStr(Num)), 2) + '-' + Id + '.usx';
    If Not WriteWholeFile(FName, O) Then BuildOutput := bibErrIO;
    End;
  End;

End.
