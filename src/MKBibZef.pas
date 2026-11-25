Unit MKBibZef;       {Zefania XML Bible object (.xml with <XMLBIBLE>)}

{$I MKBib.Def}

{
  MKBibZef - descendant of MemBibObj for Zefania XML Bible modules (zef2005; Haggai XML, which writes <VERSE>, is read too): a file with

      <XMLBIBLE biblename="American Standard Version" ...>
        <INFORMATION> <title> <identifier> <language> <rights> <description> ... </INFORMATION>
        <BIBLEBOOK bnumber="1" bname="Genesis" bsname="Gen">
          <CHAPTER cnumber="1"> <CAPTION>..</CAPTION> <VERS vnumber="1">text</VERS> ...

  The verse text is whatever is inside <VERS> (STYLE, NOTE, XREF, gr, BR; reported as bmZefania); a
  <CAPTION> before a verse becomes a heading at the start of that verse.  Books are taken from
  bnumber (1..66; this is the canonical order), else from bname / bsname.  Tag names are read
  without regard to case.  The module information comes from <INFORMATION> (title = description,
  identifier = name, language, rights = copyright, description = about).

  Writing makes <dir>/<Name>.zefania.xml in UTF-8.  Headings are dropped (the format keeps them
  outside the verses); notes, italics, bold, red letters, Strong's numbers, cross references and
  line breaks are written.
}

Interface

Uses MKBibMod, MKBibAbs, MKBibVrs, MKBibMem;

Type
  ZefaniaBibObj = Object(MemBibObj)
  Constructor Init;
  Function  LoadSource: Boolean; Virtual;
  Function  BuildOutput: Word; Virtual;
  End;

Type ZefaniaBibPtr = ^ZefaniaBibObj;

Implementation

Uses SysUtils, StrUtils, MKBibMkp;

Constructor ZefaniaBibObj.Init;
  Begin
  MemBibObj.Init;
  FileMarkup := bmZefania;
  MetaMarkup := bmZefania;
  OutExt := '.zefania.xml';
  OutIsDir := False;
  End;

Function ZefaniaBibObj.LoadSource: Boolean;
  Var
    T, U, Tag, Gap, Cap, Txt, DescS, Id, VStr: BibStr;
    P, E, BE, CE, V, VE, Q, Q2, Gp: LongInt;
    Bk, Ch, Vs, Code, N: LongInt;
    EndTag: String;
  Begin
  LoadSource := False;
  If Not ReadWholeFile(PathSpec, T) Then Exit;
  U := UpperCase(T);
  If Pos('<XMLBIBLE', U) = 0 Then Exit;
  { module information }
  P := Pos('<XMLBIBLE', U);
  E := PosEx('>', T, P);
  Tag := Copy(T, P, E - P + 1);
  DescS := XmlFirst(T, 'title');
  If DescS = '' Then DescS := XmlAttrOf(Tag, 'biblename');
  Id := XmlFirst(T, 'identifier');
  SetInfo(Id, DescS, XmlFirst(T, 'language'), XmlFirst(T, 'rights'), XmlFirst(T, 'description'), XmlFirst(T, 'date'));
  P := 1;
  While True Do
    Begin
    P := PosEx('<BIBLEBOOK', U, P);
    If P = 0 Then Break;
    E := PosEx('>', T, P);
    If E = 0 Then Break;
    Tag := Copy(T, P, E - P + 1);
    BE := PosEx('</BIBLEBOOK>', U, E);
    If BE = 0 Then BE := Length(T);
    Val(XmlAttrOf(Tag, 'bnumber'), Bk, Code);
    If (Code <> 0) Or (Bk < 1) Or (Bk > 66) Then
      Begin
      Bk := BookOfName(XmlAttrOf(Tag, 'bsname'));
      If Bk = 0 Then Bk := BookOfName(XmlAttrOf(Tag, 'bname'));
      End;
    { chapters }
    Q := E;
    While True Do
      Begin
      Q := PosEx('<CHAPTER', U, Q);
      If (Q = 0) Or (Q > BE) Then Break;
      Q2 := PosEx('>', T, Q);
      Tag := Copy(T, Q, Q2 - Q + 1);
      Val(XmlAttrOf(Tag, 'cnumber'), Ch, Code);
      If Code <> 0 Then Ch := 0;
      CE := PosEx('</CHAPTER>', U, Q2);
      If (CE = 0) Or (CE > BE) Then CE := BE;
      Gp := Q2 + 1;
      V := Q2;
      While True Do
        Begin
        V := PosEx('<VERS', U, V);
        If (V = 0) Or (V > CE) Then Break;
        { Haggai XML (the Free Scriptures flavour of Zefania) calls it <VERSE> }
        If (U[V + 5] = 'E') And (U[V + 6] In [' ', '>', '/']) Then EndTag := '</VERSE>'
        Else If U[V + 5] In [' ', '>', '/'] Then EndTag := '</VERS>'
        Else
          Begin
          Inc(V);
          Continue;
          End;
        Q2 := PosEx('>', T, V);
        Tag := Copy(T, V, Q2 - V + 1);
        VStr := XmlAttrOf(Tag, 'vnumber');
        N := 1;
        While (N <= Length(VStr)) And (VStr[N] In ['0'..'9']) Do Inc(N);
        If N = 1 Then Vs := 0 Else Val(Copy(VStr, 1, N - 1), Vs, Code);
        { the caption(s) between the last verse and this one }
        Gap := Copy(T, Gp, V - Gp);
        Cap := '';
        If Pos('<CAPTION', UpperCase(Gap)) > 0 Then Cap := Gap;
        If T[Q2 - 1] = '/' Then
          Begin
          Txt := '';
          VE := Q2;
          End
        Else
          Begin
          VE := PosEx(EndTag, U, Q2);
          If (VE = 0) Or (VE > CE) Then VE := CE;
          Txt := Copy(T, Q2 + 1, VE - Q2 - 1);
          VE := VE + Length(EndTag) - 1;
          End;
        If Cap <> '' Then Txt := Cap + Txt;
        If (Bk > 0) And (Ch > 0) And (Vs > 0) Then StoreVerse(Bk, Ch, Vs, Txt) Else Inc(Skipped);
        Gp := VE + 1;
        V := VE;
        End;
      Q := CE;
      End;
    P := BE;
    End;
  LoadSource := True;
  End;

