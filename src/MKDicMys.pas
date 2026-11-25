Unit MKDicMys;       {MySword dictionary object (.dct.mybible, SQLite)}

{$I MKBib.Def}

{
  MKDicMys - descendant of AbsDictObj for MySword dictionaries.  The module is an SQLite file with
      dictionary (relativeorder INTEGER, word TEXT primary key collate nocase, data TEXT)
      details (title, abbreviation, description, comments, author, strong, version, language, ...)
  The entry text is HTML (reported as bmHTML).  Entries are kept in relativeorder.

  Mapping of the module information:
      GetName = abbreviation   GetDescription = title   GetAbout = description   GetCopyright = comments
  details.strong = 1 marks a Strong's dictionary (the keys are then matched as Strong's numbers).

  Reading   SetBibPath(file.dct.mybible), OpenBible (loads all entries)
  Writing   SetBibPath(directory | file), CreateBible(Name) makes <dir>/<Name>.dct.mybible, PutEntry...,
            CloseBible.  Text is stored as given: HTML (or plain text) for the MySword app.
  SQLite is loaded at run time (libsqlite3.so.0 or libsqlite3.so; sqlite3.dll on Windows).
}

Interface

Uses MKBibMod, MKBibDic, sqlite3dyn;

Type
  MySwordDictObj = Object(AbsDictObj)
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
  Function  CreateBible(Name: String): Word; Virtual;
  Function  FlushBible: Word; Virtual;
  Function  IsWriting: Boolean; Virtual;
  Function  IsReadOnly: Boolean; Virtual;

  Public
  PathSpec, FileName: BibStr;
  Opened, WMode: Boolean;
  DTitle, DAbbr, DDesc, DComments, DVersion, DLang: BibStr;
  End;

Type MySwordDictPtr = ^MySwordDictObj;

Implementation

Uses SysUtils, MKBibSql;

Constructor MySwordDictObj.Init;
  Begin
  AbsDictObj.Init;
  PathSpec := ''; FileName := '';
  Opened := False; WMode := False;
  DTitle := ''; DAbbr := ''; DDesc := ''; DComments := ''; DVersion := ''; DLang := '';
  MetaMarkup := bmHTML;
  End;

Destructor MySwordDictObj.Done;
  Begin
  If Opened Or WMode Then CloseBible;
  AbsDictObj.Done;
  End;

Procedure MySwordDictObj.SetBibPath(BP: String);
  Begin
  If Opened Or WMode Then CloseBible;
  PathSpec := BP;
  End;

Function MySwordDictObj.BibleExists: Boolean;
  Begin
  BibleExists := Opened Or ((PathSpec <> '') And FileExists(PathSpec));
  End;

Function MySwordDictObj.IsOpen: Boolean;
  Begin
  IsOpen := Opened;
  End;

Function MySwordDictObj.OpenBible: Word;
  Var
    Db: psqlite3;
    St: psqlite3_stmt;
    i, N: LongInt;
    Col, V: BibStr;
  Begin
  If Opened Or WMode Then CloseBible;
  If PathSpec = '' Then
    Begin
    OpenBible := bibErrNoPath;
    Exit;
    End;
  If Not FileExists(PathSpec) Then
    Begin
    OpenBible := bibErrNotFound;
    Exit;
    End;
  If Not SqlReady Then
    Begin
    OpenBible := bibErrUnsupported;
    Exit;
    End;
  FileName := PathSpec;
  Db := Nil;
  If sqlite3_open_v2(PChar(FileName), @Db, SQLITE_OPEN_READONLY, Nil) <> SQLITE_OK Then
    Begin
    If Db <> Nil Then sqlite3_close(Db);
    OpenBible := bibErrIO;
    Exit;
    End;
  DTitle := ''; DAbbr := ''; DDesc := ''; DComments := ''; DVersion := ''; DLang := '';
  StrongsKeys := False; StrongsPre := #0;
  If sqlite3_prepare_v2(Db, 'SELECT * FROM details', -1, @St, Nil) = SQLITE_OK Then
    Begin
    If sqlite3_step(St) = SQLITE_ROW Then
      Begin
      N := sqlite3_column_count(St);
      For i := 0 To N - 1 Do
        Begin
        Col := LowerCase(SqlColName(St, i));
        V := SqlColText(St, i);
        If Col = 'title' Then DTitle := V
        Else If Col = 'abbreviation' Then DAbbr := V
        Else If Col = 'description' Then DDesc := V
        Else If Col = 'comments' Then DComments := V
        Else If Col = 'version' Then DVersion := V
        Else If Col = 'language' Then DLang := V
        Else If (Col = 'strong') And (V <> '') And (V <> '0') Then StrongsKeys := True;
        End;
      End;
    sqlite3_finalize(St);
    End;
  ClearEntries;
  If sqlite3_prepare_v2(Db, 'SELECT word, data FROM dictionary ORDER BY relativeorder', -1, @St, Nil) <> SQLITE_OK Then
    Begin
    sqlite3_close(Db);
    OpenBible := bibErrBadConf;
    Exit;
    End;
  While sqlite3_step(St) = SQLITE_ROW Do
    AddEntry(SqlColText(St, 0), SqlColText(St, 1));
  sqlite3_finalize(St);
  sqlite3_close(Db);
  Opened := True;
  SeekFirst;
  OpenBible := bibOk;
  End;

Function MySwordDictObj.CloseBible: Word;
  Begin
  If WMode Then
    Begin
    CloseBible := FlushBible;
    Exit;
    End;
  ClearEntries;
  Opened := False;
  CloseBible := bibOk;
  End;

