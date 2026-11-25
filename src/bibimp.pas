Program BibImp;
{ bibimp - import a Sword "imp" text file into a new Sword module.

  The imp format is what Sword's mod2imp writes and imp2vs reads:
      $$$Genesis 1:1
      In the beginning ...
      $$$Genesis 1:2
      ...
  Keys are  Book c:v  (full name, abbreviation or OSIS id), with  Book 0:0  the book
  introduction, Book c:0 a chapter introduction, [ Module Heading ] and
  [ Testament 1|2 Heading ].  Text is stored as is (raw markup).  Entries may be in any
  order; for a repeated key the last one wins.

  usage: bibimp <input.imp> -n <ModuleName> [options]
     -o <dir>       output root (gets mods.d/ and modules/)      default .
     -d zip|lzss|raw|mysword  storage / format (mysword = MySword .bbl.mybible)  default zip
     -b book|chapter|verse   zText block type                      default book
     -v KJV|KJVA|NRSV|NRSVA  versification                         default KJV
     -m osis|thml|gbf|tei|plain|mysword  markup of the text        default osis (mysword for -d mysword)
     -l <lang>  -D <description>  -A <about>  -V <version>  -C <copyright>
     -k <key>       encipher the module (zText); it then needs this key to be read
     -f             replace an existing module }

{$MODE OBJFPC}{$H+}
{$I-}

Uses SysUtils, MKBibVrs, MKBibMod, MKBibAbs, MKBibSwd, MKBibMys;

Type
  Ent = Record
    Level: Integer;            {0 module, 1 testament, 2 book, 3 chapter intro, 4 verse}
    Book, Chap, Verse: Integer;
    SortKey: Int64;
    Seq: LongInt;
    Txt: AnsiString;
  End;

Var
  InName, ModName, Root, Dr, Bk, Vs, Mk, Lang, Desc, About, Ver, Copy_, Key: String;
  Force: Boolean;
  SwdObj, RdSwd: SwordBibObj;
  MysObj, RdMys: MySwordBibObj;
  Bib, Rd: AbsBibPtr;
  IsMys: Boolean;
  IntroSkipped: LongInt;
  F: Text;
  Ents: Array Of Ent;
  NEnt, i, j, Gap: LongInt;
  Line, CurKey, CurTxt: AnsiString;
  HaveKey: Boolean;
  Skipped, Dups, Written, Rc: LongInt;
  Tmp: Ent;
  Sys: VrsSystem;
  Counted: LongInt;

Procedure Usage;
  Begin
  WriteLn('usage: bibimp <input.imp> -n <ModuleName> [-o dir] [-d zip|lzss|raw] [-b book|chapter|verse]');
  WriteLn('              [-v KJV|KJVA|NRSV|NRSVA] [-m osis|thml|gbf|tei|plain] [-l lang] [-D desc]');
  WriteLn('              [-A about] [-V version] [-C copyright] [-k key] [-f]');
  Halt(1);
  End;

Function ParseKey(K: String; Var E: Ent): Boolean;
  Var
    P, Q, C, V, Code: Integer;
    Nm, Rest: String;
  Begin
  ParseKey := False;
  K := Trim(K);
  E.Book := 0; E.Chap := 0; E.Verse := 0;
  If (K <> '') And (K[1] = '[') Then
    Begin
    If Pos('Module', K) > 0 Then
      Begin
      E.Level := 0; E.Book := 1;
      ParseKey := True;
      End
    Else If Pos('Testament', K) > 0 Then
      Begin
      E.Level := 1;
      If Pos('2', K) > 0 Then E.Book := BibOTBooks + 1 Else E.Book := 1;
      ParseKey := True;
      End;
    Exit;
    End;
  P := Length(K);
  While (P > 0) And (K[P] <> ' ') Do Dec(P);
  If P < 2 Then Exit;
  Nm := Copy(K, 1, P - 1);
  Rest := Copy(K, P + 1, 100);
  Q := Pos(':', Rest);
  If Q = 0 Then Exit;
  Val(Copy(Rest, 1, Q - 1), C, Code);
  If Code <> 0 Then Exit;
  Val(Copy(Rest, Q + 1, 100), V, Code);
  If Code <> 0 Then Exit;
  E.Book := Bib^.FindBook(Nm);
  If E.Book = 0 Then Exit;
  E.Chap := C; E.Verse := V;
  If C = 0 Then E.Level := 2
  Else If V = 0 Then E.Level := 3
  Else E.Level := 4;
  If (C < 0) Or (V < 0) Or (C > Bib^.GetChapterCount(E.Book)) Then Exit;
  If (E.Level = 4) And (V > Bib^.GetVerseCount(E.Book, C)) Then Exit;
  ParseKey := True;
  End;

