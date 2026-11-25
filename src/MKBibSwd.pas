Unit MKBibSwd;       {Sword module Bible object (read only)}

{$I MKBib.Def}

{
  MKBibSwd - descendant of AbsBibObj that reads Bible modules in the
  CrossWire Sword format.

  Supported:  ModDrv = zText, zText4, RawText, RawText4
              CompressType = ZIP (zlib), LZSS (also the default when absent), BZIP2
              BlockType = BOOK / CHAPTER / VERSE
              Versification = KJV, KJVA, NRSV, NRSVA.  The Apocrypha books of the "A"
                systems (numbered 67..) are available after SetApocrypha(True).
              Encoding = UTF-8 (text is passed through) or Latin-1 (converted)
              Enciphered modules (a CipherKey= line): the unlock key comes from
                SetUnlockKey, or from the conf when it holds one.
  Not supported (OpenBible returns bibErrUnsupported):  Xz compression, other
              versifications, commentary / dictionary / general book modules.
  Without a key an enciphered module gives bibErrLocked (GetUnlockInfo says where to
  get one), with a wrong key bibErrBadKey.

  Writing: CreateBible(Name) makes a new module under the directory given to SetBibPath
  (Root/mods.d/<name>.conf and Root/modules/texts/<ztext|rawtext>/<name>/).  Choose the
  storage with SetStorage first: zText (ZIP or LZSS, BlockType BOOK / CHAPTER / VERSE) or
  RawText.  Then PutVerse / PutIntro in increasing order within a testament, and
  CloseBible (or FlushBible) to finish.  An unlock key set with SetUnlockKey enciphers a
  zText module (the conf then carries an empty CipherKey=, i.e. a locked module).

  SetBibPath accepts any of
      the module name                  KJV, engWEB2015eb      (looked up in the
                                         Sword module directories)
      a .conf file                     /home/me/.sword/mods.d/web.conf
      a Sword directory                /home/me/.sword        (when it holds only one
                                         module the first Bible module is used)
  followed, optionally, by '|ModuleName' to pick one when a directory is given.

  The module directories searched for a module name are, in order: those added
  with AddSwordRoot, each entry of $SWORD_PATH, ~/.sword, ~/.sword/sword,
  /usr/share/sword, /usr/local/share/sword.
}

Interface

Uses MKBibMod, MKBibAbs, MKBibVrs, MKBibCph;

Type
  SwordDriver = (sdNone, sdZText, sdZText4, sdRawText, sdRawText4);
  SwordComp = (scZip, scLzss, scBzip2);
  SwordBlock = (sbBook, sbChapter, sbVerse);

  SwordBibObj = Object(AbsBibObj)
  Constructor Init;
  Destructor Done; Virtual;
  Procedure AddSwordRoot(Dir: String); {Extra directory holding mods.d/ and modules/}
  Procedure SetBibPath(BP: String); Virtual;   {reading: module/conf/dir;  writing: output root directory}
  Function  OpenBible: Word; Virtual;
  Function  CloseBible: Word; Virtual;
  Function  BibleExists: Boolean; Virtual;
  Function  IsOpen: Boolean; Virtual;
  Function  GetName: String; Virtual;
  Function  GetDescription: String; Virtual;
  Function  GetAbout: BibStr; Virtual;
  Function  GetLang: String; Virtual;
  Function  GetVersion: String; Virtual;
  Function  GetCopyright: String; Virtual;
  Function  GetMarkup: BibMarkup; Virtual;
  Function  HasOT: Boolean; Virtual;
  Function  HasNT: Boolean; Virtual;
  Function  GetRawVerse: BibStr; Virtual;
  Function  GetIntro(Level, Book, Chap: Word): BibStr; Virtual;
  Procedure SetStorage(Drv: SwordDriver; Comp: SwordComp; Block: SwordBlock); {before CreateBible; sdZText or sdRawText}
  Function  CreateBible(Name: String): Word; Virtual;
  Function  PutVerse(Book, Chap, Verse: Word; Const Txt: BibStr): Boolean; Virtual;
  Function  PutIntro(Level, Book, Chap: Word; Const Txt: BibStr): Boolean; Virtual;
  Function  FlushBible: Word; Virtual;
  Function  IsWriting: Boolean; Virtual;
  Function  IsReadOnly: Boolean; Virtual;
  Function  IsLocked: Boolean; Virtual;
  Procedure SetUnlockKey(Key: String); Virtual;
  Function  GetUnlockInfo: String; Virtual;
  Function  GetConfValue(Key: String): String; Virtual; {Any key of the module .conf}
  Function  HasConfKey(Key: String): Boolean; {Key appears in the .conf (even with an empty value)}
  Function  GetConfPath: String; {Full path of the .conf file in use}
  Function  GetDataPath: String; {Full path of the module data directory}

  Public   {state - used by descendants}
  Roots: Array[1..8] Of String;
  NRoots: Word;
  PathSpec: String;
  ConfPath: String;
  BaseDir: String;          {directory holding mods.d and modules}
  DataDir: String;
  ModName: String;
  Conf: BibStr;             {raw conf text of the chosen section}
  Opened: Boolean;
  Driver: SwordDriver;
  BlockExt: Char;           {b, c or v}
  Latin1: Boolean;
  CompKind: SwordComp;
  Enciphered: Boolean;
  Master: SapphireRec;      {cipher state for the unlock key}
  UnlockKey: String;
  KeyGiven: Boolean;
  { writing }
  WMode: Boolean;
  WDriver: SwordDriver;
  WComp: SwordComp;
  WBlock: SwordBlock;
  WName: String;
  WRoot, WConfFile: String;
  WIdxCount: Array[0..1] Of LongInt;      {index entries per testament}
  WIdx: Array[0..1] Of Pointer;           {index file image}
  WLast: Array[0..1] Of LongInt;          {last index written, -1 none}
  WBuf: Array[0..1] Of Pointer;           {open block (zText) }
  WBufLen, WBufCap: Array[0..1] Of LongWord;
  WBlkOpen: Array[0..1] Of Boolean;
  WKeyBook, WKeyChap: Array[0..1] Of Word;
  WBlkNo: Array[0..1] Of LongWord;
  WZzPos: Array[0..1] Of LongWord;        {bytes written to .bzz / raw text file}
  WFilesOpen: Array[0..1] Of Boolean;
  WFileS, WFileZ: Array[0..1] Of File;    {.bzs and .bzz (raw: WFileZ is the text file)}
  Markup: BibMarkup;
  Test: Array[0..1] Of Record
    Present: Boolean;
    IdxData: Pointer;       {.vss or .bzv}
    IdxSize: LongInt;
    BlkData: Pointer;       {.bzs (z drivers)}
    BlkSize: LongInt;
    TxtFile: File;
    TxtOpen: Boolean;
    CacheBlk: LongInt;      {block number held in CacheBuf, -1 none}
    CacheBuf: BibStr;
  End;
  Function  FindModule: Boolean;
  Function  LoadConf(Const FileName, Section: String): Boolean;
  Procedure FreeData;
  Function  ReadZBlock(T: Byte; Blk: LongInt): Boolean;
  Function  KeyWorks: Boolean;
  Function  ReadEntry(T: Byte; Idx: LongInt): BibStr;
  Function  WStoreEntry(T: Byte; Idx: LongInt; KBook, KChap: Word; Const Txt: BibStr): Boolean;
  Function  WFlushBlock(T: Byte): Boolean;
  Function  WOpenFiles(T: Byte): Boolean;
  Function  WDataDir: String;
  Function  WBuildConf: BibStr;
  Procedure WFree;
  End;

