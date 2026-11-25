Unit MKBibUsf;       {USFM Bible object (a folder of .usfm / .sfm book files, or a .zip of them)}

{$I MKBib.Def}

{
  MKBibUsf - descendant of MemBibObj for USFM (Unified Standard Format Markers, the Paratext / eBible.org
  text format): one file per book,

      \id GEN World English Bible (WEB)
      \c 1
      \p
      \v 1 \w In|strong="H7225"\w* the beginning ...

  SetBibPath takes a folder with the book files (*.usfm, *.sfm, any case; the book is the three letter
  code of the \id line), one such file, or a .zip of them (unpacked to a temporary folder while it is
  read).  A verse is the text after \v n up to the next \v or \c (reported as bmUSFM: \w \wj \add \f \x
  and the paragraph, poetry and heading markers).  Paragraph, poetry and heading lines that come before
  a verse (\p \q1 \s1 ...) are carried at the front of that verse; they belong to the previous verse
  only when text continues after them.  Headers (\ide \h \toc \mt ...) and parallel passage
  references (\r) are not kept.  Other books than the 66 (the Apocrypha) are counted, not stored.

  Writing makes the folder <dir>/<Name>_usfm with files NN-ABCName.usfm (ABC = the USFM book code,
  NN = 01..39 and 41..67 as in the USFM book list).
}

Interface

Uses MKBibMod, MKBibAbs, MKBibVrs, MKBibMem, MKBibUfx;

Type
  UsfmBibObj = Object(MemBibObj)
  Constructor Init;
  Function  LoadSource: Boolean; Virtual;
  Function  BuildOutput: Word; Virtual;
  Function  LoadFile(Const Path: String): Boolean;
  Function  LoadFolder(Const Dir: String): Boolean;
  End;

Type UsfmBibPtr = ^UsfmBibObj;

Implementation

Uses SysUtils, MKBibZip;

Constructor UsfmBibObj.Init;
  Begin
  MemBibObj.Init;
  FileMarkup := bmUSFM;
  MetaMarkup := bmUSFM;
  OutExt := '_usfm';
  OutIsDir := True;
  End;

{ the marker at the start of S (after the backslash), and what follows it }
Function SplitMarker(Const S: BibStr; Var Rest: BibStr): String;
  Var k: LongInt;
  Begin
  k := 2;
  While (k <= Length(S)) And (S[k] In ['a'..'z', 'A'..'Z', '0'..'9']) Do Inc(k);
  SplitMarker := LowerCase(Copy(S, 2, k - 2));
  If (k <= Length(S)) And (S[k] = ' ') Then Inc(k);
  Rest := Copy(S, k, Length(S));
  End;

Function MarkerClass(Const M: String): Integer;
  { 1 paragraph, 2 poetry, 3 heading, 4 header or reference line to drop, 0 other }
  Var c1, c2: String;
  Function Digits(From: Integer): Boolean;
    Var i: Integer;
    Begin
    Digits := Length(M) >= From;
    For i := From To Length(M) Do If Not (M[i] In ['0'..'9']) Then Digits := False;
    End;
  Begin
  c1 := Copy(M, 1, 1);
  c2 := Copy(M, 1, 2);
  MarkerClass := 0;
  If (M = 'p') Or (M = 'm') Or (M = 'b') Or (M = 'nb') Or (M = 'mi') Or (M = 'pc') Or (M = 'pr') Or (M = 'cls') Or
     (c2 = 'pi') Or (c2 = 'pm') Then MarkerClass := 1
  Else If (M = 'q') Or (M = 'qr') Or (M = 'qc') Or (M = 'qm') Or ((c1 = 'q') And Digits(2)) Or ((c2 = 'qm') And Digits(3)) Or
          (M = 'lh') Or (M = 'lf') Or (c2 = 'li') Then MarkerClass := 2
  Else If (M = 's') Or ((c1 = 's') And Digits(2)) Or (c2 = 'ms') Or (M = 'd') Or (M = 'sp') Or (M = 'qa') Then MarkerClass := 3
  Else If (M = 'mr') Or (M = 'r') Or (M = 'sr') Or (M = 'id') Or (M = 'ide') Or (c1 = 'h') Or (Copy(M, 1, 3) = 'toc') Or
          (c2 = 'mt') Or (M = 'rem') Or (M = 'cl') Or (M = 'cd') Or (M = 'cp') Or
          ((c1 = 'i') And (M <> 'it') And (M <> 'ior') And (M <> 'iex') And (M <> 'iqt')) Then MarkerClass := 4;
  End;

