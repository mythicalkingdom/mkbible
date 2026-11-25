Program ComRT;
{ Round trip a theWord commentary through this project's own reader/writer, then compare entry by entry.
    comrt <module.cmt.twm> <out dir> <new name> }
{$I MKBib.Def}
Uses MKBibMod, MKBibAbs, MKBibCom, MKComTwd, SysUtils;
Var
  Src, Chk: TheWordComObj;
  Dst: TheWordComObj;
  i: LongInt;
  FR, TR: BibRef;
  Rc: Word;
  Same, Diff: LongInt;
Begin
If ParamCount < 3 Then Begin WriteLn('usage: comrt <module.cmt.twm> <out dir> <new name>'); Halt(1); End;
Src.Init;
Src.SetBibPath(ParamStr(1));
If Src.OpenBible <> bibOk Then Begin WriteLn('cannot open source'); Halt(2); End;
Dst.Init;
Dst.SetOverwrite(True);
Dst.SetMarkup(Src.GetMarkup);
Dst.SetDescription(Src.GetDescription);
Dst.SetBibPath(ParamStr(2));
If Dst.CreateBible(ParamStr(3)) <> bibOk Then Begin WriteLn('cannot create the copy'); Halt(3); End;
For i := 1 To Src.GetEntryCount Do
  Begin
  Src.GetEntryRange(i, FR, TR);
  If Not Dst.PutEntry(FR, TR, '', Src.GetEntryAt(i)) Then WriteLn('PutEntry failed at ', i);
  End;
Rc := Dst.CloseBible;
WriteLn(Src.GetEntryCount, ' entries written, close code ', Rc);
Chk.Init;
Chk.SetBibPath(ParamStr(2) + '/' + ParamStr(3) + '.cmt.twm');
If Chk.OpenBible <> bibOk Then Begin WriteLn('cannot reopen the copy'); Halt(4); End;
WriteLn('reopened: ', Chk.GetEntryCount, ' entries');
Same := 0; Diff := 0;
For i := 1 To Src.GetEntryCount Do
  If Chk.GetEntryAt(i) = Src.GetEntryAt(i) Then Inc(Same) Else Inc(Diff);
WriteLn('identical text: ', Same, '  different: ', Diff);
Src.CloseBible;
Chk.CloseBible;
If Diff > 0 Then Halt(5);
End.
