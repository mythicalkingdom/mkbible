Unit MKBibTxt;       {Text file decoding shared by the plain text Bible formats}

{$I MKBib.Def}

Interface

Uses MKBibMod, MKBibAbs;

Function Cp1252ToUtf8(Const S: BibStr): BibStr;
Function ValidUtf8(Const S: BibStr): Boolean;
Function DecodeText(Const B: BibStr): BibStr;
  {File bytes -> UTF-8: a UTF-8 byte order mark is dropped; text that is valid UTF-8 (this includes plain
   ASCII) is kept; anything else is taken to be Windows-1252}

Implementation

Const
  { Windows-1252 0x80..0x9F as Unicode code points }
  Cp1252Hi: Array[0..31] Of Word = (
    $20AC, $0081, $201A, $0192, $201E, $2026, $2020, $2021, $02C6, $2030, $0160, $2039, $0152, $008D, $017D, $008F,
    $0090, $2018, $2019, $201C, $201D, $2022, $2013, $2014, $02DC, $2122, $0161, $203A, $0153, $009D, $017E, $0178);

Function CodeToUtf8(N: LongInt): BibStr;
  Begin
  If N < $80 Then CodeToUtf8 := Chr(N)
  Else If N < $800 Then CodeToUtf8 := Chr($C0 Or (N Shr 6)) + Chr($80 Or (N And $3F))
  Else CodeToUtf8 := Chr($E0 Or (N Shr 12)) + Chr($80 Or ((N Shr 6) And $3F)) + Chr($80 Or (N And $3F));
  End;

Function Cp1252ToUtf8(Const S: BibStr): BibStr;
  Var
    i, N: LongInt;
    R: BibStr;
  Begin
  R := '';
  For i := 1 To Length(S) Do
    Begin
    N := Ord(S[i]);
    If N < $80 Then R := R + S[i]
    Else If (N >= $80) And (N <= $9F) Then R := R + CodeToUtf8(Cp1252Hi[N - $80])
    Else R := R + CodeToUtf8(N);
    End;
  Cp1252ToUtf8 := R;
  End;

Function ValidUtf8(Const S: BibStr): Boolean;
  Var
    i, n, k: LongInt;
    C: Byte;
  Begin
  ValidUtf8 := False;
  i := 1;
  n := Length(S);
  While i <= n Do
    Begin
    C := Ord(S[i]);
    If C < $80 Then k := 0
    Else If (C And $E0) = $C0 Then k := 1
    Else If (C And $F0) = $E0 Then k := 2
    Else If (C And $F8) = $F0 Then k := 3
    Else Exit;
    If i + k > n Then Exit;
    While k > 0 Do
      Begin
      Inc(i);
      If (Ord(S[i]) And $C0) <> $80 Then Exit;
      Dec(k);
      End;
    Inc(i);
    End;
  ValidUtf8 := True;
  End;

Function DecodeText(Const B: BibStr): BibStr;
  Begin
  If (Length(B) >= 3) And (B[1] = #$EF) And (B[2] = #$BB) And (B[3] = #$BF) Then
    DecodeText := Copy(B, 4, Length(B))
  Else If ValidUtf8(B) Then
    DecodeText := B
  Else
    DecodeText := Cp1252ToUtf8(B);
  End;

End.