Function UsfmBibObj.LoadFile(Const Path: String): Boolean;
  Var
    T, Ln, S, Rest, Cur, Pending, Desc, IdRest: BibStr;
    Mk: String;
    P, E, Bk, Ch, VNum, Code, N, Cls: LongInt;
    CurValid, First: Boolean;
    VStr: BibStr;

  Procedure Finish;
    Begin
    If CurValid Then
      Begin
      If (Bk > 0) And (Ch > 0) And (VNum > 0) Then StoreVerse(Bk, Ch, VNum, Trim(Cur)) Else Inc(Skipped);
      End;
    CurValid := False;
    Cur := '';
    End;

  Procedure Line(S: BibStr);
    Var
      Again: Boolean;
    Begin
    Repeat
      Again := False;
      S := TrimLeft(S);
      If S = '' Then Exit;
      If S[1] <> '\' Then
        Begin
        If CurValid Then
          Begin
          If Pending <> '' Then Begin Cur := Cur + #10 + Pending; Pending := ''; End;
          Cur := Cur + ' ' + S;
          End;
        Exit;
        End;
      Mk := SplitMarker(S, Rest);
      If Mk = 'id' Then
        Begin
        Finish;
        IdRest := Rest;
        N := 1;
        While (N <= Length(Rest)) And (Rest[N] <> ' ') Do Inc(N);
        Bk := UsfmBookNumber(Copy(Rest, 1, N - 1));
        If First And (Bk > 0) Then
          Begin
          Desc := Trim(Copy(Rest, N + 1, Length(Rest)));
          First := False;
          End;
        Ch := 0; Pending := '';
        Exit;
        End;
      If Mk = 'c' Then
        Begin
        Finish;
        VStr := Trim(Rest);
        N := 1;
        While (N <= Length(VStr)) And (VStr[N] In ['0'..'9']) Do Inc(N);
        If N = 1 Then Ch := 0 Else Val(Copy(VStr, 1, N - 1), Ch, Code);
        Pending := '';
        Exit;
        End;
      If Mk = 'v' Then
        Begin
        Finish;
        VStr := TrimLeft(Rest);
        N := 1;
        While (N <= Length(VStr)) And (VStr[N] In ['0'..'9']) Do Inc(N);
        If N = 1 Then VNum := 0 Else Val(Copy(VStr, 1, N - 1), VNum, Code);
        { skip a range end and a letter: 2-3, 4a }
        While (N <= Length(VStr)) And (VStr[N] In ['-', '0'..'9', ',']) Do Inc(N);
        If (N <= Length(VStr)) And (VStr[N] In ['a'..'c']) And ((N = Length(VStr)) Or (VStr[N + 1] = ' ')) Then Inc(N);
        VStr := TrimLeft(Copy(VStr, N, Length(VStr)));
        Cur := Pending + VStr;
        Pending := '';
        CurValid := True;
        Exit;
        End;
      Cls := MarkerClass(Mk);
      Case Cls Of
        4: Exit;                                      {headers, parallel references: dropped}
        3: Pending := Pending + '\' + Mk + ' ' + Rest + #10;
        1, 2:
          Begin
          If TrimLeft(Rest) = '' Then Pending := Pending + '\' + Mk + #10
          Else If TrimLeft(Rest)[1] = '\' Then
            Begin
            { "\q1 \v 3 text": the marker belongs to the verse that starts on the same line }
            Pending := Pending + '\' + Mk + #10;
            S := Rest;
            Again := True;
            End
          Else
            Begin
            If CurValid Then
              Begin
              If Pending <> '' Then Begin Cur := Cur + #10 + Pending; Pending := ''; End;
              Cur := Cur + #10'\' + Mk + ' ' + Rest;
              End;
            End;
          End;
        Else
          Begin
          { a character style at the start of a line: more text of this verse }
          If CurValid Then
            Begin
            If Pending <> '' Then Begin Cur := Cur + #10 + Pending; Pending := ''; End;
            Cur := Cur + ' ' + S;
            End;
          End;
      End;
    Until Not Again;
    End;

  Begin
  LoadFile := False;
  If Not ReadWholeFile(Path, T) Then Exit;
  Bk := 0; Ch := 0; VNum := 0; CurValid := False; Cur := ''; Pending := ''; First := True; Desc := '';
  P := 1;
  While P <= Length(T) Do
    Begin
    E := P;
    While (E <= Length(T)) And (T[E] <> #10) Do Inc(E);
    Ln := Copy(T, P, E - P);
    P := E + 1;
    If (Ln <> '') And (Ln[Length(Ln)] = #13) Then SetLength(Ln, Length(Ln) - 1);
    Line(Ln);
    End;
  Finish;
  If (IDesc = '') And (Desc <> '') Then
    Begin
    { "World English Bible (WEB) 2024-01-15": the trailing date is not part of the name }
    If (Length(Desc) > 11) And (Desc[Length(Desc) - 10] = ' ') And (Desc[Length(Desc) - 5] = '-') And (Desc[Length(Desc) - 2] = '-') Then
      Desc := Trim(Copy(Desc, 1, Length(Desc) - 11));
    IDesc := Desc;
    End;
  LoadFile := True;
  End;

Function UsfmBibObj.LoadFolder(Const Dir: String): Boolean;
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
      If ((SR.Attr And faDirectory) = 0) And ((Ext = '.usfm') Or (Ext = '.sfm') Or (Ext = '.ptx')) Then
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

Function UsfmBibObj.LoadSource: Boolean;
  Var
    Tmp: String;
    Ok: Boolean;
  Begin
  LoadSource := False;
  If DirectoryExists(PathSpec) Then LoadSource := LoadFolder(PathSpec)
  Else If LowerCase(ExtractFileExt(PathSpec)) = '.zip' Then
    Begin
    Tmp := GetTempDir + 'mkbible-usfm-' + IntToStr(GetProcessID) + '/';
    Ok := UnzipTo(PathSpec, Tmp) And LoadFolder(Tmp);
    RemoveTree(Tmp);
    LoadSource := Ok;
    End
  Else LoadSource := LoadFile(PathSpec);
  End;

{ marker lines that start a verse's text before its \v : \p, \q1, \s1 Heading }
Function TakeLeading(Var Frag: BibStr): BibStr;
  Var
    R, Rest: BibStr;
    Mk: String;
    E: LongInt;
    Again: Boolean;
  Begin
  R := '';
  Repeat
    Again := False;
    While (Frag <> '') And (Frag[1] In [#10, #13, ' ']) Do Delete(Frag, 1, 1);
    If (Frag <> '') And (Frag[1] = '\') Then
      Begin
      Mk := SplitMarker(Frag, Rest);
      Case MarkerClass(Mk) Of
        1, 2:
          Begin
          R := R + '\' + Mk + #10;
          Delete(Frag, 1, Length(Mk) + 1);
          Again := True;
          End;
        3:
          Begin
          E := Pos(#10, Frag);
          If E = 0 Then E := Length(Frag) + 1;
          R := R + Copy(Frag, 1, E - 1) + #10;
          Delete(Frag, 1, E);
          Again := True;
          End;
      End;
      End;
  Until Not Again;
  TakeLeading := R;
  End;

Function UsfmBibObj.BuildOutput: Word;
  Var
    Dir, O, Nm, Pre, Frag, Desc, FName: BibStr;
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
    O := '\id ' + UsfmBookIds[B] + ' ' + Desc + #10 + '\ide UTF-8'#10 + '\h ' + Nm + #10 + '\toc1 ' + Nm + #10 + '\mt1 ' + Nm + #10;
    For C := 1 To VrsChapters(vsKJV, B) Do
      Begin
      O := O + '\c ' + IntToStr(C) + #10;
      For V := 1 To VrsVerses(vsKJV, B, C) Do
        Begin
        L := VrsLinear(vsKJV, B, C, V);
        If Lines^[L] = '' Then Continue;
        Frag := Lines^[L];
        Pre := TakeLeading(Frag);
        If (V = 1) And (Pre = '') Then Pre := '\p'#10;
        O := O + Pre + '\v ' + IntToStr(V) + ' ' + Frag + #10;
        End;
      End;
    If B <= BibOTBooks Then Num := B Else Num := B + 1;
    FName := Dir + Copy('0' + IntToStr(Num), Length(IntToStr(Num)), 2) + '-' + UsfmBookIds[B] + StringReplace(Nm, ' ', '', [rfReplaceAll]) + '.usfm';
    If Not WriteWholeFile(FName, O) Then BuildOutput := bibErrIO;
    End;
  End;

End.
