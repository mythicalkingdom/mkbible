Unit MKBibMkp;       {Markup translator: OSIS, ThML, GBF, MySword <-> each other and plain text}

{$MODE OBJFPC}{$H+}
{$I-}{$R-}{$Q-}

{
  MKBibMkp translates the text of a verse (or an introduction) between the markups Bible
  modules use.  Every markup is parsed into a neutral list of events, which is normalised
  and then written out in the target markup, so N formats need N parsers and N writers,
  not N x N converters.

  The events, and which markups carry them:
                              OSIS  ThML  GBF  MySword
      text                     x     x     x     x
      paragraph / line break   x     x     x     x
      italic, bold             x     x     x     x
      words of Jesus           x     -     x     x      (ThML: not written, not read)
      footnotes                x     x     x     x
      cross references         x     x     x     x
      headings                 x     x     x     x
      Strong's numbers         x     x     x     x      (attached to the word before them)
      morphology codes         x     x     x     x

  mfTheWord is the markup of theWord Bible modules: MySword's markup (GBF style tags, <RX b.c.v>
  references, <Wnnn> Strong's numbers) plus <CI> (a new poetry line), <wt> (ignored), <b> and <i>.

  mfVPL is the light markup found in verse-per-line text files: <red> words of Jesus </red>,
  <b> bold </b> (headings are written as bold), <em> or <i> italics, <br> line breaks.  Notes,
  Strong's numbers and cross references cannot be carried and are dropped when writing it.

  mfHTML is simple HTML, as in MySword dictionaries: p, div, br, li, b, strong, i, em, h1..h6 (as bold
  paragraphs); everything else is dropped and its text kept.  It is also written, for entries that
  have bold, italics and breaks.  mfTEI is the TEI of Sword dictionaries (entryFree, orth, pron, def):
  line breaks, paragraphs and rend="bold" / rend="italic"; read only.

  mfSTEP is the RTF text of STEP modules (QuickVerse and others).  It is read only: italics, bold,
  words of Jesus (colour 6 = red), line breaks, typographic quotes and dashes, hidden text and
  verse number superscripts (dropped), plus the groups  \*\stepnote  (a footnote) and
  \*\stephead  (a section heading) that the STEP reader puts into the verse text.

  mfUSFM, mfUSFX and mfZefania are the inline markups of USFM (\w word|strong="H1"\w*, \wj, \add, \f ... \f*,
  paragraph / poetry / heading markers), USFX (the same as XML) and Zefania XML (STYLE, NOTE, XREF, gr, BR).  Chapter and verse
  structure is the business of the module objects, not of the translator.

  Quote marks given as marker="..." (q, milestone cQuote) become text, as Sword shows
  them.  Everything else (milestones, structure divs, poetry groups, foreign / divineName
  wrappers, ...) is dropped and only its text is kept.  Translation is lossy by design:
  what the target markup cannot express is dropped, never mangled.

  Plain text (mfPlain as target) drops notes and, unless moHeadings is given, headings;
  moBreaks keeps paragraph and line breaks as new lines (for introductions).
}

Interface

Type
  MkpFormat = (mfPlain, mfOSIS, mfThML, mfGBF, mfMySword, mfSTEP, mfTheWord, mfVPL, mfHTML, mfTEI, mfUSFM, mfUSFX, mfZefania, mfUSX);
  MkpOpt = (moHeadings, moBreaks);
  MkpOpts = Set Of MkpOpt;

Function MkpTranslate(Const S: AnsiString; From, Dest: MkpFormat; Opts: MkpOpts = []): AnsiString;
Function MkpToXhtml(Const S: AnsiString; From: MkpFormat; VerseNum: Integer; WithNotes: Boolean;
  Var NoteCount: Integer; Var NoteHtml: AnsiString): AnsiString;
  {XHTML for an EPUB: inline text of one verse, to sit inside a <p>.  Paragraph breaks come out as </p><p> and
  headings as </p><h5 class="sh">..</h5><p> (the caller removes the empty paragraphs), poetry lines as <br/>, words of
  Jesus as <span class="jesus">, italics and bold as i / b.  VerseNum > 0 puts <sup class="vn">N</sup> before the first
  text.  Footnotes (cross reference notes are left out) become a marker link in the text and an
  <aside epub:type="footnote" id="fnK"> appended to NoteHtml; NoteCount numbers them across calls.}
Function MkpSummary(Const S: AnsiString; From: MkpFormat): AnsiString;
  {Counts of what the text carries after parsing, e.g. "text=57 words=9 strongs=9 notes=1 ..."}
Function MkpOsisToHuman(Const R: AnsiString): AnsiString;   {Gen.1.1 -> Gen 1:1}
Function MkpHumanToOsis(Const H: AnsiString): AnsiString;   {Gen 1:1 -> Gen.1.1 ('' if not a reference)}

Implementation

Uses SysUtils, MKBibVrs;

Type
  TEvKind = (ekText, ekPara, ekLine, ekItalicOn, ekItalicOff, ekBoldOn, ekBoldOff,
             ekJesusOn, ekJesusOff, ekNoteOn, ekNoteOff, ekXrefOn, ekXrefOff,
             ekHeadOn, ekHeadOff, ekWordOn, ekWordOff);

  TEv = Record
    Kind: TEvKind;
    Txt: AnsiString;       {ekText: the text;  ekXrefOn: OSIS reference}
    Strong: AnsiString;    {ekWordOn: "H1234 G26"}
    Morph: AnsiString;     {ekWordOn: "robinson:N-NSM"}
    Num: Integer;          {ekNoteOn: 1 = cross reference note;  ekHeadOn: level}
  End;

  TDoc = Record
    N: Integer;
    Ev: Array Of TEv;
  End;

  TTag = Record
    Name: AnsiString;
    Close, Empty: Boolean;
    Attrs: AnsiString;
  End;


{==================================================================== helpers}

Procedure Add(Var D: TDoc; K: TEvKind; Const T: AnsiString = ''; Num: Integer = 0);
  Begin
  If D.N >= Length(D.Ev) Then SetLength(D.Ev, Length(D.Ev) * 2 + 16);
  D.Ev[D.N].Kind := K;
  D.Ev[D.N].Txt := T;
  D.Ev[D.N].Strong := '';
  D.Ev[D.N].Morph := '';
  D.Ev[D.N].Num := Num;
  Inc(D.N);
  End;

Function DecodeEntities(Const S: AnsiString): AnsiString;
  Var
    R: AnsiString;
    i, j, Code: Integer;
    N: LongInt;
    Ent: AnsiString;
  Begin
  If Pos('&', S) = 0 Then
    Begin
    DecodeEntities := S;
    Exit;
    End;
  R := '';
  i := 1;
  While i <= Length(S) Do
    Begin
    If S[i] = '&' Then
      Begin
      j := i + 1;
      While (j <= Length(S)) And (j - i < 10) And (S[j] <> ';') Do Inc(j);
      If (j <= Length(S)) And (S[j] = ';') Then
        Begin
        Ent := Copy(S, i + 1, j - i - 1);
        If Ent = 'amp' Then R := R + '&'
        Else If Ent = 'lt' Then R := R + '<'
        Else If Ent = 'gt' Then R := R + '>'
        Else If Ent = 'quot' Then R := R + '"'
        Else If Ent = 'apos' Then R := R + ''''
        Else If Ent = 'nbsp' Then R := R + ' '
        Else If (Length(Ent) > 1) And (Ent[1] = '#') Then
          Begin
          If (Ent[2] = 'x') Or (Ent[2] = 'X') Then Val('$' + Copy(Ent, 3, 8), N, Code)
          Else Val(Copy(Ent, 2, 8), N, Code);
          If (Code = 0) And (N > 0) Then
            Begin
            If N < $80 Then R := R + Chr(N)
            Else If N < $800 Then R := R + Chr($C0 Or (N Shr 6)) + Chr($80 Or (N And $3F))
            Else If N < $10000 Then
              R := R + Chr($E0 Or (N Shr 12)) + Chr($80 Or ((N Shr 6) And $3F)) + Chr($80 Or (N And $3F))
            Else
              R := R + Chr($F0 Or (N Shr 18)) + Chr($80 Or ((N Shr 12) And $3F)) +
                   Chr($80 Or ((N Shr 6) And $3F)) + Chr($80 Or (N And $3F));
            End;
          End
        Else R := R + Copy(S, i, j - i + 1);
        i := j + 1;
        Continue;
        End;
      End;
    R := R + S[i];
    Inc(i);
    End;
  DecodeEntities := R;
  End;

Function Esc(Const S: AnsiString): AnsiString;
  Var
    R: AnsiString;
    i: Integer;
  Begin
  If (Pos('&', S) = 0) And (Pos('<', S) = 0) And (Pos('>', S) = 0) Then
    Begin
    Esc := S;
    Exit;
    End;
  R := '';
  For i := 1 To Length(S) Do
    Case S[i] Of
      '&': R := R + '&amp;';
      '<': R := R + '&lt;';
      '>': R := R + '&gt;';
      Else R := R + S[i];
      End;
  Esc := R;
  End;

{ Next token of S at Pos: a tag (the text between < and >) or a run of text.  Quotes inside
  a tag are respected, so a > inside an attribute value does not end it. }
Function NextToken(Const S: AnsiString; Var Pos: Integer; Var IsTag: Boolean; Var Txt: AnsiString): Boolean;
  Var
    j: Integer;
    Q: Char;
  Begin
  NextToken := False;
  If Pos > Length(S) Then Exit;
  NextToken := True;
  If S[Pos] = '<' Then
    Begin
    j := Pos + 1;
    Q := #0;
    While j <= Length(S) Do
      Begin
      If Q <> #0 Then
        Begin
        If S[j] = Q Then Q := #0;
        End
      Else If (S[j] = '"') Or (S[j] = '''') Then Q := S[j]
      Else If S[j] = '>' Then Break;
      Inc(j);
      End;
    If j <= Length(S) Then
      Begin
      IsTag := True;
      Txt := Copy(S, Pos + 1, j - Pos - 1);
      Pos := j + 1;
      Exit;
      End;
    End;
  IsTag := False;
  j := Pos + 1;
  While (j <= Length(S)) And (S[j] <> '<') Do Inc(j);
  Txt := Copy(S, Pos, j - Pos);
  Pos := j;
  End;