Type SwordBibPtr = ^SwordBibObj;


Implementation

Uses SysUtils, MKBibZ;


Function LoadFile(Const Name: String; Var P: Pointer; Var Size: LongInt): Boolean;
  Var
    F: File;
    N: LongInt;
    SaveMode: Byte;
  Begin
  LoadFile := False;
  P := Nil; Size := 0;
  SaveMode := FileMode;
  FileMode := 0;
  Assign(F, Name);
  Reset(F, 1);
  FileMode := SaveMode;
  If IOResult <> 0 Then Exit;
  N := FileSize(F);
  If N > 0 Then
    Begin
    GetMem(P, N);
    BlockRead(F, P^, N);
    If IOResult <> 0 Then
      Begin
      FreeMem(P, N);
      P := Nil;
      Close(F);
      Exit;
      End;
    End;
  Close(F);
  Size := N;
  LoadFile := True;
  End;

Function GetU32(P: Pointer; Ofs: LongInt): LongWord;
  Begin
  GetU32 := LEtoN(PLongWord(PByte(P) + Ofs)^);
  End;

Function GetU16(P: Pointer; Ofs: LongInt): Word;
  Begin
  GetU16 := LEtoN(PWord(PByte(P) + Ofs)^);
  End;

Function IsDir(Const D: String): Boolean;
  Begin
  IsDir := DirectoryExists(D);
  End;

Function AddSlash(Const D: String): String;
  Begin
  If (D <> '') And (D[Length(D)] <> '/') Then AddSlash := D + '/' Else AddSlash := D;
  End;

Function Trim2(Const S: String): String;
  Begin
  Trim2 := Trim(S);
  End;


Constructor SwordBibObj.Init;
  Begin
  AbsBibObj.Init;
  NRoots := 0;
  PathSpec := ''; ConfPath := ''; BaseDir := ''; DataDir := ''; ModName := '';
  Conf := '';
  Opened := False;
  Driver := sdNone;
  FillChar(Test, SizeOf(Test), 0);
  Markup := bmUnknown;
  Enciphered := False; KeyGiven := False; UnlockKey := '';
  WMode := False; WDriver := sdZText; WComp := scZip; WBlock := sbBook; WName := '';
  FillChar(WIdx, SizeOf(WIdx), 0); FillChar(WBuf, SizeOf(WBuf), 0);
  FillChar(WFilesOpen, SizeOf(WFilesOpen), 0);
  End;

Destructor SwordBibObj.Done;
  Begin
  If Opened Or WMode Then CloseBible;
  AbsBibObj.Done;
  End;

Procedure SwordBibObj.AddSwordRoot(Dir: String);
  Begin
  If NRoots < 8 Then
    Begin
    Inc(NRoots);
    Roots[NRoots] := AddSlash(Dir);
    End;
  End;

Procedure SwordBibObj.SetBibPath(BP: String);
  Begin
  If Opened Then CloseBible;
  PathSpec := BP;
  ConfPath := '';
  End;


{ Read a .conf and keep the section named Section (first section when Section = '').
  Continuation lines end in a backslash.  Result is "Key=Value" lines in Conf. }
