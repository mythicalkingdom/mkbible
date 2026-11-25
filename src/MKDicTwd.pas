Unit MKDicTwd;       {theWord dictionary object (.dct.twm, SQLite)}

{$I MKBib.Def}

{
  MKDicTwd - descendant of AbsDictObj for theWord dictionary modules (.dct.twm), such as Nave's Topical
  Bible, Torrey's and Easton.  The module is an SQLite file with
      topics   (id, pid, subject, rel_order, content_type)      the entries; subject is the key
      content  (topic_id, data, data2)                          the text, RTF with tw:// hyperlinks
      config   (name, value)                                    title, abbrev, lang, version.major ...
  Entries are kept in rel_order.  The text is RTF (reported as bmRTF; the translator reads it, turning
  tw://bible hyperlinks into Bible references).  Topics with a parent (pid > 0) are listed like the others.

  Mapping:  GetName = config abbrev   GetDescription = title   GetAbout = about (RTF as plain text)
            GetCopyright = creator / author   GetVersion = version.major.version.minor   GetLang = lang

  A module that stores its text as a zlib-compressed blob (config "compressed") is read like any other.
  A genuinely encrypted module (config do.encrypt / secure, e.g. Mickelson's Strong in theWord's Books
  folder: the blob is not a zlib stream) is refused with bibErrLocked.

  Writing   SetBibPath(directory | file), CreateBible(Name) makes <dir>/<Name>.dct.twm, PutEntry (RTF
            fragments, or text in a markup the translator reads: dictconv translates), CloseBible.
            The tables follow those of the sample modules; the word index tables are left empty.  No
            module written here has been opened in theWord itself.
}

Interface

Uses MKBibMod, MKBibDic, sqlite3dyn;

Type
  TheWordDictObj = Object(AbsDictObj)
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
  Function  GetConfig(Key: String): BibStr;

  Public
  PathSpec, FileName: BibStr;
  Opened, WMode: Boolean;
  Cfg: BibStr;                       {name=value lines of the config table}
  Mk: BibMarkup;
  End;

Type TheWordDictPtr = ^TheWordDictObj;

Implementation

Uses SysUtils, MKBibSql, MKBibMkp;

Constructor TheWordDictObj.Init;
  Begin
  AbsDictObj.Init;
  PathSpec := ''; FileName := '';
  Opened := False; WMode := False;
  Cfg := '';
  Mk := bmRTF;
  MetaMarkup := bmRTF;
  End;

Destructor TheWordDictObj.Done;
  Begin
  If Opened Or WMode Then CloseBible;
  AbsDictObj.Done;
  End;

Procedure TheWordDictObj.SetBibPath(BP: String);
  Begin
  If Opened Or WMode Then CloseBible;
  PathSpec := BP;
  End;

Function TheWordDictObj.BibleExists: Boolean;
  Begin
  BibleExists := Opened Or ((PathSpec <> '') And FileExists(PathSpec));
  End;

Function TheWordDictObj.IsOpen: Boolean;
  Begin
  IsOpen := Opened;
  End;

Function TheWordDictObj.GetConfig(Key: String): BibStr;
  Var
    P, E: LongInt;
    S, K: BibStr;
  Begin
  GetConfig := '';
  S := #10 + Cfg;
  K := #10 + LowerCase(Key) + '=';
  P := Pos(K, LowerCase(S));
  If P = 0 Then Exit;
  Inc(P, Length(K));
  E := P;
  While (E <= Length(S)) And (S[E] <> #10) Do Inc(E);
  GetConfig := Copy(S, P, E - P);
  End;

Function TheWordDictObj.OpenBible: Word;
  Var
    Db: psqlite3;
    St: psqlite3_stmt;
    Blobs, Total, i: LongInt;
    Txt, N, V, Sample, CT: BibStr;
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
  Cfg := '';
  If sqlite3_prepare_v2(Db, 'SELECT name, value FROM config', -1, @St, Nil) = SQLITE_OK Then
    Begin
    While sqlite3_step(St) = SQLITE_ROW Do
      Begin
      N := SqlColText(St, 0);
      V := SqlColText(St, 1);
      StringReplace(V, #10, ' ', [rfReplaceAll]);
      Cfg := Cfg + N + '=' + V + #10;
      End;
    sqlite3_finalize(St);
    End;
  ClearEntries;
  If sqlite3_prepare_v2(Db, 'SELECT t.subject, c.data FROM topics t LEFT JOIN content c ON c.topic_id = t.id ' +
       'ORDER BY t.rel_order, t.id', -1, @St, Nil) <> SQLITE_OK Then
    Begin
    sqlite3_close(Db);
    OpenBible := bibErrBadConf;
    Exit;
    End;
  Blobs := 0; Total := 0; Sample := '';
  While sqlite3_step(St) = SQLITE_ROW Do
    Begin
    Inc(Total);
    If SqlColIsBlob(St, 1) Then
      Begin
      Txt := SqlColBlobText(St, 1);               {a "compressed" module: zlib, not encrypted}
      If Txt = '' Then Inc(Blobs);
      End
    Else Txt := SqlColText(St, 1);
    If (Sample = '') And (Txt <> '') Then Sample := Copy(Txt, 1, 400);
    AddEntry(SqlColText(St, 0), Txt);
    End;
  sqlite3_finalize(St);
  sqlite3_close(Db);
  If (Total > 0) And (Blobs = Total) Then
    Begin
    ClearEntries;
    OpenBible := bibErrLocked;                    {encrypted / compressed module}
    Exit;
    End;
  { the markup: config content.type, else look at the text }
  CT := LowerCase(GetConfig('content.type'));
  If CT = 'rtf' Then Mk := bmRTF
  Else If CT = 'html' Then Mk := bmHTML
  Else If (Pos('\par', Sample) > 0) Or (Pos('{\', Sample) > 0) Or (Pos('\b', Sample) > 0) Then Mk := bmRTF
  Else If (Pos('<p', Sample) > 0) Or (Pos('<b>', Sample) > 0) Or (Pos('<br', Sample) > 0) Then Mk := bmHTML
  Else If Sample = '' Then Mk := bmRTF
  Else Mk := bmPlain;
  StrongsKeys := GetConfig('strong') = '1';
  StrongsPre := #0;
  For i := 1 To 0 Do;
  MetaMarkup := Mk;
  Opened := True;
  SeekFirst;
  OpenBible := bibOk;
  End;

Function TheWordDictObj.CloseBible: Word;
  Begin
  If WMode Then
    Begin
    CloseBible := FlushBible;
    Exit;
    End;
  ClearEntries;
  Cfg := '';
  Opened := False;
  CloseBible := bibOk;
  End;

Function TheWordDictObj.GetName: String;
  Begin
  If WMode Then GetName := AbsModObj.GetName
  Else If GetConfig('abbrev') <> '' Then GetName := GetConfig('abbrev')
  Else GetName := ChangeFileExt(ChangeFileExt(ExtractFileName(FileName), ''), '');
  End;

Function TheWordDictObj.GetDescription: String;
  Begin
  If WMode Then GetDescription := AbsModObj.GetDescription
  Else If GetConfig('title') <> '' Then GetDescription := GetConfig('title')
  Else GetDescription := GetConfig('description');
  End;

Function TheWordDictObj.GetAbout: BibStr;
  Var A: BibStr;
  Begin
  If WMode Then
    Begin
    GetAbout := AbsModObj.GetAbout;
    Exit;
    End;
  A := GetConfig('about');
  If A = '' Then A := GetConfig('description');
  If Pos('{\', A) > 0 Then A := MkpTranslate(A, mfSTEP, mfPlain, [moBreaks]);   {the about text is RTF}
  GetAbout := A;
  End;

Function TheWordDictObj.GetLang: String;
  Begin
  If WMode Then GetLang := AbsModObj.GetLang Else GetLang := GetConfig('lang');
  End;

Function TheWordDictObj.GetVersion: String;
  Var Ma, Mi: BibStr;
  Begin
  If WMode Then
    Begin
    GetVersion := AbsModObj.GetVersion;
    Exit;
    End;
  Ma := GetConfig('version.major');
  Mi := GetConfig('version.minor');
  If Ma = '' Then GetVersion := ''
  Else If Mi = '' Then GetVersion := Ma
  Else GetVersion := Ma + '.' + Mi;
  End;

Function TheWordDictObj.GetCopyright: String;
  Begin
  If WMode Then GetCopyright := AbsModObj.GetCopyright
  Else If GetConfig('copyright') <> '' Then GetCopyright := GetConfig('copyright')
  Else If GetConfig('creator') <> '' Then GetCopyright := GetConfig('creator')
  Else GetCopyright := GetConfig('author');
  End;

Function TheWordDictObj.GetMarkup: BibMarkup;
  Begin
  If WMode Then GetMarkup := MetaMarkup Else GetMarkup := Mk;
  End;


{---------------------------------------------------------------- writing}

Function TheWordDictObj.IsWriting: Boolean;
  Begin
  IsWriting := WMode;
  End;

Function TheWordDictObj.IsReadOnly: Boolean;
  Begin
  IsReadOnly := Not WMode;
  End;

Function TheWordDictObj.CreateBible(Name: String): Word;
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
  If Pos('.dct.twm', LowerCase(PathSpec)) > 0 Then FileName := PathSpec
  Else
    Begin
    Dir := PathSpec;
    If Dir = '' Then Dir := '.';
    If Dir[Length(Dir)] <> '/' Then Dir := Dir + '/';
    If Not ForceDirectories(Dir) Then Exit;
    FileName := Dir + Name + '.dct.twm';
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

Function TheWordDictObj.FlushBible: Word;
  Var
    Db: psqlite3;
    St: psqlite3_stmt;
    i, P: LongInt;
    Ok: Boolean;
    V, Ma, Mi, T: BibStr;

  Procedure Cfg_(Const K, Val_: BibStr);
    Begin
    If (Val_ = '') Or (St = Nil) Then Exit;
    SqlBindText(St, 1, K);
    SqlBindText(St, 2, Val_);
    sqlite3_step(St);
    sqlite3_reset(St);
    End;

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
  If Not (SqlExec(Db, 'CREATE TABLE content(topic_id integer primary key, data text, data2 blob)') And
          SqlExec(Db, 'CREATE TABLE config(name text, value text)') And
          SqlExec(Db, 'CREATE TABLE topics(id integer primary key, pid integer default 0, subject text, rel_order, content_type text)') And
          SqlExec(Db, 'CREATE INDEX idx_topics_rel_order on topics(rel_order)') And
          SqlExec(Db, 'CREATE INDEX idx_topics_subject on topics(subject)') And
          SqlExec(Db, 'CREATE TABLE topics_wordindex(id integer, word text, priority integer)') And
          SqlExec(Db, 'CREATE INDEX idx_topics_wordindex_word on topics_wordindex(word, priority)') And
          SqlExec(Db, 'BEGIN')) Then Ok := False;
  If Ok Then
    Begin
    If sqlite3_prepare_v2(Db, 'INSERT INTO topics (id, pid, subject, rel_order) VALUES (?, 0, ?, ?)', -1, @St, Nil) = SQLITE_OK Then
      Begin
      For i := 1 To KeyCount Do
        Begin
        sqlite3_bind_int(St, 1, i);
        SqlBindText(St, 2, Keys^[i]);
        sqlite3_bind_int(St, 3, i);
        If sqlite3_step(St) <> SQLITE_DONE Then Ok := False;
        sqlite3_reset(St);
        End;
      sqlite3_finalize(St);
      End
    Else Ok := False;
    If sqlite3_prepare_v2(Db, 'INSERT INTO content (topic_id, data) VALUES (?, ?)', -1, @St, Nil) = SQLITE_OK Then
      Begin
      For i := 1 To KeyCount Do
        Begin
        sqlite3_bind_int(St, 1, i);
        SqlBindText(St, 2, Texts^[i]);
        If sqlite3_step(St) <> SQLITE_DONE Then Ok := False;
        sqlite3_reset(St);
        End;
      sqlite3_finalize(St);
      End
    Else Ok := False;
    If sqlite3_prepare_v2(Db, 'INSERT INTO config (name, value) VALUES (?, ?)', -1, @St, Nil) = SQLITE_OK Then
      Begin
      Cfg_('type', '1');
      Cfg_('schema.version', '1');
      Cfg_('user', '0');
      T := MetaDesc;
      If T = '' Then T := MetaName;
      Cfg_('title', T);
      Cfg_('abbrev', MetaName);
      Cfg_('description', T);
      Cfg_('about', MetaAbout);
      Cfg_('lang', MetaLang);
      V := MetaVer;
      If V <> '' Then
        Begin
        P := Pos('.', V);
        If P = 0 Then Begin Ma := V; Mi := '0'; End
        Else Begin Ma := Copy(V, 1, P - 1); Mi := Copy(V, P + 1, Length(V)); End;
        Cfg_('version.major', Ma);
        Cfg_('version.minor', Mi);
        End;
      Cfg_('creator', MetaCopy);
      Case MetaMarkup Of
        bmHTML: Cfg_('content.type', 'html');
        bmRTF: Cfg_('content.type', 'rtf');
        End;
      If StrongsKeys Then Cfg_('strong', '1');
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