Procedure SplitTag(Const Raw: AnsiString; Fold: Boolean; Var T: TTag);
  Var
    i, L: Integer;
    R: AnsiString;
  Begin
  R := Raw;
  T.Close := False; T.Empty := False;
  If (R <> '') And (R[1] = '/') Then
    Begin
    T.Close := True;
    Delete(R, 1, 1);
    End;
  L := Length(R);
  While (L > 0) And (R[L] = ' ') Do Dec(L);
  If (L > 0) And (R[L] = '/') Then
    Begin
    T.Empty := True;
    SetLength(R, L - 1);
    End;
  i := 1;
  While (i <= Length(R)) And (Not (R[i] In [' ', #9, #10, #13])) Do Inc(i);
  T.Name := Copy(R, 1, i - 1);
  T.Attrs := Copy(R, i + 1, Length(R));
  If Fold Then T.Name := LowerCase(T.Name);
  End;

Function IsWSc(C: Char): Boolean;
  Begin
  IsWSc := C In [' ', #9, #10, #13];
  End;

Function Attr(Const A, Name: AnsiString; Var V: AnsiString): Boolean;
  Var
    i, j, p: Integer;
    Q: Char;
    L, Key: AnsiString;
  Begin
  Attr := False;
  V := '';
  L := LowerCase(A);
  Key := LowerCase(Name) + '=';
  p := 1;
  While p <= Length(L) Do
    Begin
    i := Pos(Key, Copy(L, p, Length(L)));
    If i = 0 Then Exit;
    i := i + p - 1;
    If (i = 1) Or (A[i - 1] In [' ', #9, #10, #13]) Then
      Begin
      j := i + Length(Key);
      If (j <= Length(A)) And ((A[j] = '"') Or (A[j] = '''')) Then
        Begin
        Q := A[j];
        Inc(j);
        i := j;
        While (j <= Length(A)) And (A[j] <> Q) Do Inc(j);
        V := DecodeEntities(Copy(A, i, j - i));
        End
      Else
        Begin
        i := j;
        While (j <= Length(A)) And (Not IsWSc(A[j])) Do Inc(j);
        V := Copy(A, i, j - i);
        End;
      Attr := True;
      Exit;
      End;
    p := i + 1;
    End;
  End;


{==================================================================== references}

Function Norm(Const S: AnsiString): AnsiString;
  Var
    R: AnsiString;
    i: Integer;
  Begin
  R := '';
  For i := 1 To Length(S) Do
    If S[i] In ['A'..'Z'] Then R := R + Chr(Ord(S[i]) + 32)
    Else If S[i] In ['a'..'z', '0'..'9'] Then R := R + S[i];
  Norm := R;
  End;

{ Normalised book name candidates: "II Kings" also matches as "2kings" }
Function NameNorm(Const Name: AnsiString): AnsiString;
  Begin
  If Copy(Name, 1, 4) = 'III ' Then NameNorm := '3' + Norm(Copy(Name, 5, Length(Name)))
  Else If Copy(Name, 1, 3) = 'II ' Then NameNorm := '2' + Norm(Copy(Name, 4, Length(Name)))
  Else If Copy(Name, 1, 2) = 'I ' Then NameNorm := '1' + Norm(Copy(Name, 3, Length(Name)))
  Else NameNorm := Norm(Name);
  End;

{ N is a lower case "name + chapter..." string without blanks ("1cor13:4"): the book number
  and the rest after the name (starting with the chapter) }
Function FindBookPrefix(Const N: AnsiString; Var Rest: AnsiString): Integer;
  Var
    i, B, Cnt, Hit, k: Integer;
    A: AnsiString;
    Cand: Array[0..2] Of AnsiString;
    BR: BookNameRec;
  Begin
  FindBookPrefix := 0;
  Rest := N;
  i := 1;
  If (i <= Length(N)) And (N[i] In ['0'..'9']) Then Inc(i);       {1cor, 2kings}
  While (i <= Length(N)) And (Not (N[i] In ['0'..'9'])) Do Inc(i);
  A := Copy(N, 1, i - 1);
  Rest := Copy(N, i, Length(N));
  If A = '' Then Exit;
  Cnt := 0; Hit := 0;
  For B := 1 To BibBooks Do
    Begin
    BR := BookInfo[B];
    Cand[0] := NameNorm(BR.Name); Cand[1] := Norm(BR.OSIS); Cand[2] := Norm(BR.Abbrev);
    For k := 0 To 2 Do
      If A = Cand[k] Then
        Begin
        FindBookPrefix := B;
        Exit;
        End;
    If (Length(A) >= 3) And (Copy(Cand[0], 1, Length(A)) = A) Then
      Begin
      Inc(Cnt);
      Hit := B;
      End;
    End;
  If Cnt = 1 Then FindBookPrefix := Hit;
  End;

Function OsisOne(Book: Integer; C, V1, C2, V2: LongInt): AnsiString;
  { Book c:v1 [- c2:v2];  C2 = 0: same chapter (V2 is then the last verse);  V2 = 0: no range }
  Var R: AnsiString;
  Begin
  R := BookInfo[Book].OSIS;
  If C > 0 Then R := R + '.' + IntToStr(C);
  If V1 > 0 Then R := R + '.' + IntToStr(V1);
  If (C2 > 0) And ((C2 <> C) Or (V2 > V1)) Then
    Begin
    R := R + '-' + BookInfo[Book].OSIS + '.' + IntToStr(C2);
    If V2 > 0 Then R := R + '.' + IntToStr(V2);
    End
  Else If (C2 = 0) And (V2 > V1) Then
    R := R + '-' + BookInfo[Book].OSIS + '.' + IntToStr(C) + '.' + IntToStr(V2);
  OsisOne := R;
  End;

{ "Gen 1:1", "Gen 1:1-3", "Ex 35:30-36:1", "1 Cor 13", "Gen 1-3", "John 3:16; Rom 5:8" -> OSIS refs
  separated by blanks }
Function MkpHumanToOsis(Const H: AnsiString): AnsiString;
  Var
    Parts, Cur, N, Rest, Rest2, Res, Tail: AnsiString;
    i, j, B, B2: Integer;
    C, V1, C2, V2, Code: LongInt;
    Ok: Boolean;
  Begin
  Res := '';
  Parts := H;
  While Trim(Parts) <> '' Do
    Begin
    i := Pos(';', Parts);
    If i = 0 Then i := Length(Parts) + 1;
    Cur := Trim(Copy(Parts, 1, i - 1));
    Parts := Copy(Parts, i + 1, Length(Parts));
    If Cur = '' Then Continue;
    N := '';
    For j := 1 To Length(Cur) Do
      If Cur[j] In ['A'..'Z'] Then N := N + Chr(Ord(Cur[j]) + 32)
      Else If Cur[j] In ['a'..'z', '0'..'9', ':', '-'] Then N := N + Cur[j];
    { a range may repeat the book: "gen1:1-gen2:3": the second book name is dropped when it is the same }
    B := FindBookPrefix(N, Rest);
    If B = 0 Then
      Begin
      MkpHumanToOsis := '';
      Exit;
      End;
    C := 0; V1 := 0; C2 := 0; V2 := 0; Code := 0; Ok := True;
    Tail := '';
    j := Pos('-', Rest);
    If j > 0 Then
      Begin
      Tail := Copy(Rest, j + 1, Length(Rest));
      Rest := Copy(Rest, 1, j - 1);
      End;
    If Rest <> '' Then
      Begin
      i := Pos(':', Rest);
      If i = 0 Then Val(Rest, C, Code)
      Else
        Begin
        Val(Copy(Rest, 1, i - 1), C, Code);
        If Code = 0 Then Val(Copy(Rest, i + 1, Length(Rest)), V1, Code);
        End;
      If Code <> 0 Then Ok := False;
      End;
    B2 := 0;
    If Ok And (Tail <> '') And (Not (Tail[1] In ['0'..'9'])) Or
       (Ok And (Tail <> '') And (Length(Tail) > 1) And (Tail[1] In ['1'..'3']) And (Tail[2] In ['a'..'z'])) Then
      Begin
      { the range ends in another book: Obad 1:1-Nah 2:13 }
      B2 := FindBookPrefix(Tail, Rest2);
      If B2 = 0 Then Ok := False
      Else
        Begin
        C2 := 0; V2 := 0;
        If Rest2 <> '' Then
          Begin
          i := Pos(':', Rest2);
          If i = 0 Then Val(Rest2, C2, Code)
          Else
            Begin
            Val(Copy(Rest2, 1, i - 1), C2, Code);
            If Code = 0 Then Val(Copy(Rest2, i + 1, Length(Rest2)), V2, Code);
            End;
          If Code <> 0 Then Ok := False;
          End;
        End;
      End
    Else If Ok And (Tail <> '') Then
      Begin
      i := Pos(':', Tail);
      If i > 0 Then
        Begin
        Val(Copy(Tail, 1, i - 1), C2, Code);
        If Code = 0 Then Val(Copy(Tail, i + 1, Length(Tail)), V2, Code);
        End
      Else If V1 > 0 Then Val(Tail, V2, Code)             {Gen 1:1-3}
      Else Val(Tail, C2, Code);                           {Gen 1-3}
      If Code <> 0 Then Ok := False;
      End;
    If Not Ok Then
      Begin
      MkpHumanToOsis := '';
      Exit;
      End;
    If Res <> '' Then Res := Res + ' ';
    If B2 > 0 Then Res := Res + OsisOne(B, C, V1, 0, 0) + '-' + OsisOne(B2, C2, V2, 0, 0)
    Else Res := Res + OsisOne(B, C, V1, C2, V2);
    End;
  MkpHumanToOsis := Res;
  End;

Function OsisBookToNum(Const O: AnsiString): Integer;
  Var B: Integer;
  Begin
  OsisBookToNum := 0;
  For B := 1 To BibBooks Do
    If LowerCase(BookInfo[B].OSIS) = LowerCase(O) Then
      Begin
      OsisBookToNum := B;
      Exit;
      End;
  End;

{ Gen.1.1 -> Gen 1:1, John.3.16-John.3.18 -> John 3:16-18, several separated by blanks -> "; " }
Function MkpOsisToHuman(Const R: AnsiString): AnsiString;
  Var
    Rem, Item, A, B2, Res, One: AnsiString;
    i, k: Integer;
    f: Array[0..3] Of AnsiString;
    Bk: Integer;

  Function Split3(Const X: AnsiString; Var Bn, Ch, Vs: AnsiString): Boolean;
    Var p1, p2: Integer;
    Begin
    p1 := Pos('.', X);
    Bn := ''; Ch := ''; Vs := '';
    If p1 = 0 Then
      Begin
      Bn := X;
      Split3 := True;
      Exit;
      End;
    Bn := Copy(X, 1, p1 - 1);
    p2 := Pos('.', Copy(X, p1 + 1, Length(X)));
    If p2 = 0 Then Ch := Copy(X, p1 + 1, Length(X))
    Else
      Begin
      Ch := Copy(X, p1 + 1, p2 - 1);
      Vs := Copy(X, p1 + p2 + 1, Length(X));
      End;
    Split3 := True;
    End;

  Var
    b1, c1, v1, b2n, c2, v2: AnsiString;
  Begin
  Res := '';
  Rem := Trim(R);
  While Rem <> '' Do
    Begin
    i := Pos(' ', Rem);
    If i = 0 Then i := Length(Rem) + 1;
    Item := Copy(Rem, 1, i - 1);
    Rem := Trim(Copy(Rem, i + 1, Length(Rem)));
    k := Pos('-', Item);
    If k = 0 Then A := Item Else A := Copy(Item, 1, k - 1);
    Split3(A, b1, c1, v1);
    Bk := OsisBookToNum(b1);
    If Bk > 0 Then One := BookInfo[Bk].Abbrev Else One := b1;
    If c1 <> '' Then One := One + ' ' + c1;
    If v1 <> '' Then One := One + ':' + v1;
    If k > 0 Then
      Begin
      B2 := Copy(Item, k + 1, Length(Item));
      Split3(B2, b2n, c2, v2);
      If (b2n = b1) And (c2 = c1) And (v2 <> '') Then One := One + '-' + v2
      Else If (b2n = b1) And (c2 <> '') And (v2 = '') Then One := One + '-' + c2
      Else If (b2n = b1) And (c2 <> '') And (v2 <> '') Then One := One + '-' + c2 + ':' + v2
      Else
        Begin
        Bk := OsisBookToNum(b2n);
        If Bk > 0 Then One := One + '-' + BookInfo[Bk].Abbrev Else One := One + '-' + b2n;
        If c2 <> '' Then One := One + ' ' + c2;
        If v2 <> '' Then One := One + ':' + v2;
        End;
      End;
    If Res <> '' Then Res := Res + '; ';
    Res := Res + One;
    End;
  MkpOsisToHuman := Res;
  End;

{ MySword <RX 43.3.16-18>: book.chapter.verse[-lastverse] with book 1..66 }
Function MySwordRefToOsis(Const R: AnsiString): AnsiString;
  Var
    p: Array[0..3] Of LongInt;
    n, i, j, Code: Integer;
    Part: AnsiString;
    S: AnsiString;
  Begin
  MySwordRefToOsis := '';
  S := Trim(R);
  n := 0;
  i := 1;
  While (i <= Length(S)) And (n < 4) Do
    Begin
    j := i;
    While (j <= Length(S)) And (S[j] In ['0'..'9']) Do Inc(j);
    If j = i Then Exit;
    Part := Copy(S, i, j - i);
    Val(Part, p[n], Code);
    Inc(n);
    i := j + 1;
    End;
  If (n < 3) Or (p[0] < 1) Or (p[0] > BibBooks) Then Exit;
  If (n = 4) And (p[3] > p[2]) Then MySwordRefToOsis := OsisOne(p[0], p[1], p[2], 0, p[3])
  Else MySwordRefToOsis := OsisOne(p[0], p[1], p[2], 0, 0);
  End;

{ OSIS ref -> MySword 43.3.16[-18]; '' if it cannot be expressed (several refs, cross-book ranges) }
Function OsisToMySwordRef(Const R: AnsiString): AnsiString;
  Var
    A, B2: AnsiString;
    k: Integer;
    f1, f2: Array[0..2] Of AnsiString;

  Procedure Split(Const X: AnsiString; Var F: Array Of AnsiString);
    Var p1, p2: Integer;
    Begin
    F[0] := ''; F[1] := ''; F[2] := '';
    p1 := Pos('.', X);
    If p1 = 0 Then Begin F[0] := X; Exit; End;
    F[0] := Copy(X, 1, p1 - 1);
    p2 := Pos('.', Copy(X, p1 + 1, Length(X)));
    If p2 = 0 Then F[1] := Copy(X, p1 + 1, Length(X))
    Else
      Begin
      F[1] := Copy(X, p1 + 1, p2 - 1);
      F[2] := Copy(X, p1 + p2 + 1, Length(X));
      End;
    End;

  Var Bk: Integer;
  Begin
  OsisToMySwordRef := '';
  If (R = '') Or (Pos(' ', Trim(R)) > 0) Then Exit;
  k := Pos('-', R);
  If k = 0 Then A := R Else A := Copy(R, 1, k - 1);
  Split(A, f1);
  Bk := OsisBookToNum(f1[0]);
  If (Bk = 0) Or (f1[1] = '') Or (f1[2] = '') Then Exit;
  OsisToMySwordRef := IntToStr(Bk) + '.' + f1[1] + '.' + f1[2];
  If k > 0 Then
    Begin
    B2 := Copy(R, k + 1, Length(R));
    Split(B2, f2);
    If (f2[0] = f1[0]) And (f2[1] = f1[1]) And (f2[2] <> '') Then
      OsisToMySwordRef := OsisToMySwordRef + '-' + f2[2];
    End;
  End;


{==================================================================== normalising}

Function IsWS(C: Char): Boolean;
  Begin
  IsWS := C In [' ', #9, #10, #13];
  End;

Function IsBreak(K: TEvKind): Boolean;
  Begin
  IsBreak := K In [ekPara, ekLine];
  End;

{ Tidy the event list: merge text, collapse white space, merge breaks, drop empty pairs,
  trim the ends, and give cross references without a reference one derived from their text. }
Procedure Normalize(Var D: TDoc);
  Var
    O: TDoc;
    i, j, k: Integer;
    T: AnsiString;
    LastSpace: Boolean;       {output so far ends in a blank / break / start}
    Pending: Integer;         {a break waiting to be written: 0 none, 1 line, 2 paragraph}
    Started: Boolean;         {some visible content has been written}
    Ev: TEv;
    Collect: AnsiString;
    Saved: Array[0..31] Of Boolean;     {outer white space state while inside a note / heading}
    SDepth: Integer;

  Procedure FlushBreak;
    Begin
    If (Pending > 0) And Started Then
      Begin
      If Pending = 2 Then Add(O, ekPara) Else Add(O, ekLine);
      End;
    Pending := 0;
    End;

  Begin
  O.N := 0;
  SetLength(O.Ev, D.N + 8);
  LastSpace := True;
  Pending := 0;
  Started := False;
  SDepth := 0;
  For i := 0 To D.N - 1 Do
    Begin
    Ev := D.Ev[i];
    { text inside a note or heading is a separate stream: it must not decide whether the text
      after it needs a blank (plain text drops it) }
    If Ev.Kind In [ekNoteOn, ekHeadOn] Then
      Begin
      If SDepth < 32 Then Saved[SDepth] := LastSpace;
      Inc(SDepth);
      End;
    Case Ev.Kind Of
      ekText:
        Begin
        T := '';
        For j := 1 To Length(Ev.Txt) Do
          If IsWS(Ev.Txt[j]) Then
            Begin
            If Not LastSpace Then
              Begin
              T := T + ' ';
              LastSpace := True;
              End;
            End
          Else
            Begin
            If Pending > 0 Then
              Begin
              If T <> '' Then
                Begin
                If (O.N > 0) And (O.Ev[O.N - 1].Kind = ekText) Then O.Ev[O.N - 1].Txt := O.Ev[O.N - 1].Txt + T
                Else Add(O, ekText, T);
                T := '';
                End;
              FlushBreak;
              End;
            T := T + Ev.Txt[j];
            LastSpace := False;
            Started := True;
            End;
        If T <> '' Then
          Begin
          If (O.N > 0) And (O.Ev[O.N - 1].Kind = ekText) Then O.Ev[O.N - 1].Txt := O.Ev[O.N - 1].Txt + T
          Else Add(O, ekText, T);
          End;
        End;
      ekPara, ekLine:
        Begin
        { a break inside a note or heading stays inside it: it must not leak out after it }
        If (Started) And (SDepth = 0) Then
          Begin
          If Ev.Kind = ekPara Then Pending := 2
          Else If Pending < 1 Then Pending := 1;
          LastSpace := True;
          { a blank just before the break is not needed (look back past closing events) }
          k := O.N - 1;
          While (k >= 0) And (O.Ev[k].Kind In [ekItalicOff, ekBoldOff, ekJesusOff, ekXrefOff, ekWordOff]) Do Dec(k);   {not past a note / heading: separate text}
          If (k >= 0) And (O.Ev[k].Kind = ekText) Then
            Begin
            T := O.Ev[k].Txt;
            While (T <> '') And (T[Length(T)] = ' ') Do SetLength(T, Length(T) - 1);
            If T = '' Then
              Begin
              For j := k To O.N - 2 Do O.Ev[j] := O.Ev[j + 1];
              Dec(O.N);
              End
            Else O.Ev[k].Txt := T;
            End;
          End;
        End;
      Else
        Begin
        { a structural event; the "On" ones may not come before a pending break }
        If Ev.Kind In [ekItalicOn, ekBoldOn, ekJesusOn, ekNoteOn, ekXrefOn, ekHeadOn, ekWordOn] Then FlushBreak;
        { a note or heading does not end in a blank }
        If (Ev.Kind In [ekNoteOff, ekHeadOff]) And (O.N > 0) And (O.Ev[O.N - 1].Kind = ekText) Then
          Begin
          T := O.Ev[O.N - 1].Txt;
          While (T <> '') And (T[Length(T)] = ' ') Do SetLength(T, Length(T) - 1);
          If T = '' Then Dec(O.N) Else O.Ev[O.N - 1].Txt := T;
          End;
        Add(O, Ev.Kind, Ev.Txt, Ev.Num);
        O.Ev[O.N - 1].Strong := Ev.Strong;
        O.Ev[O.N - 1].Morph := Ev.Morph;
        End;
    End;
    If Ev.Kind In [ekNoteOn, ekHeadOn] Then LastSpace := True;   {fresh stream inside}
    If Ev.Kind In [ekNoteOff, ekHeadOff] Then
      Begin
      If SDepth > 0 Then Dec(SDepth);
      If SDepth < 32 Then LastSpace := Saved[SDepth];
      End;
    End;
  { trailing blanks: nothing visible after the last non-blank text }
  k := O.N - 1;
  While (k >= 0) And (O.Ev[k].Kind In [ekItalicOff, ekBoldOff, ekJesusOff, ekXrefOff, ekWordOff]) Do Dec(k);
  If (k >= 0) And (O.Ev[k].Kind = ekText) Then
    Begin
    T := O.Ev[k].Txt;
    While (T <> '') And (T[Length(T)] = ' ') Do SetLength(T, Length(T) - 1);
    If T = '' Then
      Begin
      For j := k To O.N - 2 Do O.Ev[j] := O.Ev[j + 1];
      Dec(O.N);
      End
    Else O.Ev[k].Txt := T;
    End;
  { second pass: drop empty on/off pairs, derive missing references }
  D.N := 0;
  For i := 0 To O.N - 1 Do
    Begin
    Ev := O.Ev[i];
    If (Ev.Kind In [ekItalicOff, ekBoldOff, ekJesusOff, ekNoteOff, ekHeadOff, ekWordOff, ekXrefOff]) And (D.N > 0) And
       (Ord(D.Ev[D.N - 1].Kind) = Ord(Ev.Kind) - 1) Then
      Begin
      Dec(D.N);                 {the matching On was the previous event: an empty element}
      Continue;
      End;
    { two spans of the same style that touch (or only a blank between them) are one span:
      "<FR>For<Fr><FR> God<Fr>" is red letter text, not two pieces of it }
    If Ev.Kind In [ekJesusOn, ekItalicOn, ekBoldOn] Then
      Begin
      If (D.N > 0) And (Ord(D.Ev[D.N - 1].Kind) = Ord(Ev.Kind) + 1) Then
        Begin
        Dec(D.N);
        Continue;
        End;
      If (D.N > 1) And (D.Ev[D.N - 1].Kind = ekText) And (Trim(D.Ev[D.N - 1].Txt) = '') And
         (Ord(D.Ev[D.N - 2].Kind) = Ord(Ev.Kind) + 1) Then
        Begin
        D.Ev[D.N - 2] := D.Ev[D.N - 1];
        Dec(D.N);
        Continue;
        End;
      End;
    If D.N >= Length(D.Ev) Then SetLength(D.Ev, D.N * 2 + 16);
    D.Ev[D.N] := Ev;
    Inc(D.N);
    End;
  For i := 0 To D.N - 1 Do
    If (D.Ev[i].Kind = ekXrefOn) And (D.Ev[i].Txt = '') Then
      Begin
      Collect := '';
      k := i + 1;
      While (k < D.N) And (D.Ev[k].Kind <> ekXrefOff) Do
        Begin
        If D.Ev[k].Kind = ekText Then Collect := Collect + D.Ev[k].Txt;
        Inc(k);
        End;
      D.Ev[i].Txt := MkpHumanToOsis(Collect);
      End;
  End;


{ Merge spans of the same style that touch, or only have a blank between them. }
Procedure MergeSpans(Var D: TDoc);
  Var
    O: TDoc;
    i: Integer;
    Ev: TEv;
  Begin
  O.N := 0;
  SetLength(O.Ev, D.N + 4);
  For i := 0 To D.N - 1 Do
    Begin
    Ev := D.Ev[i];
    If Ev.Kind In [ekJesusOn, ekItalicOn, ekBoldOn] Then
      Begin
      If (O.N > 0) And (Ord(O.Ev[O.N - 1].Kind) = Ord(Ev.Kind) + 1) Then
        Begin
        Dec(O.N);
        Continue;
        End;
      If (O.N > 1) And (O.Ev[O.N - 1].Kind = ekText) And (Trim(O.Ev[O.N - 1].Txt) = '') And
         (Ord(O.Ev[O.N - 2].Kind) = Ord(Ev.Kind) + 1) Then
        Begin
        O.Ev[O.N - 2] := O.Ev[O.N - 1];
        Dec(O.N);
        Continue;
        End;
      End;
    If O.N >= Length(O.Ev) Then SetLength(O.Ev, O.N * 2 + 16);
    O.Ev[O.N] := Ev;
    Inc(O.N);
    End;
  D := O;
  End;

{ Make the on / off events balance: an off with no matching on is dropped, what is still open at the end
  (words of Jesus that run on into the next verse, a note cut off by the end of the text) is closed.
  Every verse is translated on its own, so this keeps the written markup well formed. }
Procedure Balance(Var D: TDoc);
  Var
    O: TDoc;
    Stack: Array Of TEvKind;      {the "off" kind each open "on" is waiting for}
    N, i, k, Top: Integer;
    Ev: TEv;
    Off: TEvKind;
    IsOn, IsOff: Boolean;

  Procedure Put(Const E: TEv);
    Begin
    If O.N >= Length(O.Ev) Then SetLength(O.Ev, O.N * 2 + 16);
    O.Ev[O.N] := E;
    Inc(O.N);
    End;

  Procedure PutKind(K: TEvKind);
    Var E: TEv;
    Begin
    E.Kind := K; E.Txt := ''; E.Strong := ''; E.Morph := ''; E.Num := 0;
    Put(E);
    End;

  Begin
  O.N := 0;
  SetLength(O.Ev, D.N + 8);
  SetLength(Stack, 16);
  Top := 0;
  For i := 0 To D.N - 1 Do
    Begin
    Ev := D.Ev[i];
    IsOn := True;
    Case Ev.Kind Of
      ekItalicOn: Off := ekItalicOff;
      ekBoldOn: Off := ekBoldOff;
      ekJesusOn: Off := ekJesusOff;
      ekNoteOn: Off := ekNoteOff;
      ekXrefOn: Off := ekXrefOff;
      ekHeadOn: Off := ekHeadOff;
      ekWordOn: Off := ekWordOff;
      Else IsOn := False;
    End;
    IsOff := Ev.Kind In [ekItalicOff, ekBoldOff, ekJesusOff, ekNoteOff, ekXrefOff, ekHeadOff, ekWordOff];
    If IsOn Then
      Begin
      If Top >= Length(Stack) Then SetLength(Stack, Top * 2);
      Stack[Top] := Off;
      Inc(Top);
      Put(Ev);
      End
    Else If IsOff Then
      Begin
      k := Top - 1;
      While (k >= 0) And (Stack[k] <> Ev.Kind) Do Dec(k);
      If k >= 0 Then
        Begin
        While Top - 1 > k Do Begin Dec(Top); PutKind(Stack[Top]); End;       {close what was opened inside it}
        Dec(Top);
        Put(Ev);
        End;                                                                   {no matching on: dropped}
      End
    Else Put(Ev);
    End;
  While Top > 0 Do Begin Dec(Top); PutKind(Stack[Top]); End;
  D := O;
  End;

{==================================================================== parsers}

Type
  TOpen = Record
    Name: AnsiString;
    Off: TEvKind;           {event to emit when it closes}
    HasOff: Boolean;
    Marker: AnsiString;     {OSIS q: marker to print at the close}
    HasMarker: Boolean;
  End;

  TStack = Record
    N: Integer;
    A: Array Of TOpen;
  End;

Procedure Push(Var S: TStack; Const Name: AnsiString; Off: TEvKind; HasOff: Boolean);
  Begin
  If S.N >= Length(S.A) Then SetLength(S.A, S.N * 2 + 8);
  S.A[S.N].Name := Name;
  S.A[S.N].Off := Off;
  S.A[S.N].HasOff := HasOff;
  S.A[S.N].Marker := '';
  S.A[S.N].HasMarker := False;
  Inc(S.N);
  End;

{ Close the open element called Name (and anything opened inside it that never closed) }
Procedure PopTo(Var D: TDoc; Var S: TStack; Const Name: AnsiString);
  Var i, j: Integer;
  Begin
  i := S.N - 1;
  While (i >= 0) And (S.A[i].Name <> Name) Do Dec(i);
  If i < 0 Then Exit;
  For j := S.N - 1 DownTo i Do
    If S.A[j].HasOff Then Add(D, S.A[j].Off);
  S.N := i;
  End;

{ Make the last word before here carry Strong's number(s) / morphology.  The word is the last run
  of non-blank text; footnotes and closing events (italic off, ...) after it are skipped, so
  "word<note>..</note><sync .../>" and "<i>word</i><WG1>" find their word. }
Procedure AttachWord(Var D: TDoc; Const Strong, Morph: AnsiString);
  Var
    i, j, p, q, depth, k, TailN: Integer;
    T, Before, W, After: AnsiString;
    Tail: Array Of TEv;
  Begin
  If (Strong = '') And (Morph = '') Then Exit;
  i := D.N - 1;
  { skip blanks, closing events and whole notes between the tag and its word }
  j := i;
  While j >= 0 Do
    Begin
    Case D.Ev[j].Kind Of
      ekItalicOff, ekBoldOff, ekJesusOff, ekXrefOff, ekHeadOff:
        Dec(j);
      ekNoteOff:
        Begin
        depth := 1;
        Dec(j);
        While (j >= 0) And (depth > 0) Do
          Begin
          If D.Ev[j].Kind = ekNoteOff Then Inc(depth)
          Else If D.Ev[j].Kind = ekNoteOn Then Dec(depth);
          Dec(j);
          End;
        End;
      ekText:
        If Trim(D.Ev[j].Txt) = '' Then Dec(j) Else Break;
      Else Break;
    End;
    End;
  If j < 0 Then Exit;
  { already a word: add to it }
  If D.Ev[j].Kind = ekWordOff Then
    Begin
    p := j - 1;
    While (p >= 0) And (D.Ev[p].Kind <> ekWordOn) Do Dec(p);
    If p >= 0 Then
      Begin
      If Strong <> '' Then
        Begin
        If D.Ev[p].Strong <> '' Then D.Ev[p].Strong := D.Ev[p].Strong + ' ';
        D.Ev[p].Strong := D.Ev[p].Strong + Strong;
        End;
      If Morph <> '' Then
        Begin
        If D.Ev[p].Morph <> '' Then D.Ev[p].Morph := D.Ev[p].Morph + ' ';
        D.Ev[p].Morph := D.Ev[p].Morph + Morph;
        End;
      End;
    Exit;
    End;
  If D.Ev[j].Kind <> ekText Then Exit;
  { split the text event into: before, WORD, after; events after it stay after the word }
  T := D.Ev[j].Txt;
  q := Length(T);
  While (q > 0) And IsWS(T[q]) Do Dec(q);
  p := q;
  While (p > 0) And (Not IsWS(T[p])) Do Dec(p);
  Before := Copy(T, 1, p);
  W := Copy(T, p + 1, q - p);
  After := Copy(T, q + 1, Length(T));
  TailN := D.N - 1 - j;
  SetLength(Tail, TailN);
  For k := 0 To TailN - 1 Do Tail[k] := D.Ev[j + 1 + k];
  D.N := j;
  If Before <> '' Then Add(D, ekText, Before);
  Add(D, ekWordOn);
  D.Ev[D.N - 1].Strong := Strong;
  D.Ev[D.N - 1].Morph := Morph;
  Add(D, ekText, W);
  Add(D, ekWordOff);
  If After <> '' Then Add(D, ekText, After);
  For k := 0 To TailN - 1 Do
    Begin
    If D.N >= Length(D.Ev) Then SetLength(D.Ev, D.N * 2 + 16);
    D.Ev[D.N] := Tail[k];
    Inc(D.N);
    End;
  End;

Function StripZeros(Const S: AnsiString): AnsiString;
  { H0430 -> H430, G0026 -> G26;  anything else unchanged }
  Var i: Integer;
  Begin
  StripZeros := S;
  If (Length(S) > 1) And (S[1] In ['G', 'H', 'g', 'h']) Then
    Begin
    i := 2;
    While (i < Length(S)) And (S[i] = '0') Do Inc(i);
    StripZeros := UpCase(S[1]) + Copy(S, i, Length(S));
    End;
  End;

{ ---- OSIS ---- }
Procedure ParseOSIS(Const S: AnsiString; Var D: TDoc);
  Var
    Pos_: Integer;
    IsTag: Boolean;
    Txt, V, Mk, Lem, Tok, Mor, StrongL, MorphL: AnsiString;
    T: TTag;
    St: TStack;
    i, k: Integer;
    Lvl: Integer;
    HasM: Boolean;

  Procedure Words(Const L: AnsiString; Prefix: Boolean; Var Outp: AnsiString);
    { split a blank separated list of prefix:value tokens }
    Var Rem, One: AnsiString; p: Integer;
    Begin
    Rem := Trim(L);
    While Rem <> '' Do
      Begin
      p := Pos(' ', Rem);
      If p = 0 Then p := Length(Rem) + 1;
      One := Copy(Rem, 1, p - 1);
      Rem := Trim(Copy(Rem, p + 1, Length(Rem)));
      If Outp <> '' Then Outp := Outp + ' ';
      Outp := Outp + One;
      End;
    End;

  Begin
  St.N := 0;
  Pos_ := 1;
  While NextToken(S, Pos_, IsTag, Txt) Do
    Begin
    If Not IsTag Then
      Begin
      Add(D, ekText, DecodeEntities(Txt));
      Continue;
      End;
    SplitTag(Txt, False, T);
    If (T.Name = '') Or (T.Name[1] In ['!', '?']) Then Continue;
    If T.Close Then
      Begin
      If T.Name = 'q' Then
        Begin
        { </q>: print the marker of the opening tag, as Sword does }
        i := St.N - 1;
        While (i >= 0) And (St.A[i].Name <> 'q') Do Dec(i);
        If (i >= 0) And St.A[i].HasMarker And (St.A[i].Marker <> '') Then Add(D, ekText, St.A[i].Marker);
        End;
      PopTo(D, St, T.Name);
      Continue;
      End;

    { ---- opening or empty tags ---- }
    If T.Name = 'w' Then
      Begin
      StrongL := ''; MorphL := '';
      If Attr(T.Attrs, 'lemma', V) Then
        Begin
        Lem := '';
        Words(V, False, Lem);
        While Lem <> '' Do
          Begin
          k := Pos(' ', Lem);
          If k = 0 Then k := Length(Lem) + 1;
          Tok := Copy(Lem, 1, k - 1);
          Lem := Trim(Copy(Lem, k + 1, Length(Lem)));
          If LowerCase(Copy(Tok, 1, 7)) = 'strong:' Then
            Begin
            If StrongL <> '' Then StrongL := StrongL + ' ';
            StrongL := StrongL + StripZeros(Copy(Tok, 8, Length(Tok)));
            End;
          End;
        End;
      If Attr(T.Attrs, 'morph', V) Then Words(V, False, MorphL);
      If T.Empty Then Continue;
      PopTo(D, St, 'w');            {words do not nest: an unclosed <w> ends where the next one starts}
      If (StrongL <> '') Or (MorphL <> '') Then
        Begin
        Add(D, ekWordOn);
        D.Ev[D.N - 1].Strong := StrongL;
        D.Ev[D.N - 1].Morph := MorphL;
        Push(St, 'w', ekWordOff, True);
        End
      Else Push(St, 'w', ekWordOff, False);
      End
    Else If T.Name = 'note' Then
      Begin
      If T.Empty Then Continue;
      Attr(T.Attrs, 'type', V);
      If (V = 'crossReference') Or (V = 'x-cross-ref') Then k := 1 Else k := 0;
      Add(D, ekNoteOn, '', k);
      Push(St, 'note', ekNoteOff, True);
      End
    Else If T.Name = 'reference' Then
      Begin
      If T.Empty Then Continue;
      If Attr(T.Attrs, 'osisRef', V) And (V <> '') Then
        Begin
        Add(D, ekXrefOn, V);
        Push(St, 'reference', ekXrefOff, True);
        End
      Else Push(St, 'reference', ekXrefOff, False);
      End
    Else If T.Name = 'hi' Then
      Begin
      If T.Empty Then Continue;
      Attr(T.Attrs, 'type', V);
      If (V = 'italic') Or (V = 'i') Or (V = 'emphasis') Then
        Begin Add(D, ekItalicOn); Push(St, 'hi', ekItalicOff, True); End
      Else If (V = 'bold') Or (V = 'b') Then
        Begin Add(D, ekBoldOn); Push(St, 'hi', ekBoldOff, True); End
      Else Push(St, 'hi', ekItalicOff, False);
      End
    Else If T.Name = 'transChange' Then
      Begin
      If T.Empty Then Continue;
      Attr(T.Attrs, 'type', V);
      If (V = 'added') Or (V = 'supplied') Then
        Begin Add(D, ekItalicOn); Push(St, 'transChange', ekItalicOff, True); End
      Else Push(St, 'transChange', ekItalicOff, False);
      End
    Else If T.Name = 'q' Then
      Begin
      HasM := Attr(T.Attrs, 'marker', Mk);
      Attr(T.Attrs, 'who', V);
      If T.Empty Then
        Begin
        { milestone form: sID opens, eID closes }
        If Attr(T.Attrs, 'sID', Lem) Then
          Begin
          If V = 'Jesus' Then Add(D, ekJesusOn);
          If HasM And (Mk <> '') Then Add(D, ekText, Mk);
          End
        Else If Attr(T.Attrs, 'eID', Lem) Then
          Begin
          If HasM And (Mk <> '') Then Add(D, ekText, Mk);
          If V = 'Jesus' Then Add(D, ekJesusOff);
          End;
        End
      Else
        Begin
        If V = 'Jesus' Then Add(D, ekJesusOn);
        If HasM And (Mk <> '') Then Add(D, ekText, Mk);
        Push(St, 'q', ekJesusOff, V = 'Jesus');
        St.A[St.N - 1].Marker := Mk;
        St.A[St.N - 1].HasMarker := HasM;
        End;
      End
    Else If T.Name = 'title' Then
      Begin
      If T.Empty Then Continue;
      Attr(T.Attrs, 'type', V);
      If V = 'main' Then Lvl := 1 Else If (V = 'sub') Or (V = 'x-sub') Then Lvl := 3 Else Lvl := 2;
      Add(D, ekHeadOn, '', Lvl);
      Push(St, 'title', ekHeadOff, True);
      End
    Else If T.Name = 'p' Then
      Begin
      If T.Empty Then Continue;
      Attr(T.Attrs, 'type', V);
      If (Copy(V, 1, 4) = 'x-ms') Or (V = 'x-s') Or (V = 'x-sr') Then
        Begin
        Add(D, ekHeadOn, '', 2);
        Push(St, 'p', ekHeadOff, True);
        End
      Else
        Begin
        Add(D, ekPara);
        Push(St, 'p', ekLine, False);
        End;
      End
    Else If T.Name = 'lb' Then
      Begin
      Attr(T.Attrs, 'type', V);
      If (V = 'x-begin-paragraph') Or (V = 'x-p') Then Add(D, ekPara)
      Else If V = 'x-end-paragraph' Then
      Else Add(D, ekLine);
      If Not T.Empty Then Push(St, 'lb', ekLine, False);
      End
    Else If T.Name = 'l' Then
      Begin
      { poetry line: sID / plain open start a line, eID ends it }
      If Not Attr(T.Attrs, 'eID', V) Then Add(D, ekLine);
      If Not T.Empty Then Push(St, 'l', ekLine, False);
      End
    Else If T.Name = 'item' Then
      Begin
      Add(D, ekLine);
      If Not T.Empty Then Push(St, 'item', ekLine, False);
      End
    Else If T.Name = 'div' Then
      Begin
      Attr(T.Attrs, 'type', V);
      If ((V = 'paragraph') Or (V = 'x-p')) And (Not Attr(T.Attrs, 'eID', Lem)) Then Add(D, ekPara);
      If Not T.Empty Then Push(St, 'div', ekLine, False);
      End
    Else If T.Name = 'milestone' Then
      Begin
      Attr(T.Attrs, 'type', V);
      HasM := Attr(T.Attrs, 'marker', Mk);
      If V = 'line' Then
        Begin
        Add(D, ekLine);
        If Attr(T.Attrs, 'subType', Lem) And (Lem = 'x-PM') Then Add(D, ekPara);
        End
      Else If V = 'x-p' Then
        Begin
        If HasM And (Mk <> '') Then Add(D, ekText, Mk) Else Add(D, ekPara);
        End
      Else If V = 'cQuote' Then
        Begin
        If HasM And (Mk <> '') Then Add(D, ekText, Mk);
        End;
      If Not T.Empty Then Push(St, 'milestone', ekLine, False);
      End
    Else If Not T.Empty Then
      Push(St, T.Name, ekLine, False);        {unknown element: keep its text, drop the tag}
    End;
  { close anything left open }
  For i := St.N - 1 DownTo 0 Do
    If St.A[i].HasOff Then Add(D, St.A[i].Off);
  End;

{ ---- ThML ---- }
Procedure ParseThML(Const S: AnsiString; Var D: TDoc);
  Var
    Pos_: Integer;
    IsTag: Boolean;
    Txt, V, V2: AnsiString;
    T: TTag;
    St: TStack;
    i, k: Integer;
  Begin
  St.N := 0;
  Pos_ := 1;
  While NextToken(S, Pos_, IsTag, Txt) Do
    Begin
    If Not IsTag Then
      Begin
      Add(D, ekText, DecodeEntities(Txt));
      Continue;
      End;
    SplitTag(Txt, True, T);
    If (T.Name = '') Or (T.Name[1] In ['!', '?']) Then Continue;
    If T.Close Then
      Begin
      PopTo(D, St, T.Name);
      Continue;
      End;
    If T.Name = 'p' Then
      Begin
      Add(D, ekPara);
      If Not T.Empty Then Push(St, 'p', ekLine, False);
      End
    Else If T.Name = 'br' Then
      Add(D, ekLine)
    Else If (T.Name = 'i') Or (T.Name = 'em') Or (T.Name = 'added') Then
      Begin
      If T.Empty Then Continue;
      Add(D, ekItalicOn);
      Push(St, T.Name, ekItalicOff, True);
      End
    Else If (T.Name = 'b') Or (T.Name = 'strong') Then
      Begin
      If T.Empty Then Continue;
      Add(D, ekBoldOn);
      Push(St, T.Name, ekBoldOff, True);
      End
    Else If T.Name = 'note' Then
      Begin
      If T.Empty Then Continue;
      Attr(T.Attrs, 'type', V);
      If (V = 'crossReference') Or (V = 'x-cross-ref') Then k := 1 Else k := 0;
      Add(D, ekNoteOn, '', k);
      Push(St, 'note', ekNoteOff, True);
      End
    Else If T.Name = 'scripref' Then
      Begin
      If T.Empty Then Continue;
      If Attr(T.Attrs, 'passage', V) Then V2 := MkpHumanToOsis(V) Else V2 := '';
      If V2 = '' Then
        Begin
        If Attr(T.Attrs, 'osisref', V) Then V2 := V;
        End;
      Add(D, ekXrefOn, V2);
      Push(St, 'scripref', ekXrefOff, True);
      End
    Else If T.Name = 'sync' Then
      Begin
      Attr(T.Attrs, 'type', V);
      If Attr(T.Attrs, 'value', V2) Then
        Begin
        If LowerCase(V) = 'strongs' Then AttachWord(D, StripZeros(Trim(V2)), '')
        Else If LowerCase(V) = 'morph' Then AttachWord(D, '', Trim(V2));
        End;
      End
    Else If (Length(T.Name) = 2) And (T.Name[1] = 'h') And (T.Name[2] In ['1'..'6']) Then
      Begin
      If T.Empty Then Continue;
      Add(D, ekHeadOn, '', Ord(T.Name[2]) - Ord('0'));
      Push(St, T.Name, ekHeadOff, True);
      End
    Else If T.Name = 'div' Then
      Begin
      If T.Empty Then Continue;
      If Attr(T.Attrs, 'class', V) And ((LowerCase(V) = 'sechead') Or (LowerCase(V) = 'title')) Then
        Begin
        Add(D, ekHeadOn, '', 2);
        Push(St, 'div', ekHeadOff, True);
        End
      Else Push(St, 'div', ekLine, False);
      End
    Else If Not T.Empty Then
      Push(St, T.Name, ekLine, False);
    End;
  For i := St.N - 1 DownTo 0 Do
    If St.A[i].HasOff Then Add(D, St.A[i].Off);
  End;

{ ---- GBF and MySword (case sensitive tags like <FI> ... <Fi>) ---- }
Procedure ParseGBF(Const S: AnsiString; Var D: TDoc; MySword: Boolean; TheWord: Boolean = False);
  Var
    Pos_: Integer;
    IsTag: Boolean;
    Txt, Tg, Rest, Osis: AnsiString;
    T: TTag;
    i, Lvl: Integer;
    NoteOpen, HeadOpen, ItOpen, BoldOpen, JesusOpen, XrefOpen: Integer;
  Begin
  NoteOpen := 0; HeadOpen := 0; ItOpen := 0; BoldOpen := 0; JesusOpen := 0; XrefOpen := 0;
  Pos_ := 1;
  While NextToken(S, Pos_, IsTag, Txt) Do
    Begin
    If Not IsTag Then
      Begin
      Add(D, ekText, DecodeEntities(Txt));
      Continue;
      End;
    Tg := Txt;
    If Tg = '' Then Continue;
    If Tg = 'FI' Then Begin Add(D, ekItalicOn); Inc(ItOpen); End
    Else If Tg = 'Fi' Then Begin If ItOpen > 0 Then Begin Add(D, ekItalicOff); Dec(ItOpen); End; End
    Else If Tg = 'FB' Then Begin Add(D, ekBoldOn); Inc(BoldOpen); End
    Else If Tg = 'Fb' Then Begin If BoldOpen > 0 Then Begin Add(D, ekBoldOff); Dec(BoldOpen); End; End
    Else If Tg = 'FR' Then Begin Add(D, ekJesusOn); Inc(JesusOpen); End
    Else If Tg = 'Fr' Then Begin If JesusOpen > 0 Then Begin Add(D, ekJesusOff); Dec(JesusOpen); End; End
    Else If (Tg = 'RF') Or (Copy(Tg, 1, 3) = 'RF ') Then Begin Add(D, ekNoteOn, '', 0); Inc(NoteOpen); End
    Else If Tg = 'Rf' Then Begin If NoteOpen > 0 Then Begin Add(D, ekNoteOff); Dec(NoteOpen); End; End
    Else If (Tg = 'TS') Or (Tg = 'TH') Then Begin Add(D, ekHeadOn, '', 2); Inc(HeadOpen); End
    Else If (Length(Tg) = 3) And (Copy(Tg, 1, 2) = 'TS') And (Tg[3] In ['1'..'3']) Then
      Begin Add(D, ekHeadOn, '', Ord(Tg[3]) - Ord('0')); Inc(HeadOpen); End
    Else If (Tg = 'Ts') Or (Tg = 'Th') Then Begin If HeadOpen > 0 Then Begin Add(D, ekHeadOff); Dec(HeadOpen); End; End
    Else If Tg = 'CM' Then Add(D, ekPara)
    Else If Tg = 'CL' Then Add(D, ekLine)
    Else If (Tg = 'CI') And TheWord Then Add(D, ekLine)       {theWord: a new (indented) poetry line}
    Else If Tg = 'RX' Then
      Begin
      If Not MySword Then Begin Add(D, ekXrefOn, ''); Inc(XrefOpen); End;
      End
    Else If (MySword) And (Copy(Tg, 1, 3) = 'RX ') Then
      Begin
      { <RX 43.3.16-18>: a cross reference without text: a note holding the reference }
      Osis := MySwordRefToOsis(Copy(Tg, 4, Length(Tg)));
      If Osis <> '' Then
        Begin
        Add(D, ekNoteOn, '', 1);
        Add(D, ekXrefOn, Osis);
        Add(D, ekText, MkpOsisToHuman(Osis));
        Add(D, ekXrefOff);
        Add(D, ekNoteOff);
        End;
      End
    Else If Tg = 'Rx' Then Begin If XrefOpen > 0 Then Begin Add(D, ekXrefOff); Dec(XrefOpen); End; End
    Else If (Copy(Tg, 1, 2) = 'WG') Or (Copy(Tg, 1, 2) = 'WH') Then
      Begin
      Rest := Trim(Copy(Tg, 3, Length(Tg)));
      If Rest <> '' Then AttachWord(D, StripZeros(Tg[2] + Rest), '');
      End
    Else If (Copy(Tg, 1, 2) = 'WT') Then
      Begin
      Rest := Trim(Copy(Tg, 3, Length(Tg)));
      { MySword: <WTN-NSM l="..."> ; GBF: <WTG1234> / <WTH8804> are Strong's tense, skip those }
      If (Rest <> '') And (Not ((Rest[1] In ['G', 'H']) And (Length(Rest) > 1) And (Rest[2] In ['0'..'9']))) Then
        Begin
        i := Pos(' l=', Rest);
        If i > 0 Then Rest := Copy(Rest, 1, i - 1);
        AttachWord(D, '', Rest);
        End;
      End
    Else If MySword Then
      Begin
      { the html style tags MySword also allows }
      SplitTag(Tg, True, T);
      If T.Name = 'br' Then Add(D, ekLine)
      Else If T.Name = 'p' Then Begin If Not T.Close Then Add(D, ekPara); End
      Else If T.Name = 'i' Then
        Begin
        If T.Close Then Begin If ItOpen > 0 Then Begin Add(D, ekItalicOff); Dec(ItOpen); End; End
        Else Begin Add(D, ekItalicOn); Inc(ItOpen); End;
        End
      Else If T.Name = 'b' Then
        Begin
        If T.Close Then Begin If BoldOpen > 0 Then Begin Add(D, ekBoldOff); Dec(BoldOpen); End; End
        Else Begin Add(D, ekBoldOn); Inc(BoldOpen); End;
        End;
      End;
    End;
  { close what was left open }
  While XrefOpen > 0 Do Begin Add(D, ekXrefOff); Dec(XrefOpen); End;
  While NoteOpen > 0 Do Begin Add(D, ekNoteOff); Dec(NoteOpen); End;
  While HeadOpen > 0 Do Begin Add(D, ekHeadOff); Dec(HeadOpen); End;
  While JesusOpen > 0 Do Begin Add(D, ekJesusOff); Dec(JesusOpen); End;
  While BoldOpen > 0 Do Begin Add(D, ekBoldOff); Dec(BoldOpen); End;
  While ItOpen > 0 Do Begin Add(D, ekItalicOff); Dec(ItOpen); End;
  End;


Const
  Cp1252Hi: Array[0..31] Of Word = (
    $20AC, $0081, $201A, $0192, $201E, $2026, $2020, $2021, $02C6, $2030, $0160, $2039, $0152, $008D, $017D, $008F,
    $0090, $2018, $2019, $201C, $201D, $2022, $2013, $2014, $02DC, $2122, $0161, $203A, $0153, $009D, $017E, $0178);

{ ---- RTF: STEP modules, theWord books and dictionaries ---- }
Procedure ParseSTEP(Const S: AnsiString; Var D: TDoc);
  Type
    TGroupKind = (gkPlain, gkSkip, gkNote, gkHead, gkLink, gkInst);
    TRState = Record
      Bold, Italic, Hidden, Super, Jesus: Boolean;
      Kind: TGroupKind;
    End;
  Var
    St: Array Of TRState;
    Top: Integer;
    Cur: TRState;
    OpenJ, OpenB, OpenI: Boolean;       {style events currently open}
    Buf: AnsiString;
    i, n: Integer;
    c: Char;
    Name_, Param: AnsiString;
    HasParam: Boolean;
    NumP: LongInt;
    LinkInst, LinkOsis: AnsiString;       {hyperlink field: its instruction text and the Bible reference it names}
    LinkMark: Boolean;
    LinkRef: AnsiString;
    i2: Integer;

  Procedure CloseStyles;
    Begin
    If OpenI Then Begin Add(D, ekItalicOff); OpenI := False; End;
    If OpenB Then Begin Add(D, ekBoldOff); OpenB := False; End;
    If OpenJ Then Begin Add(D, ekJesusOff); OpenJ := False; End;
    End;

  Procedure SyncStyles;
    Var WJ, WB, WI: Boolean;
    Begin
    WJ := Cur.Jesus And (Cur.Kind <> gkNote);
    WB := Cur.Bold And (Cur.Kind <> gkHead);
    WI := Cur.Italic;
    If (WJ <> OpenJ) Or (WB <> OpenB) Or (WI <> OpenI) Then
      Begin
      CloseStyles;               {close everything, reopen in a fixed order: the nesting stays proper}
      If WJ Then Begin Add(D, ekJesusOn); OpenJ := True; End;
      If WB Then Begin Add(D, ekBoldOn); OpenB := True; End;
      If WI Then Begin Add(D, ekItalicOn); OpenI := True; End;
      End;
    End;

  Procedure FlushText;
    Begin
    If Buf <> '' Then
      Begin
      SyncStyles;
      Add(D, ekText, Buf);
      Buf := '';
      End;
    End;

  Function Visible: Boolean;
    Begin
    Visible := (Cur.Kind <> gkSkip) And (Not Cur.Hidden) And (Not Cur.Super);
    End;

  Procedure PutStr(Const T: AnsiString);
    Begin
    If Cur.Kind = gkInst Then LinkInst := LinkInst + T
    Else If Visible Then Buf := Buf + T;
    End;

  Procedure PutCode(N: LongInt);
    Begin
    If N < 0 Then N := N + 65536;
    If N < $80 Then PutStr(Chr(N))
    Else If N < $800 Then PutStr(Chr($C0 Or (N Shr 6)) + Chr($80 Or (N And $3F)))
    Else PutStr(Chr($E0 Or (N Shr 12)) + Chr($80 Or ((N Shr 6) And $3F)) + Chr($80 Or (N And $3F)));
    End;

  Procedure PutByte(N: LongInt);
    Begin
    If (N >= $80) And (N <= $9F) Then PutCode(Cp1252Hi[N - $80])
    Else PutCode(N);
    End;

  Procedure Brk;
    Begin
    If Not Visible Then Exit;
    If Cur.Kind In [gkHead, gkNote] Then
      PutStr(' ')                    {a break inside a note or heading is just a blank}
    Else
      Begin
      FlushText;
      Add(D, ekLine);
      End;
    End;

  Procedure PushGroup;
    Begin
    If Top + 1 >= Length(St) Then SetLength(St, Length(St) * 2 + 8);
    St[Top] := Cur;
    Inc(Top);
    End;

  Procedure PopGroup;
    Begin
    If Top = 0 Then Exit;
    If Cur.Kind = gkNote Then Begin FlushText; CloseStyles; Add(D, ekNoteOff); End
    Else If Cur.Kind = gkHead Then Begin FlushText; CloseStyles; Add(D, ekHeadOff); End
    Else If Cur.Kind = gkLink Then
      Begin
      FlushText;
      CloseStyles;
      Add(D, ekXrefOff);
      LinkOsis := '';
      End
    Else If Cur.Kind = gkInst Then
      Begin
      { HYPERLINK "tw://bible.*?id=66.9.11": a Bible passage as book.chapter.verse }
      LinkOsis := '';
      i2 := Pos('tw://bible', LinkInst);
      If i2 > 0 Then
        Begin
        i2 := Pos('id=', LinkInst);
        If i2 > 0 Then
          Begin
          LinkRef := Copy(LinkInst, i2 + 3, Length(LinkInst));
          i2 := Pos('"', LinkRef);
          If i2 > 0 Then LinkRef := Copy(LinkRef, 1, i2 - 1);
          LinkOsis := MySwordRefToOsis(LinkRef);
          End;
        End;
      End;
    Dec(Top);
    Cur := St[Top];
    End;

  Procedure Control(Const W: AnsiString; HasP: Boolean; P: LongInt);
    Begin
    If W = 'par' Then Brk
    Else If (W = 'line') Or (W = 'row') Then Brk
    Else If (W = 'tab') Or (W = 'cell') Then PutStr(' ')
    Else If W = 'emdash' Then PutStr(#$E2#$80#$94)
    Else If W = 'endash' Then PutStr(#$E2#$80#$93)
    Else If W = 'lquote' Then PutStr(#$E2#$80#$98)
    Else If W = 'rquote' Then PutStr(#$E2#$80#$99)
    Else If W = 'ldblquote' Then PutStr(#$E2#$80#$9C)
    Else If W = 'rdblquote' Then PutStr(#$E2#$80#$9D)
    Else If W = 'bullet' Then PutStr(#$E2#$80#$A2)
    Else If W = 'plain' Then
      Begin
      Cur.Bold := False; Cur.Italic := False; Cur.Hidden := False; Cur.Super := False; Cur.Jesus := False;
      End
    Else If W = 'b' Then Cur.Bold := (Not HasP) Or (P <> 0)
    Else If W = 'i' Then Cur.Italic := (Not HasP) Or (P <> 0)
    Else If W = 'v' Then Cur.Hidden := (Not HasP) Or (P <> 0)
    Else If W = 'super' Then Cur.Super := True
    Else If W = 'nosupersub' Then Cur.Super := False
    Else If (W = 'fonttbl') Or (W = 'colortbl') Or (W = 'stylesheet') Or (W = 'info') Or (W = 'pict') Or
            (W = 'header') Or (W = 'footer') Or (W = 'generator') Or (W = 'listtable') Or (W = 'listoverridetable') Then
      Cur.Kind := gkSkip                                          {document header groups: no text}
    Else If W = 'fldrslt' Then
      Begin
      { the displayed result of a hyperlink field: if the instruction named a Bible passage it is a reference }
      If (LinkOsis <> '') And (Cur.Kind = gkPlain) Then
        Begin
        FlushText;
        CloseStyles;
        Add(D, ekXrefOn, LinkOsis);
        Cur.Kind := gkLink;
        End;
      End
    Else If W = 'cf' Then Cur.Jesus := HasP And (P = 6)       {STEP's colour table: 6 = red = words of Jesus}
    Else If W = 'u' Then
      Begin
      If HasP Then PutCode(P);
      { skip the one fallback character that follows \uN }
      If (i + 1 <= n) And (S[i] = '\') And (S[i + 1] = Chr(39)) Then Inc(i, 4)
      Else If i <= n Then Inc(i);
      End;
    End;

  Begin
  SetLength(St, 16);
  Top := 0;
  FillChar(Cur, SizeOf(Cur), 0);
  Cur.Kind := gkPlain;
  OpenJ := False; OpenB := False; OpenI := False;
  Buf := '';
  n := Length(S);
  i := 1;
  While i <= n Do
    Begin
    c := S[i];
    Inc(i);
    Case c Of
      '{':
        Begin
        PushGroup;
        { a group starting with \* is an ignorable destination unless it is one of ours }
        If (i + 1 <= n) And (S[i] = '\') And (S[i + 1] = '*') Then
          Begin
          i := i + 2;
          While (i <= n) And (S[i] = ' ') Do Inc(i);
          Name_ := '';
          If (i <= n) And (S[i] = '\') Then
            Begin
            Inc(i);
            While (i <= n) And (S[i] In ['a'..'z', 'A'..'Z']) Do Begin Name_ := Name_ + S[i]; Inc(i); End;
            If (i <= n) And (S[i] = ' ') Then Inc(i);
            End;
          If Name_ = 'stepnote' Then
            Begin
            FlushText;
            CloseStyles;
            Add(D, ekNoteOn, '', 0);
            Cur.Kind := gkNote;
            Cur.Bold := False; Cur.Italic := False; Cur.Jesus := False; Cur.Hidden := False; Cur.Super := False;
            End
          Else If Name_ = 'fldinst' Then
            Begin
            Cur.Kind := gkInst;                       {collect the field instruction instead of showing it}
            LinkInst := '';
            LinkOsis := '';
            End
          Else If Name_ = 'stephead' Then
            Begin
            FlushText;
            CloseStyles;
            Add(D, ekHeadOn, '', 2);
            Cur.Kind := gkHead;
            Cur.Bold := False; Cur.Italic := False; Cur.Jesus := False; Cur.Hidden := False; Cur.Super := False;
            End
          Else Cur.Kind := gkSkip;
          End;
        End;
      '}':
        Begin
        { a link whose text is the placeholder [vref] shows the reference it points to }
        If (Cur.Kind = gkLink) And (Buf = '[vref]') Then Buf := MkpOsisToHuman(LinkOsis);
        FlushText;
        PopGroup;
        End;
      #10, #13: ;                         {line ends in RTF files carry no meaning}
      '\':
        Begin
        If i > n Then Break;
        c := S[i];
        If c In ['a'..'z', 'A'..'Z'] Then
          Begin
          Name_ := '';
          While (i <= n) And (S[i] In ['a'..'z', 'A'..'Z']) Do Begin Name_ := Name_ + S[i]; Inc(i); End;
          Param := '';
          HasParam := False;
          If (i < n) And (S[i] = '-') And (S[i + 1] In ['0'..'9']) Then Begin Param := '-'; Inc(i); End;
          While (i <= n) And (S[i] In ['0'..'9']) Do Begin Param := Param + S[i]; Inc(i); HasParam := True; End;
          If (i <= n) And (S[i] = ' ') Then Inc(i);       {the delimiter blank belongs to the control word}
          NumP := 0;
          If HasParam Then NumP := StrToIntDef(Param, 0);
          { text collected so far has the old style: write it out before the style changes }
          If (Name_ = 'b') Or (Name_ = 'i') Or (Name_ = 'cf') Or (Name_ = 'plain') Or (Name_ = 'v') Or
             (Name_ = 'super') Or (Name_ = 'nosupersub') Or (Name_ = 'par') Or (Name_ = 'line') Then FlushText;
          Control(Name_, HasParam, NumP);
          End
        Else
          Begin
          Inc(i);
          Case c Of
            '\', '{', '}': PutStr(c);
            '~': PutStr(' ');
            Chr(39):
              Begin
              If i + 1 <= n Then
                Begin
                NumP := StrToIntDef('$' + Copy(S, i, 2), 32);
                Inc(i, 2);
                If NumP >= $80 Then PutByte(NumP) Else PutStr(Chr(NumP));
                End;
              End;
            #10, #13: Brk;               {a backslash before a line end is a paragraph}
            Else ;                       {\* \- \_ \| ... : ignored}
          End;
          End;
        End;
      Else
        PutStr(c);
    End;
    End;
  FlushText;
  While Top > 0 Do PopGroup;
  CloseStyles;
  End;


{ ---- light markup of verse-per-line files ---- }
Procedure ParseLight(Const S: AnsiString; Var D: TDoc);
  Var
    Pos_: Integer;
    IsTag: Boolean;
    Txt: AnsiString;
    T: TTag;
    Jn, Bn, In_: Integer;
  Begin
  Jn := 0; Bn := 0; In_ := 0;
  Pos_ := 1;
  While NextToken(S, Pos_, IsTag, Txt) Do
    Begin
    If Not IsTag Then
      Begin
      Add(D, ekText, DecodeEntities(Txt));
      Continue;
      End;
    SplitTag(Txt, True, T);
    If T.Name = 'red' Then
      Begin
      If Not T.Close Then Begin Add(D, ekJesusOn); Inc(Jn); End
      Else If Jn > 0 Then Begin Add(D, ekJesusOff); Dec(Jn); End;
      End
    Else If (T.Name = 'b') Or (T.Name = 'strong') Then
      Begin
      If Not T.Close Then Begin Add(D, ekBoldOn); Inc(Bn); End
      Else If Bn > 0 Then Begin Add(D, ekBoldOff); Dec(Bn); End;
      End
    Else If (T.Name = 'i') Or (T.Name = 'em') Then
      Begin
      If Not T.Close Then Begin Add(D, ekItalicOn); Inc(In_); End
      Else If In_ > 0 Then Begin Add(D, ekItalicOff); Dec(In_); End;
      End
    Else If T.Name = 'br' Then Add(D, ekLine)
    Else If (T.Name = 'p') And (Not T.Close) Then Add(D, ekPara);
    End;
  While In_ > 0 Do Begin Add(D, ekItalicOff); Dec(In_); End;
  While Bn > 0 Do Begin Add(D, ekBoldOff); Dec(Bn); End;
  While Jn > 0 Do Begin Add(D, ekJesusOff); Dec(Jn); End;
  End;


{ ---- HTML (MySword dictionaries and the like) ---- }
Procedure ParseHTML(Const S: AnsiString; Var D: TDoc);
  Var
    Pos_: Integer;
    IsTag: Boolean;
    Txt: AnsiString;
    T: TTag;
    Bn, In_, Skip: Integer;
  Begin
  Bn := 0; In_ := 0; Skip := 0;
  Pos_ := 1;
  While NextToken(S, Pos_, IsTag, Txt) Do
    Begin
    If Not IsTag Then
      Begin
      If Skip = 0 Then Add(D, ekText, DecodeEntities(Txt));
      Continue;
      End;
    SplitTag(Txt, True, T);
    If (T.Name = 'script') Or (T.Name = 'style') Then
      Begin
      If T.Close Then Begin If Skip > 0 Then Dec(Skip); End
      Else If Not T.Empty Then Inc(Skip);
      End
    Else If Skip > 0 Then
    Else If (T.Name = 'b') Or (T.Name = 'strong') Then
      Begin
      If Not T.Close Then Begin Add(D, ekBoldOn); Inc(Bn); End
      Else If Bn > 0 Then Begin Add(D, ekBoldOff); Dec(Bn); End;
      End
    Else If (T.Name = 'i') Or (T.Name = 'em') Or (T.Name = 'cite') Then
      Begin
      If Not T.Close Then Begin Add(D, ekItalicOn); Inc(In_); End
      Else If In_ > 0 Then Begin Add(D, ekItalicOff); Dec(In_); End;
      End
    Else If (Length(T.Name) = 2) And (T.Name[1] = 'h') And (T.Name[2] In ['1'..'6']) Then
      Begin
      { a heading inside an entry: a bold paragraph }
      Add(D, ekPara);
      If Not T.Close Then Begin Add(D, ekBoldOn); Inc(Bn); End
      Else If Bn > 0 Then Begin Add(D, ekBoldOff); Dec(Bn); End;
      End
    Else If (T.Name = 'p') Or (T.Name = 'div') Then
      Begin
      If Not T.Close Then Add(D, ekPara) Else Add(D, ekLine);
      End
    Else If (T.Name = 'br') Or (T.Name = 'li') Or (T.Name = 'tr') Then
      Begin
      If Not T.Close Then Add(D, ekLine);
      End;
    End;
  While In_ > 0 Do Begin Add(D, ekItalicOff); Dec(In_); End;
  While Bn > 0 Do Begin Add(D, ekBoldOff); Dec(Bn); End;
  End;

{ ---- TEI (Sword dictionaries: entryFree, orth, pron, def, ref ...) ---- }
Procedure ParseTEI(Const S: AnsiString; Var D: TDoc);
  Var
    Pos_: Integer;
    IsTag: Boolean;
    Txt, V: AnsiString;
    T: TTag;
    St: TStack;
    i: Integer;
  Begin
  St.N := 0;
  Pos_ := 1;
  While NextToken(S, Pos_, IsTag, Txt) Do
    Begin
    If Not IsTag Then
      Begin
      Add(D, ekText, DecodeEntities(Txt));
      Continue;
      End;
    SplitTag(Txt, False, T);
    If (T.Name = '') Or (T.Name[1] In ['!', '?']) Then Continue;
    If T.Close Then
      Begin
      PopTo(D, St, T.Name);
      Continue;
      End;
    If T.Name = 'lb' Then Add(D, ekLine)
    Else If T.Name = 'p' Then
      Begin
      Add(D, ekPara);
      If Not T.Empty Then Push(St, 'p', ekLine, False);
      End
    Else If T.Empty Then
    Else If Attr(T.Attrs, 'rend', V) And (LowerCase(V) = 'bold') Then
      Begin
      Add(D, ekBoldOn);
      Push(St, T.Name, ekBoldOff, True);
      End
    Else If Attr(T.Attrs, 'rend', V) And ((LowerCase(V) = 'italic') Or (LowerCase(V) = 'i')) Then
      Begin
      Add(D, ekItalicOn);
      Push(St, T.Name, ekItalicOff, True);
      End
    Else
      Push(St, T.Name, ekLine, False);
    End;
  For i := St.N - 1 DownTo 0 Do
    If St.A[i].HasOff Then Add(D, St.A[i].Off);
  End;


{==================================================================== writers}

Function MorphValue(Const Tok: AnsiString): AnsiString;
  Var p: Integer;
  Begin
  p := Pos(':', Tok);
  If p > 0 Then MorphValue := Copy(Tok, p + 1, Length(Tok)) Else MorphValue := Tok;
  End;

Function FirstTok(Const L: AnsiString; Var Rest: AnsiString): AnsiString;
  Var p: Integer;
  Begin
  p := Pos(' ', L);
  If p = 0 Then
    Begin
    FirstTok := L;
    Rest := '';
    End
  Else
    Begin
    FirstTok := Copy(L, 1, p - 1);
    Rest := Trim(Copy(L, p + 1, Length(L)));
    End;
  End;

Function WriteOSIS(Const D: TDoc): AnsiString;
  Var
    O, L, Tok, Rest, Pre: AnsiString;
    i: Integer;
  Begin
  O := '';
  For i := 0 To D.N - 1 Do
    With D.Ev[i] Do
      Case Kind Of
        ekText: O := O + Esc(Txt);
        ekPara: O := O + '<milestone type="x-p"/>';
        ekLine: O := O + '<lb/>';
        ekItalicOn: O := O + '<hi type="italic">';
        ekItalicOff, ekBoldOff: O := O + '</hi>';
        ekBoldOn: O := O + '<hi type="bold">';
        ekJesusOn: O := O + '<q who="Jesus" marker="">';
        ekJesusOff: O := O + '</q>';
        ekNoteOn: If Num = 1 Then O := O + '<note type="crossReference">' Else O := O + '<note type="study">';
        ekNoteOff: O := O + '</note>';
        ekXrefOn: If Txt <> '' Then O := O + '<reference osisRef="' + Esc(Txt) + '">' Else O := O + '<reference>';
        ekXrefOff: O := O + '</reference>';
        ekHeadOn: If Num = 1 Then O := O + '<title type="main">' Else If Num >= 3 Then O := O + '<title type="sub">' Else O := O + '<title type="section">';
        ekHeadOff: O := O + '</title>';
        ekWordOn:
          Begin
          O := O + '<w';
          If Strong <> '' Then
            Begin
            L := Strong;
            Pre := '';
            While L <> '' Do
              Begin
              Tok := FirstTok(L, Rest);
              L := Rest;
              If Pre <> '' Then Pre := Pre + ' ';
              Pre := Pre + 'strong:' + Tok;
              End;
            O := O + ' lemma="' + Pre + '"';
            End;
          If Morph <> '' Then
            Begin
            L := Morph;
            Pre := '';
            While L <> '' Do
              Begin
              Tok := FirstTok(L, Rest);
              L := Rest;
              If Pre <> '' Then Pre := Pre + ' ';
              If Pos(':', Tok) > 0 Then Pre := Pre + Tok Else Pre := Pre + 'robinson:' + Tok;
              End;
            O := O + ' morph="' + Pre + '"';
            End;
          O := O + '>';
          End;
        ekWordOff: O := O + '</w>';
      End;
  WriteOSIS := O;
  End;

Function WriteThML(Const D: TDoc): AnsiString;
  Var
    O, L, Tok, Rest, WStrong, WMorph: AnsiString;
    i: Integer;
  Begin
  O := '';
  For i := 0 To D.N - 1 Do
    With D.Ev[i] Do
      Case Kind Of
        ekText: O := O + Esc(Txt);
        ekPara: O := O + '<p/>';
        ekLine: O := O + '<br/>';
        ekItalicOn: O := O + '<i>';
        ekItalicOff: O := O + '</i>';
        ekBoldOn: O := O + '<b>';
        ekBoldOff: O := O + '</b>';
        ekJesusOn, ekJesusOff: ;                       {ThML has no words-of-Jesus markup in Sword}
        ekNoteOn: If Num = 1 Then O := O + '<note type="crossReference">' Else O := O + '<note>';
        ekNoteOff: O := O + '</note>';
        ekXrefOn: If Txt <> '' Then O := O + '<scripRef passage="' + Esc(MkpOsisToHuman(Txt)) + '">' Else O := O + '<scripRef>';
        ekXrefOff: O := O + '</scripRef>';
        ekHeadOn: O := O + '<div class="sechead">';
        ekHeadOff: O := O + '</div>';
        ekWordOn: Begin WStrong := Strong; WMorph := Morph; End;
        ekWordOff:
          Begin
          L := WStrong;
          While L <> '' Do
            Begin
            Tok := FirstTok(L, Rest);
            L := Rest;
            O := O + '<sync type="Strongs" value="' + Tok + '" />';
            End;
          L := WMorph;
          While L <> '' Do
            Begin
            Tok := FirstTok(L, Rest);
            L := Rest;
            O := O + '<sync type="morph" class="robinson" value="' + MorphValue(Tok) + '" />';
            End;
          WStrong := ''; WMorph := '';
          End;
      End;
  WriteThML := O;
  End;

{ GBF and MySword share most tags }
Function WriteGBF(Const D: TDoc; MySword: Boolean): AnsiString;
  Var
    O, L, Tok, Rest, WStrong, WMorph, MyRef: AnsiString;
    i, j: Integer;
    SkipNote: Boolean;
  Begin
  O := '';
  WStrong := ''; WMorph := '';
  i := 0;
  While i < D.N Do
    Begin
    With D.Ev[i] Do
      Case Kind Of
        ekText: O := O + Esc(Txt);
        ekPara: O := O + '<CM>';
        ekLine: O := O + '<CL>';
        ekItalicOn: O := O + '<FI>';
        ekItalicOff: O := O + '<Fi>';
        ekBoldOn: O := O + '<FB>';
        ekBoldOff: O := O + '<Fb>';
        ekJesusOn: O := O + '<FR>';
        ekJesusOff: O := O + '<Fr>';
        ekNoteOn:
          Begin
          SkipNote := False;
          If MySword And (Num = 1) Then
            Begin
            { a cross reference note becomes <RX b.c.v> tags when each reference can be expressed }
            j := i + 1;
            MyRef := '';
            While (j < D.N) And (D.Ev[j].Kind <> ekNoteOff) Do
              Begin
              If D.Ev[j].Kind = ekXrefOn Then
                Begin
                Tok := OsisToMySwordRef(D.Ev[j].Txt);
                If Tok <> '' Then MyRef := MyRef + '<RX ' + Tok + '>';
                End;
              Inc(j);
              End;
            If MyRef <> '' Then
              Begin
              O := O + MyRef;
              i := j;                          {skip to the NoteOff}
              SkipNote := True;
              End;
            End;
          If Not SkipNote Then O := O + '<RF>';
          End;
        ekNoteOff: If Not SkipNote Then O := O + '<Rf>';
        ekXrefOn, ekXrefOff: ;       {neither GBF (Sword's GBF filters do not know <RX>) nor MySword carry inline references}
        ekHeadOn: If Num = 1 Then O := O + '<TS1>' Else If Num >= 3 Then O := O + '<TS3>' Else O := O + '<TS>';
        ekHeadOff: O := O + '<Ts>';
        ekWordOn: Begin WStrong := Strong; WMorph := Morph; End;
        ekWordOff:
          Begin
          L := WStrong;
          While L <> '' Do
            Begin
            Tok := FirstTok(L, Rest);
            L := Rest;
            If (Tok <> '') And (Tok[1] In ['G', 'H']) Then O := O + '<W' + Tok[1] + Copy(Tok, 2, Length(Tok)) + '>';
            End;
          L := WMorph;
          While L <> '' Do
            Begin
            Tok := FirstTok(L, Rest);
            L := Rest;
            O := O + '<WT' + MorphValue(Tok) + '>';
            End;
          WStrong := ''; WMorph := '';
          End;
      End;
    Inc(i);
    End;
  WriteGBF := O;
  End;

{ light markup: what a verse-per-line file can hold }
Function WriteLight(Const D: TDoc): AnsiString;
  Var
    O: AnsiString;
    i, Skip: Integer;
  Begin
  O := '';
  Skip := 0;
  For i := 0 To D.N - 1 Do
    With D.Ev[i] Do
      Case Kind Of
        ekNoteOn: Inc(Skip);
        ekNoteOff: If Skip > 0 Then Dec(Skip);
        ekText: If Skip = 0 Then O := O + Esc(Txt);
        ekPara, ekLine: If Skip = 0 Then O := O + '<br>';
        ekItalicOn: If Skip = 0 Then O := O + '<em>';
        ekItalicOff: If Skip = 0 Then O := O + '</em>';
        ekBoldOn, ekHeadOn: If Skip = 0 Then O := O + '<b>';
        ekBoldOff: If Skip = 0 Then O := O + '</b>';
        ekHeadOff: If Skip = 0 Then O := O + '</b> ';
        ekJesusOn: If Skip = 0 Then O := O + '<red>';
        ekJesusOff: If Skip = 0 Then O := O + '</red>';
      End;
  WriteLight := O;
  End;


{ simple HTML }
Function WriteHTML(Const D: TDoc): AnsiString;
  Var
    O: AnsiString;
    i, Skip: Integer;
  Begin
  O := '';
  Skip := 0;
  For i := 0 To D.N - 1 Do
    With D.Ev[i] Do
      Case Kind Of
        ekNoteOn: Inc(Skip);
        ekNoteOff: If Skip > 0 Then Dec(Skip);
        ekText: If Skip = 0 Then O := O + Esc(Txt);
        ekLine: If Skip = 0 Then O := O + '<br>';
        ekPara: If Skip = 0 Then O := O + '<br><br>';
        ekItalicOn: If Skip = 0 Then O := O + '<i>';
        ekItalicOff: If Skip = 0 Then O := O + '</i>';
        ekBoldOn, ekHeadOn: If Skip = 0 Then O := O + '<b>';
        ekBoldOff: If Skip = 0 Then O := O + '</b>';
        ekHeadOff: If Skip = 0 Then O := O + '</b> ';
      End;
  WriteHTML := O;
  End;


Function WriteXhtml(Const D: TDoc; VerseNum: Integer; WithNotes: Boolean; Var NoteCount: Integer; Var NoteHtml: AnsiString): AnsiString;
  Var
    O, NB: AnsiString;
    i, InNote, HeadDepth: Integer;
    NumDone, XrefNote: Boolean;

  Procedure Emit(Const T: AnsiString);
    Begin
    If InNote > 0 Then NB := NB + T Else O := O + T;
    End;

  Begin
  O := '';
  NB := '';
  InNote := 0;
  HeadDepth := 0;
  NumDone := VerseNum <= 0;
  XrefNote := False;
  For i := 0 To D.N - 1 Do
    With D.Ev[i] Do
      Case Kind Of
        ekNoteOn:
          Begin
          If InNote = 0 Then
            Begin
            XrefNote := (Num = 1) Or Not WithNotes;
            NB := '';
            End;
          Inc(InNote);
          End;
        ekNoteOff:
          If InNote > 0 Then
            Begin
            Dec(InNote);
            If (InNote = 0) And Not XrefNote And (Trim(NB) <> '') Then
              Begin
              Inc(NoteCount);
              O := O + '<a class="fn" epub:type="noteref" id="r' + IntToStr(NoteCount) + '" href="#fn' + IntToStr(NoteCount) + '">*</a>';
              NoteHtml := NoteHtml + '<aside epub:type="footnote" id="fn' + IntToStr(NoteCount) + '"><p><a href="#r' + IntToStr(NoteCount) +
                          '">*</a> ' + Trim(NB) + '</p></aside>' + #10;
              End;
            If InNote = 0 Then NB := '';
            End;
        ekText:
          If Not ((InNote > 0) And XrefNote) Then
            Begin
            If Not NumDone And (InNote = 0) And (HeadDepth = 0) And (Trim(Txt) <> '') Then
              Begin
              O := O + '<sup class="vn">' + IntToStr(VerseNum) + '</sup> ';
              NumDone := True;
              End;
            Emit(Esc(Txt));
            End;
        ekLine: If InNote = 0 Then O := O + '<br/>';
        ekPara: If InNote = 0 Then O := O + '</p><p>';
        ekItalicOn: If Not ((InNote > 0) And XrefNote) Then Emit('<i>');
        ekItalicOff: If Not ((InNote > 0) And XrefNote) Then Emit('</i>');
        ekBoldOn: If Not ((InNote > 0) And XrefNote) Then Emit('<b>');
        ekBoldOff: If Not ((InNote > 0) And XrefNote) Then Emit('</b>');
        ekJesusOn: If InNote = 0 Then O := O + '<span class="jesus">';
        ekJesusOff: If InNote = 0 Then O := O + '</span>';
        ekHeadOn: If InNote = 0 Then Begin O := O + '</p><h5 class="sh">'; Inc(HeadDepth); End;
        ekHeadOff: If (InNote = 0) And (HeadDepth > 0) Then Begin O := O + '</h5><p>'; Dec(HeadDepth); End;
      End;
  WriteXhtml := O;
  End;


{ RTF fragment, in the style of theWord's books and dictionaries: bold and italic groups, \par for breaks,
  \uN? for non-ASCII text, and Bible references as theWord hyperlinks (tw://bible id=book.chapter.verse) }
Function WriteRTF(Const D: TDoc): AnsiString;
  Var
    O, R, Id: AnsiString;
    i, Skip, k, n, Need: Integer;
    C: Byte;
    Cp: LongInt;
    InLink: Boolean;

  Function EscRtf(Const T: AnsiString): AnsiString;
    Var
      j: Integer;
      B: Byte;
      Res: AnsiString;
      U: LongInt;
    Begin
    Res := '';
    j := 1;
    While j <= Length(T) Do
      Begin
      B := Ord(T[j]);
      If B < $80 Then
        Begin
        If T[j] In ['\', '{', '}'] Then Res := Res + '\' + T[j] Else Res := Res + T[j];
        Inc(j);
        End
      Else
        Begin
        If (B And $E0) = $C0 Then Begin Need := 1; U := B And $1F; End
        Else If (B And $F0) = $E0 Then Begin Need := 2; U := B And $0F; End
        Else If (B And $F8) = $F0 Then Begin Need := 3; U := B And $07; End
        Else Begin Need := 0; U := B; End;
        Inc(j);
        While (Need > 0) And (j <= Length(T)) Do
          Begin
          U := (U Shl 6) Or (Ord(T[j]) And $3F);
          Inc(j);
          Dec(Need);
          End;
        If U >= $10000 Then
          Begin
          U := U - $10000;
          Res := Res + '\u' + IntToStr(SmallInt($D800 + (U Shr 10))) + '?\u' + IntToStr(SmallInt($DC00 + (U And $3FF))) + '?';
          End
        Else Res := Res + '\u' + IntToStr(SmallInt(U)) + '?';
        End;
      End;
    EscRtf := Res;
    End;

  Begin
  O := '';
  Skip := 0;
  InLink := False;
  For i := 0 To D.N - 1 Do
    With D.Ev[i] Do
      Case Kind Of
        ekNoteOn: Inc(Skip);
        ekNoteOff: If Skip > 0 Then Dec(Skip);
        ekText: If Skip = 0 Then O := O + EscRtf(Txt);
        ekPara, ekLine: If Skip = 0 Then O := O + '\par ';
        ekBoldOn, ekHeadOn: If Skip = 0 Then O := O + '{\b ';
        ekItalicOn: If Skip = 0 Then O := O + '{\i ';
        ekBoldOff, ekItalicOff: If Skip = 0 Then O := O + '}';
        ekHeadOff: If Skip = 0 Then O := O + '}\par ';
        ekXrefOn:
          If Skip = 0 Then
            Begin
            Id := OsisToMySwordRef(Txt);
            InLink := Id <> '';
            If InLink Then
              Begin
              { theWord ids are book.chapter.verse with dots }
              O := O + '{\field{\*\fldinst HYPERLINK "tw://bible.*?id=' + Id + '"}{\fldrslt\cf2 ';
              End;
            End;
        ekXrefOff:
          If (Skip = 0) And InLink Then
            Begin
            O := O + '}}';
            InLink := False;
            End;
      End;
  WriteRTF := O;
  End;


Function WritePlain(Const D: TDoc; Opts: MkpOpts): AnsiString;
  Var
    O: AnsiString;
    i, Skip, HeadDepth: Integer;
    Brk: AnsiString;
  Begin
  O := '';
  Skip := 0;
  HeadDepth := 0;
  If moBreaks In Opts Then Brk := #10 Else Brk := ' ';
  For i := 0 To D.N - 1 Do
    With D.Ev[i] Do
      Case Kind Of
        ekNoteOn: Inc(Skip);
        ekNoteOff: If Skip > 0 Then Dec(Skip);
        ekHeadOn:
          Begin
          If Not (moHeadings In Opts) Then Inc(Skip)
          Else If O <> '' Then O := O + Brk;
          Inc(HeadDepth);
          End;
        ekHeadOff:
          Begin
          If HeadDepth > 0 Then Dec(HeadDepth);
          If Not (moHeadings In Opts) Then
            Begin
            If Skip > 0 Then Dec(Skip);
            End
          Else O := O + Brk;
          End;
        ekText: If Skip = 0 Then O := O + Txt;
        ekPara: If Skip = 0 Then O := O + Brk;
        ekLine: If Skip = 0 Then O := O + Brk;
      End;
  { tidy: no double blanks, no blanks around new lines, no leading / trailing blanks }
  i := 1;
  Brk := '';
  While i <= Length(O) Do
    Begin
    If O[i] = ' ' Then
      Begin
      If (Brk <> '') And (Brk[Length(Brk)] <> ' ') And (Brk[Length(Brk)] <> #10) Then Brk := Brk + ' ';
      End
    Else If O[i] = #10 Then
      Begin
      While (Brk <> '') And (Brk[Length(Brk)] = ' ') Do SetLength(Brk, Length(Brk) - 1);
      If (Brk <> '') And (Brk[Length(Brk)] <> #10) Then Brk := Brk + #10;
      End
    Else Brk := Brk + O[i];
    Inc(i);
    End;
  While (Brk <> '') And (Brk[Length(Brk)] In [' ', #10]) Do SetLength(Brk, Length(Brk) - 1);
  WritePlain := Brk;
  End;


{==================================================================== USFM, USFX, Zefania}

{ Strong's tokens from an attribute value: "H8064", "H1234,G5", "strong:H1" ... -> "H8064 H1234 G5" }
Function StrongList(Const V: AnsiString): AnsiString;
  Var
    R, Tok: AnsiString;
    i: Integer;
  Begin
  R := '';
  Tok := '';
  For i := 1 To Length(V) + 1 Do
    If (i > Length(V)) Or (V[i] In [' ', ',', ';']) Then
      Begin
      If Tok <> '' Then
        Begin
        If LowerCase(Copy(Tok, 1, 7)) = 'strong:' Then Tok := Copy(Tok, 8, Length(Tok));
        If R <> '' Then R := R + ' ';
        R := R + StripZeros(Tok);
        End;
      Tok := '';
      End
    Else Tok := Tok + V[i];
  StrongList := R;
  End;

Function MorphList(Const V: AnsiString): AnsiString;
  Var
    R, Tok: AnsiString;
    i: Integer;
  Begin
  R := '';
  Tok := '';
  For i := 1 To Length(V) + 1 Do
    If (i > Length(V)) Or (V[i] In [' ', ',', ';']) Then
      Begin
      If Tok <> '' Then
        Begin
        If R <> '' Then R := R + ' ';
        R := R + Tok;
        End;
      Tok := '';
      End
    Else Tok := Tok + V[i];
  MorphList := R;
  End;


{ ---- USFM ---- }
{ what a USFM marker is: 0 character style or unknown (no break), 1 paragraph, 2 poetry line, 3 heading,
  4 header / metadata line (its text is dropped), 5 chapter }
Function UsfmDigitsFrom(Const M: AnsiString; From: Integer): Boolean;
  Var i: Integer;
  Begin
  UsfmDigitsFrom := Length(M) >= From;
  For i := From To Length(M) Do
    If Not (M[i] In ['0'..'9']) Then UsfmDigitsFrom := False;
  End;

Function UsfmClass(Const M: AnsiString): Integer;
  Var c1, c2: AnsiString;
  Begin
  c1 := Copy(M, 1, 1);
  c2 := Copy(M, 1, 2);
  UsfmClass := 0;
  If (M = 'p') Or (M = 'm') Or (M = 'b') Or (M = 'nb') Or (M = 'mi') Or (M = 'pc') Or (M = 'pr') Or (M = 'cls') Or
     (c2 = 'pi') Or (c2 = 'pm') Then UsfmClass := 1
  Else If (M = 'q') Or (M = 'qr') Or (M = 'qc') Or (M = 'qm') Or ((c1 = 'q') And UsfmDigitsFrom(M, 2)) Or
          ((c2 = 'qm') And UsfmDigitsFrom(M, 3)) Or (M = 'lh') Or (M = 'lf') Or (c2 = 'li') Then UsfmClass := 2
  Else If (M = 's') Or ((c1 = 's') And UsfmDigitsFrom(M, 2)) Or (c2 = 'ms') Or (M = 'd') Or (M = 'sp') Or (M = 'qa') Then UsfmClass := 3
  Else If (M = 'mr') Or (M = 'r') Or (M = 'sr') Or (M = 'id') Or (M = 'ide') Or (c1 = 'h') Or (Copy(M, 1, 3) = 'toc') Or
          (c2 = 'mt') Or (M = 'rem') Or (M = 'cl') Or (M = 'cd') Or (M = 'cp') Or
          ((c1 = 'i') And (M <> 'it') And (M <> 'ior') And (M <> 'iex') And (M <> 'iqt')) Then UsfmClass := 4
  Else If M = 'c' Then UsfmClass := 5;
  End;

{ drop the verse / chapter number that follows \v or \c: 12, 12-13, 12a }
Function UsfmStripNumber(Const Seg: AnsiString): AnsiString;
  Var j: Integer;
  Begin
  j := 1;
  While (j <= Length(Seg)) And (Seg[j] = ' ') Do Inc(j);
  If (j <= Length(Seg)) And (Seg[j] In ['0'..'9']) Then
    Begin
    While (j <= Length(Seg)) And (Seg[j] In ['0'..'9', '-', ',']) Do Inc(j);
    If (j <= Length(Seg)) And (Seg[j] In ['a'..'c']) And ((j = Length(Seg)) Or (Seg[j + 1] = ' ')) Then Inc(j);
    End
  Else j := 1;
  While (j <= Length(Seg)) And (Seg[j] = ' ') Do Inc(j);
  UsfmStripNumber := Copy(Seg, j, Length(Seg));
  End;

Procedure ParseUSFM(Const S: AnsiString; Var D: TDoc);
  Var
    i, j, k, WordIdx, HeadLvl, Cls: Integer;
    Mk, Seg, Attrs, V: AnsiString;
    Closing, SkipNext, SkipNum, SkipLine, HeadOpen, SkipCaller, HeadIsTitle: Boolean;
    St: TStack;

  Procedure CloseHead;
    Begin
    If HeadOpen Then
      Begin
      If HeadIsTitle Then Add(D, ekItalicOff) Else Add(D, ekHeadOff);
      HeadOpen := False;
      End;
    End;

  Procedure CloseAll;
    Var q: Integer;
    Begin
    For q := St.N - 1 DownTo 0 Do
      If St.A[q].HasOff Then Add(D, St.A[q].Off);
    St.N := 0;
    WordIdx := -1;
    End;

  Procedure Handle(Const M: AnsiString; Cl: Boolean);
    Begin
    If Cl Then
      Begin
      If M = 'w' Then WordIdx := -1;
      If (M = 'w') Or (M = 'wj') Or (M = 'add') Or (M = 'it') Or (M = 'em') Or (M = 'bd') Or (M = 'bdit') Or (M = 'x') Then
        PopTo(D, St, M)
      Else If M = 'fe' Then PopTo(D, St, 'f')
      Else If M = 'f' Then PopTo(D, St, 'f')
      Else If (M = 'fig') Or (M = 'ca') Or (M = 'va') Or (M = 'vp') Or (M = 'rq') Or (M = 'cat') Then SkipLine := False;
      Exit;
      End;
    Cls := UsfmClass(M);
    If Cls <> 0 Then
      Begin
      CloseHead;
      CloseAll;
      SkipLine := False;
      End;
    Case Cls Of
      1: Add(D, ekPara);
      2: Add(D, ekLine);
      3:
        If M = 'd' Then
          Begin
          { a psalm title is text of the verse, in italics }
          Add(D, ekPara);
          Add(D, ekItalicOn);
          HeadOpen := True;
          HeadIsTitle := True;
          End
        Else
          Begin
          If Copy(M, 1, 2) = 'ms' Then HeadLvl := 1
          Else If (M = 's2') Or (M = 's3') Or (M = 's4') Then HeadLvl := 3
          Else HeadLvl := 2;
          Add(D, ekHeadOn, '', HeadLvl);
          HeadOpen := True;
          HeadIsTitle := False;
          End;
      4: SkipLine := True;
      5: SkipNum := True;
      Else
        Begin
        If M = 'w' Then
          Begin
          PopTo(D, St, 'w');
          Add(D, ekWordOn);
          WordIdx := D.N - 1;
          Push(St, 'w', ekWordOff, True);
          End
        Else If M = 'wj' Then Begin Add(D, ekJesusOn); Push(St, 'wj', ekJesusOff, True); End
        Else If (M = 'add') Or (M = 'it') Or (M = 'em') Then Begin Add(D, ekItalicOn); Push(St, M, ekItalicOff, True); End
        Else If M = 'bd' Then Begin Add(D, ekBoldOn); Push(St, M, ekBoldOff, True); End
        Else If M = 'bdit' Then Begin Add(D, ekBoldOn); Add(D, ekItalicOn); Push(St, M, ekItalicOff, True); End
        Else If (M = 'f') Or (M = 'fe') Then Begin Add(D, ekNoteOn, '', 0); Push(St, 'f', ekNoteOff, True); SkipCaller := True; End
        Else If M = 'x' Then Begin Add(D, ekNoteOn, '', 1); Push(St, 'x', ekNoteOff, True); SkipCaller := True; End
        Else If (M = 'fr') Or (M = 'xo') Or (M = 'fv') Then SkipNext := True
        Else If (M = 'fig') Or (M = 'ca') Or (M = 'va') Or (M = 'vp') Or (M = 'rq') Or (M = 'cat') Then SkipLine := True
        Else If M = 'v' Then SkipNum := True;
        End;
    End;
    End;

  Begin
  St.N := 0;
  WordIdx := -1; HeadOpen := False; HeadIsTitle := False; SkipNext := False; SkipNum := False; SkipLine := False; SkipCaller := False;
  i := 1;
  While i <= Length(S) Do
    Begin
    If S[i] = '\' Then
      Begin
      j := i + 1;
      If (j <= Length(S)) And (S[j] = '+') Then Inc(j);
      k := j;
      While (k <= Length(S)) And (S[k] In ['a'..'z', 'A'..'Z', '0'..'9']) Do Inc(k);
      Mk := LowerCase(Copy(S, j, k - j));
      If Mk = '' Then
        Begin
        If Not SkipLine Then Add(D, ekText, '\');
        Inc(i);
        Continue;
        End;
      Closing := (k <= Length(S)) And (S[k] = '*');
      If Closing Then Inc(k);
      If (Not Closing) And (k <= Length(S)) And (S[k] = ' ') Then Inc(k);
      i := k;
      Handle(Mk, Closing);
      End
    Else
      Begin
      k := i;
      While (k <= Length(S)) And (S[k] <> '\') Do Inc(k);
      Seg := Copy(S, i, k - i);
      i := k;
      For j := 1 To Length(Seg) Do If Seg[j] In [#10, #13, #9] Then Seg[j] := ' ';
      If SkipNum Then
        Begin
        Seg := UsfmStripNumber(Seg);
        SkipNum := False;
        End;
      If SkipCaller Then
        Begin
        { the note's caller (+ - ? a letter) is the first word after \f or \x }
        SkipCaller := False;
        j := 1;
        While (j <= Length(Seg)) And (Seg[j] = ' ') Do Inc(j);
        While (j <= Length(Seg)) And (Seg[j] <> ' ') Do Inc(j);
        Seg := Copy(Seg, j, Length(Seg));
        End;
      If SkipNext Then
        Begin
        SkipNext := False;
        Seg := '';
        End;
      If (WordIdx >= 0) And (Pos('|', Seg) > 0) Then
        Begin
        Attrs := Copy(Seg, Pos('|', Seg) + 1, Length(Seg));
        Seg := Copy(Seg, 1, Pos('|', Seg) - 1);
        If Attr(Attrs, 'strong', V) Then D.Ev[WordIdx].Strong := StrongList(V);
        If Attr(Attrs, 'x-morph', V) Or Attr(Attrs, 'morph', V) Then D.Ev[WordIdx].Morph := MorphList(V);
        End;
      If (Seg <> '') And (Not SkipLine) Then Add(D, ekText, Seg);
      End;
    End;
  CloseHead;
  CloseAll;
  End;

{ ---- USFX ---- }
Procedure ParseUSFX(Const S: AnsiString; Var D: TDoc);
  Var
    Pos_, Skip, Lvl: Integer;
    IsTag: Boolean;
    Txt, V, Sf, Lem: AnsiString;
    T: TTag;
    St: TStack;
    i: Integer;

  Function IsSkipName(Const N: AnsiString): Boolean;
    Begin
    IsSkipName := (N = 'fr') Or (N = 'xo') Or (N = 'fig') Or (N = 'ca') Or (N = 'va') Or (N = 'vp') Or
                  (N = 'rq') Or (N = 'toc') Or (N = 'h') Or (N = 'id') Or (N = 'ide') Or (N = 'mt') Or
                  (N = 'cl') Or (N = 'cp') Or (N = 'rem') Or (N = 'r') Or (N = 'mr') Or (N = 'sr') Or (N = 'fv');
    End;

  Function SfmKind(Const N: AnsiString): Integer;
    { 0 = paragraph, 1 = skip, 2 = heading level 1, 3 = level 2, 4 = level 3 }
    Begin
    SfmKind := 0;
    If (Copy(N, 1, 2) = 'mt') Or (Copy(N, 1, 3) = 'toc') Or (Copy(N, 1, 2) = 'is') Or (Copy(N, 1, 2) = 'ip') Or
       (Copy(N, 1, 2) = 'im') Or (Copy(N, 1, 2) = 'io') Or (N = 'mr') Or (N = 'r') Or (N = 'sr') Or (N = 'cl') Or
       (N = 'rem') Or (N = 'h') Or (N = 'ie') Then SfmKind := 1
    Else If Copy(N, 1, 2) = 'ms' Then SfmKind := 2
    Else If N = 'd' Then SfmKind := 5
    Else If (N = 's') Or (N = 's1') Or (N = 'sp') Then SfmKind := 3
    Else If (N = 's2') Or (N = 's3') Or (N = 's4') Then SfmKind := 4;
    End;

  Begin
  St.N := 0;
  Skip := 0;
  Pos_ := 1;
  While NextToken(S, Pos_, IsTag, Txt) Do
    Begin
    If Not IsTag Then
      Begin
      If Skip = 0 Then Add(D, ekText, DecodeEntities(Txt));
      Continue;
      End;
    SplitTag(Txt, False, T);
    If (T.Name = '') Or (T.Name[1] In ['!', '?']) Then Continue;
    If T.Close Then
      Begin
      i := St.N - 1;
      While (i >= 0) And (St.A[i].Name <> T.Name) Do Dec(i);
      If (i >= 0) And (St.A[i].Marker = 'skip') And (Skip > 0) Then Dec(Skip);
      PopTo(D, St, T.Name);
      Continue;
      End;
    If (T.Name = 'v') Or (T.Name = 've') Or (T.Name = 'c') Or (T.Name = 'book') Or (T.Name = 'usfx') Or
       (T.Name = 'languageCode') Then Continue;
    If T.Name = 'w' Then
      Begin
      Lem := '';
      If Attr(T.Attrs, 's', V) Or Attr(T.Attrs, 'strong', V) Or Attr(T.Attrs, 'lemma', V) Then Lem := StrongList(V);
      If T.Empty Then Continue;
      PopTo(D, St, 'w');
      Add(D, ekWordOn);
      D.Ev[D.N - 1].Strong := Lem;
      If Attr(T.Attrs, 'morph', V) Or Attr(T.Attrs, 'm', V) Or Attr(T.Attrs, 'x-morph', V) Then D.Ev[D.N - 1].Morph := MorphList(V);
      Push(St, 'w', ekWordOff, True);
      End
    Else If T.Name = 'wj' Then
      Begin
      If Not T.Empty Then Begin Add(D, ekJesusOn); Push(St, 'wj', ekJesusOff, True); End;
      End
    Else If (T.Name = 'add') Or (T.Name = 'it') Or (T.Name = 'em') Then
      Begin
      If Not T.Empty Then Begin Add(D, ekItalicOn); Push(St, T.Name, ekItalicOff, True); End;
      End
    Else If T.Name = 'bd' Then
      Begin
      If Not T.Empty Then Begin Add(D, ekBoldOn); Push(St, T.Name, ekBoldOff, True); End;
      End
    Else If T.Name = 'f' Then
      Begin
      If Not T.Empty Then Begin Add(D, ekNoteOn, '', 0); Push(St, 'f', ekNoteOff, True); End;
      End
    Else If T.Name = 'x' Then
      Begin
      If Not T.Empty Then Begin Add(D, ekNoteOn, '', 1); Push(St, 'x', ekNoteOff, True); End;
      End
    Else If T.Name = 'ref' Then
      Begin
      If T.Empty Then Continue;
      If Attr(T.Attrs, 'tgt', V) And (MkpHumanToOsis(V) <> '') Then
        Begin Add(D, ekXrefOn, MkpHumanToOsis(V)); Push(St, 'ref', ekXrefOff, True); End
      Else Push(St, 'ref', ekXrefOff, False);
      End
    Else If IsSkipName(T.Name) Then
      Begin
      If Not T.Empty Then
        Begin
        Inc(Skip);
        Push(St, T.Name, ekLine, False);
        St.A[St.N - 1].Marker := 'skip';
        End;
      End
    Else If T.Name = 'b' Then Add(D, ekPara)
    Else If (T.Name = 'p') Or (T.Name = 's') Or (T.Name = 'ms') Or (T.Name = 'd') Then
      Begin
      Sf := '';
      Attr(T.Attrs, 'sfm', Sf);
      If (T.Name = 'p') And (Sf = '') Then
        Begin
        Add(D, ekPara);
        If Not T.Empty Then Push(St, 'p', ekLine, False);
        End
      Else
        Begin
        If Sf = '' Then Sf := T.Name;
        Sf := LowerCase(Sf);
        Lvl := SfmKind(Sf);
        If Lvl = 1 Then
          Begin
          If Not T.Empty Then
            Begin
            Inc(Skip);
            Push(St, T.Name, ekLine, False);
            St.A[St.N - 1].Marker := 'skip';
            End;
          End
        Else If Lvl = 5 Then
          Begin
          Add(D, ekPara);
          Add(D, ekItalicOn);
          If Not T.Empty Then Push(St, T.Name, ekItalicOff, True) Else Add(D, ekItalicOff);
          End
        Else If Lvl >= 2 Then
          Begin
          Add(D, ekHeadOn, '', Lvl - 1);
          If Not T.Empty Then Push(St, T.Name, ekHeadOff, True) Else Add(D, ekHeadOff);
          End
        Else
          Begin
          If (Copy(Sf, 1, 1) = 'q') Or (Copy(Sf, 1, 2) = 'li') Then Add(D, ekLine) Else Add(D, ekPara);
          If Not T.Empty Then Push(St, T.Name, ekLine, False);
          End;
        End;
      End
    Else If (T.Name = 'q') Or (T.Name = 'li') Or (T.Name = 'qr') Or (T.Name = 'qc') Or (T.Name = 'qm') Or (T.Name = 'lh') Then
      Begin
      Add(D, ekLine);
      If Not T.Empty Then Push(St, T.Name, ekLine, False);
      End
    Else If (T.Name = 'm') Or (T.Name = 'pi') Or (T.Name = 'pc') Or (T.Name = 'pm') Or (T.Name = 'mi') Or (T.Name = 'nb') Then
      Begin
      Add(D, ekPara);
      If Not T.Empty Then Push(St, T.Name, ekLine, False);
      End
    Else If Not T.Empty Then
      Push(St, T.Name, ekLine, False);
    End;
  For i := St.N - 1 DownTo 0 Do
    If St.A[i].HasOff Then Add(D, St.A[i].Off);
  End;

{ ---- Zefania ---- }
Procedure ParseZefania(Const S: AnsiString; Var D: TDoc);
  Var
    Pos_, Skip: Integer;
    IsTag: Boolean;
    Txt, V, Css: AnsiString;
    T: TTag;
    St: TStack;
    i: Integer;
  Begin
  St.N := 0;
  Skip := 0;
  Pos_ := 1;
  While NextToken(S, Pos_, IsTag, Txt) Do
    Begin
    If Not IsTag Then
      Begin
      If Skip = 0 Then Add(D, ekText, DecodeEntities(Txt));
      Continue;
      End;
    SplitTag(Txt, True, T);
    If (T.Name = '') Or (T.Name[1] In ['!', '?']) Then Continue;
    If T.Close Then
      Begin
      If (T.Name = 'remark') And (Skip > 0) Then Dec(Skip);
      PopTo(D, St, T.Name);
      Continue;
      End;
    If T.Name = 'br' Then Add(D, ekLine)
    Else If T.Name = 'remark' Then
      Begin
      If Not T.Empty Then Begin Inc(Skip); Push(St, 'remark', ekLine, False); End;
      End
    Else If T.Name = 'style' Then
      Begin
      If T.Empty Then Continue;
      Attr(T.Attrs, 'css', Css);
      Css := LowerCase(Css);
      If (Pos('color', Css) > 0) And ((Pos('ff0000', Css) > 0) Or (Pos('red', Css) > 0) Or (Pos('#f00', Css) > 0)) Then
        Begin Add(D, ekJesusOn); Push(St, 'style', ekJesusOff, True); End
      Else If Pos('italic', Css) > 0 Then Begin Add(D, ekItalicOn); Push(St, 'style', ekItalicOff, True); End
      Else If Pos('bold', Css) > 0 Then Begin Add(D, ekBoldOn); Push(St, 'style', ekBoldOff, True); End
      Else Push(St, 'style', ekLine, False);
      End
    Else If T.Name = 'note' Then
      Begin
      If T.Empty Then Continue;
      Add(D, ekNoteOn, '', 0);
      Push(St, 'note', ekNoteOff, True);
      End
    Else If T.Name = 'xref' Then
      Begin
      If T.Empty Then Continue;
      If Attr(T.Attrs, 'fscope', V) And (MkpHumanToOsis(V) <> '') Then
        Begin Add(D, ekXrefOn, MkpHumanToOsis(V)); Push(St, 'xref', ekXrefOff, True); End
      Else Push(St, 'xref', ekXrefOff, False);
      End
    Else If T.Name = 'gr' Then
      Begin
      If T.Empty Then Continue;
      PopTo(D, St, 'gr');
      If Attr(T.Attrs, 'str', V) And (StrongList(V) <> '') Then
        Begin
        Add(D, ekWordOn);
        D.Ev[D.N - 1].Strong := StrongList(V);
        If Attr(T.Attrs, 'rmac', V) Or Attr(T.Attrs, 'morph', V) Then D.Ev[D.N - 1].Morph := MorphList(V);
        Push(St, 'gr', ekWordOff, True);
        End
      Else Push(St, 'gr', ekLine, False);
      End
    Else If (T.Name = 'caption') Or (T.Name = 'title') Then
      Begin
      If T.Empty Then Continue;
      Add(D, ekHeadOn, '', 2);
      Push(St, T.Name, ekHeadOff, True);
      End
    Else If (T.Name = 'p') Or (T.Name = 'div') Then
      Begin
      Add(D, ekPara);
      If Not T.Empty Then Push(St, T.Name, ekLine, False);
      End
    Else If Not T.Empty Then
      Push(St, T.Name, ekLine, False);
    End;
  For i := St.N - 1 DownTo 0 Do
    If St.A[i].HasOff Then Add(D, St.A[i].Off);
  End;

{ ---- USX (USX 2 and 3: the XML of USFM, <para style="p"><verse number="1"/>text<char style="wj">..</char></para>) ---- }
Procedure ParseUSX(Const S: AnsiString; Var D: TDoc);
  Var
    Pos_, Skip, Cls, Lvl: Integer;
    IsTag: Boolean;
    Txt, V, Sty: AnsiString;
    T: TTag;
    St: TStack;
    i: Integer;
  Begin
  St.N := 0;
  Skip := 0;
  Pos_ := 1;
  While NextToken(S, Pos_, IsTag, Txt) Do
    Begin
    If Not IsTag Then
      Begin
      If Skip = 0 Then Add(D, ekText, DecodeEntities(Txt));
      Continue;
      End;
    SplitTag(Txt, False, T);
    If (T.Name = '') Or (T.Name[1] In ['!', '?']) Then Continue;
    If T.Close Then
      Begin
      i := St.N - 1;
      While (i >= 0) And (St.A[i].Name <> T.Name) Do Dec(i);
      If (i >= 0) And (St.A[i].Marker = 'skip') And (Skip > 0) Then Dec(Skip);
      PopTo(D, St, T.Name);
      Continue;
      End;
    If (T.Name = 'verse') Or (T.Name = 'chapter') Or (T.Name = 'usx') Or (T.Name = 'optbreak') Or (T.Name = 'ms') Then Continue;
    Sty := '';
    Attr(T.Attrs, 'style', Sty);
    Sty := LowerCase(Sty);
    If T.Name = 'book' Then
      Begin
      If Not T.Empty Then
        Begin Inc(Skip); Push(St, 'book', ekLine, False); St.A[St.N - 1].Marker := 'skip'; End;
      End
    Else If T.Name = 'para' Then
      Begin
      Cls := UsfmClass(Sty);
      If Sty = '' Then Cls := 1;
      Case Cls Of
        2: Add(D, ekLine);
        3:
          If Sty = 'd' Then
            Begin
            Add(D, ekPara);
            Add(D, ekItalicOn);
            If Not T.Empty Then Push(St, 'para', ekItalicOff, True) Else Add(D, ekItalicOff);
            Continue;
            End
          Else
            Begin
            If Copy(Sty, 1, 2) = 'ms' Then Lvl := 1 Else If (Sty = 's2') Or (Sty = 's3') Or (Sty = 's4') Then Lvl := 3 Else Lvl := 2;
            Add(D, ekHeadOn, '', Lvl);
            If Not T.Empty Then Push(St, 'para', ekHeadOff, True) Else Add(D, ekHeadOff);
            Continue;
            End;
        4:
          Begin
          If Not T.Empty Then
            Begin Inc(Skip); Push(St, 'para', ekLine, False); St.A[St.N - 1].Marker := 'skip'; End;
          Continue;
          End;
        Else Add(D, ekPara);
      End;
      If Not T.Empty Then Push(St, 'para', ekLine, False);
      End
    Else If T.Name = 'char' Then
      Begin
      If T.Empty Then Continue;
      If Sty = 'w' Then
        Begin
        PopTo(D, St, 'char');
        Add(D, ekWordOn);
        If Attr(T.Attrs, 'strong', V) Or Attr(T.Attrs, 'lemma', V) Then D.Ev[D.N - 1].Strong := StrongList(V);
        If Attr(T.Attrs, 'x-morph', V) Or Attr(T.Attrs, 'morph', V) Then D.Ev[D.N - 1].Morph := MorphList(V);
        Push(St, 'char', ekWordOff, True);
        End
      Else If Sty = 'wj' Then Begin Add(D, ekJesusOn); Push(St, 'char', ekJesusOff, True); End
      Else If (Sty = 'add') Or (Sty = 'it') Or (Sty = 'em') Then Begin Add(D, ekItalicOn); Push(St, 'char', ekItalicOff, True); End
      Else If Sty = 'bd' Then Begin Add(D, ekBoldOn); Push(St, 'char', ekBoldOff, True); End
      Else If Sty = 'bdit' Then Begin Add(D, ekBoldOn); Add(D, ekItalicOn); Push(St, 'char', ekItalicOff, True); End
      Else If (Sty = 'fr') Or (Sty = 'xo') Or (Sty = 'fv') Or (Sty = 'fig') Or (Sty = 'ca') Or (Sty = 'va') Or
              (Sty = 'vp') Or (Sty = 'rq') Or (Sty = 'cat') Then
        Begin Inc(Skip); Push(St, 'char', ekLine, False); St.A[St.N - 1].Marker := 'skip'; End
      Else Push(St, 'char', ekLine, False);
      End
    Else If T.Name = 'note' Then
      Begin
      If T.Empty Then Continue;
      If (Sty = 'x') Or (Sty = 'ex') Then Add(D, ekNoteOn, '', 1) Else Add(D, ekNoteOn, '', 0);
      Push(St, 'note', ekNoteOff, True);
      End
    Else If T.Name = 'ref' Then
      Begin
      If T.Empty Then Continue;
      If Attr(T.Attrs, 'loc', V) And (MkpHumanToOsis(V) <> '') Then
        Begin Add(D, ekXrefOn, MkpHumanToOsis(V)); Push(St, 'ref', ekXrefOff, True); End
      Else Push(St, 'ref', ekXrefOff, False);
      End
    Else If T.Name = 'row' Then
      Begin
      Add(D, ekLine);
      If Not T.Empty Then Push(St, 'row', ekLine, False);
      End
    Else If T.Name = 'figure' Then
      Begin
      If Not T.Empty Then
        Begin Inc(Skip); Push(St, 'figure', ekLine, False); St.A[St.N - 1].Marker := 'skip'; End;
      End
    Else If Not T.Empty Then
      Push(St, T.Name, ekLine, False);
    End;
  For i := St.N - 1 DownTo 0 Do
    If St.A[i].HasOff Then Add(D, St.A[i].Off);
  End;

{ ---- writers ---- }
Function WriteUSFM(Const D: TDoc): AnsiString;
  Var
    O, WStrong, WMorph: AnsiString;
    i, N: Integer;
    NoteX: Array Of Boolean;
  Begin
  O := '';
  N := 0;
  SetLength(NoteX, 8);
  WStrong := ''; WMorph := '';
  For i := 0 To D.N - 1 Do
    With D.Ev[i] Do
      Case Kind Of
        ekText: O := O + Txt;
        ekPara: If N = 0 Then O := O + #10'\p'#10;
        ekLine: If N = 0 Then O := O + #10'\q1 ';
        ekItalicOn: O := O + '\it ';
        ekItalicOff: O := O + '\it*';
        ekBoldOn: O := O + '\bd ';
        ekBoldOff: O := O + '\bd*';
        ekJesusOn: O := O + '\wj ';
        ekJesusOff: O := O + '\wj*';
        ekNoteOn:
          Begin
          If N >= Length(NoteX) Then SetLength(NoteX, N * 2);
          NoteX[N] := Num = 1;
          Inc(N);
          If Num = 1 Then O := O + '\x - \xt ' Else O := O + '\f + \ft ';
          End;
        ekNoteOff:
          If N > 0 Then
            Begin
            Dec(N);
            If NoteX[N] Then O := O + '\x*' Else O := O + '\f*';
            End;
        ekHeadOn: If N = 0 Then O := O + #10'\s1 ';
        ekHeadOff: If N = 0 Then O := O + #10;
        ekWordOn:
          Begin
          O := O + '\w ';
          WStrong := Strong; WMorph := Morph;
          End;
        ekWordOff:
          Begin
          If WStrong <> '' Then
            Begin
            O := O + '|strong="' + StringReplace(WStrong, ' ', ',', [rfReplaceAll]) + '"';
            If WMorph <> '' Then O := O + ' x-morph="' + WMorph + '"';
            End
          Else If WMorph <> '' Then O := O + '|x-morph="' + WMorph + '"';
          O := O + '\w*';
          End;
      End;
  WriteUSFM := O;
  End;

Function WriteUSFX(Const D: TDoc): AnsiString;
  { the object that stores the chapters wraps them in <p> ... </p>, so a new paragraph here is </p><p> }
  Var
    O, WStrong, WMorph: AnsiString;
    i, N: Integer;
    NoteX: Array Of Boolean;
  Begin
  O := '';
  N := 0;
  SetLength(NoteX, 8);
  For i := 0 To D.N - 1 Do
    With D.Ev[i] Do
      Case Kind Of
        ekText: O := O + Esc(Txt);
        ekPara: If N = 0 Then O := O + '</p><p>';
        ekLine: If N = 0 Then O := O + '</p><p sfm="q1">';
        ekItalicOn: O := O + '<it>';
        ekItalicOff: O := O + '</it>';
        ekBoldOn: O := O + '<bd>';
        ekBoldOff: O := O + '</bd>';
        ekJesusOn: O := O + '<wj>';
        ekJesusOff: O := O + '</wj>';
        ekNoteOn:
          Begin
          If N >= Length(NoteX) Then SetLength(NoteX, N * 2);
          NoteX[N] := Num = 1;
          Inc(N);
          If Num = 1 Then O := O + '<x>' Else O := O + '<f caller="+">';
          End;
        ekNoteOff:
          If N > 0 Then
            Begin
            Dec(N);
            If NoteX[N] Then O := O + '</x>' Else O := O + '</f>';
            End;
        ekXrefOn: If (Txt <> '') And (N = 0) Then O := O + '<ref tgt="' + Esc(MkpOsisToHuman(Txt)) + '">' Else O := O + '<ref>';
        ekXrefOff: O := O + '</ref>';
        ekHeadOn: If N = 0 Then O := O + '</p><p sfm="s">';
        ekHeadOff: If N = 0 Then O := O + '</p><p>';
        ekWordOn:
          Begin
          O := O + '<w';
          If Strong <> '' Then O := O + ' s="' + Strong + '"';
          If Morph <> '' Then O := O + ' m="' + Esc(Morph) + '"';
          O := O + '>';
          End;
        ekWordOff: O := O + '</w>';
      End;
  WriteUSFX := O;
  End;

Function WriteZefania(Const D: TDoc): AnsiString;
  Var
    O: AnsiString;
    i, Skip: Integer;
  Begin
  O := '';
  Skip := 0;
  For i := 0 To D.N - 1 Do
    With D.Ev[i] Do
      Case Kind Of
        ekText: If Skip = 0 Then O := O + Esc(Txt);
        ekPara, ekLine: If Skip = 0 Then O := O + '<BR/>';
        ekItalicOn: If Skip = 0 Then O := O + '<STYLE css="font-style:italic">';
        ekBoldOn: If Skip = 0 Then O := O + '<STYLE css="font-weight:bold">';
        ekJesusOn: If Skip = 0 Then O := O + '<STYLE css="color:#ff0000">';
        ekItalicOff, ekBoldOff, ekJesusOff: If Skip = 0 Then O := O + '</STYLE>';
        ekNoteOn: If Skip = 0 Then O := O + '<NOTE type="x-studynote">';
        ekNoteOff: If Skip = 0 Then O := O + '</NOTE>';
        ekHeadOn: Inc(Skip);
        ekHeadOff: If Skip > 0 Then Dec(Skip);
        ekXrefOn: If (Skip = 0) And (Txt <> '') Then O := O + '<XREF fscope="' + Esc(MkpOsisToHuman(Txt)) + '">' Else If Skip = 0 Then O := O + '<XREF>';
        ekXrefOff: If Skip = 0 Then O := O + '</XREF>';
        ekWordOn:
          If Skip = 0 Then
            Begin
            O := O + '<gr';
            If Strong <> '' Then O := O + ' str="' + Strong + '"';
            If Morph <> '' Then O := O + ' rmac="' + Esc(Morph) + '"';
            O := O + '>';
            End;
        ekWordOff: If Skip = 0 Then O := O + '</gr>';
      End;
  WriteZefania := O;
  End;


Function WriteUSX(Const D: TDoc): AnsiString;
  { for the inside of a <para style="p">: a new paragraph is </para><para style="..."> }
  Var
    O, WStrong, WMorph: AnsiString;
    i, N: Integer;
    NoteX: Array Of Boolean;
  Begin
  O := '';
  N := 0;
  SetLength(NoteX, 8);
  For i := 0 To D.N - 1 Do
    With D.Ev[i] Do
      Case Kind Of
        ekText: O := O + Esc(Txt);
        ekPara: If N = 0 Then O := O + '</para><para style="p">';
        ekLine: If N = 0 Then O := O + '</para><para style="q1">';
        ekItalicOn: O := O + '<char style="it">';
        ekItalicOff, ekBoldOff, ekJesusOff: O := O + '</char>';
        ekBoldOn: O := O + '<char style="bd">';
        ekJesusOn: O := O + '<char style="wj">';
        ekNoteOn:
          Begin
          If N >= Length(NoteX) Then SetLength(NoteX, N * 2);
          NoteX[N] := Num = 1;
          Inc(N);
          If Num = 1 Then O := O + '<note caller="-" style="x"><char style="xt">' Else O := O + '<note caller="+" style="f"><char style="ft">';
          End;
        ekNoteOff:
          If N > 0 Then
            Begin
            Dec(N);
            O := O + '</char></note>';
            End;
        ekXrefOn: If (Txt <> '') And (N = 0) Then O := O + '<ref loc="' + Esc(MkpOsisToHuman(Txt)) + '">' Else O := O + '<ref loc="">';
        ekXrefOff: O := O + '</ref>';
        ekHeadOn: If N = 0 Then O := O + '</para><para style="s1">';
        ekHeadOff: If N = 0 Then O := O + '</para><para style="p">';
        ekWordOn:
          Begin
          O := O + '<char style="w"';
          If Strong <> '' Then O := O + ' strong="' + StringReplace(Strong, ' ', ',', [rfReplaceAll]) + '"';
          If Morph <> '' Then O := O + ' x-morph="' + Esc(Morph) + '"';
          O := O + '>';
          End;
        ekWordOff: O := O + '</char>';
      End;
  WriteUSX := O;
  End;

{==================================================================== API}

Function MkpTranslate(Const S: AnsiString; From, Dest: MkpFormat; Opts: MkpOpts): AnsiString;
  Var
    D: TDoc;
    i, j: Integer;
  Begin
  D.N := 0;
  SetLength(D.Ev, 16);
  Case From Of
    mfPlain: Add(D, ekText, S);
    mfOSIS: ParseOSIS(S, D);
    mfThML: ParseThML(S, D);
    mfGBF: ParseGBF(S, D, False);
    mfMySword: ParseGBF(S, D, True);
    mfSTEP: ParseSTEP(S, D);
    mfTheWord: ParseGBF(S, D, True, True);
    mfVPL: ParseLight(S, D);
    mfHTML: ParseHTML(S, D);
    mfTEI: ParseTEI(S, D);
    mfUSFM: ParseUSFM(S, D);
    mfUSFX: ParseUSFX(S, D);
    mfZefania: ParseZefania(S, D);
    mfUSX: ParseUSX(S, D);
  End;
  Normalize(D);
  Balance(D);
  If Dest = mfThML Then
    Begin
    { ThML has no words of Jesus: without them neighbouring spans may touch }
    j := 0;
    For i := 0 To D.N - 1 Do
      If Not (D.Ev[i].Kind In [ekJesusOn, ekJesusOff]) Then
        Begin
        D.Ev[j] := D.Ev[i];
        Inc(j);
        End;
    D.N := j;
    MergeSpans(D);
    End;
  Case Dest Of
    mfPlain: MkpTranslate := WritePlain(D, Opts);
    mfSTEP: MkpTranslate := WriteRTF(D);                        {RTF fragment (theWord books); STEP modules themselves are read only}
    mfOSIS: MkpTranslate := WriteOSIS(D);
    mfThML: MkpTranslate := WriteThML(D);
    mfGBF: MkpTranslate := WriteGBF(D, False);
    mfVPL: MkpTranslate := WriteLight(D);
    mfHTML: MkpTranslate := WriteHTML(D);
    mfUSFM: MkpTranslate := WriteUSFM(D);
    mfUSFX: MkpTranslate := WriteUSFX(D);
    mfZefania: MkpTranslate := WriteZefania(D);
    mfUSX: MkpTranslate := WriteUSX(D);
    mfMySword, mfTheWord: MkpTranslate := WriteGBF(D, True);       {theWord reads what MySword reads}
  End;
  End;

Function MkpToXhtml(Const S: AnsiString; From: MkpFormat; VerseNum: Integer; WithNotes: Boolean;
  Var NoteCount: Integer; Var NoteHtml: AnsiString): AnsiString;
  Var
    D: TDoc;
  Begin
  D.N := 0;
  SetLength(D.Ev, 16);
  Case From Of
    mfPlain: Add(D, ekText, S);
    mfOSIS: ParseOSIS(S, D);
    mfThML: ParseThML(S, D);
    mfGBF: ParseGBF(S, D, False);
    mfMySword: ParseGBF(S, D, True);
    mfSTEP: ParseSTEP(S, D);
    mfTheWord: ParseGBF(S, D, True, True);
    mfVPL: ParseLight(S, D);
    mfHTML: ParseHTML(S, D);
    mfTEI: ParseTEI(S, D);
    mfUSFM: ParseUSFM(S, D);
    mfUSFX: ParseUSFX(S, D);
    mfZefania: ParseZefania(S, D);
    mfUSX: ParseUSX(S, D);
  End;
  Normalize(D);
  Balance(D);
  MkpToXhtml := WriteXhtml(D, VerseNum, WithNotes, NoteCount, NoteHtml);
  End;

Function MkpSummary(Const S: AnsiString; From: MkpFormat): AnsiString;
  Var
    D: TDoc;
    i, Words, Strongs, Morphs, N0, N1, X, J, H, P, L, It, B: Integer;
    Tok, Rest: AnsiString;
  Begin
  D.N := 0;
  SetLength(D.Ev, 16);
  Case From Of
    mfPlain: Add(D, ekText, S);
    mfOSIS: ParseOSIS(S, D);
    mfThML: ParseThML(S, D);
    mfGBF: ParseGBF(S, D, False);
    mfMySword: ParseGBF(S, D, True);
    mfSTEP: ParseSTEP(S, D);
    mfTheWord: ParseGBF(S, D, True, True);
    mfVPL: ParseLight(S, D);
    mfHTML: ParseHTML(S, D);
    mfTEI: ParseTEI(S, D);
    mfUSFM: ParseUSFM(S, D);
    mfUSFX: ParseUSFX(S, D);
    mfZefania: ParseZefania(S, D);
    mfUSX: ParseUSX(S, D);
  End;
  Normalize(D);
  Balance(D);
  Words := 0; Strongs := 0; Morphs := 0; N0 := 0; N1 := 0; X := 0; J := 0; H := 0; P := 0; L := 0; It := 0; B := 0;
  For i := 0 To D.N - 1 Do
    With D.Ev[i] Do
      Case Kind Of
        ekWordOn:
          Begin
          Inc(Words);
          Rest := Strong;
          While Rest <> '' Do Begin FirstTok(Rest, Tok); Rest := Tok; Inc(Strongs); End;
          Rest := Morph;
          While Rest <> '' Do Begin FirstTok(Rest, Tok); Rest := Tok; Inc(Morphs); End;
          End;
        ekNoteOn: If Num = 1 Then Inc(N1) Else Inc(N0);
        ekXrefOn: Inc(X);
        ekJesusOn: Inc(J);
        ekHeadOn: Inc(H);
        ekPara: Inc(P);
        ekLine: Inc(L);
        ekItalicOn: Inc(It);
        ekBoldOn: Inc(B);
      End;
  MkpSummary := 'text=' + IntToStr(Length(WritePlain(D, []))) + ' words=' + IntToStr(Words) + ' strongs=' + IntToStr(Strongs) +
    ' morph=' + IntToStr(Morphs) + ' notes=' + IntToStr(N0) + ' xnotes=' + IntToStr(N1) + ' xrefs=' + IntToStr(X) +
    ' jesus=' + IntToStr(J) + ' heads=' + IntToStr(H) + ' paras=' + IntToStr(P) + ' lines=' + IntToStr(L) +
    ' italic=' + IntToStr(It) + ' bold=' + IntToStr(B);
  End;

End.
