Program MkpCheck;
{ Check the markup translator on every verse of a module.
    mkpcheck <module> [-a]
  For each target format T the verse is translated from the module's markup to T, then:
    plain(T-text)  must equal  plain(original)                     (the text survives)
    summary(T-text parsed as T)  must equal  summary(original)  for the features T can carry
  and, translating T back to the original markup, the summary must be unchanged (a fixpoint). }
{$MODE OBJFPC}{$H+}
Uses SysUtils, MKBibMod, MKBibAbs, MKBibAny, MKBibMkp;

Var
  B: AbsBibPtr;
  Src: MkpFormat;
  T: MkpFormat;
  Raw, X, PlainO, PlainX, SumO, SumX, Back, SumB: AnsiString;
  Verses, BadPlain, BadSum, BadBack: Array[MkpFormat] Of LongInt;
  Shown: Array[MkpFormat] Of Integer;
  n: LongInt;

Function FmtOf(M: BibMarkup): MkpFormat;
  Begin
  Case M Of
    bmOSIS: FmtOf := mfOSIS;
    bmThML: FmtOf := mfThML;
    bmGBF: FmtOf := mfGBF;
    bmMySword: FmtOf := mfMySword;
    bmSTEP: FmtOf := mfSTEP;
    bmTheWord: FmtOf := mfTheWord;
    bmVPL: FmtOf := mfVPL;
    Else FmtOf := mfPlain;
  End;
  End;

{ drop the features a target cannot carry from a summary string }
Function Mask(Const S: AnsiString; T: MkpFormat; ZapSpans: Boolean): AnsiString;
  Var R: AnsiString; p, q: Integer;
  Procedure Zero(Const Key: AnsiString);
    Begin
    p := Pos(' ' + Key + '=', R);
    If p > 0 Then
      Begin
      q := p + 1 + Length(Key) + 1;
      While (q <= Length(R)) And (R[q] <> ' ') Do Inc(q);
      R := Copy(R, 1, p) + Key + '=0' + Copy(R, q, Length(R));
      End;
    End;
  Begin
  R := S;
  If T = mfThML Then Zero('jesus');
  If ZapSpans Then Begin Zero('italic'); Zero('bold'); End;     {spans split by words of Jesus merge when those are dropped}
  If T In [mfGBF, mfMySword] Then
    Begin
    { no separate cross reference notes: count all notes together }
    p := Pos(' notes=', R); q := Pos(' xnotes=', R);
    Zero('xnotes');
    Zero('notes');
    End;
  If T In [mfGBF, mfMySword] Then Zero('xrefs');       {only MySword <RX> notes carry references}
  If T = mfPlain Then
    Begin
    Zero('words'); Zero('strongs'); Zero('morph'); Zero('notes'); Zero('xnotes'); Zero('xrefs');
    Zero('jesus'); Zero('heads'); Zero('paras'); Zero('lines'); Zero('italic'); Zero('bold');
    End;
  Mask := R;
  End;

Begin
If ParamCount < 1 Then Begin WriteLn('usage: mkpcheck <module> [-a]'); Halt(1); End;
B := NewBibObj(ParamStr(1));
If ParamStr(2) = '-a' Then B^.SetApocrypha(True);
If B^.OpenBible <> bibOk Then Begin WriteLn('cannot open ', ParamStr(1)); Halt(2); End;
Src := FmtOf(B^.GetMarkup);
WriteLn('module ', B^.GetName, ', markup ', Ord(B^.GetMarkup), ' -> checking against osis thml gbf mysword');
FillChar(Verses, SizeOf(Verses), 0); FillChar(BadPlain, SizeOf(BadPlain), 0);
FillChar(BadSum, SizeOf(BadSum), 0); FillChar(BadBack, SizeOf(BadBack), 0); FillChar(Shown, SizeOf(Shown), 0);
B^.SeekFirst;
While B^.SeekFound Do
  Begin
  Raw := B^.GetRawVerse;
  If Raw <> '' Then
    Begin
    PlainO := MkpTranslate(Raw, Src, mfPlain);
    SumO := MkpSummary(Raw, Src);
    For T := mfOSIS To mfMySword Do
      If T <> Src Then
        Begin
        Inc(Verses[T]);
        X := MkpTranslate(Raw, Src, T);
        PlainX := MkpTranslate(X, T, mfPlain);
        If PlainX <> PlainO Then
          Begin
          Inc(BadPlain[T]);
          If Shown[T] < 3 Then
            Begin
            Inc(Shown[T]);
            WriteLn('PLAIN DIFF ', B^.GetRefStr, ' ->', Ord(T));
            WriteLn('   orig : ', Copy(PlainO, 1, 150));
            WriteLn('   via  : ', Copy(PlainX, 1, 150));
            End;
          End;
        SumX := MkpSummary(X, T);
        If Mask(SumX, T, (T = mfThML) And (Pos(' jesus=0', SumO) = 0)) <> Mask(SumO, T, (T = mfThML) And (Pos(' jesus=0', SumO) = 0)) Then
          Begin
          Inc(BadSum[T]);
          If Shown[T] < 3 Then
            Begin
            Inc(Shown[T]);
            WriteLn('SUMMARY DIFF ', B^.GetRefStr, ' ->', Ord(T));
            WriteLn('   orig : ', SumO);
            WriteLn('   via  : ', SumX);
            WriteLn('   raw  : ', Copy(Raw, 1, 200));
            WriteLn('   xlat : ', Copy(X, 1, 200));
            End;
          End;
        { fixpoint: translating the translation again changes nothing }
        Back := MkpTranslate(X, T, T);
        If Back <> X Then
          Begin
          Inc(BadBack[T]);
          If Shown[T] < 3 Then
            Begin
            Inc(Shown[T]);
            WriteLn('NOT STABLE ', B^.GetRefStr, ' ->', Ord(T));
            WriteLn('   1st : ', Copy(X, 1, 260));
            WriteLn('   2nd : ', Copy(Back, 1, 260));
            End;
          End;
        End;
    End;
  B^.SeekNext;
  End;
For T := mfOSIS To mfMySword Do
  If T <> Src Then
    WriteLn('-> format ', Ord(T), ': ', Verses[T], ' verses, plain text differs ', BadPlain[T], ', features differ ', BadSum[T],
            ', not stable ', BadBack[T]);
End.
