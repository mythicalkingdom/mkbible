Program BokTest;
{ Try a theWord general book (.gbk.twm).
    boktest <module.gbk.twm>              module information and the top level table of contents
    boktest <module.gbk.twm> <node#>      that node's title, path and text }
{$I MKBib.Def}
Uses MKBibMod, MKBibBok, MKBokTwd, SysUtils, StrUtils;
Var
  D: TheWordBookObj;
  Rc: Word;
  N, Node: LongInt;

Procedure ShowChildren(Parent, Depth: LongInt);
  Var C: LongInt;
  Begin
  C := D.GetFirstChild(Parent);
  While C <> 0 Do
    Begin
    WriteLn(StringOfChar(' ', Depth * 2), C, ': ', D.GetNodeTitle(C));
    If Depth < 1 Then ShowChildren(C, Depth + 1);
    C := D.GetNextSibling(C);
    End;
  End;

Begin
If ParamCount < 1 Then Begin WriteLn('usage: boktest <module.gbk.twm> [node#]'); Halt(1); End;
D.Init;
D.SetBibPath(ParamStr(1));
Rc := D.OpenBible;
If Rc <> bibOk Then
  Begin
  WriteLn('OpenBible failed, code ', Rc);
  Halt(2);
  End;
If ParamCount = 1 Then
  Begin
  WriteLn('Module     : ', D.GetName);
  WriteLn('Description: ', D.GetDescription);
  WriteLn('Language   : ', D.GetLang, '   Version: ', D.GetVersion);
  WriteLn('Copyright  : ', D.GetCopyright);
  WriteLn('Nodes      : ', D.GetNodeCount, '   markup code ', Ord(D.GetMarkup));
  ShowChildren(0, 0);
  End
Else
  Begin
  Node := StrToIntDef(ParamStr(2), 0);
  If (Node < 1) Or (Node > D.GetNodeCount) Then WriteLn('no such node')
  Else
    Begin
    WriteLn('[', Node, ']  ', D.GetNodePath(Node));
    WriteLn(D.GetNodeText(Node));
    End;
  End;
D.CloseBible;
End.
