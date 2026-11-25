Program BibDump;
{ Dump every verse of a module in a mod2imp-like layout ("$$$Book c:v" then the
  raw text), for checking against Sword's own mod2imp.   bibdump <module> [-a] [-k key] [-p] }
{ -p dumps the plain text (markup removed) instead of the raw text }
{$I MKBib.Def}
Uses MKBibMod, MKBibAbs, MKBibAny, SysUtils;
Var I: Integer; Plain: Boolean; B: AbsBibPtr; S: BibStr;
Begin
B := NewBibObj(ParamStr(1));
Plain := False;
For I := 2 To ParamCount Do
  Begin
  If ParamStr(I) = '-a' Then B^.SetApocrypha(True)
  Else If ParamStr(I) = '-p' Then Plain := True
  Else If (ParamStr(I) = '-k') And (I < ParamCount) Then B^.SetUnlockKey(ParamStr(I + 1));
  End;
If B^.OpenBible <> bibOk Then Halt(2);
B^.SeekFirst;
While B^.SeekFound Do
  Begin
  If Plain Then S := B^.GetVerseText Else S := B^.GetRawVerse;
  If S <> '' Then
    Begin
    WriteLn('$$$', B^.GetBookOSIS(B^.GetBook), ' ', B^.GetChapter, ':', B^.GetVerse);
    WriteLn(S);
    End;
  B^.SeekNext;
  End;
End.