Procedure AddEntry;
  Var E: Ent;
  Begin
  If Not HaveKey Then Exit;
  While (Length(CurTxt) > 0) And (CurTxt[Length(CurTxt)] In [#10, #13, ' ']) Do SetLength(CurTxt, Length(CurTxt) - 1);
  If ParseKey(CurKey, E) Then
    Begin
    E.Txt := CurTxt;
    E.Seq := NEnt;
    {sort key: testament file, then Sword index within it}
    Case E.Level Of
      0: E.SortKey := 0;
      1: If VrsInNT(E.Book) Then E.SortKey := 100000000 + 1 Else E.SortKey := 1;
      2: E.SortKey := VrsTestOffset(Bib^.VSys, E.Book, 0, 0);
      Else E.SortKey := VrsTestOffset(Bib^.VSys, E.Book, E.Chap, E.Verse);
      End;
    If (E.Level >= 2) And VrsInNT(E.Book) Then Inc(E.SortKey, 100000000);
    If NEnt >= Length(Ents) Then SetLength(Ents, Length(Ents) * 2 + 1024);
    Ents[NEnt] := E;
    Inc(NEnt);
    End
  Else
    Begin
    Inc(Skipped);
    If Skipped <= 5 Then WriteLn('skipped key: ', CurKey);
    End;
  End;

Function Less(Const A, B: Ent): Boolean;
  Begin
  If A.SortKey <> B.SortKey Then Less := A.SortKey < B.SortKey
  Else Less := A.Seq < B.Seq;
  End;

Begin
If ParamCount < 1 Then Usage;
InName := ParamStr(1);
ModName := ''; Root := '.'; Dr := 'zip'; Bk := 'book'; Vs := 'KJV'; Mk := 'osis';
Lang := ''; Desc := ''; About := ''; Ver := ''; Copy_ := ''; Key := ''; Force := False;
i := 2;
While i <= ParamCount Do
  Begin
  If ParamStr(i) = '-f' Then Force := True
  Else If i < ParamCount Then
    Begin
    If ParamStr(i) = '-n' Then ModName := ParamStr(i + 1)
    Else If ParamStr(i) = '-o' Then Root := ParamStr(i + 1)
    Else If ParamStr(i) = '-d' Then Dr := LowerCase(ParamStr(i + 1))
    Else If ParamStr(i) = '-b' Then Bk := LowerCase(ParamStr(i + 1))
    Else If ParamStr(i) = '-v' Then Vs := ParamStr(i + 1)
    Else If ParamStr(i) = '-m' Then Mk := LowerCase(ParamStr(i + 1))
    Else If ParamStr(i) = '-l' Then Lang := ParamStr(i + 1)
    Else If ParamStr(i) = '-D' Then Desc := ParamStr(i + 1)
    Else If ParamStr(i) = '-A' Then About := ParamStr(i + 1)
    Else If ParamStr(i) = '-V' Then Ver := ParamStr(i + 1)
    Else If ParamStr(i) = '-C' Then Copy_ := ParamStr(i + 1)
    Else If ParamStr(i) = '-k' Then Key := ParamStr(i + 1)
    Else Usage;
    Inc(i);
    End
  Else Usage;
  Inc(i);
  End;
If ModName = '' Then Usage;

IsMys := Dr = 'mysword';
If IsMys Then
  Begin
  MysObj.Init; Bib := @MysObj;
  If Mk = 'osis' Then Mk := 'mysword';
  End
Else
  Begin
  SwdObj.Init; Bib := @SwdObj;
  End;
If Not VrsFind(Vs, Sys) Then
  Begin
  WriteLn('unsupported versification: ', Vs);
  Halt(2);
  End;
If Not Bib^.SetVersification(Vs) Then
  Begin
  WriteLn('unsupported versification for this format: ', Vs);
  Halt(2);
  End;
Bib^.SetApocrypha(True);

Assign(F, InName);
Reset(F);
If IOResult <> 0 Then
  Begin
  WriteLn('cannot read ', InName);
  Halt(2);
  End;
SetLength(Ents, 40000);
NEnt := 0; Skipped := 0; Dups := 0; HaveKey := False; CurTxt := '';
While Not Eof(F) Do
  Begin
  ReadLn(F, Line);
  If (Length(Line) > 0) And (Line[Length(Line)] = #13) Then SetLength(Line, Length(Line) - 1);
  If Copy(Line, 1, 3) = '$$$' Then
    Begin
    AddEntry;
    CurKey := Copy(Line, 4, Length(Line));
    CurTxt := '';
    HaveKey := True;
    End
  Else If HaveKey Then
    Begin
    If CurTxt <> '' Then CurTxt := CurTxt + #10;
    CurTxt := CurTxt + Line;
    End;
  End;
AddEntry;
Close(F);
WriteLn(NEnt, ' entries read, ', Skipped, ' skipped');

{ shell sort by (SortKey, Seq) }
Gap := NEnt Div 2;
While Gap > 0 Do
  Begin
  For i := Gap To NEnt - 1 Do
    Begin
    Tmp := Ents[i];
    j := i;
    While (j >= Gap) And Less(Tmp, Ents[j - Gap]) Do
      Begin
      Ents[j] := Ents[j - Gap];
      Dec(j, Gap);
      End;
    Ents[j] := Tmp;
    End;
  Gap := Gap Div 2;
  End;

{ storage options }
If Not IsMys Then
  Begin
  If Dr = 'raw' Then SwdObj.SetStorage(sdRawText, scZip, sbBook)
  Else If Dr = 'lzss' Then
    Begin
    If Bk = 'chapter' Then SwdObj.SetStorage(sdZText, scLzss, sbChapter)
    Else If Bk = 'verse' Then SwdObj.SetStorage(sdZText, scLzss, sbVerse)
    Else SwdObj.SetStorage(sdZText, scLzss, sbBook);
    End
  Else
    Begin
    If Bk = 'chapter' Then SwdObj.SetStorage(sdZText, scZip, sbChapter)
    Else If Bk = 'verse' Then SwdObj.SetStorage(sdZText, scZip, sbVerse)
    Else SwdObj.SetStorage(sdZText, scZip, sbBook);
    End;
  End;
If Mk = 'osis' Then Bib^.SetMarkup(bmOSIS)
Else If Mk = 'thml' Then Bib^.SetMarkup(bmThML)
Else If Mk = 'gbf' Then Bib^.SetMarkup(bmGBF)
Else If Mk = 'tei' Then Bib^.SetMarkup(bmTEI)
Else If Mk = 'mysword' Then Bib^.SetMarkup(bmMySword)
Else Bib^.SetMarkup(bmPlain);
Bib^.SetLang(Lang); Bib^.SetDescription(Desc); Bib^.SetAbout(About);
Bib^.SetVersion(Ver); Bib^.SetCopyright(Copy_);
If Key <> '' Then Bib^.SetUnlockKey(Key);
Bib^.SetOverwrite(Force);
Bib^.SetBibPath(Root);

Rc := Bib^.CreateBible(ModName);
Case Rc Of
  bibOk: ;
  bibErrExists: Begin WriteLn('module ', ModName, ' already exists in ', Root, ' (use -f to replace)'); Halt(3); End;
  bibErrUnsupported: Begin WriteLn('that storage / key combination is not supported for writing'); Halt(3); End;
  Else Begin WriteLn('cannot create module (code ', Rc, ')'); Halt(3); End;
End;

Written := 0; IntroSkipped := 0;
For i := 0 To NEnt - 1 Do
  Begin
  If (i + 1 < NEnt) And (Ents[i + 1].SortKey = Ents[i].SortKey) Then
    Begin
    Inc(Dups);                         {a later entry with the same key wins}
    Continue;
    End;
  Case Ents[i].Level Of
    0, 1, 2: If Not Bib^.PutIntro(Ents[i].Level, Ents[i].Book, 1, Ents[i].Txt) Then
      Begin
      If IsMys Then Inc(IntroSkipped) Else WriteLn('write failed: intro ', Ents[i].Book);
      End;
    3: If Not Bib^.PutVerse(Ents[i].Book, Ents[i].Chap, 0, Ents[i].Txt) Then WriteLn('write failed: ', Ents[i].Book, ' ', Ents[i].Chap, ':0');
    Else
      If Bib^.PutVerse(Ents[i].Book, Ents[i].Chap, Ents[i].Verse, Ents[i].Txt) Then
        Begin
        If Ents[i].Txt <> '' Then Inc(Written);
        End
      Else WriteLn('write failed: ', Bib^.GetBookName(Ents[i].Book), ' ', Ents[i].Chap, ':', Ents[i].Verse);
    End;
  End;
Rc := Bib^.CloseBible;
If Rc <> bibOk Then
  Begin
  WriteLn('error finishing module (code ', Rc, ')');
  Halt(4);
  End;
WriteLn(Written, ' verses written, ', Dups, ' duplicate keys dropped');
If IntroSkipped > 0 Then WriteLn(IntroSkipped, ' module/testament/book introductions skipped (not supported by MySword)');
If IsMys Then WriteLn('module: ', Root, '/', ModName, '.bbl.mybible')
Else WriteLn('module: ', Root, '/mods.d/', LowerCase(ModName), '.conf');

{ read it back }
If IsMys Then
  Begin
  RdMys.Init; Rd := @RdMys;
  Rd^.SetBibPath(Root + '/' + ModName + '.bbl.mybible');
  End
Else
  Begin
  RdSwd.Init; Rd := @RdSwd;
  Rd^.SetBibPath(Root + '/mods.d/' + LowerCase(ModName) + '.conf');
  End;
If Key <> '' Then Rd^.SetUnlockKey(Key);
Rd^.SetApocrypha(True);
Rc := Rd^.OpenBible;
If Rc <> bibOk Then
  Begin
  WriteLn('verify: cannot open the new module (code ', Rc, ')');
  Halt(5);
  End;
Counted := 0;
Rd^.SeekFirst;
While Rd^.SeekFound Do
  Begin
  If Rd^.GetRawVerse <> '' Then Inc(Counted);
  Rd^.SeekNext;
  End;
If Counted = Written Then WriteLn('verified: ', Counted, ' verses read back')
Else
  Begin
  WriteLn('VERIFY FAILED: wrote ', Written, ', read back ', Counted);
  Halt(6);
  End;
Rd^.Done;
Bib^.Done;
End.
