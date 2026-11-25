Unit MKBibMys;       {MySword Bible module object (SQLite, .bbl.mybible)}

{$I MKBib.Def}

{
  MKBibMys - descendant of AbsBibObj for MySword (Android Bible reader) modules.

  A MySword module is an SQLite database with two tables:
      Details (Title, Description, Abbreviation, Comments, Version, Language, OT, NT,
               Strong, RightToLeft, ...)           one row of module information
      Bible   (Book, Chapter, Verse, Scripture)    books 1..66, verse 0 = chapter intro
  The text is MySword's own GBF-like markup (<FI>italic<Fi>, <RF>note<Rf>, <TS>title<Ts>,
  <WG1234> Strong's numbers, <CM> paragraph ...), reported as bmMySword.

  Mapping of the module information:
      GetName        = Abbreviation        GetDescription = Title
      GetAbout       = Description         GetCopyright   = Comments
  MySword modules always use the KJV versification and have no Apocrypha, so
  SetVersification accepts KJV only and the module has 66 books.

  Reading   SetBibPath(file)      the .bbl.mybible file (the extension may be left off)
            OpenBible             loads the whole Bible table into memory
  Writing   SetBibPath(dir|file)  CreateBible(Name) makes <dir>/<Name>.bbl.mybible
            PutVerse / PutIntro(bilChapter) in any order, then CloseBible
  The text is stored exactly as given: write MySword markup (or plain text) if the module
  is for the MySword app.  Encrypted modules (Details.Encryption set) are not supported.

  SQLite is loaded at run time (libsqlite3.so.0 or libsqlite3.so; sqlite3.dll on Windows), so nothing is linked in.
}

Interface

Uses MKBibMod, MKBibAbs, MKBibVrs, sqlite3dyn;

