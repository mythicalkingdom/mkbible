Program DictConv;
{ dictconv - convert a dictionary from one format to another.

  usage: dictconv <source> [-n NewName] [-t sword|mysword|theword] [-o dir] [-m markup] [-D desc] [-f]
     <source>   a Sword dictionary (module name or .conf), a .dct.mybible file, or a theWord .dct.twm file
     -n <name>  name of the new module (default: the source's name)
     -t         target format, default sword
     -o <dir>   output directory (Sword: mods.d/ and modules/ go below it)     default .
     -m auto|same|plain|html|rtf|thml|osis|gbf
                markup of the entries in the new module.  auto keeps the source markup when the target can hold
                it (Sword: TEI, OSIS, ThML, GBF, plain;  MySword: HTML, plain; theWord: RTF, plain) and otherwise translates (to ThML for
                Sword, to HTML for MySword, to RTF for theWord).  plain: plain text.
     -D <text>  description override         -f  replace an existing module

  The name, description, language, version, copyright and Strong's flag are copied. }
{$MODE OBJFPC}{$H+}
{$I-}
Uses SysUtils, MKBibMod, MKBibMkp, MKBibDic, MKDicSwd, MKDicMys, MKDicTwd, MKDicAny;

Var
  SrcName, NewName, Tg, Root, Mk, Desc: String;
  Force: Boolean;
  Src, Dst, Chk: AbsDictPtr;
  SwdD: SwordDictObj;
  MysD: MySwordDictObj;
  TwdD: TheWordDictObj;
  i, Failed, Empty, Counted, NSrc: LongInt;
  Rc: Word;
  SrcFmt, DstFmt: MkpFormat;
  DstMk: BibMarkup;
  Raw: Boolean;
  Txt: BibStr;
  K: Integer;
  Order, NextDup: Array Of LongInt;
  Skip: Array Of Boolean;
  UK: Array Of AnsiString;
  NMerged, NNoKey, Gap, j, m, cur: LongInt;
  tmp: LongInt;
  Sep: BibStr;

Procedure Usage;
  Begin
  WriteLn('usage: dictconv <source> [-n NewName] [-t sword|mysword] [-o dir] [-m auto|same|plain|html|thml|osis|gbf] [-D desc] [-f]');
  Halt(1);
  End;

Function MarkupName(M: BibMarkup): String;
  Begin
  Case M Of
    bmPlain: MarkupName := 'plain text';
    bmOSIS: MarkupName := 'OSIS';
    bmThML: MarkupName := 'ThML';
    bmGBF: MarkupName := 'GBF';
    bmTEI: MarkupName := 'TEI';
    bmHTML: MarkupName := 'HTML';
    bmRTF: MarkupName := 'RTF';
    Else MarkupName := 'other';
  End;
  End;

Begin
If ParamCount < 1 Then Usage;
SrcName := ParamStr(1);
NewName := ''; Tg := 'sword'; Root := '.'; Mk := 'auto'; Desc := ''; Force := False;
K := 2;
While K <= ParamCount Do
  Begin
  If ParamStr(K) = '-f' Then Force := True
  Else If K < ParamCount Then
    Begin
    If ParamStr(K) = '-n' Then NewName := ParamStr(K + 1)
    Else If ParamStr(K) = '-t' Then Tg := LowerCase(ParamStr(K + 1))
    Else If ParamStr(K) = '-o' Then Root := ParamStr(K + 1)
    Else If ParamStr(K) = '-m' Then Mk := LowerCase(ParamStr(K + 1))
    Else If ParamStr(K) = '-D' Then Desc := ParamStr(K + 1)
    Else Usage;
    Inc(K);
    End
  Else Usage;
  Inc(K);
  End;

Src := NewDictObj(SrcName);
Rc := Src^.OpenBible;
If Rc <> bibOk Then
  Begin
  Case Rc Of
    bibErrNotFound: WriteLn('source not found: ', SrcName);
    bibErrLocked: WriteLn('source is locked or encrypted');
    bibErrUnsupported: WriteLn('source format or storage is not supported');
    Else WriteLn('cannot open source (code ', Rc, ')');
  End;
  Halt(2);
  End;
If NewName = '' Then NewName := Src^.GetName;
If NewName = '' Then NewName := 'Converted';
For K := 1 To Length(NewName) Do If NewName[K] = ' ' Then NewName[K] := '_';

If Tg = 'mysword' Then Begin MysD.Init; Dst := @MysD; End
Else If Tg = 'theword' Then Begin TwdD.Init; Dst := @TwdD; End
Else If Tg = 'sword' Then Begin SwdD.Init; Dst := @SwdD; End
Else Usage;

{ markup policy }
SrcFmt := Src^.GetMkpFormat;
Raw := False;
If Mk = 'auto' Then
  Begin
  If Tg = 'mysword' Then
    Begin
    If Src^.GetMarkup In [bmHTML, bmPlain] Then Mk := 'same' Else Mk := 'html';
    End
  Else
    Begin
    If Src^.GetMarkup In [bmTEI, bmOSIS, bmThML, bmGBF, bmPlain] Then Mk := 'same' Else Mk := 'thml';
    End;
  If Tg = 'theword' Then
    Begin
    If Src^.GetMarkup In [bmRTF, bmPlain] Then Mk := 'same' Else Mk := 'rtf';
    End;
  End;
If Mk = 'same' Then
  Begin
  Raw := True;
  DstMk := Src^.GetMarkup;
  If ((Tg = 'mysword') And Not (DstMk In [bmHTML, bmPlain])) Or
     ((Tg = 'theword') And Not (DstMk In [bmRTF, bmPlain])) Or
     ((Tg = 'sword') And Not (DstMk In [bmTEI, bmOSIS, bmThML, bmGBF, bmPlain])) Then
    Begin
    WriteLn('the source markup (', MarkupName(DstMk), ') cannot be stored as it is in that target; use -m auto, plain or another markup');
    Halt(3);
    End;
  DstFmt := SrcFmt;
  End
Else If Mk = 'plain' Then Begin DstMk := bmPlain; DstFmt := mfPlain; End
Else If Mk = 'html' Then Begin DstMk := bmHTML; DstFmt := mfHTML; End
Else If Mk = 'thml' Then Begin DstMk := bmThML; DstFmt := mfThML; End
Else If Mk = 'osis' Then Begin DstMk := bmOSIS; DstFmt := mfOSIS; End
Else If Mk = 'gbf' Then Begin DstMk := bmGBF; DstFmt := mfGBF; End
Else If Mk = 'rtf' Then Begin DstMk := bmRTF; DstFmt := mfSTEP; End
Else Usage;
If (Tg = 'mysword') And Not (DstMk In [bmHTML, bmPlain]) Then
  Begin WriteLn('a MySword dictionary holds HTML or plain text'); Halt(3); End;
If (Tg = 'theword') And Not (DstMk In [bmRTF, bmPlain]) Then
  Begin WriteLn('a theWord dictionary holds RTF or plain text'); Halt(3); End;
If (Not Raw) And Not Src^.CanTranslateMarkup Then
  Begin WriteLn('the source markup cannot be translated; use -m same'); Halt(3); End;
Dst^.SetMarkup(DstMk);
Dst^.SetLang(Src^.GetLang);
Dst^.SetVersion(Src^.GetVersion);
Dst^.SetCopyright(Src^.GetCopyright);
Dst^.SetAbout(Src^.GetAbout);
If Desc <> '' Then Dst^.SetDescription(Desc) Else Dst^.SetDescription(Src^.GetDescription);
Dst^.SetStrongs(Src^.IsStrongs, Src^.GetStrongsPrefix);
Dst^.SetOverwrite(Force);
Dst^.SetBibPath(Root);
Rc := Dst^.CreateBible(NewName);
Case Rc Of
  bibOk: ;
  bibErrExists: Begin WriteLn('module ', NewName, ' already exists in ', Root, ' (use -f to replace)'); Halt(4); End;
  Else Begin WriteLn('cannot create the new module (code ', Rc, ')'); Halt(4); End;
End;

WriteLn('converting ', Src^.GetName, ' (', MarkupName(Src^.GetMarkup), ', ', Src^.GetEntryCount, ' entries) -> ', NewName,
        ' (', MarkupName(DstMk), ', ', Tg, ')');
Failed := 0; Empty := 0; NMerged := 0; NNoKey := 0;
{ entries with the same key (ignoring case) cannot all be kept as they are: they are merged into the first one }
SetLength(Order, Src^.GetEntryCount + 1);
SetLength(NextDup, Src^.GetEntryCount + 1);
SetLength(Skip, Src^.GetEntryCount + 1);
SetLength(UK, Src^.GetEntryCount + 1);
For i := 1 To Src^.GetEntryCount Do
  Begin
  Order[i] := i; NextDup[i] := 0; Skip[i] := False;
  UK[i] := UpperCase(Src^.GetKeyAt(i));
  End;
Gap := Src^.GetEntryCount Div 2;
While Gap > 0 Do
  Begin
  For i := Gap + 1 To Src^.GetEntryCount Do
    Begin
    tmp := Order[i];
    j := i;
    While (j > Gap) And ((UK[Order[j - Gap]] > UK[tmp]) Or ((UK[Order[j - Gap]] = UK[tmp]) And (Order[j - Gap] > tmp))) Do
      Begin
      Order[j] := Order[j - Gap];
      Dec(j, Gap);
      End;
    Order[j] := tmp;
    End;
  Gap := Gap Div 2;
  End;
For i := 2 To Src^.GetEntryCount Do
  If (UK[Order[i]] = UK[Order[i - 1]]) And (UK[Order[i]] <> '') Then
    Begin
    Skip[Order[i]] := True;
    m := Order[i - 1];
    While NextDup[m] <> 0 Do m := NextDup[m];
    NextDup[m] := Order[i];
    End;
Case Src^.GetMarkup Of
  bmRTF: Sep := '\par \par ';
  bmHTML: Sep := '<br><br>';
  bmTEI: Sep := '<lb/><lb/>';
  bmOSIS, bmThML: Sep := '<lb/><lb/>';
  bmGBF: Sep := '<CM>';
  Else Sep := #10#10;
End;
For i := 1 To Src^.GetEntryCount Do
  Begin
  If Skip[i] Then
    Begin
    Inc(NMerged);
    Continue;
    End;
  If UK[i] = '' Then
    Begin
    Inc(NNoKey);                                  {an entry without a key cannot be stored}
    Continue;
    End;
  Txt := Src^.GetEntryAt(i);
  cur := NextDup[i];
  While cur <> 0 Do
    Begin
    Txt := Txt + Sep + Src^.GetEntryAt(cur);
    cur := NextDup[cur];
    End;
  If (Txt <> '') And (Not Raw) Then
    Begin
    If DstFmt = mfPlain Then Txt := MkpTranslate(Txt, SrcFmt, mfPlain, [moHeadings, moBreaks])
    Else Txt := MkpTranslate(Txt, SrcFmt, DstFmt);
    End;
  If Txt = '' Then Inc(Empty);
  If Not Dst^.PutEntry(Src^.GetKeyAt(i), Txt) Then Inc(Failed);
  End;
NSrc := Src^.GetEntryCount;
Src^.CloseBible;
Rc := Dst^.CloseBible;
If Rc <> bibOk Then Begin WriteLn('error finishing the new module (code ', Rc, ')'); Halt(5); End;
WriteLn(NSrc, ' entries, ', Empty, ' empty, ', Failed, ' failed');
If NMerged > 0 Then WriteLn(NMerged, ' entries with a repeated key were merged into the first one with that key');
If NNoKey > 0 Then WriteLn(NNoKey, ' entries without a key were skipped');
If Tg = 'theword' Then Chk := NewDictObj(Root + '/' + NewName + '.dct.twm')
Else If Tg = 'mysword' Then Chk := NewDictObj(Root + '/' + NewName + '.dct.mybible')
Else Chk := NewDictObj(Root + '/mods.d/' + LowerCase(NewName) + '.conf');
If Chk^.OpenBible <> bibOk Then Begin WriteLn('verify: cannot open the new module'); Halt(6); End;
Counted := Chk^.GetEntryCount;
Chk^.CloseBible;
WriteLn('verified: ', Counted, ' entries read back');
End.
