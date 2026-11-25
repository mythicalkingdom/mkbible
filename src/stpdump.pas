Program StpDump;
{ Dump the raw section text of every verse of a STEP module in the format of CrossWire's
  step2vpl ("<name> <text>", line ends removed), to compare the reader with it. }
{$I MKBib.Def}
Uses MKBibMod, MKBibAbs, MKBibVrs, MKBibStp, SysUtils;
Var
  S: StepBibObj;
  B, C, V: Word;
  T: BibStr;
  L, Sec, i: LongInt;
  Nm: BibStr;
  R: SecRec;
Begin
S.Init;
S.SetBibPath(ParamStr(1));
If S.OpenBible <> bibOk Then Halt(2);
For B := 1 To 66 Do
  For C := 1 To VrsChapters(vsKJV, B) Do
    For V := 1 To VrsVerses(vsKJV, B, C) Do
      Begin
      L := VrsLinear(vsKJV, B, C, V);
      Sec := S.VerseSec^[L] - 1;
      If Sec < 0 Then Continue;
      S.ReadSec(Sec, R);
      Nm := S.SecName(R.NameOfs);
      T := S.SecText(Sec, False);
      i := 1;
      While i <= Length(T) Do
        Begin
        If (T[i] = #10) Or (T[i] = #13) Then Delete(T, i, 1) Else Inc(i);
        End;
      WriteLn(Nm, ' ', T);
      End;
End.
