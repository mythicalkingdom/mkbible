Unit MKBibUnb;       {Unbound Bible object (tab separated text file from the Biola University Unbound Bible)}

{$I MKBib.Def}

{
  MKBibUnb - descendant of MemBibObj for the Unbound Bible text files (unbound.biola.edu):

      #THE UNBOUND BIBLE (www.unboundbible.org)
      #name <TAB> American Standard Version
      #columns <TAB> orig_book_index <TAB> orig_chapter <TAB> orig_verse <TAB> orig_subverse <TAB> order_by <TAB> text
      01O <TAB> 1 <TAB> 1 <TAB> <TAB> 10 <TAB> In the beginning ...

  The first three columns are book, chapter and verse; the last is the text.  The book index is a number
  with an O / N (Old / New Testament) suffix, which is ignored.  Rows with a sub-verse are added to the
  verse.  The text is plain.  Writing makes <dir>/<Name>.unbound.txt (Unmapped-BCVS).
}

Interface

Uses MKBibMod, MKBibAbs, MKBibVrs, MKBibMem;

Type
  UnboundBibObj = Object(MemBibObj)
  Constructor Init;
  Function  LoadSource: Boolean; Virtual;
  Function  BuildOutput: Word; Virtual;
  End;

Type UnboundBibPtr = ^UnboundBibObj;

Implementation

Uses SysUtils, StrUtils, Classes;

Constructor UnboundBibObj.Init;
  Begin
  MemBibObj.Init;
  FileMarkup := bmPlain;
  MetaMarkup := bmPlain;
  OutExt := '.unbound.txt';
  OutIsDir := False;
  End;

{ the Nth tab separated field (1 based) of a line, '' when there is none }
Function Field(Const S: BibStr; N: Integer): BibStr;
  Var
    P, Q, K: LongInt;
  Begin
  P := 1;
  K := 1;
  While K < N Do
    Begin
    Q := PosEx(#9, S, P);
    If Q = 0 Then Begin Field := ''; Exit; End;
    P := Q + 1;
    Inc(K);
    End;
  Q := PosEx(#9, S, P);
  If Q = 0 Then Field := Copy(S, P, Length(S)) Else Field := Copy(S, P, Q - P);
  End;

Function UnboundBibObj.LoadSource: Boolean;
  Var
    T, Ln, Txt, Old, Bs: BibStr;
    P, E, Bk, Ch, Vs, Code, NCols, I: LongInt;
    Cols: Array[1..12] Of String;
    Hdr: BibStr;
    Got: Boolean;
  Begin
  LoadSource := False;
  If Not ReadWholeFile(PathSpec, T) Then Exit;
  If (Pos('#THE UNBOUND BIBLE', UpperCase(Copy(T, 1, 200))) = 0) And (Pos(#10'#columns', LowerCase(Copy(T, 1, 2000))) = 0) Then Exit;
  Got := False;
  P := 1;
  NCols := 0;
  While P <= Length(T) Do
    Begin
    E := PosEx(#10, T, P);
    If E = 0 Then E := Length(T) + 1;
    Ln := Copy(T, P, E - P);
    P := E + 1;
    If (Ln <> '') And (Ln[Length(Ln)] = #13) Then SetLength(Ln, Length(Ln) - 1);
    If Ln = '' Then Continue;
    If Ln[1] = '#' Then
      Begin
      Hdr := LowerCase(Field(Ln, 1));
      If Hdr = '#name' Then SetInfo('', Field(Ln, 2), '', '', '', '')
      Else If Hdr = '#columns' Then
        Begin
        NCols := 0;
        I := 2;
        While (Field(Ln, I) <> '') And (NCols < 12) Do
          Begin
          Inc(NCols);
          Cols[NCols] := Field(Ln, I);
          Inc(I);
          End;
        End;
      Continue;
      End;
    { book, chapter, verse, [subverse, order_by,] text: the text is the column named text, else the last }
    Txt := '';
    If NCols > 0 Then
      Begin
      For I := 1 To NCols Do
        If LowerCase(Cols[I]) = 'text' Then Txt := Field(Ln, I);
      End
    Else
      Begin
      I := Length(Ln);
      While (I > 0) And (Ln[I] <> #9) Do Dec(I);
      Txt := Copy(Ln, I + 1, Length(Ln));
      End;
    Bs := Field(Ln, 1);
    I := 1;
    While (I <= Length(Bs)) And (Bs[I] In ['0'..'9']) Do Inc(I);
    If I = 1 Then Bk := 0 Else Val(Copy(Bs, 1, I - 1), Bk, Code);
    Val(Field(Ln, 2), Ch, Code);
    If Code <> 0 Then Ch := 0;
    Val(Field(Ln, 3), Vs, Code);
    If Code <> 0 Then Vs := 0;
    If (Bk < 1) Or (Bk > 66) Or (Ch < 1) Or (Vs < 1) Then
      Begin
      Inc(Skipped);
      Continue;
      End;
    Txt := Trim(Txt);
    Old := VerseText(Bk, Ch, Vs);
    If Old <> '' Then Txt := Old + ' ' + Txt;
    StoreVerse(Bk, Ch, Vs, Txt);
    Got := True;
    End;
  LoadSource := Got;
  End;

Function UnboundBibObj.BuildOutput: Word;
  Var
    O, Bs: BibStr;
    B, C, V: Word;
    L: LongInt;
  Begin
  O := '#THE UNBOUND BIBLE (www.unboundbible.org)'#13#10 +
       '#name'#9 + GetDescription + #13#10 +
       '#filetype'#9'Unmapped-BCVS'#13#10 +
       '#copyright'#9 + MetaCopy + #13#10 +
       '#abbreviation'#9 + MetaName + #13#10 +
       '#language'#9 + MetaLang + #13#10 +
       '#note'#9#13#10 +
       '#columns'#9'orig_book_index'#9'orig_chapter'#9'orig_verse'#9'orig_subverse'#9'order_by'#9'text'#13#10;
  For B := 1 To BibBooks Do
    Begin
    Bs := Copy('0' + IntToStr(B), Length(IntToStr(B)), 2);
    If B <= BibOTBooks Then Bs := Bs + 'O' Else Bs := Bs + 'N';
    For C := 1 To VrsChapters(vsKJV, B) Do
      For V := 1 To VrsVerses(vsKJV, B, C) Do
        Begin
        L := VrsLinear(vsKJV, B, C, V);
        If Lines^[L] <> '' Then
          O := O + Bs + #9 + IntToStr(C) + #9 + IntToStr(V) + #9#9 + IntToStr(V * 10) + #9 +
               StringReplace(StringReplace(Lines^[L], #9, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]) + #13#10;
        End;
    End;
  If WriteWholeFile(FileName, O) Then BuildOutput := bibOk Else BuildOutput := bibErrIO;
  End;

End.
