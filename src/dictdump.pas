Program DictDump;
{ Dump every entry of a dictionary in mod2imp's layout ("$$$key" then the entry text), to compare with
  Sword's mod2imp.   dictdump <module> [-p]     -p: plain text instead of the stored markup }
{$I MKBib.Def}
Uses MKBibMod, MKBibDic, MKDicAny, SysUtils;
Var
  D: AbsDictPtr;
  i: LongInt;
  Plain: Boolean;
  Rc: Word;
Begin
If ParamCount < 1 Then Begin WriteLn('usage: dictdump <module> [-p]'); Halt(1); End;
Plain := ParamStr(2) = '-p';
D := NewDictObj(ParamStr(1));
Rc := D^.OpenBible;
If Rc <> bibOk Then Begin WriteLn('cannot open (code ', Rc, ')'); Halt(2); End;
For i := 1 To D^.GetEntryCount Do
  Begin
  WriteLn('$$$', D^.GetKeyAt(i));
  If Plain Then WriteLn(D^.GetEntryTextAt(i)) Else WriteLn(D^.GetEntryAt(i));
  End;
End.
