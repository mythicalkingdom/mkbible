Unit MKComTwd;       {theWord commentary object (.cmt.twm, SQLite)}

{$I MKBib.Def}

{
  MKComTwd - descendant of AbsComObj for theWord commentary modules (.cmt.twm), such as the Treasury of
  Scripture Knowledge and F. B. Hole's Commentary.  The module is an SQLite file with
      bible_refs (topic_id, bi, ci, fvi, tvi, content_type)    the entries, in topic_id order
      content    (topic_id, data, data2)                       the text, RTF with tw:// hyperlinks
      config     (name, value)                                 title, abbrev, lang, version.major ...
  bi is the book 1..66 (standard order, matching this project's KJV versification); ci/fvi/tvi give the
  entry's range: ci = 0 means the whole book; fvi = tvi = 0 (ci > 0) means the whole chapter; otherwise
  fvi..tvi are verses within chapter ci.  There is no stored title (GetEntryTitle returns '').

  Mapping, markup detection and the locked-module check are as in MKDicTwd (same config keys, same RTF
  with tw:// hyperlinks the translator turns into Bible references).

  Writing   SetBibPath(directory | file), CreateBible(Name) makes <dir>/<Name>.cmt.twm, PutEntry (whole
            book / whole chapter / a verse range, all within one chapter - PutEntry fails for a range
            that spans chapters, which this schema cannot hold), CloseBible.  No module written here has
            been opened in theWord itself.
}

Interface

Uses MKBibMod, MKBibAbs, MKBibCom, sqlite3dyn;

Type
  TheWordComStrArr = Array[0..0] Of BibStr;
  PTheWordComStrArr = ^TheWordComStrArr;
  TheWordComRefArr = Array[0..0] Of BibRef;
  PTheWordComRefArr = ^TheWordComRefArr;

Type
  TheWordComObj = Object(AbsComObj)
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

  Function  GetEntryCount: LongInt; Virtual;
  Procedure GetEntryRange(Idx: LongInt; Var FromRef, ToRef: BibRef); Virtual;
  Function  GetEntryTitle(Idx: LongInt): BibStr; Virtual;
  Function  GetEntryAt(Idx: LongInt): BibStr; Virtual;
  Function  PutEntry(Const FromRef, ToRef: BibRef; Const Title, Txt: BibStr): Boolean; Virtual;

  Public
  PathSpec, FileName: BibStr;
  Opened, WMode: Boolean;
  Cfg: BibStr;
  Mk: BibMarkup;
  EFrom, ETo: PTheWordComRefArr;    {entries 1..EntCount}
  EText: PTheWordComStrArr;
  EntCount, EntCap: LongInt;
  End;

Type TheWordComPtr = ^TheWordComObj;

Implementation

Uses SysUtils, MKBibSql, MKBibMkp;

Constructor TheWordComObj.Init;
  Begin
  AbsComObj.Init;
  PathSpec := ''; FileName := '';
  Opened := False; WMode := False;
  Cfg := '';
  Mk := bmRTF;
  MetaMarkup := bmRTF;
  EFrom := Nil; ETo := Nil; EText := Nil;
  EntCount := 0; EntCap := 0;
  End;

Destructor TheWordComObj.Done;
  Begin
  If Opened Or WMode Then CloseBible;
  AbsComObj.Done;
  End;

Procedure TheWordComObj.SetBibPath(BP: String);
  Begin
  If Opened Or WMode Then CloseBible;
  PathSpec := BP;
  End;

Function TheWordComObj.BibleExists: Boolean;
  Begin
  BibleExists := Opened Or ((PathSpec <> '') And FileExists(PathSpec));
  End;

Function TheWordComObj.IsOpen: Boolean;
  Begin
  IsOpen := Opened;
  End;

Function TheWordComObj.GetConfig(Key: String): BibStr;
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

{ make room for N entries; the arrays move by raw copy (BibRef has no managed fields; the string
  array is zeroed first, so the old block is freed without releasing the strings it held) }
Procedure GrowComTo(Var FromArr, ToArr: PTheWordComRefArr; Var TextArr: PTheWordComStrArr;
                     Var Cap: LongInt; Count, N: LongInt);
  Var
    NewCap: LongInt;
    NF, NO: PTheWordComRefArr;
    NT: PTheWordComStrArr;
  Begin
  If N <= Cap Then Exit;
  NewCap := Cap * 2;
  If NewCap < N Then NewCap := N;
  If NewCap < 256 Then NewCap := 256;
  GetMem(NF, (NewCap + 1) * SizeOf(BibRef));
  FillChar(NF^, (NewCap + 1) * SizeOf(BibRef), 0);
  GetMem(NO, (NewCap + 1) * SizeOf(BibRef));
  FillChar(NO^, (NewCap + 1) * SizeOf(BibRef), 0);
  GetMem(NT, (NewCap + 1) * SizeOf(BibStr));
  FillChar(NT^, (NewCap + 1) * SizeOf(BibStr), 0);
  If FromArr <> Nil Then
    Begin
    Move(FromArr^, NF^, (Count + 1) * SizeOf(BibRef));
    Move(ToArr^, NO^, (Count + 1) * SizeOf(BibRef));
    Move(TextArr^, NT^, (Count + 1) * SizeOf(BibStr));
    FreeMem(FromArr);
    FreeMem(ToArr);
    FreeMem(TextArr);
    End;
  FromArr := NF; ToArr := NO; TextArr := NT;
  Cap := NewCap;
  End;

Procedure ClearComEntries(Var FromArr, ToArr: PTheWordComRefArr; Var TextArr: PTheWordComStrArr;
                           Var Count, Cap: LongInt);
  Var i: LongInt;
  Begin
  If TextArr <> Nil Then
    Begin
    For i := 1 To Count Do TextArr^[i] := '';
    FreeMem(TextArr);
    TextArr := Nil;
    End;
  If FromArr <> Nil Then FreeMem(FromArr);
  If ToArr <> Nil Then FreeMem(ToArr);
  FromArr := Nil; ToArr := Nil;
  Count := 0; Cap := 0;
  End;

Function TheWordComObj.OpenBible: Word;
  Var
    Db: psqlite3;
    St: psqlite3_stmt;
    Blobs, Total: LongInt;
    Txt, N, V, Sample, CT: BibStr;
    Bi, Ci, Fvi, Tvi: LongInt;
    FR, TR: BibRef;
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
  ClearComEntries(EFrom, ETo, EText, EntCount, EntCap);
  If sqlite3_prepare_v2(Db, 'SELECT b.bi, b.ci, b.fvi, b.tvi, c.data FROM bible_refs b ' +
       'JOIN content c ON c.topic_id = b.topic_id ORDER BY b.topic_id', -1, @St, Nil) <> SQLITE_OK Then
    Begin
    sqlite3_close(Db);
    OpenBible := bibErrBadConf;
    Exit;
    End;
  Blobs := 0; Total := 0; Sample := '';
  While sqlite3_step(St) = SQLITE_ROW Do
    Begin
    Inc(Total);
    Bi := sqlite3_column_int(St, 0);
    Ci := sqlite3_column_int(St, 1);
    Fvi := sqlite3_column_int(St, 2);
    Tvi := sqlite3_column_int(St, 3);
    If SqlColIsBlob(St, 4) Then
      Begin
      Txt := SqlColBlobText(St, 4);               {a "compressed" module: zlib, not encrypted}
      If Txt = '' Then Inc(Blobs);
      End
    Else Txt := SqlColText(St, 4);
    If (Sample = '') And (Txt <> '') Then Sample := Copy(Txt, 1, 400);
    If (Bi < 1) Or (Bi > GetBookCount) Then Continue;      {a malformed reference: skip it}
    If Ci = 0 Then
      Begin                                                {the whole book}
      FR.Book := Bi; FR.Chapter := 1; FR.Verse := 1;
      TR.Book := Bi; TR.Chapter := GetChapterCount(Bi); TR.Verse := GetVerseCount(Bi, TR.Chapter);
      End
    Else If (Fvi = 0) And (Tvi = 0) Then
      Begin                                                {the whole chapter}
      FR.Book := Bi; FR.Chapter := Ci; FR.Verse := 1;
      TR.Book := Bi; TR.Chapter := Ci; TR.Verse := GetVerseCount(Bi, Ci);
      End
    Else
      Begin
      FR.Book := Bi; FR.Chapter := Ci; FR.Verse := Fvi;
      TR.Book := Bi; TR.Chapter := Ci; TR.Verse := Tvi;
      End;
    GrowComTo(EFrom, ETo, EText, EntCap, EntCount, EntCount + 1);
    Inc(EntCount);
    EFrom^[EntCount] := FR;
    ETo^[EntCount] := TR;
    EText^[EntCount] := Txt;
    End;
  sqlite3_finalize(St);
  sqlite3_close(Db);
  If (Total > 0) And (Blobs = Total) Then
    Begin
    ClearComEntries(EFrom, ETo, EText, EntCount, EntCap);
    OpenBible := bibErrLocked;                    {encrypted / compressed module}
    Exit;
    End;
  CT := LowerCase(GetConfig('content.type'));
  If CT = 'rtf' Then Mk := bmRTF
  Else If CT = 'html' Then Mk := bmHTML
  Else If (Pos('\par', Sample) > 0) Or (Pos('{\', Sample) > 0) Or (Pos('\b', Sample) > 0) Then Mk := bmRTF
  Else If (Pos('<p', Sample) > 0) Or (Pos('<b>', Sample) > 0) Or (Pos('<br', Sample) > 0) Then Mk := bmHTML
  Else If Sample = '' Then Mk := bmRTF
  Else Mk := bmPlain;
  MetaMarkup := Mk;
  Opened := True;
  SetRef(1, 1, 1);
  OpenBible := bibOk;
  End;

Function TheWordComObj.CloseBible: Word;
  Begin
  If WMode Then
    Begin
    CloseBible := FlushBible;
    Exit;
    End;
  ClearComEntries(EFrom, ETo, EText, EntCount, EntCap);
  Cfg := '';
  Opened := False;
  CloseBible := bibOk;
  End;

Function TheWordComObj.GetName: String;
  Begin
  If WMode Then GetName := AbsModObj.GetName
  Else If GetConfig('abbrev') <> '' Then GetName := GetConfig('abbrev')
  Else GetName := ChangeFileExt(ChangeFileExt(ExtractFileName(FileName), ''), '');
  End;

Function TheWordComObj.GetDescription: String;
  Begin
  If WMode Then GetDescription := AbsModObj.GetDescription
  Else If GetConfig('title') <> '' Then GetDescription := GetConfig('title')
  Else GetDescription := GetConfig('description');
  End;

Function TheWordComObj.GetAbout: BibStr;
  Var A: BibStr;
  Begin
  If WMode Then
    Begin
    GetAbout := AbsModObj.GetAbout;
    Exit;
    End;
  A := GetConfig('about');
  If A = '' Then A := GetConfig('description');
  If Pos('{\', A) > 0 Then A := MkpTranslate(A, mfSTEP, mfPlain, [moBreaks]);
  GetAbout := A;
  End;

Function TheWordComObj.GetLang: String;
  Begin
  If WMode Then GetLang := AbsModObj.GetLang Else GetLang := GetConfig('lang');
  End;

Function TheWordComObj.GetVersion: String;
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

Function TheWordComObj.GetCopyright: String;
  Begin
  If WMode Then GetCopyright := AbsModObj.GetCopyright
  Else If GetConfig('copyright') <> '' Then GetCopyright := GetConfig('copyright')
  Else If GetConfig('creator') <> '' Then GetCopyright := GetConfig('creator')
  Else GetCopyright := GetConfig('author');
  End;

Function TheWordComObj.GetMarkup: BibMarkup;
  Begin
  If WMode Then GetMarkup := MetaMarkup Else GetMarkup := Mk;
  End;

Function TheWordComObj.GetEntryCount: LongInt;
  Begin
  GetEntryCount := EntCount;
  End;

Procedure TheWordComObj.GetEntryRange(Idx: LongInt; Var FromRef, ToRef: BibRef);
  Begin
  If (Idx < 1) Or (Idx > EntCount) Then
    Begin
    FillChar(FromRef, SizeOf(FromRef), 0);
    FillChar(ToRef, SizeOf(ToRef), 0);
    Exit;
    End;
  FromRef := EFrom^[Idx];
  ToRef := ETo^[Idx];
  End;

Function TheWordComObj.GetEntryTitle(Idx: LongInt): BibStr;
  Begin
  GetEntryTitle := '';                 {not stored by this format}
  End;

Function TheWordComObj.GetEntryAt(Idx: LongInt): BibStr;
  Begin
  If (Idx < 1) Or (Idx > EntCount) Then GetEntryAt := ''
  Else GetEntryAt := EText^[Idx];
  End;


{---------------------------------------------------------------- writing}

Function TheWordComObj.IsWriting: Boolean;
  Begin
  IsWriting := WMode;
  End;

Function TheWordComObj.IsReadOnly: Boolean;
  Begin
  IsReadOnly := Not WMode;
  End;

Function TheWordComObj.CreateBible(Name: String): Word;
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
  If Pos('.cmt.twm', LowerCase(PathSpec)) > 0 Then FileName := PathSpec
  Else
    Begin
    Dir := PathSpec;
    If Dir = '' Then Dir := '.';
    If Dir[Length(Dir)] <> '/' Then Dir := Dir + '/';
    If Not ForceDirectories(Dir) Then Exit;
    FileName := Dir + Name + '.cmt.twm';
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
  ClearComEntries(EFrom, ETo, EText, EntCount, EntCap);
  WMode := True;
  CreateBible := bibOk;
  End;

Function TheWordComObj.PutEntry(Const FromRef, ToRef: BibRef; Const Title, Txt: BibStr): Boolean;
  Begin
  PutEntry := False;
  If Not WMode Then Exit;
  If (FromRef.Book < 1) Or (FromRef.Book > GetBookCount) Then Exit;
  If FromRef.Book <> ToRef.Book Then Exit;                 {this schema keeps one book per entry}
  If (FromRef.Chapter <> ToRef.Chapter) And
     Not ((FromRef.Chapter = 1) And (FromRef.Verse = 1) And
          (ToRef.Chapter = GetChapterCount(FromRef.Book)) And
          (ToRef.Verse = GetVerseCount(FromRef.Book, ToRef.Chapter))) Then
    Exit;                                                  {a range spanning chapters: not "whole book" either}
  GrowComTo(EFrom, ETo, EText, EntCap, EntCount, EntCount + 1);
  Inc(EntCount);
  EFrom^[EntCount] := FromRef;
  ETo^[EntCount] := ToRef;
  EText^[EntCount] := Txt;
  PutEntry := True;
  End;

Function TheWordComObj.FlushBible: Word;
  Var
    Db: psqlite3;
    StR, StC, StCfg: psqlite3_stmt;
    i, P, Bi, Ci, Fvi, Tvi: LongInt;
    Ok: Boolean;
    V, Ma, Mi, T: BibStr;
    FR, TR: BibRef;

  Procedure Cfg_(Const K, Val_: BibStr);
    Begin
    If (Val_ = '') Or (StCfg = Nil) Then Exit;
    SqlBindText(StCfg, 1, K);
    SqlBindText(StCfg, 2, Val_);
    sqlite3_step(StCfg);
    sqlite3_reset(StCfg);
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
    ClearComEntries(EFrom, ETo, EText, EntCount, EntCap);
    FlushBible := bibErrIO;
    Exit;
    End;
  If Not (SqlExec(Db, 'CREATE TABLE content(topic_id integer primary key, data BLOB, data2 blob)') And
          SqlExec(Db, 'CREATE TABLE config(name text, value text)') And
          SqlExec(Db, 'CREATE TABLE bible_refs(topic_id integer primary key AUTOINCREMENT, bi integer, ' +
                      'ci integer, fvi integer, tvi integer, content_type text)') And
          SqlExec(Db, 'BEGIN')) Then Ok := False;
  If Ok Then
    Begin
    StR := Nil; StC := Nil;
    If sqlite3_prepare_v2(Db, 'INSERT INTO bible_refs (topic_id, bi, ci, fvi, tvi) VALUES (?, ?, ?, ?, ?)',
         -1, @StR, Nil) <> SQLITE_OK Then Ok := False;
    If Ok And (sqlite3_prepare_v2(Db, 'INSERT INTO content (topic_id, data) VALUES (?, ?)', -1, @StC, Nil)
         <> SQLITE_OK) Then Ok := False;
    If Ok Then
      For i := 1 To EntCount Do
        Begin
        FR := EFrom^[i]; TR := ETo^[i];
        Bi := FR.Book;
        If (FR.Chapter = 1) And (FR.Verse = 1) And (TR.Chapter = GetChapterCount(Bi)) And
           (TR.Verse = GetVerseCount(Bi, TR.Chapter)) Then
          Begin Ci := 0; Fvi := 0; Tvi := 0; End          {the whole book}
        Else If (FR.Verse = 1) And (TR.Verse = GetVerseCount(Bi, FR.Chapter)) Then
          Begin Ci := FR.Chapter; Fvi := 0; Tvi := 0; End {the whole chapter}
        Else
          Begin Ci := FR.Chapter; Fvi := FR.Verse; Tvi := TR.Verse; End;
        sqlite3_bind_int(StR, 1, i);
        sqlite3_bind_int(StR, 2, Bi);
        sqlite3_bind_int(StR, 3, Ci);
        sqlite3_bind_int(StR, 4, Fvi);
        sqlite3_bind_int(StR, 5, Tvi);
        If sqlite3_step(StR) <> SQLITE_DONE Then Ok := False;
        sqlite3_reset(StR);
        sqlite3_bind_int(StC, 1, i);
        SqlBindText(StC, 2, EText^[i]);
        If sqlite3_step(StC) <> SQLITE_DONE Then Ok := False;
        sqlite3_reset(StC);
        End;
    If StR <> Nil Then sqlite3_finalize(StR);
    If StC <> Nil Then sqlite3_finalize(StC);
    StCfg := Nil;
    If sqlite3_prepare_v2(Db, 'INSERT INTO config (name, value) VALUES (?, ?)', -1, @StCfg, Nil) = SQLITE_OK Then
      Begin
      Cfg_('type', '2');
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
      sqlite3_finalize(StCfg);
      End
    Else Ok := False;
    If Not SqlExec(Db, 'COMMIT') Then Ok := False;
    End;
  sqlite3_close(Db);
  ClearComEntries(EFrom, ETo, EText, EntCount, EntCap);
  WMode := False;
  If Not Ok Then FlushBible := bibErrIO;
  End;

End.
