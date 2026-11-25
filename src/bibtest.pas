Program BibTest;
{ Command line test for the MK Bible objects.
    bibtest <module|conf|dir>                     module information
    bibtest <module> "John 3:16"                  show a verse
    bibtest <module> "Psalm 23" -c                show a whole chapter
    bibtest <module> -s "text" [-n max] [-ot|-nt|-ap] search
  Options: -a include the Apocrypha, -k <unlock key> for an enciphered module }

{$I MKBib.Def}

Uses MKBibMod, MKBibAbs, MKBibSwd, MKBibAny, SysUtils;

Var
  Bib: AbsBibPtr;
  IsSword: Boolean;
  Rc: Word;
  i, N, Max: Integer;
  Ref, Srch, A: String;
  WholeChap, OnlyOT, OnlyNT, OnlyAp, UseAp: Boolean;
  UKey: String;
  Ch: Word;

Begin
If ParamCount < 1 Then
  Begin
  WriteLn('usage: bibtest <module> [reference [-c]] | -s text [-n max] [-ot|-nt]');
  Halt(1);
  End;
Ref := ''; Srch := ''; WholeChap := False; Max := 20; OnlyOT := False; OnlyNT := False; OnlyAp := False; UseAp := False; UKey := '';
i := 2;
While i <= ParamCount Do
  Begin
  A := ParamStr(i);
  If A = '-c' Then WholeChap := True
  Else If A = '-ot' Then OnlyOT := True
  Else If A = '-nt' Then OnlyNT := True
  Else If A = '-ap' Then OnlyAp := True
  Else If A = '-a' Then UseAp := True
  Else If (A = '-k') And (i < ParamCount) Then Begin Inc(i); UKey := ParamStr(i); End
  Else If (A = '-s') And (i < ParamCount) Then Begin Inc(i); Srch := ParamStr(i); End
  Else If (A = '-n') And (i < ParamCount) Then Begin Inc(i); Max := StrToIntDef(ParamStr(i), 20); End
  Else Ref := A;
  Inc(i);
  End;

IsSword := DetectBibKind(ParamStr(1)) = bkSword;
Bib := NewBibObj(ParamStr(1));
If UKey <> '' Then Bib^.SetUnlockKey(UKey);
If UseAp Or OnlyAp Then Bib^.SetApocrypha(True);
Rc := Bib^.OpenBible;
If Rc <> bibOk Then
  Begin
  WriteLn('OpenBible failed, code ', Rc);
  If Rc = bibErrLocked Then WriteLn('Module is locked: ', Bib^.GetUnlockInfo);
  Halt(2);
  End;

If (Ref = '') And (Srch = '') Then
  Begin
  WriteLn('Module     : ', Bib^.GetName);
  WriteLn('Description: ', Bib^.GetDescription);
  WriteLn('Language   : ', Bib^.GetLang, '   Version: ', Bib^.GetVersion);
  WriteLn('Copyright  : ', Bib^.GetCopyright);
  WriteLn('Testaments : OT=', Bib^.HasOT, ' NT=', Bib^.HasNT);
  If IsSword Then
    Begin
    WriteLn('Conf       : ', SwordBibPtr(Bib)^.GetConfPath);
    WriteLn('Data       : ', SwordBibPtr(Bib)^.GetDataPath);
    End;
  WriteLn('Verses     : ', Bib^.GetTotalVerses, '  Books: ', Bib^.GetBookCount, '  Apocrypha: ', Bib^.HasApocrypha);
  End
Else If Srch <> '' Then
  Begin
  If OnlyOT Then Bib^.SetSearchScope(bsOT)
  Else If OnlyNT Then Bib^.SetSearchScope(bsNT)
  Else If OnlyAp Then Bib^.SetSearchScope(bsApoc);
  N := 0;
  Bib^.SearchFirst(Srch, False);
  While Bib^.SearchFound And (N < Max) Do
    Begin
    Inc(N);
    WriteLn(Bib^.GetRefStr, ' - ', Bib^.GetVerseText);
    Bib^.SearchNext;
    End;
  WriteLn(N, ' shown');
  End
Else
  Begin
  If Not Bib^.SetRefStr(Ref) Then
    Begin
    WriteLn('Cannot parse reference "', Ref, '"');
    Halt(3);
    End;
  If WholeChap Then
    Begin
    Ch := Bib^.GetChapter;
    Bib^.SetRef(Bib^.GetBook, Ch, 1);
    While Bib^.SeekFound And (Bib^.GetChapter = Ch) Do
      Begin
      WriteLn(Bib^.GetChapter, ':', Bib^.GetVerse, ' ', Bib^.GetVerseText);
      Bib^.SeekNext;
      End;
    End
  Else
    Begin
    WriteLn(Bib^.GetRefStr);
    Bib^.TextStartUp;
    While Not Bib^.EOM Do
      WriteLn('  ', Bib^.GetString(60));
    End;
  End;
Bib^.Done;
End.