Type
  PBibStrArr = ^TBibStrArr;
  TBibStrArr = Array[0..0] Of BibStr;

  MySwordBibObj = Object(AbsBibObj)
  Constructor Init;
  Destructor Done; Virtual;
  Procedure SetBibPath(BP: String); Virtual;
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
  Function  SetVersification(Name: String): Boolean; Virtual;
  Function  GetRawVerse: BibStr; Virtual;
  Function  GetIntro(Level, Book, Chap: Word): BibStr; Virtual;   {chapter introductions only}
  Function  HasStrongs: Boolean; {Details.Strong flag (reading) / Strong's tags seen (writing)}
  Function  GetSkippedRows: LongInt; {rows that did not fit the KJV verse structure}
  Function  CreateBible(Name: String): Word; Virtual;
  Function  PutVerse(Book, Chap, Verse: Word; Const Txt: BibStr): Boolean; Virtual;
  Function  PutIntro(Level, Book, Chap: Word; Const Txt: BibStr): Boolean; Virtual;
  Function  FlushBible: Word; Virtual;
  Function  IsWriting: Boolean; Virtual;
  Function  IsReadOnly: Boolean; Virtual;

  Public
  PathSpec, FileName: BibStr;
  Db: psqlite3;
  Opened, WMode: Boolean;
  Texts, Intros: PBibStrArr;          {by linear verse number 1..31102 (index 0 unused)}
  DName, DTitle, DDesc, DComments, DVersion, DLang: BibStr;
  DOT, DNT, DStrong: Boolean;
  Skipped: LongInt;
  WStmt: psqlite3_stmt;
  WSawOT, WSawNT, WSawStrong: Boolean;
  Function  LoadDetails: Boolean;
  Function  LoadBible: Boolean;
  Procedure FreeTexts;
  Function  FindFile: Boolean;
  End;

Type MySwordBibPtr = ^MySwordBibObj;

Implementation

Uses SysUtils, Strings;

{$WARN SYMBOL_DEPRECATED OFF}

Var
  SqlReady: Boolean;
  SqlTried: Boolean;

Function InitSql: Boolean;
  Begin
  If Not SqlTried Then
    Begin
    SqlTried := True;
{$IFDEF WINDOWS}
    SqlReady := (InitialiseSQLite('sqlite3.dll') > 0) Or (InitialiseSQLite('winsqlite3.dll') > 0);
{$ELSE}
    SqlReady := (InitialiseSQLite('libsqlite3.so.0') > 0) Or (InitialiseSQLite('libsqlite3.so') > 0);
{$ENDIF}
    End;
  InitSql := SqlReady;
  End;

Function PCharToBib(P: PChar): BibStr;
  Var
    N: LongInt;
    R: BibStr;
  Begin
  R := '';
  If P <> Nil Then
    Begin
    N := StrLen(P);
    SetLength(R, N);
    If N > 0 Then Move(P^, R[1], N);
    End;
  PCharToBib := R;
  End;

Function ColText(St: psqlite3_stmt; Col: LongInt): BibStr;
  Var
    P: PChar;
    N: LongInt;
    R: BibStr;
  Begin
  R := '';
  P := PChar(sqlite3_column_text(St, Col));
  If P <> Nil Then
    Begin
    N := sqlite3_column_bytes(St, Col);
    SetLength(R, N);
    If N > 0 Then Move(P^, R[1], N);
    End;
  ColText := R;
  End;

Procedure BindText(St: psqlite3_stmt; Idx: LongInt; Const S: BibStr);
  Begin
  If S = '' Then sqlite3_bind_text(St, Idx, '', 0, sqlite3_destructor_type(SQLITE_TRANSIENT))
  Else sqlite3_bind_text(St, Idx, PChar(S), Length(S), sqlite3_destructor_type(SQLITE_TRANSIENT));
  End;

Function ExecSql(Db: psqlite3; Const Sql: AnsiString): Boolean;
  Begin
  ExecSql := sqlite3_exec(Db, PChar(Sql), Nil, Nil, Nil) = SQLITE_OK;
  End;


Constructor MySwordBibObj.Init;
  Begin
  AbsBibObj.Init;
  PathSpec := ''; FileName := '';
  Db := Nil; Opened := False; WMode := False;
  Texts := Nil; Intros := Nil;
  DName := ''; DTitle := ''; DDesc := ''; DComments := ''; DVersion := ''; DLang := '';
  DOT := False; DNT := False; DStrong := False;
  Skipped := 0;
  WStmt := Nil;
  MetaMarkup := bmMySword;
  End;

Destructor MySwordBibObj.Done;
  Begin
  If Opened Or WMode Then CloseBible;
  AbsBibObj.Done;
  End;

Procedure MySwordBibObj.SetBibPath(BP: String);
  Begin
  If Opened Or WMode Then CloseBible;
  PathSpec := BP;
  End;

Function MySwordBibObj.FindFile: Boolean;
  Begin
  FindFile := False;
  If PathSpec = '' Then Exit;
  If FileExists(PathSpec) Then FileName := PathSpec
  Else If FileExists(PathSpec + '.bbl.mybible') Then FileName := PathSpec + '.bbl.mybible'
  Else If FileExists(PathSpec + '.mybible') Then FileName := PathSpec + '.mybible'
  Else Exit;
  FindFile := True;
  End;

Function MySwordBibObj.BibleExists: Boolean;
  Begin
  BibleExists := Opened Or FindFile;
  End;

Function MySwordBibObj.IsOpen: Boolean;
  Begin
  IsOpen := Opened;
  End;

Function MySwordBibObj.SetVersification(Name: String): Boolean;
  Begin
  SetVersification := AbsBibObj.SetVersification(Name) And (VSys = vsKJV);
  VSys := vsKJV;
  End;

Procedure MySwordBibObj.FreeTexts;
  Var i: LongInt;
  Begin
  If Texts <> Nil Then
    Begin
    For i := 0 To BibTotalVerses Do Texts^[i] := '';
    FreeMem(Texts);
    Texts := Nil;
    End;
  If Intros <> Nil Then
    Begin
    For i := 0 To BibTotalVerses Do Intros^[i] := '';
    FreeMem(Intros);
    Intros := Nil;
    End;
  End;


{ Details: one row, column names vary a little between modules (case) }
Function MySwordBibObj.LoadDetails: Boolean;
  Var
    St: psqlite3_stmt;
    i, N: LongInt;
    Col, Val_, ColName: BibStr;
  Begin
  LoadDetails := False;
  If sqlite3_prepare_v2(Db, 'SELECT * FROM Details', -1, @St, Nil) <> SQLITE_OK Then Exit;
  If sqlite3_step(St) = SQLITE_ROW Then
    Begin
    N := sqlite3_column_count(St);
    For i := 0 To N - 1 Do
      Begin
      ColName := PCharToBib(PChar(sqlite3_column_name(St, i)));
      Col := LowerCase(ColName);
      Val_ := ColText(St, i);
      If Col = 'title' Then DTitle := Val_
      Else If Col = 'description' Then DDesc := Val_
      Else If Col = 'abbreviation' Then DName := Val_
      Else If Col = 'comments' Then DComments := Val_
      Else If Col = 'version' Then DVersion := Val_
      Else If Col = 'language' Then DLang := Val_
      Else If Col = 'ot' Then DOT := (Val_ <> '') And (Val_ <> '0')
      Else If Col = 'nt' Then DNT := (Val_ <> '') And (Val_ <> '0')
      Else If Col = 'strong' Then DStrong := (Val_ <> '') And (Val_ <> '0')
      Else If (Col = 'encryption') And (Val_ <> '') And (Val_ <> '0') Then
        Begin
        sqlite3_finalize(St);
        Exit;                     {encrypted: not supported}
        End;
      End;
    End;
  sqlite3_finalize(St);
  LoadDetails := True;
  End;

Function MySwordBibObj.LoadBible: Boolean;
  Var
    St: psqlite3_stmt;
    B, C, V, L: LongInt;
  Begin
  LoadBible := False;
  GetMem(Texts, (BibTotalVerses + 1) * SizeOf(BibStr));
  FillChar(Texts^, (BibTotalVerses + 1) * SizeOf(BibStr), 0);
  GetMem(Intros, (BibTotalVerses + 1) * SizeOf(BibStr));
  FillChar(Intros^, (BibTotalVerses + 1) * SizeOf(BibStr), 0);
  If sqlite3_prepare_v2(Db, 'SELECT Book, Chapter, Verse, Scripture FROM Bible', -1, @St, Nil) <> SQLITE_OK Then Exit;
  Skipped := 0;
  While sqlite3_step(St) = SQLITE_ROW Do
    Begin
    B := sqlite3_column_int(St, 0);
    C := sqlite3_column_int(St, 1);
    V := sqlite3_column_int(St, 2);
    If V = 0 Then
      Begin
      L := VrsLinear(vsKJV, B, C, 1);          {chapter intro: stored with the chapter's first verse}
      If L > 0 Then Intros^[L] := ColText(St, 3) Else Inc(Skipped);
      End
    Else
      Begin
      L := VrsLinear(vsKJV, B, C, V);
      If L > 0 Then Texts^[L] := ColText(St, 3) Else Inc(Skipped);
      End;
    End;
  sqlite3_finalize(St);
  LoadBible := True;
  End;

Function MySwordBibObj.OpenBible: Word;
  Var
    L: LongInt;
    Ok: Boolean;
  Begin
  If Opened Or WMode Then CloseBible;
  If PathSpec = '' Then
    Begin
    OpenBible := bibErrNoPath;
    Exit;
    End;
  If Not FindFile Then
    Begin
    OpenBible := bibErrNotFound;
    Exit;
    End;
  If Not InitSql Then
    Begin
    OpenBible := bibErrUnsupported;       {SQLite library not available}
    Exit;
    End;
  If sqlite3_open_v2(PChar(FileName), @Db, SQLITE_OPEN_READONLY, Nil) <> SQLITE_OK Then
    Begin
    If Db <> Nil Then sqlite3_close(Db);
    Db := Nil;
    OpenBible := bibErrIO;
    Exit;
    End;
  DName := ''; DTitle := ''; DDesc := ''; DComments := ''; DVersion := ''; DLang := '';
  If Not LoadDetails Then
    Begin
    sqlite3_close(Db); Db := Nil;
    OpenBible := bibErrUnsupported;       {no Details table, or encrypted}
    Exit;
    End;
  Ok := LoadBible;
  sqlite3_close(Db); Db := Nil;
  If Not Ok Then
    Begin
    FreeTexts;
    OpenBible := bibErrBadConf;           {no Bible table}
    Exit;
    End;
  If DName = '' Then DName := ChangeFileExt(ChangeFileExt(ExtractFileName(FileName), ''), '');
  DOT := False; DNT := False;
  For L := 1 To BibTotalVerses Do
    If Texts^[L] <> '' Then
      Begin
      If L <= 23145 Then DOT := True Else DNT := True;   {Malachi 4:6 is verse 23145}
      End;
  VSys := vsKJV;
  UseApoc := False;
  Opened := True;
  SeekFirst;
  OpenBible := bibOk;
  End;

Function MySwordBibObj.CloseBible: Word;
  Begin
  If WMode Then
    Begin
    CloseBible := FlushBible;
    Exit;
    End;
  FreeTexts;
  Opened := False;
  CloseBible := bibOk;
  End;

Function MySwordBibObj.GetName: String;
  Begin
  If WMode Then GetName := AbsBibObj.GetName Else GetName := DName;
  End;

Function MySwordBibObj.GetDescription: String;
  Begin
  If WMode Then GetDescription := AbsBibObj.GetDescription
  Else If DTitle <> '' Then GetDescription := DTitle
  Else GetDescription := DDesc;
  End;

Function MySwordBibObj.GetAbout: BibStr;
  Begin
  If WMode Then GetAbout := AbsBibObj.GetAbout Else GetAbout := DDesc;
  End;

Function MySwordBibObj.GetLang: String;
  Begin
  If WMode Then GetLang := AbsBibObj.GetLang Else GetLang := DLang;
  End;

Function MySwordBibObj.GetVersion: String;
  Begin
  If WMode Then GetVersion := AbsBibObj.GetVersion Else GetVersion := DVersion;
  End;

Function MySwordBibObj.GetCopyright: String;
  Begin
  If WMode Then GetCopyright := AbsBibObj.GetCopyright Else GetCopyright := DComments;
  End;

Function MySwordBibObj.GetMarkup: BibMarkup;
  Begin
  GetMarkup := bmMySword;
  End;

Function MySwordBibObj.HasOT: Boolean;
  Begin
  If WMode Then HasOT := WSawOT Else HasOT := DOT;
  End;

Function MySwordBibObj.HasNT: Boolean;
  Begin
  If WMode Then HasNT := WSawNT Else HasNT := DNT;
  End;

Function MySwordBibObj.HasStrongs: Boolean;
  Begin
  If WMode Then HasStrongs := WSawStrong Else HasStrongs := DStrong;
  End;

Function MySwordBibObj.GetSkippedRows: LongInt;
  Begin
  GetSkippedRows := Skipped;
  End;

Function MySwordBibObj.GetRawVerse: BibStr;
  Var L: LongInt;
  Begin
  GetRawVerse := '';
  If (Not Opened) Or (Not Found) Then Exit;
  L := VrsLinear(vsKJV, GetBook, GetChapter, GetVerse);
  If L > 0 Then GetRawVerse := Texts^[L];
  End;

Function MySwordBibObj.GetIntro(Level, Book, Chap: Word): BibStr;
  Var L: LongInt;
  Begin
  GetIntro := '';
  If (Not Opened) Or (Level <> bilChapter) Then Exit;
  L := VrsLinear(vsKJV, Book, Chap, 1);          {a chapter intro is stored with the chapter's first verse}
  If L > 0 Then GetIntro := Intros^[L];
  End;


{---------------------------------------------------------------- writing}

Function MySwordBibObj.IsWriting: Boolean;
  Begin
  IsWriting := WMode;
  End;

Function MySwordBibObj.IsReadOnly: Boolean;
  Begin
  IsReadOnly := Not WMode;
  End;

Function MySwordBibObj.CreateBible(Name: String): Word;
  Var
    i: Word;
    Dir: BibStr;
  Begin
  If Opened Or WMode Then CloseBible;
  CreateBible := bibErrCreate;
  If Name = '' Then Exit;
  For i := 1 To Length(Name) Do
    If Not (Name[i] In ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', ' ']) Then Exit;
  If Not InitSql Then
    Begin
    CreateBible := bibErrUnsupported;
    Exit;
    End;
  If (LowerCase(ExtractFileExt(PathSpec)) = '.mybible') Then FileName := PathSpec
  Else
    Begin
    Dir := PathSpec;
    If Dir = '' Then Dir := '.';
    If Dir[Length(Dir)] <> '/' Then Dir := Dir + '/';
    If Not ForceDirectories(Dir) Then Exit;
    FileName := Dir + Name + '.bbl.mybible';
    End;
  MetaName := Name;
  If FileExists(FileName) Then
    Begin
    If Not Overwrite Then
      Begin
      CreateBible := bibErrExists;
      Exit;
      End;
    DeleteFile(FileName);
    End;
  VSys := vsKJV;
  UseApoc := False;
  If sqlite3_open(PChar(FileName), @Db) <> SQLITE_OK Then
    Begin
    If Db <> Nil Then sqlite3_close(Db);
    Db := Nil;
    Exit;
    End;
  If Not (ExecSql(Db, 'CREATE TABLE Details (Title NVARCHAR(255), Description TEXT, Abbreviation NVARCHAR(50), ' +
        'Comments TEXT, Version TEXT, VersionDate DATETIME, PublishDate DATETIME, Publisher TEXT, Author TEXT, ' +
        'Creator TEXT, Source TEXT, EditorialComments TEXT, Language NVARCHAR(3), RightToLeft BOOL, OT BOOL, ' +
        'NT BOOL, Strong BOOL, VerseRules TEXT)') And
      ExecSql(Db, 'CREATE TABLE Bible (Book INT, Chapter INT, Verse INT, Scripture TEXT)') And
      ExecSql(Db, 'CREATE UNIQUE INDEX bible_key ON Bible (Book ASC, Chapter ASC, Verse ASC)') And
      ExecSql(Db, 'BEGIN')) Then
    Begin
    sqlite3_close(Db); Db := Nil;
    Exit;
    End;
  If sqlite3_prepare_v2(Db, 'INSERT OR REPLACE INTO Bible (Book, Chapter, Verse, Scripture) VALUES (?, ?, ?, ?)',
       -1, @WStmt, Nil) <> SQLITE_OK Then
    Begin
    sqlite3_close(Db); Db := Nil;
    Exit;
    End;
  WSawOT := False; WSawNT := False; WSawStrong := False;
  WMode := True;
  CreateBible := bibOk;
  End;

Function MySwordBibObj.PutVerse(Book, Chap, Verse: Word; Const Txt: BibStr): Boolean;
  Begin
  PutVerse := False;
  If Not WMode Then Exit;
  If Verse = 0 Then
    Begin
    If (Book < 1) Or (Book > BibBooks) Or (Chap < 1) Or (Chap > GetChapterCount(Book)) Then Exit;
    End
  Else If Not ValidRef(Book, Chap, Verse) Then Exit;
  If Txt = '' Then
    Begin
    PutVerse := True;              {nothing to store}
    Exit;
    End;
  sqlite3_bind_int(WStmt, 1, Book);
  sqlite3_bind_int(WStmt, 2, Chap);
  sqlite3_bind_int(WStmt, 3, Verse);
  BindText(WStmt, 4, Txt);
  PutVerse := sqlite3_step(WStmt) = SQLITE_DONE;
  sqlite3_reset(WStmt);
  If Verse > 0 Then
    Begin
    If Book <= BibOTBooks Then WSawOT := True Else WSawNT := True;
    End;
  If (Pos('<WG', Txt) > 0) Or (Pos('<WH', Txt) > 0) Then WSawStrong := True;
  End;

Function MySwordBibObj.PutIntro(Level, Book, Chap: Word; Const Txt: BibStr): Boolean;
  Begin
  If Level = bilChapter Then PutIntro := PutVerse(Book, Chap, 0, Txt)
  Else PutIntro := False;          {MySword has no module / testament / book introductions}
  End;

Function MySwordBibObj.FlushBible: Word;
  Var
    St: psqlite3_stmt;
    Ok: Boolean;
    Title: BibStr;
  Begin
  FlushBible := bibOk;
  If Not WMode Then Exit;
  Ok := True;
  sqlite3_finalize(WStmt);
  WStmt := Nil;
  Title := MetaDesc;
  If Title = '' Then Title := MetaName;
  If sqlite3_prepare_v2(Db, 'INSERT INTO Details (Title, Description, Abbreviation, Comments, Version, Language, ' +
       'RightToLeft, OT, NT, Strong, VerseRules) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)', -1, @St, Nil) = SQLITE_OK Then
    Begin
    BindText(St, 1, Title);
    BindText(St, 2, MetaAbout);
    BindText(St, 3, MetaName);
    BindText(St, 4, MetaCopy);
    BindText(St, 5, MetaVer);
    BindText(St, 6, MetaLang);
    sqlite3_bind_int(St, 7, Ord(WSawOT));
    sqlite3_bind_int(St, 8, Ord(WSawNT));
    sqlite3_bind_int(St, 9, Ord(WSawStrong));
    BindText(St, 10, '');
    If sqlite3_step(St) <> SQLITE_DONE Then Ok := False;
    sqlite3_finalize(St);
    End
  Else Ok := False;
  If Not ExecSql(Db, 'COMMIT') Then Ok := False;
  sqlite3_close(Db);
  Db := Nil;
  WMode := False;
  If Not Ok Then FlushBible := bibErrIO;
  End;


End.
