Unit MKBibUfx;       {USFX XML Bible object (.usfx.xml)}

{$I MKBib.Def}

{
  MKBibUfx - descendant of MemBibObj for USFX (Unified Scripture Format XML, eBible.org's XML form of
  USFM):

      <book id="GEN"> <id id="GEN">name</id> <h>Genesis</h> <c id="1"/>
        <p><v id="1"/>text<ve/><v id="2"/>text<ve/></p> ...

  The verse is what lies between <v id="n"/> and <ve/> (reported as bmUSFX: w, wj, add, f, x, q, ...).
  Paragraph, poetry (<q>), blank line and heading elements between two verses are carried at the
  front of the verse that follows, back to the chapter start.  Books are the three letter ids
  (GEN ... REV); other ids (the Apocrypha) are counted, not stored.

  Module information: the text of the first <id>, <languageCode>.  Writing makes
  <dir>/<Name>.usfx.xml in UTF-8: one <p> per chapter, with </p><p> where the text breaks.
}

Interface

Uses MKBibMod, MKBibAbs, MKBibVrs, MKBibMem;

Const
  UsfmBookIds: Array[1..66] Of String[3] = (
    'GEN', 'EXO', 'LEV', 'NUM', 'DEU', 'JOS', 'JDG', 'RUT', '1SA', '2SA', '1KI', '2KI', '1CH', '2CH', 'EZR',
    'NEH', 'EST', 'JOB', 'PSA', 'PRO', 'ECC', 'SNG', 'ISA', 'JER', 'LAM', 'EZK', 'DAN', 'HOS', 'JOL', 'AMO',
    'OBA', 'JON', 'MIC', 'NAM', 'HAB', 'ZEP', 'HAG', 'ZEC', 'MAL', 'MAT', 'MRK', 'LUK', 'JHN', 'ACT', 'ROM',
    '1CO', '2CO', 'GAL', 'EPH', 'PHP', 'COL', '1TH', '2TH', '1TI', '2TI', 'TIT', 'PHM', 'HEB', 'JAS', '1PE',
    '2PE', '1JN', '2JN', '3JN', 'JUD', 'REV');

Type
  UsfxBibObj = Object(MemBibObj)
  Constructor Init;
  Function  LoadSource: Boolean; Virtual;
  Function  BuildOutput: Word; Virtual;
  End;

Type UsfxBibPtr = ^UsfxBibObj;

Function UsfmBookNumber(Const Id: String): Word;     {GEN -> 1 ... REV -> 66, 0 = not one of the 66}

Implementation

Uses SysUtils, StrUtils, MKBibMkp;

Function UsfmBookNumber(Const Id: String): Word;
  Var
    i: Word;
    U: String;
  Begin
  UsfmBookNumber := 0;
  U := UpperCase(Trim(Id));
  For i := 1 To 66 Do
    If UsfmBookIds[i] = U Then
      Begin
      UsfmBookNumber := i;
      Exit;
      End;
  End;

Constructor UsfxBibObj.Init;
  Begin
  MemBibObj.Init;
  FileMarkup := bmUSFX;
  MetaMarkup := bmUSFX;
  OutExt := '.usfx.xml';
  OutIsDir := False;
  End;