Function SwordBibObj.LoadConf(Const FileName, Section: String): Boolean;
  Var
    F: Text;
    L, Acc: String;
    InSec, Want: Boolean;
    Sec: String;
  Begin
  LoadConf := False;
  Assign(F, FileName);
  Reset(F);
  If IOResult <> 0 Then Exit;
  Conf := '';
  InSec := False; Want := False;
  Acc := '';
  While Not Eof(F) Do
    Begin
    ReadLn(F, L);
    If (Length(L) > 0) And (L[Length(L)] = #13) Then Delete(L, Length(L), 1);
    If (Acc <> '') Then      {continuation of a multi line value}
      Begin
      Acc := Acc + #10 + L;
      If (L = '') Or (L[Length(L)] <> '\') Then
        Begin
        If Want Then Conf := Conf + Acc + #13#10;
        Acc := '';
        End
      Else Acc := Copy(Acc, 1, Length(Acc) - 1);
      Continue;
      End;
    If (L <> '') And (L[1] = '[') Then
      Begin
      Sec := Copy(L, 2, Pos(']', L) - 2);
      If Want Then Break;        {next section: done}
      If InSec Then Break;
      If (Section = '') Or (LowerCase(Sec) = LowerCase(Section)) Then
        Begin
        Want := True;
        InSec := True;
        ModName := Sec;
        End;
      Continue;
      End;
    If (Not Want) Or (L = '') Or (L[1] = '#') Or (Pos('=', L) = 0) Then Continue;
    If L[Length(L)] = '\' Then Acc := Copy(L, 1, Length(L) - 1)
    Else Conf := Conf + L + #13#10;
    End;
  Close(F);
  LoadConf := Want;
  End;


Function SwordBibObj.GetConfValue(Key: String): String;
  { Value of Key (case insensitive); multiple occurrences are joined by newlines }
  Var
    P, E: LongInt;
    Line, K, R: String;
    S: BibStr;
  Begin
  R := '';
  S := Conf;
  Key := LowerCase(Key);
  P := 1;
  While P <= Length(S) Do
    Begin
    E := P;
    While (E <= Length(S)) And (S[E] <> #13) Do Inc(E);
    Line := Copy(S, P, E - P);
    If Pos('=', Line) > 0 Then
      Begin
      K := LowerCase(Trim(Copy(Line, 1, Pos('=', Line) - 1)));
      If K = Key Then
        Begin
        If R <> '' Then R := R + #10;
        R := R + Trim(Copy(Line, Pos('=', Line) + 1, 255));
        End;
      End;
    P := E + 2;
    End;
  GetConfValue := R;
  End;


Function SwordBibObj.FindModule: Boolean;
  { Fills ConfPath/BaseDir from PathSpec }
  Var
    Spec, Wanted, Dir, Env, Entry: String;
    SR: TSearchRec;
    i, P: Word;
    Dirs: Array[1..24] Of String;
    ND: Word;

  Procedure AddDir(D: String);
    Begin
    If (D <> '') And (ND < 24) Then
      Begin
      Inc(ND);
      Dirs[ND] := AddSlash(D);
      End;
    End;

  Function TryDir(D: String): Boolean;
    { D holds mods.d: look for a conf whose file name or [section] is Wanted
      (or the first Bible module when Wanted = '') }
    Var Found: Boolean;
    Begin
    TryDir := False;
    If Not IsDir(D + 'mods.d') Then Exit;
    Found := False;
    If (Wanted <> '') And FileExists(D + 'mods.d/' + LowerCase(Wanted) + '.conf') Then
      Begin
      If LoadConf(D + 'mods.d/' + LowerCase(Wanted) + '.conf', Wanted) Then
        Begin
        ConfPath := D + 'mods.d/' + LowerCase(Wanted) + '.conf';
        Found := True;
        End;
      End;
    If (Not Found) And (FindFirst(D + 'mods.d/*.conf', faAnyFile, SR) = 0) Then
      Begin
      Repeat
        If LoadConf(D + 'mods.d/' + SR.Name, Wanted) Then
          If (Wanted <> '') Or (Pos('text', LowerCase(GetConfValue('DataPath'))) > 0) Then
            If (LowerCase(Copy(GetConfValue('ModDrv'), 1, 4)) = 'ztex') Or
               (LowerCase(Copy(GetConfValue('ModDrv'), 1, 7)) = 'rawtext') Then
              Begin
              ConfPath := D + 'mods.d/' + SR.Name;
              Found := True;
              End;
      Until Found Or (FindNext(SR) <> 0);
      FindClose(SR);
      End;
    If Found Then
      Begin
      BaseDir := D;
      TryDir := True;
      End;
    End;

  Begin
  FindModule := False;
  Spec := PathSpec;
  Wanted := '';
  P := Pos('|', Spec);
  If P > 0 Then
    Begin
    Wanted := Copy(Spec, P + 1, 255);
    Spec := Copy(Spec, 1, P - 1);
    End;
  If Spec = '' Then Exit;

  {a conf file}
  If FileExists(Spec) And (LowerCase(ExtractFileExt(Spec)) = '.conf') Then
    Begin
    If Not LoadConf(Spec, Wanted) Then Exit;
    ConfPath := ExpandFileName(Spec);
    BaseDir := AddSlash(ExpandFileName(ExtractFileDir(ExtractFileDir(ConfPath))));
    FindModule := True;
    Exit;
    End;

  {a Sword directory (has mods.d)}
  If IsDir(Spec) And IsDir(AddSlash(Spec) + 'mods.d') Then
    Begin
    FindModule := TryDir(AddSlash(ExpandFileName(Spec)));
    Exit;
    End;

  {a module name}
  Wanted := Spec;
  ND := 0;
  For i := 1 To NRoots Do AddDir(Roots[i]);
  Env := GetEnvironmentVariable('SWORD_PATH');
  While Env <> '' Do
    Begin
    P := Pos(':', Env);
    If P = 0 Then
      Begin
      Entry := Env;
      Env := '';
      End
    Else
      Begin
      Entry := Copy(Env, 1, P - 1);
      Env := Copy(Env, P + 1, 255);
      End;
    AddDir(Entry);
    End;
  Dir := GetEnvironmentVariable('HOME');
  If Dir <> '' Then
    Begin
    AddDir(AddSlash(Dir) + '.sword');
    AddDir(AddSlash(Dir) + '.sword/sword');
    End;
  AddDir('/usr/share/sword');
  AddDir('/usr/local/share/sword');
  For i := 1 To ND Do
    If TryDir(Dirs[i]) Then
      Begin
      FindModule := True;
      Exit;
      End;
  End;


Function SwordBibObj.BibleExists: Boolean;
  Begin
  If Opened Then BibleExists := True
  Else BibleExists := FindModule;
  End;

Function SwordBibObj.IsOpen: Boolean;
  Begin
  IsOpen := Opened;
  End;

Procedure SwordBibObj.FreeData;
  Var T: Byte;
  Begin
  For T := 0 To 1 Do
    Begin
    If Test[T].IdxData <> Nil Then FreeMem(Test[T].IdxData, Test[T].IdxSize);
    If Test[T].BlkData <> Nil Then FreeMem(Test[T].BlkData, Test[T].BlkSize);
    If Test[T].TxtOpen Then Close(Test[T].TxtFile);
    Test[T].IdxData := Nil; Test[T].BlkData := Nil;
    Test[T].TxtOpen := False; Test[T].Present := False;
    Test[T].CacheBuf := ''; Test[T].CacheBlk := -1;
    End;
  End;


Function SwordBibObj.OpenBible: Word;
  Var
    Drv, CompName, Key, Blk, Enc, Src, Vers, DP, Stem, Nm: String;
    T: Byte;
    SaveMode: Byte;
  Begin
  If Opened Then CloseBible;
  If PathSpec = '' Then
    Begin
    OpenBible := bibErrNoPath;
    Exit;
    End;
  If Not FindModule Then
    Begin
    OpenBible := bibErrNotFound;
    Exit;
    End;
  Drv := LowerCase(GetConfValue('ModDrv'));
  If Drv = 'ztext' Then Driver := sdZText
  Else If Drv = 'ztext4' Then Driver := sdZText4
  Else If Drv = 'rawtext' Then Driver := sdRawText
  Else If Drv = 'rawtext4' Then Driver := sdRawText4
  Else
    Begin
    OpenBible := bibErrUnsupported;
    Exit;
    End;
  CompKind := scLzss;                      {Sword's default when CompressType is absent}
  If Driver In [sdZText, sdZText4] Then
    Begin
    CompName := LowerCase(GetConfValue('CompressType'));
    If CompName = 'zip' Then CompKind := scZip
    Else If CompName = 'bzip2' Then CompKind := scBzip2
    Else If (CompName = 'lzss') Or (CompName = '') Then CompKind := scLzss
    Else
      Begin
      OpenBible := bibErrUnsupported;    {XZ and anything else}
      Exit;
      End;
    End;
  Enciphered := HasConfKey('CipherKey');   {even an empty CipherKey= marks a locked module}
  If Enciphered Then
    Begin
    If KeyGiven Then Key := UnlockKey Else Key := GetConfValue('CipherKey');
    If Key = '' Then
      Begin
      Enciphered := False;
      OpenBible := bibErrLocked;
      Exit;
      End;
    CipherSetKey(Master, Key);
    End;
  Vers := GetConfValue('Versification');
  If Not SetVersification(Vers) Then
    Begin
    OpenBible := bibErrUnsupported;
    Exit;
    End;
  Blk := LowerCase(GetConfValue('BlockType'));
  If Blk = 'chapter' Then BlockExt := 'c'
  Else If Blk = 'verse' Then BlockExt := 'v'
  Else BlockExt := 'b';
  Enc := LowerCase(GetConfValue('Encoding'));
  Latin1 := (Enc = 'latin1') Or (Enc = 'latin-1') Or (Enc = 'iso-8859-1') Or (Enc = 'cp1252');
  Src := LowerCase(GetConfValue('SourceType'));
  If Src = 'osis' Then Markup := bmOSIS
  Else If Src = 'thml' Then Markup := bmThML
  Else If Src = 'gbf' Then Markup := bmGBF
  Else If Src = 'tei' Then Markup := bmTEI
  Else If Src = 'plain' Then Markup := bmPlain
  Else Markup := bmUnknown;

  DP := GetConfValue('DataPath');
  If Copy(DP, 1, 2) = './' Then DP := Copy(DP, 3, 255);
  If (DP <> '') And (DP[1] <> '/') Then DataDir := BaseDir + DP Else DataDir := DP;
  DataDir := AddSlash(DataDir);
  If Not IsDir(DataDir) Then
    Begin
    OpenBible := bibErrNotFound;
    Exit;
    End;

  FillChar(Test, SizeOf(Test), 0);
  For T := 0 To 1 Do
    Begin
    Test[T].CacheBlk := -1;
    If T = 0 Then Stem := 'ot' Else Stem := 'nt';
    Case Driver Of
      sdZText, sdZText4:
        Begin
        Nm := DataDir + Stem + '.' + BlockExt + 'zv';
        If FileExists(Nm) Then
          Begin
          If Not LoadFile(Nm, Test[T].IdxData, Test[T].IdxSize) Then
            Begin FreeData; OpenBible := bibErrIO; Exit; End;
          If Not LoadFile(DataDir + Stem + '.' + BlockExt + 'zs', Test[T].BlkData, Test[T].BlkSize) Then
            Begin FreeData; OpenBible := bibErrIO; Exit; End;
          SaveMode := FileMode;
          FileMode := 0;
          Assign(Test[T].TxtFile, DataDir + Stem + '.' + BlockExt + 'zz');
          Reset(Test[T].TxtFile, 1);
          FileMode := SaveMode;
          If IOResult <> 0 Then
            Begin FreeData; OpenBible := bibErrIO; Exit; End;
          Test[T].TxtOpen := True;
          Test[T].Present := True;
          End;
        End;
      sdRawText, sdRawText4:
        Begin
        Nm := DataDir + Stem + '.vss';
        If FileExists(Nm) Then
          Begin
          If Not LoadFile(Nm, Test[T].IdxData, Test[T].IdxSize) Then
            Begin FreeData; OpenBible := bibErrIO; Exit; End;
          SaveMode := FileMode;
          FileMode := 0;
          Assign(Test[T].TxtFile, DataDir + Stem);
          Reset(Test[T].TxtFile, 1);
          FileMode := SaveMode;
          If IOResult <> 0 Then
            Begin FreeData; OpenBible := bibErrIO; Exit; End;
          Test[T].TxtOpen := True;
          Test[T].Present := True;
          End;
        End;
      End;
    End;
  If Not (Test[0].Present Or Test[1].Present) Then
    Begin
    OpenBible := bibErrNotFound;
    Exit;
    End;
  Opened := True;
  If Enciphered And (Not KeyWorks) Then
    Begin
    CloseBible;
    OpenBible := bibErrBadKey;
    Exit;
    End;
  SeekFirst;
  OpenBible := bibOk;
  End;


Function SwordBibObj.CloseBible: Word;
  Begin
  If WMode Then
    Begin
    CloseBible := FlushBible;
    Exit;
    End;
  FreeData;
  Opened := False;
  CloseBible := bibOk;
  End;


Function SwordBibObj.GetName: String;
  Begin
  If WMode Then
    Begin
    GetName := AbsBibObj.GetName;
    Exit;
    End;
  GetName := ModName;
  End;

Function SwordBibObj.GetDescription: String;
  Begin
  If WMode Then
    Begin
    GetDescription := AbsBibObj.GetDescription;
    Exit;
    End;
  GetDescription := GetConfValue('Description');
  End;

Function SwordBibObj.GetAbout: BibStr;
  Var A: BibStr; i: LongInt;
  Begin
  If WMode Then
    Begin
    GetAbout := AbsBibObj.GetAbout;
    Exit;
    End;
  A := GetConfValue('About');
  {RTF-ish: \par is a paragraph break}
  i := Pos('\par', A);
  While i > 0 Do
    Begin
    Delete(A, i, 4);
    Insert(#10, A, i);
    i := Pos('\par', A);
    End;
  GetAbout := A;
  End;

Function SwordBibObj.GetLang: String;
  Begin
  If WMode Then
    Begin
    GetLang := AbsBibObj.GetLang;
    Exit;
    End;
  GetLang := GetConfValue('Lang');
  End;

Function SwordBibObj.GetVersion: String;
  Begin
  If WMode Then
    Begin
    GetVersion := AbsBibObj.GetVersion;
    Exit;
    End;
  GetVersion := GetConfValue('Version');
  End;

Function SwordBibObj.GetCopyright: String;
  Var S: String;
  Begin
  If WMode Then
    Begin
    GetCopyright := AbsBibObj.GetCopyright;
    Exit;
    End;
  S := GetConfValue('ShortCopyright');
  If S = '' Then S := GetConfValue('Copyright');
  If S = '' Then S := GetConfValue('DistributionLicense');
  GetCopyright := S;
  End;

Function SwordBibObj.GetMarkup: BibMarkup;
  Begin
  If WMode Then
    Begin
    GetMarkup := AbsBibObj.GetMarkup;
    Exit;
    End;
  GetMarkup := Markup;
  End;

Function SwordBibObj.HasOT: Boolean;
  Begin
  If WMode Then HasOT := WLast[0] >= 0 Else HasOT := Test[0].Present;
  End;

Function SwordBibObj.HasNT: Boolean;
  Begin
  If WMode Then HasNT := WLast[1] >= 0 Else HasNT := Test[1].Present;
  End;

Function SwordBibObj.HasConfKey(Key: String): Boolean;
  Begin
  HasConfKey := Pos(#10 + LowerCase(Key) + '=', #10 + LowerCase(StringReplace(Conf, #13#10, #10, [rfReplaceAll]))) > 0;
  End;

Function SwordBibObj.IsLocked: Boolean;
  Begin
  If Conf = '' Then FindModule;
  IsLocked := HasConfKey('CipherKey') And (Not KeyGiven) And (GetConfValue('CipherKey') = '');
  End;

Procedure SwordBibObj.SetUnlockKey(Key: String);
  Begin
  UnlockKey := Trim(Key);
  KeyGiven := UnlockKey <> '';
  End;

Function SwordBibObj.GetUnlockInfo: String;
  Begin
  If Conf = '' Then FindModule;
  GetUnlockInfo := GetConfValue('UnlockInfo');
  End;

{ After opening an enciphered module: do the first verses read as text?  A wrong key
  gives garbage (control characters) or a block that will not inflate. }
Function SwordBibObj.KeyWorks: Boolean;
  Var
    N, i: Word;
    S: BibStr;
    Bad: LongInt;
  Begin
  KeyWorks := False;
  SeekFirst;
  For N := 1 To 400 Do
    Begin
    S := GetRawVerse;
    If S <> '' Then
      Begin
      Bad := 0;
      For i := 1 To Length(S) Do
        If (S[i] < ' ') And (Not (S[i] In [#9, #10, #13])) Then Inc(Bad);
      KeyWorks := Bad = 0;
      Exit;
      End;
    SeekNext;
    If Not Found Then Break;
    End;
  End;

Function SwordBibObj.GetConfPath: String;
  Begin
  GetConfPath := ConfPath;
  End;

Function SwordBibObj.GetDataPath: String;
  Begin
  GetDataPath := DataDir;
  End;


{ Load and inflate block Blk of testament T into Test[T].CacheBuf }
Function SwordBibObj.ReadZBlock(T: Byte; Blk: LongInt): Boolean;
  Var
    Ofs, CSize, USize: LongWord;
    Comp: Pointer;
    ULen: LongWord;
    Res: Integer;
    Got: LongInt;
  Begin
  ReadZBlock := False;
  If Test[T].CacheBlk = Blk Then
    Begin
    ReadZBlock := True;
    Exit;
    End;
  If (Blk < 0) Or ((Blk + 1) * 12 > Test[T].BlkSize) Then Exit;
  Ofs := GetU32(Test[T].BlkData, Blk * 12);
  CSize := GetU32(Test[T].BlkData, Blk * 12 + 4);
  USize := GetU32(Test[T].BlkData, Blk * 12 + 8);
  If (CSize = 0) Or (USize = 0) Or (USize > 64 * 1024 * 1024) Then Exit;
  GetMem(Comp, CSize);
  Seek(Test[T].TxtFile, Ofs);
  BlockRead(Test[T].TxtFile, Comp^, CSize, Got);
  If (IOResult <> 0) Or (Got <> LongInt(CSize)) Then
    Begin
    FreeMem(Comp, CSize);
    Exit;
    End;
  If Enciphered Then CipherDecryptBuf(Master, Comp, CSize);
  SetLength(Test[T].CacheBuf, USize + 18);        {LZSS may write a few bytes past the nominal size}
  ULen := USize + 18;
  Case CompKind Of
    scLzss: Res := LzssUncompress(Comp, CSize, @Test[T].CacheBuf[1], ULen);
    scBzip2: Res := BzUncompress(Comp, CSize, @Test[T].CacheBuf[1], ULen);
    Else Res := ZUncompress(Comp, CSize, @Test[T].CacheBuf[1], ULen);
    End;
  FreeMem(Comp, CSize);
  If Res <> 0 Then
    Begin
    Test[T].CacheBuf := '';
    Test[T].CacheBlk := -1;
    Exit;
    End;
  SetLength(Test[T].CacheBuf, ULen);
  Test[T].CacheBlk := Blk;
  ReadZBlock := True;
  End;


Function SwordBibObj.GetRawVerse: BibStr;
  Var T: Byte;
  Begin
  GetRawVerse := '';
  If (Not Opened) Or (Not Found) Then Exit;
  If VrsInNT(GetBook) Then T := 1 Else T := 0;
  GetRawVerse := ReadEntry(T, VrsTestOffset(VSys, GetBook, GetChapter, GetVerse));
  End;

Function SwordBibObj.GetIntro(Level, Book, Chap: Word): BibStr;
  Var T: Byte;
  Begin
  GetIntro := '';
  If Not Opened Then Exit;
  Case Level Of
    bilModule: GetIntro := ReadEntry(0, 0);
    bilTestament:
      Begin
      If (Book < 1) Or (Book > GetBookCount) Then Exit;
      If VrsInNT(Book) Then GetIntro := ReadEntry(1, 1) Else GetIntro := ReadEntry(0, 1);
      End;
    bilBook, bilChapter:
      Begin
      If (Book < 1) Or (Book > GetBookCount) Then Exit;
      If VrsInNT(Book) Then T := 1 Else T := 0;
      If Level = bilBook Then GetIntro := ReadEntry(T, VrsTestOffset(VSys, Book, 0, 0))
      Else If (Chap >= 1) And (Chap <= GetChapterCount(Book)) Then
        GetIntro := ReadEntry(T, VrsTestOffset(VSys, Book, Chap, 0));
      End;
    End;
  End;

{ The text stored at index Idx of testament file T (0 = OT, 1 = NT) }
Function SwordBibObj.ReadEntry(T: Byte; Idx: LongInt): BibStr;
  Var
    EOfs: LongInt;
    Blk, Start, Size: LongWord;
    S: BibStr;
    L: LongInt;
  Begin
  ReadEntry := '';
  If Not Test[T].Present Then Exit;
  S := '';
  Case Driver Of
    sdZText, sdZText4:
      Begin
      If Driver = sdZText Then EOfs := 10 Else EOfs := 12;
      If (Idx + 1) * EOfs > Test[T].IdxSize Then Exit;
      Blk := GetU32(Test[T].IdxData, Idx * EOfs);
      Start := GetU32(Test[T].IdxData, Idx * EOfs + 4);
      If Driver = sdZText Then Size := GetU16(Test[T].IdxData, Idx * EOfs + 8)
      Else Size := GetU32(Test[T].IdxData, Idx * EOfs + 8);
      If Size = 0 Then Exit;
      If Not ReadZBlock(T, Blk) Then Exit;
      If Start >= LongWord(Length(Test[T].CacheBuf)) Then Exit;
      If Start + Size > LongWord(Length(Test[T].CacheBuf)) Then
        Size := Length(Test[T].CacheBuf) - Start;
      S := Copy(Test[T].CacheBuf, Start + 1, Size);
      End;
    sdRawText, sdRawText4:
      Begin
      If Driver = sdRawText Then EOfs := 6 Else EOfs := 8;
      If (Idx + 1) * EOfs > Test[T].IdxSize Then Exit;
      Start := GetU32(Test[T].IdxData, Idx * EOfs);
      If Driver = sdRawText Then Size := GetU16(Test[T].IdxData, Idx * EOfs + 4)
      Else Size := GetU32(Test[T].IdxData, Idx * EOfs + 4);
      If Size = 0 Then Exit;
      SetLength(S, Size);
      Seek(Test[T].TxtFile, Start);
      BlockRead(Test[T].TxtFile, S[1], Size, L);
      If (IOResult <> 0) Or (L <> LongInt(Size)) Then Exit;
      End;
    End;
  If Enciphered And (Driver In [sdRawText, sdRawText4]) And (S <> '') Then
    CipherDecryptBuf(Master, PByte(@S[1]), Length(S));
  {an entry is ended by a NUL (z) or a newline (raw); cut there}
  L := Pos(#0, S);
  If L > 0 Then SetLength(S, L - 1);
  While (Length(S) > 0) And (S[Length(S)] In [#10, #13, ' ']) Do SetLength(S, Length(S) - 1);
  If Latin1 Then S := Latin1ToUtf8(S);
  ReadEntry := S;
  End;


{---------------------------------------------------------------- writing}

Const
  VrsNames: Array[VrsSystem] Of String[8] = ('KJV', 'KJVA', 'NRSV', 'NRSVA');

Procedure PutLE32(P: Pointer; V: LongWord);
  Begin
  PLongWord(P)^ := NtoLE(V);
  End;

Procedure PutLE16(P: Pointer; V: Word);
  Begin
  PWord(P)^ := NtoLE(V);
  End;

Procedure SwordBibObj.SetStorage(Drv: SwordDriver; Comp: SwordComp; Block: SwordBlock);
  Begin
  WDriver := Drv;
  WComp := Comp;
  WBlock := Block;
  End;

Function SwordBibObj.IsWriting: Boolean;
  Begin
  IsWriting := WMode;
  End;

Function SwordBibObj.IsReadOnly: Boolean;
  Begin
  IsReadOnly := Not WMode;
  End;

Function SwordBibObj.WDataDir: String;
  Begin
  If WDriver = sdRawText Then
    WDataDir := WRoot + 'modules/texts/rawtext/' + LowerCase(WName) + '/'
  Else
    WDataDir := WRoot + 'modules/texts/ztext/' + LowerCase(WName) + '/';
  End;

Function BlockLetter(B: SwordBlock): Char;
  Begin
  Case B Of
    sbChapter: BlockLetter := 'c';
    sbVerse: BlockLetter := 'v';
    Else BlockLetter := 'b';
    End;
  End;

Function SwordBibObj.WOpenFiles(T: Byte): Boolean;
  Var
    Stem: String;
  Begin
  WOpenFiles := False;
  If T = 0 Then Stem := 'ot' Else Stem := 'nt';
  If WFilesOpen[T] Then
    Begin
    WOpenFiles := True;
    Exit;
    End;
  If WDriver = sdRawText Then
    Begin
    Assign(WFileZ[T], WDataDir + Stem);
    Rewrite(WFileZ[T], 1);
    If IOResult <> 0 Then Exit;
    End
  Else
    Begin
    Assign(WFileS[T], WDataDir + Stem + '.' + BlockLetter(WBlock) + 'zs');
    Rewrite(WFileS[T], 1);
    If IOResult <> 0 Then Exit;
    Assign(WFileZ[T], WDataDir + Stem + '.' + BlockLetter(WBlock) + 'zz');
    Rewrite(WFileZ[T], 1);
    If IOResult <> 0 Then Exit;
    End;
  WZzPos[T] := 0;
  WBlkNo[T] := 0;
  WFilesOpen[T] := True;
  WOpenFiles := True;
  End;

Procedure SwordBibObj.WFree;
  Var T: Byte;
  Begin
  For T := 0 To 1 Do
    Begin
    If WIdx[T] <> Nil Then FreeMem(WIdx[T]);
    If WBuf[T] <> Nil Then FreeMem(WBuf[T]);
    WIdx[T] := Nil; WBuf[T] := Nil;
    WBufLen[T] := 0; WBufCap[T] := 0; WBlkOpen[T] := False;
    End;
  End;

Function SwordBibObj.CreateBible(Name: String): Word;
  Var
    T: Byte;
    LastB, i: Word;
    Stem, Ext, Dir: String;
  Begin
  If Opened Or WMode Then CloseBible;
  CreateBible := bibErrCreate;
  If Name = '' Then Exit;
  For i := 1 To Length(Name) Do
    If Not (Name[i] In ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.']) Then Exit;
  If (WDriver <> sdZText) And (WDriver <> sdRawText) Then
    Begin
    CreateBible := bibErrUnsupported;
    Exit;
    End;
  If (WDriver = sdZText) And (WComp = scBzip2) Then
    Begin
    CreateBible := bibErrUnsupported;     {bzip2 can be read but not written}
    Exit;
    End;
  If (WDriver = sdRawText) And KeyGiven Then
    Begin
    CreateBible := bibErrUnsupported;     {enciphering is for zText}
    Exit;
    End;
  If PathSpec = '' Then WRoot := './' Else WRoot := AddSlash(PathSpec);
  WName := Name;
  MetaName := Name;
  WConfFile := WRoot + 'mods.d/' + LowerCase(Name) + '.conf';
  If FileExists(WConfFile) And (Not Overwrite) Then
    Begin
    CreateBible := bibErrExists;
    Exit;
    End;
  Dir := WDataDir;
  If (Not ForceDirectories(WRoot + 'mods.d')) Or (Not ForceDirectories(Dir)) Then Exit;
  {remove files of an older module with this name}
  For T := 0 To 1 Do
    Begin
    If T = 0 Then Stem := 'ot' Else Stem := 'nt';
    If WDriver = sdRawText Then
      Begin
      DeleteFile(Dir + Stem);
      DeleteFile(Dir + Stem + '.vss');
      End
    Else
      Begin
      Ext := BlockLetter(WBlock);
      DeleteFile(Dir + Stem + '.' + Ext + 'zs');
      DeleteFile(Dir + Stem + '.' + Ext + 'zz');
      DeleteFile(Dir + Stem + '.' + Ext + 'zv');
      End;
    End;
  {the Apocrypha, when the versification has them, are part of the OT file}
  UseApoc := VrsHasApoc(VSys);
  LastB := BibOTBooks;
  If UseApoc Then LastB := GetBookCount;
  WIdxCount[0] := VrsTestOffset(VSys, LastB, GetChapterCount(LastB), GetVerseCount(LastB, GetChapterCount(LastB))) + 1;
  WIdxCount[1] := VrsTestOffset(VSys, BibBooks, GetChapterCount(BibBooks), GetVerseCount(BibBooks, GetChapterCount(BibBooks))) + 1;
  For T := 0 To 1 Do
    Begin
    If WDriver = sdRawText Then i := 6 Else i := 10;
    GetMem(WIdx[T], WIdxCount[T] * i);
    FillChar(WIdx[T]^, WIdxCount[T] * i, 0);
    WLast[T] := -1;
    WBufLen[T] := 0; WBufCap[T] := 0; WBuf[T] := Nil; WBlkOpen[T] := False;
    WFilesOpen[T] := False;
    WBlkNo[T] := 0; WZzPos[T] := 0;
    End;
  Enciphered := KeyGiven;
  If Enciphered Then CipherSetKey(Master, UnlockKey);
  WMode := True;
  CreateBible := bibOk;
  End;


Function SwordBibObj.WFlushBlock(T: Byte): Boolean;
  Var
    Dst: Pointer;
    Cap, DL: LongWord;
    Rec: Array[0..11] Of Byte;
    Res: Integer;
  Begin
  WFlushBlock := True;
  If (Not WBlkOpen[T]) Or (WBufLen[T] = 0) Then
    Begin
    WBlkOpen[T] := False;
    Exit;
    End;
  WFlushBlock := False;
  Cap := WBufLen[T] + WBufLen[T] Div 8 + 64;
  GetMem(Dst, Cap);
  DL := Cap;
  If WComp = scLzss Then Res := LzssCompress(WBuf[T], WBufLen[T], Dst, DL)
  Else Res := ZCompress(WBuf[T], WBufLen[T], Dst, DL);
  If Res = 0 Then
    Begin
    If Enciphered Then CipherEncryptBuf(Master, PByte(Dst), DL);
    BlockWrite(WFileZ[T], Dst^, DL);
    If IOResult = 0 Then
      Begin
      PutLE32(@Rec[0], WZzPos[T]);
      PutLE32(@Rec[4], DL);
      PutLE32(@Rec[8], WBufLen[T]);
      BlockWrite(WFileS[T], Rec, 12);
      WFlushBlock := IOResult = 0;
      End;
    Inc(WZzPos[T], DL);
    End;
  FreeMem(Dst);
  Inc(WBlkNo[T]);
  WBufLen[T] := 0;
  WBlkOpen[T] := False;
  End;


Function SwordBibObj.WStoreEntry(T: Byte; Idx: LongInt; KBook, KChap: Word; Const Txt: BibStr): Boolean;
  Var
    Size: LongWord;
    P: PByte;
    NewCap: LongWord;
    NL: Char;
  Begin
  WStoreEntry := False;
  If (Idx <= WLast[T]) Or (Idx >= WIdxCount[T]) Then Exit;
  Size := Length(Txt);
  If Size > 65535 Then Exit;
  WLast[T] := Idx;
  If Size = 0 Then
    Begin
    WStoreEntry := True;           {empty = missing verse = zero index entry}
    Exit;
    End;
  If Not WOpenFiles(T) Then Exit;
  If WDriver = sdRawText Then
    Begin
    P := PByte(WIdx[T]) + Idx * 6;
    PutLE32(P, WZzPos[T]);
    PutLE16(P + 4, Size);
    BlockWrite(WFileZ[T], Txt[1], Size);
    NL := #10;
    BlockWrite(WFileZ[T], NL, 1);
    If IOResult <> 0 Then Exit;
    Inc(WZzPos[T], Size + 1);
    WStoreEntry := True;
    Exit;
    End;
  {zText: a new block when the block boundary of the block type is crossed}
  If WBlkOpen[T] Then
    If (WBlock = sbVerse) Or (KBook <> WKeyBook[T]) Or ((WBlock = sbChapter) And (KChap <> WKeyChap[T])) Then
      If Not WFlushBlock(T) Then Exit;
  If Not WBlkOpen[T] Then
    Begin
    WBlkOpen[T] := True;
    WKeyBook[T] := KBook;
    WKeyChap[T] := KChap;
    WBufLen[T] := 0;
    End;
  If WBufLen[T] + Size > WBufCap[T] Then
    Begin
    NewCap := WBufCap[T] * 2;
    If NewCap < WBufLen[T] + Size Then NewCap := WBufLen[T] + Size;
    If NewCap < 65536 Then NewCap := 65536;
    ReallocMem(WBuf[T], NewCap);
    WBufCap[T] := NewCap;
    End;
  P := PByte(WIdx[T]) + Idx * 10;
  PutLE32(P, WBlkNo[T]);
  PutLE32(P + 4, WBufLen[T]);
  PutLE16(P + 8, Size);
  Move(Txt[1], (PByte(WBuf[T]) + WBufLen[T])^, Size);
  Inc(WBufLen[T], Size);
  If WBlock = sbVerse Then
    If Not WFlushBlock(T) Then Exit;
  WStoreEntry := True;
  End;


Function SwordBibObj.PutVerse(Book, Chap, Verse: Word; Const Txt: BibStr): Boolean;
  Var T: Byte;
  Begin
  PutVerse := False;
  If Not WMode Then Exit;
  If Verse = 0 Then
    Begin
    If (Book < 1) Or (Book > GetBookCount) Or (Chap < 1) Or (Chap > GetChapterCount(Book)) Then Exit;
    End
  Else If Not ValidRef(Book, Chap, Verse) Then Exit;
  If VrsInNT(Book) Then T := 1 Else T := 0;
  PutVerse := WStoreEntry(T, VrsTestOffset(VSys, Book, Chap, Verse), Book, Chap, Txt);
  End;


Function SwordBibObj.PutIntro(Level, Book, Chap: Word; Const Txt: BibStr): Boolean;
  Var T: Byte;
  Begin
  PutIntro := False;
  If Not WMode Then Exit;
  Case Level Of
    bilModule: PutIntro := WStoreEntry(0, 0, 1, 1, Txt);
    bilTestament:
      Begin
      If (Book < 1) Or (Book > GetBookCount) Then Exit;
      If VrsInNT(Book) Then PutIntro := WStoreEntry(1, 1, BibOTBooks + 1, 1, Txt)
      Else PutIntro := WStoreEntry(0, 1, 1, 1, Txt);
      End;
    bilBook:
      Begin
      If (Book < 1) Or (Book > GetBookCount) Then Exit;
      If VrsInNT(Book) Then T := 1 Else T := 0;
      PutIntro := WStoreEntry(T, VrsTestOffset(VSys, Book, 0, 0), Book, 1, Txt);
      End;
    bilChapter: PutIntro := PutVerse(Book, Chap, 0, Txt);
    End;
  End;


Function SwordBibObj.WBuildConf: BibStr;
  Var
    C, Ab: BibStr;
    i: LongInt;
  Begin
  C := '[' + WName + ']'#10;
  If WDriver = sdRawText Then
    C := C + 'DataPath=./modules/texts/rawtext/' + LowerCase(WName) + '/'#10'ModDrv=RawText'#10
  Else
    Begin
    C := C + 'DataPath=./modules/texts/ztext/' + LowerCase(WName) + '/'#10'ModDrv=zText'#10;
    Case WBlock Of
      sbChapter: C := C + 'BlockType=CHAPTER'#10;
      sbVerse: C := C + 'BlockType=VERSE'#10;
      Else C := C + 'BlockType=BOOK'#10;
      End;
    If WComp = scLzss Then C := C + 'CompressType=LZSS'#10 Else C := C + 'CompressType=ZIP'#10;
    End;
  Case MetaMarkup Of
    bmOSIS: C := C + 'SourceType=OSIS'#10;
    bmThML: C := C + 'SourceType=ThML'#10;
    bmGBF: C := C + 'SourceType=GBF'#10;
    bmTEI: C := C + 'SourceType=TEI'#10;
    bmPlain: C := C + 'SourceType=Plain'#10;
    End;
  C := C + 'Encoding=UTF-8'#10;
  C := C + 'Versification=' + VrsNames[VSys] + #10;
  If MetaLang <> '' Then C := C + 'Lang=' + MetaLang + #10;
  If MetaVer <> '' Then C := C + 'Version=' + MetaVer + #10;
  If MetaDesc <> '' Then C := C + 'Description=' + MetaDesc + #10;
  If MetaCopy <> '' Then C := C + 'Copyright=' + MetaCopy + #10;
  If MetaAbout <> '' Then
    Begin
    Ab := '';
    For i := 1 To Length(MetaAbout) Do
      Case MetaAbout[i] Of
        #13: ;
        #10: Ab := Ab + '\par ';
        Else Ab := Ab + MetaAbout[i];
        End;
    C := C + 'About=' + Ab + #10;
    End;
  If Enciphered Then C := C + 'CipherKey='#10;
  WBuildConf := C;
  End;


Function SwordBibObj.FlushBible: Word;
  Var
    T: Byte;
    Stem, Nm: String;
    F: File;
    Conf_: BibStr;
    Fail: Boolean;
    EntSize: LongInt;
  Begin
  FlushBible := bibOk;
  If Not WMode Then Exit;
  Fail := False;
  If WDriver = sdRawText Then EntSize := 6 Else EntSize := 10;
  For T := 0 To 1 Do
    Begin
    If T = 0 Then Stem := 'ot' Else Stem := 'nt';
    If WDriver = sdZText Then
      If Not WFlushBlock(T) Then Fail := True;
    If WFilesOpen[T] Then
      Begin
      Close(WFileZ[T]);
      If WDriver = sdZText Then Close(WFileS[T]);
      If WDriver = sdRawText Then Nm := WDataDir + Stem + '.vss'
      Else Nm := WDataDir + Stem + '.' + BlockLetter(WBlock) + 'zv';
      Assign(F, Nm);
      Rewrite(F, 1);
      If IOResult <> 0 Then Fail := True
      Else
        Begin
        BlockWrite(F, WIdx[T]^, WIdxCount[T] * EntSize);
        If IOResult <> 0 Then Fail := True;
        Close(F);
        End;
      WFilesOpen[T] := False;
      End;
    End;
  Conf_ := WBuildConf;
  Assign(F, WConfFile);
  Rewrite(F, 1);
  If IOResult <> 0 Then Fail := True
  Else
    Begin
    BlockWrite(F, Conf_[1], Length(Conf_));
    If IOResult <> 0 Then Fail := True;
    Close(F);
    End;
  WFree;
  WMode := False;
  Enciphered := False;
  If Fail Then FlushBible := bibErrIO;
  End;


End.