Function MySwordDictObj.GetName: String;
  Begin
  If WMode Then GetName := AbsModObj.GetName
  Else If DAbbr <> '' Then GetName := DAbbr
  Else GetName := ChangeFileExt(ChangeFileExt(ExtractFileName(FileName), ''), '');
  End;

Function MySwordDictObj.GetDescription: String;
  Begin
  If WMode Then GetDescription := AbsModObj.GetDescription Else GetDescription := DTitle;
  End;

Function MySwordDictObj.GetAbout: BibStr;
  Begin
  If WMode Then GetAbout := AbsModObj.GetAbout Else GetAbout := DDesc;
  End;

Function MySwordDictObj.GetLang: String;
  Begin
  If WMode Then GetLang := AbsModObj.GetLang Else GetLang := DLang;
  End;

Function MySwordDictObj.GetVersion: String;
  Begin
  If WMode Then GetVersion := AbsModObj.GetVersion Else GetVersion := DVersion;
  End;

Function MySwordDictObj.GetCopyright: String;
  Begin
  If WMode Then GetCopyright := AbsModObj.GetCopyright Else GetCopyright := DComments;
  End;

Function MySwordDictObj.GetMarkup: BibMarkup;
  Begin
  If WMode Then GetMarkup := MetaMarkup Else GetMarkup := bmHTML;
  End;


{---------------------------------------------------------------- writing}

Function MySwordDictObj.IsWriting: Boolean;
  Begin
  IsWriting := WMode;
  End;

Function MySwordDictObj.IsReadOnly: Boolean;
  Begin
  IsReadOnly := Not WMode;
  End;

Function MySwordDictObj.CreateBible(Name: String): Word;
  Var
    i: Word;
    Dir: BibStr;
  Begin
  If Opened Or WMode Then CloseBible;
  CreateBible := bibErrCreate;
  If Name = '' Then Exit;
  For i := 1 To Length(Name) Do
    If Not (Name[i] In ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', ' ']) Then Exit;
  If Not SqlReady Then
    Begin
    CreateBible := bibErrUnsupported;
    Exit;
    End;
  If Pos('.dct.mybible', LowerCase(PathSpec)) > 0 Then FileName := PathSpec
  Else
    Begin
    Dir := PathSpec;
    If Dir = '' Then Dir := '.';
    If Dir[Length(Dir)] <> '/' Then Dir := Dir + '/';
    If Not ForceDirectories(Dir) Then Exit;
    FileName := Dir + Name + '.dct.mybible';
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
  ClearEntries;
  WMode := True;
  CreateBible := bibOk;
  End;

Function MySwordDictObj.FlushBible: Word;
  Var
    Db: psqlite3;
    St: psqlite3_stmt;
    i: LongInt;
    Ok: Boolean;
    Title: BibStr;
  Begin
  FlushBible := bibOk;
  If Not WMode Then Exit;
  Ok := True;
  Db := Nil;
  If sqlite3_open(PChar(FileName), @Db) <> SQLITE_OK Then
    Begin
    If Db <> Nil Then sqlite3_close(Db);
    WMode := False;
    ClearEntries;
    FlushBible := bibErrIO;
    Exit;
    End;
  If Not (SqlExec(Db, 'CREATE TABLE dictionary(relativeorder INTEGER, word TEXT primary key collate nocase, data TEXT)') And
          SqlExec(Db, 'CREATE INDEX dictionary_relativeorder on dictionary(relativeorder asc)') And
          SqlExec(Db, 'CREATE TABLE details(title TEXT, abbreviation TEXT, description TEXT, comments TEXT, author TEXT, ' +
                      'strong INTEGER, version TEXT, versiondate DATETIME, publishdate TEXT, publisher TEXT, creator TEXT, ' +
                      'source TEXT, language NVARCHAR(3), editorialcomments TEXT, righttoleft INT default 0, customcss TEXT)') And
          SqlExec(Db, 'BEGIN')) Then Ok := False;
  If Ok Then
    Begin
    If sqlite3_prepare_v2(Db, 'INSERT OR REPLACE INTO dictionary (relativeorder, word, data) VALUES (?, ?, ?)',
         -1, @St, Nil) = SQLITE_OK Then
      Begin
      For i := 1 To KeyCount Do
        Begin
        sqlite3_bind_int(St, 1, i);
        SqlBindText(St, 2, Keys^[i]);
        SqlBindText(St, 3, Texts^[i]);
        If sqlite3_step(St) <> SQLITE_DONE Then Ok := False;
        sqlite3_reset(St);
        End;
      sqlite3_finalize(St);
      End
    Else Ok := False;
    Title := MetaDesc;
    If Title = '' Then Title := MetaName;
    If sqlite3_prepare_v2(Db, 'INSERT INTO details (title, abbreviation, description, comments, strong, version, language) ' +
         'VALUES (?, ?, ?, ?, ?, ?, ?)', -1, @St, Nil) = SQLITE_OK Then
      Begin
      SqlBindText(St, 1, Title);
      SqlBindText(St, 2, MetaName);
      SqlBindText(St, 3, MetaAbout);
      SqlBindText(St, 4, MetaCopy);
      sqlite3_bind_int(St, 5, Ord(StrongsKeys));
      SqlBindText(St, 6, MetaVer);
      SqlBindText(St, 7, MetaLang);
      If sqlite3_step(St) <> SQLITE_DONE Then Ok := False;
      sqlite3_finalize(St);
      End
    Else Ok := False;
    If Not SqlExec(Db, 'COMMIT') Then Ok := False;
    End;
  sqlite3_close(Db);
  ClearEntries;
  WMode := False;
  If Not Ok Then FlushBible := bibErrIO;
  End;

End.