Function ZefaniaBibObj.BuildOutput: Word;
  Var
    O, Nm, Lang: BibStr;
    B, C, V: Word;
    L: LongInt;
    Any: Boolean;
  Begin
  Nm := MetaName;
  Lang := MetaLang;
  If Lang = '' Then Lang := 'ENG';
  O := '<?xml version="1.0" encoding="utf-8"?>'#10 +
       '<XMLBIBLE xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="zef2005.xsd" ' +
       'version="2.0.1.18" status="v" biblename="' + XmlEsc(GetDescription) + '" type="x-bible">'#10 +
       '  <INFORMATION>'#10 +
       '    <title>' + XmlEsc(GetDescription) + '</title>'#10 +
       '    <creator></creator>'#10 +
       '    <subject>holy bible</subject>'#10 +
       '    <description>' + XmlEsc(MetaAbout) + '</description>'#10 +
       '    <publisher></publisher>'#10 +
       '    <contributors></contributors>'#10 +
       '    <date>' + XmlEsc(MetaVer) + '</date>'#10 +
       '    <type>Bible</type>'#10 +
       '    <format>Zefania XML Bible Markup Language</format>'#10 +
       '    <identifier>' + XmlEsc(Nm) + '</identifier>'#10 +
       '    <source></source>'#10 +
       '    <language>' + XmlEsc(Lang) + '</language>'#10 +
       '    <coverage></coverage>'#10 +
       '    <rights>' + XmlEsc(MetaCopy) + '</rights>'#10 +
       '  </INFORMATION>'#10;
  For B := 1 To BibBooks Do
    Begin
    Any := False;
    For C := 1 To VrsChapters(vsKJV, B) Do
      For V := 1 To VrsVerses(vsKJV, B, C) Do
        If Lines^[VrsLinear(vsKJV, B, C, V)] <> '' Then Any := True;
    If Not Any Then Continue;
    O := O + '  <BIBLEBOOK bnumber="' + IntToStr(B) + '" bname="' + XmlEsc(BookInfo[B].Name) + '" bsname="' +
         XmlEsc(BookInfo[B].Abbrev) + '">'#10;
    For C := 1 To VrsChapters(vsKJV, B) Do
      Begin
      O := O + '    <CHAPTER cnumber="' + IntToStr(C) + '">'#10;
      For V := 1 To VrsVerses(vsKJV, B, C) Do
        Begin
        L := VrsLinear(vsKJV, B, C, V);
        If Lines^[L] <> '' Then
          O := O + '      <VERS vnumber="' + IntToStr(V) + '">' + MkpTranslate(Lines^[L], mfZefania, mfZefania) + '</VERS>'#10;
        End;
      O := O + '    </CHAPTER>'#10;
      End;
    O := O + '  </BIBLEBOOK>'#10;
    End;
  O := O + '</XMLBIBLE>'#10;
  If WriteWholeFile(FileName, O) Then BuildOutput := bibOk Else BuildOutput := bibErrIO;
  End;

End.
