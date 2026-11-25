Program BibConv;
{ bibconv - convert a Bible module from one format to another.

  usage: bibconv <source> [-n <NewName>] [options]
     <source>   a Sword module name / .conf file / Sword directory, or a .bbl.mybible file
     -n <name>  name of the new module (default: the source's name)
     -t zip|lzss|raw|mysword|theword|vpl|osis|zefania|usfx|usfm   target format           default zip
     -o <dir>   output root (Sword: mods.d/ + modules/;  MySword: the .bbl.mybible lands here)   default .
     -b book|chapter|verse     Sword zText block type              default book
     -m auto|same|plain|osis|thml|gbf|mysword|theword|vpl|zefania|usfx|usfm    markup of the text in the new module   default auto
     -r         same as -m same
     -k <key>   unlock key of an enciphered source          -e <key>  encipher the new Sword module
     -D <text>  description override                        -f        replace an existing module

  Markup.  The text is translated between OSIS, ThML, GBF and MySword markup (Mkp unit): notes,
  cross references, headings, paragraphs, italics, bold, words of Jesus, Strong's numbers and
  morphology are kept wherever the target markup can carry them (ThML cannot carry words of
  Jesus), everything else is dropped, never mangled.
     auto    MySword target: MySword markup.  Sword target: the source's markup when it is OSIS,
             ThML or GBF, else OSIS.  When source and target markup are the same the text is
             copied untouched.
     same    copy untouched (the target must accept the source's markup)
     plain   plain text: markup, notes, headings and Strong's numbers removed
     osis thml gbf   (Sword targets)     mysword   (MySword target)
  Introductions (module, testament, book and chapter) are copied where the target has them
  (MySword keeps chapter introductions only), translated like the verses.

  The name, description, language, version and copyright are copied.  The verse structure must be
  the same in both formats (MySword: KJV only; a KJVA/NRSVA source keeps its Apocrypha when the
  target is Sword). }

{$MODE OBJFPC}{$H+}
{$I-}

Uses SysUtils, MKBibVrs, MKBibMod, MKBibAbs, MKBibSwd, MKBibMys, MKBibTwd, MKBibVpl, MKBibOsi, MKBibZef, MKBibUfx, MKBibUsf,
  MKBibAny, MKBibMkp;

Var
  SrcName, NewName, Tg, Root, Bk, SKey, EKey, Desc, Mk: String;
  Raw, Force: Boolean;
  SrcFmt, DstFmt: MkpFormat;
  DstMk: BibMarkup;
  IntroCount: LongInt;
  SwdD: SwordBibObj;
  MysD: MySwordBibObj;
  TwdD: TheWordBibObj;
  VplD: VplBibObj;
  OsiD: OsisBibObj;
  ZefD: ZefaniaBibObj;
  UfxD: UsfxBibObj;
  UsfD: UsfmBibObj;
  DstMem: Boolean;
  MemFile: String;
  OwnMk: BibMarkup;
  Src, Dst, Chk: AbsBibPtr;
  DstMys, DstTw, DstVpl, DstFlat: Boolean;
  I: Integer;
  Rc: Word;
  B, C, V: Word;
  Txt: BibStr;
  Copied, Empty, Failed, Counted: LongInt;
  Sys: VrsSystem;

Procedure Usage;
  Begin
  WriteLn('usage: bibconv <source> [-n NewName] [-t zip|lzss|raw|mysword] [-o dir] [-b book|chapter|verse]');
  WriteLn('               [-m auto|same|plain|osis|thml|gbf|mysword] [-k srckey] [-e destkey] [-D description] [-f]');
  WriteLn('The text is translated between OSIS, ThML, GBF and MySword markup (-m auto by default).');
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
    bmMySword: MarkupName := 'MySword';
    bmSTEP: MarkupName := 'STEP (RTF)';
    bmTheWord: MarkupName := 'theWord';
    bmVPL: MarkupName := 'verse-per-line markup';
    bmUSFM: MarkupName := 'USFM';
    bmUSFX: MarkupName := 'USFX';
    bmZefania: MarkupName := 'Zefania XML';
    Else MarkupName := 'unknown markup';
    End;
  End;

Procedure CopyIntro(Level, Bk_, Ch_: Word);
  Var T: BibStr;
  Begin
  T := Src^.GetIntro(Level, Bk_, Ch_);
  If T = '' Then Exit;
  If Not Raw Then
    Begin
    If Mk = 'plain' Then T := MkpTranslate(T, SrcFmt, mfPlain, [moHeadings, moBreaks])
    Else T := MkpTranslate(T, SrcFmt, DstFmt);
    End;
  If T = '' Then Exit;
  If Dst^.PutIntro(Level, Bk_, Ch_, T) Then Inc(IntroCount);
  End;

Begin
If ParamCount < 1 Then Usage;
SrcName := ParamStr(1);
NewName := ''; Tg := 'zip'; Root := '.'; Bk := 'book'; SKey := ''; EKey := ''; Desc := '';
Raw := False; Force := False; Mk := 'auto';
I := 2;
While I <= ParamCount Do
  Begin
  If ParamStr(I) = '-r' Then Mk := 'same'
  Else If ParamStr(I) = '-f' Then Force := True
  Else If I < ParamCount Then
    Begin
    If ParamStr(I) = '-n' Then NewName := ParamStr(I + 1)
    Else If ParamStr(I) = '-t' Then Tg := LowerCase(ParamStr(I + 1))
    Else If ParamStr(I) = '-o' Then Root := ParamStr(I + 1)
    Else If ParamStr(I) = '-b' Then Bk := LowerCase(ParamStr(I + 1))
    Else If ParamStr(I) = '-k' Then SKey := ParamStr(I + 1)
    Else If ParamStr(I) = '-e' Then EKey := ParamStr(I + 1)
    Else If ParamStr(I) = '-D' Then Desc := ParamStr(I + 1)
    Else If ParamStr(I) = '-m' Then Mk := LowerCase(ParamStr(I + 1))
    Else Usage;
    Inc(I);
    End
  Else Usage;
  Inc(I);
  End;

{ ---- source ---- }
Src := NewBibObj(SrcName);
If SKey <> '' Then Src^.SetUnlockKey(SKey);
Src^.SetApocrypha(True);
Rc := Src^.OpenBible;
If Rc <> bibOk Then
  Begin
  Case Rc Of
    bibErrNotFound: WriteLn('source not found: ', SrcName);
    bibErrLocked: WriteLn('source is locked: give its unlock key with -k.  ', Src^.GetUnlockInfo);
    bibErrBadKey: WriteLn('the unlock key does not decrypt the source');
    bibErrUnsupported: WriteLn('source format or storage is not supported');
    Else WriteLn('cannot open source (code ', Rc, ')');
  End;
  Halt(2);
  End;
If NewName = '' Then NewName := Src^.GetName;
If NewName = '' Then NewName := 'Converted';
{ the new name must be usable as a file name }
For I := 1 To Length(NewName) Do
  If NewName[I] = ' ' Then NewName[I] := '_';

{ ---- target ---- }
DstMys := Tg = 'mysword';
DstTw := Tg = 'theword';
DstVpl := Tg = 'vpl';
DstMem := (Tg = 'osis') Or (Tg = 'zefania') Or (Tg = 'usfx') Or (Tg = 'usfm');
DstFlat := DstMys Or DstTw Or DstVpl Or DstMem;    {one file / folder, KJV structure, no Apocrypha}
If (Tg <> 'zip') And (Tg <> 'lzss') And (Tg <> 'raw') And (Not DstFlat) Then Usage;
If DstMys Then Begin MysD.Init; Dst := @MysD; End
Else If DstTw Then Begin TwdD.Init; Dst := @TwdD; End
Else If DstVpl Then Begin VplD.Init; Dst := @VplD; End
Else If Tg = 'osis' Then Begin OsiD.Init; Dst := @OsiD; End
Else If Tg = 'zefania' Then Begin ZefD.Init; Dst := @ZefD; End
Else If Tg = 'usfx' Then Begin UfxD.Init; Dst := @UfxD; End
Else If Tg = 'usfm' Then Begin UsfD.Init; Dst := @UsfD; End
Else Begin SwdD.Init; Dst := @SwdD; End;
Sys := Src^.VSys;
If DstFlat And (Sys In [vsNRSV, vsNRSVA]) Then
  Begin
  WriteLn('the source uses the ', VrsName(Sys), ' versification; MySword, theWord, .vpl, OSIS, Zefania, USFX and USFM files are written with the KJV structure only.');
  Halt(3);
  End;
If DstFlat Then Dst^.SetVersification('KJV') Else Dst^.SetVersification(VrsName(Sys));
If DstFlat Then Dst^.SetApocrypha(False) Else Dst^.SetApocrypha(True);

{ markup policy }
OwnMk := bmPlain;
If Tg = 'osis' Then OwnMk := bmOSIS
Else If Tg = 'zefania' Then OwnMk := bmZefania
Else If Tg = 'usfx' Then OwnMk := bmUSFX
Else If Tg = 'usfm' Then OwnMk := bmUSFM;
SrcFmt := Src^.GetMkpFormat;
Raw := False;
If Mk = 'auto' Then
  Begin
  If DstMys Then Mk := 'mysword'
  Else If DstTw Then Mk := 'theword'
  Else If DstVpl Then Mk := 'vpl'
  Else If DstMem Then Mk := Tg
  Else If Src^.GetMarkup In [bmOSIS, bmThML, bmGBF] Then Mk := 'same'
  Else Mk := 'osis';
  End;
If (Mk = 'osis') And (Src^.GetMarkup = bmOSIS) Then Mk := 'same';
If (Mk = 'thml') And (Src^.GetMarkup = bmThML) Then Mk := 'same';
If (Mk = 'gbf') And (Src^.GetMarkup = bmGBF) Then Mk := 'same';
If (Mk = 'mysword') And (Src^.GetMarkup = bmMySword) Then Mk := 'same';
If (Mk = 'theword') And (Src^.GetMarkup = bmTheWord) Then Mk := 'same';
If (Mk = 'vpl') And (Src^.GetMarkup = bmVPL) Then Mk := 'same';
If (Mk = 'zefania') And (Src^.GetMarkup = bmZefania) Then Mk := 'same';
If (Mk = 'usfx') And (Src^.GetMarkup = bmUSFX) Then Mk := 'same';
If (Mk = 'usfm') And (Src^.GetMarkup = bmUSFM) Then Mk := 'same';
If Mk = 'same' Then
  Begin
  Raw := True;
  If Src^.GetMarkup = bmSTEP Then
    Begin
    WriteLn('STEP (RTF) text cannot be stored in another format as it is.');
    WriteLn('Use -m osis, -m thml, -m gbf, -m mysword or -m plain.');
    Halt(3);
    End;
  If DstVpl And (Src^.GetMarkup <> bmVPL) And (Src^.GetMarkup <> bmPlain) Then
    Begin
    WriteLn('the source markup is ', MarkupName(Src^.GetMarkup), '; a .vpl file needs its light markup or plain text.');
    WriteLn('Use -m vpl (translate) or -m plain.');
    Halt(3);
    End;
  If DstTw And (Src^.GetMarkup <> bmTheWord) And (Src^.GetMarkup <> bmPlain) Then
    Begin
    WriteLn('the source markup is ', MarkupName(Src^.GetMarkup), '; a theWord module needs theWord markup or plain text.');
    WriteLn('Use -m theword (translate) or -m plain.');
    Halt(3);
    End;
  If DstMys And (Src^.GetMarkup <> bmMySword) And (Src^.GetMarkup <> bmPlain) Then
    Begin
    WriteLn('the source markup is ', MarkupName(Src^.GetMarkup), '; a MySword module needs MySword markup or plain text.');
    WriteLn('Use -m mysword (translate) or -m plain.');
    Halt(3);
    End;
  If DstMem And (Src^.GetMarkup <> OwnMk) And (Src^.GetMarkup <> bmPlain) Then
    Begin
    WriteLn('the source markup is ', MarkupName(Src^.GetMarkup), '; a ', MarkupName(OwnMk), ' file needs that markup or plain text.');
    WriteLn('Use -m ', Tg, ' (translate) or -m plain.');
    Halt(3);
    End;
  If (Not DstFlat) And (Src^.GetMarkup In [bmMySword, bmTheWord, bmVPL, bmUSFM, bmUSFX, bmZefania]) Then
    Begin
    WriteLn('the source markup is MySword / theWord / light / USFM / USFX / Zefania markup; a Sword module needs OSIS, ThML, GBF or plain text.');
    WriteLn('Use -m osis, -m thml, -m gbf or -m plain.');
    Halt(3);
    End;
  DstMk := Src^.GetMarkup;
  DstFmt := SrcFmt;
  End
Else
  Begin
  If Mk = 'plain' Then Begin DstMk := bmPlain; DstFmt := mfPlain; End
  Else If Mk = 'osis' Then Begin DstMk := bmOSIS; DstFmt := mfOSIS; End
  Else If Mk = 'thml' Then Begin DstMk := bmThML; DstFmt := mfThML; End
  Else If Mk = 'gbf' Then Begin DstMk := bmGBF; DstFmt := mfGBF; End
  Else If Mk = 'mysword' Then Begin DstMk := bmMySword; DstFmt := mfMySword; End
  Else If Mk = 'theword' Then Begin DstMk := bmTheWord; DstFmt := mfTheWord; End
  Else If Mk = 'vpl' Then Begin DstMk := bmVPL; DstFmt := mfVPL; End
  Else If Mk = 'zefania' Then Begin DstMk := bmZefania; DstFmt := mfZefania; End
  Else If Mk = 'usfx' Then Begin DstMk := bmUSFX; DstFmt := mfUSFX; End
  Else If Mk = 'usfm' Then Begin DstMk := bmUSFM; DstFmt := mfUSFM; End
  Else Usage;
  If DstMem And (Not (DstMk In [OwnMk, bmPlain])) Then
    Begin
    WriteLn('a ', MarkupName(OwnMk), ' file can only hold its own markup or plain text.');
    Halt(3);
    End;
  If DstVpl And (Not (DstMk In [bmVPL, bmPlain])) Then
    Begin
    WriteLn('a .vpl file can only hold its light markup or plain text.');
    Halt(3);
    End;
  If DstTw And (Not (DstMk In [bmTheWord, bmPlain])) Then
    Begin
    WriteLn('a theWord module can only hold theWord markup or plain text.');
    Halt(3);
    End;
  If DstMys And (Not (DstMk In [bmMySword, bmPlain])) Then
    Begin
    WriteLn('a MySword module can only hold MySword markup or plain text.');
    Halt(3);
    End;
  If (Not DstFlat) And (DstMk In [bmMySword, bmTheWord, bmVPL, bmUSFM, bmUSFX, bmZefania]) Then
    Begin
    WriteLn('Sword modules cannot use MySword / theWord markup: use -m osis, thml, gbf or plain.');
    Halt(3);
    End;
  If (Not Src^.CanTranslateMarkup) And (DstMk <> bmPlain) Then
    Begin
    WriteLn('the source markup (', MarkupName(Src^.GetMarkup), ') cannot be translated; use -m same or -m plain.');
    Halt(3);
    End;
  End;
Dst^.SetMarkup(DstMk);

If Not DstFlat Then
  Begin
  If Tg = 'raw' Then SwdD.SetStorage(sdRawText, scZip, sbBook)
  Else If Tg = 'lzss' Then
    Begin
    If Bk = 'chapter' Then SwdD.SetStorage(sdZText, scLzss, sbChapter)
    Else If Bk = 'verse' Then SwdD.SetStorage(sdZText, scLzss, sbVerse)
    Else SwdD.SetStorage(sdZText, scLzss, sbBook);
    End
  Else
    Begin
    If Bk = 'chapter' Then SwdD.SetStorage(sdZText, scZip, sbChapter)
    Else If Bk = 'verse' Then SwdD.SetStorage(sdZText, scZip, sbVerse)
    Else SwdD.SetStorage(sdZText, scZip, sbBook);
    End;
  End;
If EKey <> '' Then Dst^.SetUnlockKey(EKey);
Dst^.SetLang(Src^.GetLang);
Dst^.SetVersion(Src^.GetVersion);
Dst^.SetCopyright(Src^.GetCopyright);
Dst^.SetAbout(Src^.GetAbout);
If Desc <> '' Then Dst^.SetDescription(Desc) Else Dst^.SetDescription(Src^.GetDescription);
Dst^.SetOverwrite(Force);
Dst^.SetBibPath(Root);
Rc := Dst^.CreateBible(NewName);
Case Rc Of
  bibOk: ;
  bibErrExists: Begin WriteLn('module ', NewName, ' already exists in ', Root, ' (use -f to replace)'); Halt(4); End;
  bibErrUnsupported: Begin WriteLn('that storage / key combination is not supported for writing'); Halt(4); End;
  Else Begin WriteLn('cannot create the new module (code ', Rc, ')'); Halt(4); End;
End;

{ ---- copy ---- }
WriteLn('converting ', Src^.GetName, ' (', MarkupName(Src^.GetMarkup), ') -> ', NewName, ' (',
        MarkupName(Dst^.GetMarkup), ', ', Tg, ')');
Copied := 0; Empty := 0; Failed := 0; IntroCount := 0;
For B := 1 To Src^.GetBookCount Do
  Begin
  If DstFlat And (B > BibBooks) Then Break;      {no Apocrypha in MySword / theWord}
  { module / testament introductions come before the first book of the testament }
  If B = 1 Then
    Begin
    CopyIntro(bilModule, 1, 1);
    CopyIntro(bilTestament, 1, 1);
    End
  Else If B = BibOTBooks + 1 Then
    CopyIntro(bilTestament, B, 1);
  CopyIntro(bilBook, B, 1);
  For C := 1 To Src^.GetChapterCount(B) Do
    Begin
    CopyIntro(bilChapter, B, C);
    For V := 1 To Src^.GetVerseCount(B, C) Do
      Begin
      Src^.SetRef(B, C, V);
      Txt := Src^.GetRawVerse;
      If (Txt <> '') And (Not Raw) Then
        Begin
        If Mk = 'plain' Then Txt := Src^.GetVerseText
        Else Txt := MkpTranslate(Txt, SrcFmt, DstFmt);
        End;
      If Txt = '' Then Inc(Empty)
      Else If Dst^.PutVerse(B, C, V, Txt) Then Inc(Copied)
      Else
        Begin
        Inc(Failed);
        If Failed <= 5 Then WriteLn('could not write ', Src^.GetBookName(B), ' ', C, ':', V);
        End;
      End;
    End;
  End;
Src^.CloseBible;
Rc := Dst^.CloseBible;
If Rc <> bibOk Then
  Begin
  WriteLn('error finishing the new module (code ', Rc, ')');
  Halt(5);
  End;
WriteLn(Copied, ' verses written, ', Empty, ' empty verses not stored, ', Failed, ' failed, ', IntroCount, ' introductions copied');
MemFile := '';
If Tg = 'osis' Then MemFile := OsiD.FileName
Else If Tg = 'zefania' Then MemFile := ZefD.FileName
Else If Tg = 'usfx' Then MemFile := UfxD.FileName
Else If Tg = 'usfm' Then MemFile := UsfD.FileName;
If DstMem Then WriteLn('module: ', MemFile)
Else If DstVpl Then WriteLn('module: ', VplD.FileName)
Else If DstTw Then WriteLn('module: ', TwdD.FileName)
Else If DstMys Then WriteLn('module: ', Root, '/', NewName, '.bbl.mybible')
Else WriteLn('module: ', Root, '/mods.d/', LowerCase(NewName), '.conf');

{ ---- read back ---- }
If DstMem Then Chk := NewBibObj(MemFile)
Else If DstVpl Then Chk := NewBibObj(VplD.FileName)
Else If DstTw Then Chk := NewBibObj(TwdD.FileName)
Else If DstMys Then Chk := NewBibObj(Root + '/' + NewName + '.bbl.mybible')
Else Chk := NewBibObj(Root + '/mods.d/' + LowerCase(NewName) + '.conf');
If EKey <> '' Then Chk^.SetUnlockKey(EKey);
Chk^.SetApocrypha(True);
If Chk^.OpenBible <> bibOk Then
  Begin
  WriteLn('verify: cannot open the new module');
  Halt(6);
  End;
Counted := 0;
Chk^.SeekFirst;
While Chk^.SeekFound Do
  Begin
  If Chk^.GetRawVerse <> '' Then Inc(Counted);
  Chk^.SeekNext;
  End;
Chk^.CloseBible;
If Counted = Copied Then WriteLn('verified: ', Counted, ' verses read back')
Else
  Begin
  WriteLn('VERIFY FAILED: wrote ', Copied, ', read back ', Counted);
  Halt(6);
  End;
End.
