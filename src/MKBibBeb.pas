Unit MKBibBeb;       {Beblia XML Bible object (.xml with <bible><testament><book><chapter><verse>)}

{$I MKBib.Def}

{
  MKBibBeb - descendant of MemBibObj for the Beblia XML format (beblia.com):

      <bible translation="Name">
        <testament name="Old">
          <book number="1">
            <chapter number="1"> <verse number="1">text</verse> ...

  Books are numbered 1..66 (the New Testament goes on from 40).  The verses are plain text (XML entities
  are decoded), so the module reports bmPlain.  Writing makes <dir>/<Name>.beblia.xml.
}

Interface

Uses MKBibMod, MKBibAbs, MKBibVrs, MKBibMem;

Type
  BebliaBibObj = Object(MemBibObj)
  Constructor Init;
  Function  LoadSource: Boolean; Virtual;
  Function  BuildOutput: Word; Virtual;
  End;

Type BebliaBibPtr = ^BebliaBibObj;

Implementation

Uses SysUtils, StrUtils;

Constructor BebliaBibObj.Init;
  Begin
  MemBibObj.Init;
  FileMarkup := bmPlain;
  MetaMarkup := bmPlain;
  OutExt := '.beblia.xml';
  OutIsDir := False;
  End;

Function BebliaBibObj.LoadSource: Boolean;
  Var
    T, U, Tag, VStr: BibStr;
    P, E, BE, Q, Q2, CE, V, VE, Bk, Ch, Vs, Code: LongInt;
  Begin
  LoadSource := False;
  If Not ReadWholeFile(PathSpec, T) Then Exit;
  U := LowerCase(T);
  P := Pos('<bible', U);
  If (P = 0) Or (Pos('<testament', U) = 0) Then Exit;
  E := PosEx('>', T, P);
  SetInfo('', XmlAttrOf(Copy(T, P, E - P + 1), 'translation'), '', '', '', '');
  P := 1;
  While True Do
    Begin
    P := PosEx('<book ', U, P);
    If P = 0 Then Break;
    E := PosEx('>', T, P);
    If E = 0 Then Break;
    Tag := Copy(T, P, E - P + 1);
    BE := PosEx('</book>', U, E);
    If BE = 0 Then BE := Length(T);
    Val(XmlAttrOf(Tag, 'number'), Bk, Code);
    If Code <> 0 Then Bk := 0;
    Q := E;
    While True Do
      Begin
      Q := PosEx('<chapter ', U, Q);
      If (Q = 0) Or (Q > BE) Then Break;
      Q2 := PosEx('>', T, Q);
      Val(XmlAttrOf(Copy(T, Q, Q2 - Q + 1), 'number'), Ch, Code);
      If Code <> 0 Then Ch := 0;
      CE := PosEx('</chapter>', U, Q2);
      If (CE = 0) Or (CE > BE) Then CE := BE;
      V := Q2;
      While True Do
        Begin
        V := PosEx('<verse ', U, V);
        If (V = 0) Or (V > CE) Then Break;
        Q2 := PosEx('>', T, V);
        VStr := XmlAttrOf(Copy(T, V, Q2 - V + 1), 'number');
        Val(VStr, Vs, Code);
        If Code <> 0 Then Vs := 0;
        If T[Q2 - 1] = '/' Then
          Begin
          VE := Q2;
          If (Bk > 0) And (Ch > 0) And (Vs > 0) Then StoreVerse(Bk, Ch, Vs, '');
          End
        Else
          Begin
          VE := PosEx('</verse>', U, Q2);
          If (VE = 0) Or (VE > CE) Then VE := CE;
          If (Bk > 0) And (Ch > 0) And (Vs > 0) Then StoreVerse(Bk, Ch, Vs, XmlDecode(Copy(T, Q2 + 1, VE - Q2 - 1)))
          Else Inc(Skipped);
          End;
        V := VE;
        End;
      Q := CE;
      End;
    P := BE;
    End;
  LoadSource := True;
  End;

Function BebliaBibObj.BuildOutput: Word;
  Var
    O: BibStr;
    B, C, V: Word;
    L: LongInt;
    Any: Boolean;
    CurT, Want: Integer;
  Begin
  O := '<?xml version="1.0" encoding="UTF-8"?>'#10'<bible translation="' + XmlEsc(GetDescription) + '">'#10;
  CurT := 0;
  For B := 1 To BibBooks Do
    Begin
    Any := False;
    For C := 1 To VrsChapters(vsKJV, B) Do
      For V := 1 To VrsVerses(vsKJV, B, C) Do
        If Lines^[VrsLinear(vsKJV, B, C, V)] <> '' Then Any := True;
    If Not Any Then Continue;
    If B <= BibOTBooks Then Want := 1 Else Want := 2;
    If Want <> CurT Then
      Begin
      If CurT <> 0 Then O := O + '  </testament>'#10;
      If Want = 1 Then O := O + '  <testament name="Old">'#10 Else O := O + '  <testament name="New">'#10;
      CurT := Want;
      End;
    O := O + '    <book number="' + IntToStr(B) + '">'#10;
    For C := 1 To VrsChapters(vsKJV, B) Do
      Begin
      O := O + '      <chapter number="' + IntToStr(C) + '">'#10;
      For V := 1 To VrsVerses(vsKJV, B, C) Do
        Begin
        L := VrsLinear(vsKJV, B, C, V);
        If Lines^[L] <> '' Then
          O := O + '        <verse number="' + IntToStr(V) + '">' + XmlEsc(Lines^[L]) + '</verse>'#10;
        End;
      O := O + '      </chapter>'#10;
      End;
    O := O + '    </book>'#10;
    End;
  If CurT <> 0 Then O := O + '  </testament>'#10;
  O := O + '</bible>'#10;
  If WriteWholeFile(FileName, O) Then BuildOutput := bibOk Else BuildOutput := bibErrIO;
  End;

End.
