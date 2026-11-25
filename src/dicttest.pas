Program DictTest;
{ Try a dictionary.
    dicttest <module>                    module information
    dicttest <module> <key>              the entry for a key (exact, Strong's numbers are flexible, else prefix)
    dicttest <module> -l [first [n]]     list n keys (default 20) from entry number first
    dicttest <module> -s <text> [-k|-t]  search keys (-k), entry texts (-t) or both }
{$I MKBib.Def}
Uses MKBibMod, MKBibDic, MKDicAny, SysUtils;
Var
  D: AbsDictPtr;
  i, First, N: LongInt;
  Rc: Word;
  Sc: DictScope;
  Shown: Integer;
Begin
If ParamCount < 1 Then Begin WriteLn('usage: dicttest <module> [key | -l [first [n]] | -s text [-k|-t]]'); Halt(1); End;
D := NewDictObj(ParamStr(1));
Rc := D^.OpenBible;
If Rc <> bibOk Then
  Begin
  WriteLn('OpenBible failed, code ', Rc);
  If Rc = bibErrLocked Then WriteLn('Module is locked: ', D^.GetUnlockInfo);
  Halt(2);
  End;
If ParamCount = 1 Then
  Begin
  WriteLn('Module     : ', D^.GetName);
  WriteLn('Description: ', D^.GetDescription);
  WriteLn('Language   : ', D^.GetLang, '   Version: ', D^.GetVersion);
  WriteLn('Copyright  : ', D^.GetCopyright);
  WriteLn('Entries    : ', D^.GetEntryCount, '   Strong''s keys: ', D^.IsStrongs, '   markup code ', Ord(D^.GetMarkup));
  D^.SeekFirst;
  WriteLn('First key  : ', D^.GetKey);
  D^.SeekLast;
  WriteLn('Last key   : ', D^.GetKey);
  End
Else If ParamStr(2) = '-l' Then
  Begin
  First := 1; N := 20;
  If ParamCount >= 3 Then First := StrToIntDef(ParamStr(3), 1);
  If ParamCount >= 4 Then N := StrToIntDef(ParamStr(4), 20);
  For i := First To First + N - 1 Do
    If i <= D^.GetEntryCount Then WriteLn(i, ': ', D^.GetKeyAt(i));
  End
Else If ParamStr(2) = '-s' Then
  Begin
  Sc := dsBoth;
  If ParamStr(4) = '-k' Then Sc := dsKeys Else If ParamStr(4) = '-t' Then Sc := dsText;
  Shown := 0;
  D^.SearchFirst(ParamStr(3), False, Sc);
  While D^.SearchFound And (Shown < 20) Do
    Begin
    Inc(Shown);
    WriteLn(D^.GetCurIndex, ': ', D^.GetKey);
    D^.SearchNext;
    End;
  WriteLn(Shown, ' shown');
  End
Else
  Begin
  D^.SeekKey(ParamStr(2));
  If Not D^.SeekFound Then WriteLn('no entry for ', ParamStr(2))
  Else
    Begin
    WriteLn('[', D^.GetKey, ']  (entry ', D^.GetCurIndex, ' of ', D^.GetEntryCount, ')');
    WriteLn(D^.GetEntryText);
    End;
  End;
End.
