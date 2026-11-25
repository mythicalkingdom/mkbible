Program BokRT;
{ Round trip a theWord general book through this project's own reader/writer, then compare node by node.
    bokrt <module.gbk.twm> <out dir> <new name> }
{$I MKBib.Def}
Uses MKBibMod, MKBibBok, MKBokTwd, SysUtils;
Var
  Src, Dst, Chk: TheWordBookObj;
  Rc: Word;
  Same, Diff, Total, C: LongInt;

Function Copy_(SrcNode, DstParent: LongInt): LongInt;
  Var Ch, NewNode: LongInt;
  Begin
  NewNode := Dst.AddNode(DstParent, Src.GetNodeTitle(SrcNode), Src.GetNodeText(SrcNode));
  Ch := Src.GetFirstChild(SrcNode);
  While Ch <> 0 Do
    Begin
    Copy_(Ch, NewNode);
    Ch := Src.GetNextSibling(Ch);
    End;
  Copy_ := NewNode;
  End;

Begin
If ParamCount < 3 Then Begin WriteLn('usage: bokrt <module.gbk.twm> <out dir> <new name>'); Halt(1); End;
Src.Init;
Src.SetBibPath(ParamStr(1));
If Src.OpenBible <> bibOk Then Begin WriteLn('cannot open source'); Halt(2); End;
Dst.Init;
Dst.SetOverwrite(True);
Dst.SetMarkup(Src.GetMarkup);
Dst.SetDescription(Src.GetDescription);
Dst.SetBibPath(ParamStr(2));
If Dst.CreateBible(ParamStr(3)) <> bibOk Then Begin WriteLn('cannot create the copy'); Halt(3); End;
C := Src.GetFirstChild(0);
While C <> 0 Do
  Begin
  Copy_(C, 0);
  C := Src.GetNextSibling(C);
  End;
Total := Src.GetNodeCount;
Rc := Dst.CloseBible;
WriteLn(Total, ' nodes written, close code ', Rc);
Chk.Init;
Chk.SetBibPath(ParamStr(2) + '/' + ParamStr(3) + '.gbk.twm');
If Chk.OpenBible <> bibOk Then Begin WriteLn('cannot reopen the copy'); Halt(4); End;
WriteLn('reopened: ', Chk.GetNodeCount, ' nodes');
Same := 0; Diff := 0;
For C := 1 To Total Do
  If (Chk.GetNodeTitle(C) = Src.GetNodeTitle(C)) And (Chk.GetNodeText(C) = Src.GetNodeText(C)) And
     (Chk.GetNodePath(C) = Src.GetNodePath(C)) Then Inc(Same) Else Inc(Diff);
WriteLn('identical (title+text+path): ', Same, '  different: ', Diff);
If (Chk.GetNodeCount <> Total) Or (Diff > 0) Then Halt(5);
Src.CloseBible;
Chk.CloseBible;
End.
