Program ComTest;
{ Try a theWord commentary (.cmt.twm).
    comtest <module.cmt.twm>                   module information
    comtest <module.cmt.twm> <ref>             the entry covering "John 3:16" (or "Matt 1" or "Matt")
    comtest <module.cmt.twm> -l [first [n]]    list n entries (default 20) from entry number first }
{$I MKBib.Def}
Uses MKBibMod, MKBibAbs, MKBibCom, MKComTwd, SysUtils;
Var
  D: TheWordComObj;
  i, First, N, Idx: LongInt;
  Rc: Word;
  FR, TR: BibRef;
Begin
If ParamCount < 1 Then Begin WriteLn('usage: comtest <module.cmt.twm> [ref | -l [first [n]]]'); Halt(1); End;
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
  WriteLn('Entries    : ', D.GetEntryCount, '   markup code ', Ord(D.GetMarkup));
  D.GetEntryRange(1, FR, TR);
  WriteLn('First entry: ', D.GetBookName(FR.Book), ' ', FR.Chapter, ':', FR.Verse,
          ' - ', D.GetBookName(TR.Book), ' ', TR.Chapter, ':', TR.Verse);
  End
Else If ParamStr(2) = '-l' Then
  Begin
  First := 1; N := 20;
  If ParamCount >= 3 Then First := StrToIntDef(ParamStr(3), 1);
  If ParamCount >= 4 Then N := StrToIntDef(ParamStr(4), 20);
  For i := First To First + N - 1 Do
    If i <= D.GetEntryCount Then
      Begin
      D.GetEntryRange(i, FR, TR);
      WriteLn(i, ': ', D.GetBookName(FR.Book), ' ', FR.Chapter, ':', FR.Verse,
              ' - ', D.GetBookName(TR.Book), ' ', TR.Chapter, ':', TR.Verse);
      End;
  End
Else
  Begin
  If Not D.SetRefStr(ParamStr(2)) Then WriteLn('cannot parse ', ParamStr(2))
  Else
    Begin
    Idx := D.FindEntryForVerse(D.GetBook, D.GetChapter, D.GetVerse, 0);
    If Idx = 0 Then WriteLn('no entry covers ', D.GetRefStr)
    Else
      Begin
      D.GetEntryRange(Idx, FR, TR);
      WriteLn('[entry ', Idx, ' of ', D.GetEntryCount, ']  ', D.GetBookName(FR.Book), ' ', FR.Chapter, ':', FR.Verse,
              ' - ', D.GetBookName(TR.Book), ' ', TR.Chapter, ':', TR.Verse);
      WriteLn(D.GetEntryAt(Idx));
      End;
    End;
  End;
D.CloseBible;
End.