Function UsfxBibObj.LoadSource: Boolean;
  Var
    T, L, Tag, Id, Txt, Gap, Desc, Lang: BibStr;
    P, E, BE, Bk, Ch, Vs, Code, N, Q, VE, NextV, Gp, K: LongInt;
    VStr: BibStr;
    FirstId: Boolean;
  Begin
  LoadSource := False;
  If Not ReadWholeFile(PathSpec, T) Then Exit;
  L := LowerCase(T);
  If Pos('<usfx', L) = 0 Then Exit;
  Lang := XmlFirst(T, 'languageCode');
  Desc := '';
  FirstId := True;
  P := 1;
  While True Do
    Begin
    P := PosEx('<book ', L, P);
    If P = 0 Then Break;
    E := PosEx('>', T, P);
    Tag := Copy(T, P, E - P + 1);
    BE := PosEx('</book>', L, E);
    If BE = 0 Then BE := Length(T);
    Bk := UsfmBookNumber(XmlAttrOf(Tag, 'id'));
    If FirstId Then
      Begin
      Desc := XmlFirst(Copy(T, E, BE - E), 'id');
      K := Pos('.sfm ', Desc);
      If K > 0 Then Desc := Copy(Desc, K + 5, Length(Desc));
      Desc := Trim(Desc);
      FirstId := False;
      End;
    Ch := 0;
    Gp := E + 1;
    Q := E;
    While True Do
      Begin
      { next chapter or verse marker }
      N := PosEx('<c id=', L, Q);
      NextV := PosEx('<v id=', L, Q);
      If (N > 0) And (N < BE) And ((NextV = 0) Or (N < NextV)) Then
        Begin
        Q := PosEx('>', T, N);
        VStr := XmlAttrOf(Copy(T, N, Q - N + 1), 'id');
        Val(VStr, Ch, Code);
        If Code <> 0 Then Ch := 0;
        Gp := Q + 1;
        Continue;
        End;
      If (NextV = 0) Or (NextV > BE) Then Break;
      Q := PosEx('>', T, NextV);
      VStr := XmlAttrOf(Copy(T, NextV, Q - NextV + 1), 'id');
      N := 1;
      While (N <= Length(VStr)) And (VStr[N] In ['0'..'9']) Do Inc(N);
      If N = 1 Then Vs := 0 Else Val(Copy(VStr, 1, N - 1), Vs, Code);
      Gap := Copy(T, Gp, NextV - Gp);
      { the verse ends at <ve/> or at the next verse / chapter marker }
      VE := PosEx('<ve/>', L, Q);
      If VE = 0 Then VE := PosEx('<ve />', L, Q);
      N := PosEx('<v id=', L, Q);
      If (VE = 0) Or ((N > 0) And (N < VE)) Then VE := N;
      N := PosEx('<c id=', L, Q);
      If (VE = 0) Or ((N > 0) And (N < VE)) Then VE := N;
      If (VE = 0) Or (VE > BE) Then VE := BE;
      Txt := Copy(T, Q + 1, VE - Q - 1);
      If Trim(Gap) <> '' Then Txt := Gap + Txt;
      If (Bk > 0) And (Ch > 0) And (Vs > 0) Then StoreVerse(Bk, Ch, Vs, Txt) Else Inc(Skipped);
      If (VE < BE) And (Copy(L, VE, 4) = '<ve/') Then
        Begin
        Q := PosEx('>', T, VE);
        If Q = 0 Then Q := VE;
        End
      Else Q := VE - 1;
      Gp := Q + 1;
      End;
    P := BE;
    End;
  SetInfo('', Desc, Lang, '', '', '');
  LoadSource := True;
  End;

Function UsfxBibObj.BuildOutput: Word;
  Var
    O, Nm, Lang: BibStr;
    B, C, V: Word;
    L: LongInt;
    Any: Boolean;
  Begin
  Lang := MetaLang;
  If Lang = '' Then Lang := 'eng';
  Nm := GetDescription;
  If Nm = '' Then Nm := MetaName;
  O := '<?xml version="1.0" encoding="UTF-8"?>'#10 +
       '<usfx xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="usfx.xsd">'#10 +
       '<languageCode>' + XmlEsc(Lang) + '</languageCode>'#10;
  For B := 1 To BibBooks Do
    Begin
    Any := False;
    For C := 1 To VrsChapters(vsKJV, B) Do
      For V := 1 To VrsVerses(vsKJV, B, C) Do
        If Lines^[VrsLinear(vsKJV, B, C, V)] <> '' Then Any := True;
    If Not Any Then Continue;
    O := O + '<book id="' + UsfmBookIds[B] + '"><id id="' + UsfmBookIds[B] + '">' + XmlEsc(Nm) + #10'</id>' +
         '<ide charset="UTF-8"/><h>' + XmlEsc(BookInfo[B].Name) + #10'</h>' +
         '<toc level="1">' + XmlEsc(BookInfo[B].Name) + #10'</toc>'#10;
    For C := 1 To VrsChapters(vsKJV, B) Do
      Begin
      O := O + '<c id="' + IntToStr(C) + '"/>'#10'<p>';
      For V := 1 To VrsVerses(vsKJV, B, C) Do
        Begin
        L := VrsLinear(vsKJV, B, C, V);
        If Lines^[L] <> '' Then O := O + '<v id="' + IntToStr(V) + '"/>' + MkpTranslate(Lines^[L], mfUSFX, mfUSFX) + '<ve/>'#10;
        End;
      O := O + '</p>'#10;
      End;
    O := O + '</book>'#10;
    End;
  O := O + '</usfx>'#10;
  If WriteWholeFile(FileName, O) Then BuildOutput := bibOk Else BuildOutput := bibErrIO;
  End;

End.
