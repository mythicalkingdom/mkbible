Unit MKBokTwd;       {theWord general book object (.gbk.twm, SQLite)}

{$I MKBib.Def}

{
  MKBokTwd - descendant of AbsBookObj for theWord general book modules (.gbk.twm), such as Bunyan's
  Pilgrim's Progress and Spurgeon's All of Grace.  The module is an SQLite file with
      topics            (id, pid, subject, rel_order, content_type)   the sections; subject is the title
      content           (topic_id, data, data2)                      the text, RTF with tw:// hyperlinks
      config            (name, value)                                 title, abbrev, lang, version.major ...
      topics_wordindex  (id, word, priority)                          a search index (not used here)
  This is the same table layout as a theWord dictionary (MKDicTwd), but topics keep their tree: pid = 0
  for a top level section, else the id of the parent section.  Sections are mapped to our own nodes
  1..GetNodeCount in rel_order (a single, book-wide sequence; theWord keeps a parent's rel_order before
  its children's); node 0 is the AbsBookObj root, and theWord's own top level sections become its
  children.  Markup detection and the locked-module check are as in MKDicTwd.

  Writing   SetBibPath(directory | file), CreateBible(Name) makes <dir>/<Name>.gbk.twm, AddNode (RTF
            fragments, or text in a markup the translator reads), CloseBible.  topics_wordindex is left
            empty.  No module written here has been opened in theWord itself.
}

Interface

Uses MKBibMod, MKBibBok, sqlite3dyn;

Type
  TheWordBokStrArr = Array[0..0] Of BibStr;
  PTheWordBokStrArr = ^TheWordBokStrArr;
  TheWordBokIntArr = Array[0..0] Of LongInt;
  PTheWordBokIntArr = ^TheWordBokIntArr;

Type
  TheWordBookObj = Object(AbsBookObj)
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

  Function  GetNodeCount: LongInt; Virtual;
  Function  GetFirstChild(Node: LongInt): LongInt; Virtual;
  Function  GetNextSibling(Node: LongInt): LongInt; Virtual;
  Function  GetParent(Node: LongInt): LongInt; Virtual;
  Function  GetNodeTitle(Node: LongInt): BibStr; Virtual;
  Function  GetNodeText(Node: LongInt): BibStr; Virtual;
  Function  AddNode(Parent: LongInt; Const Title, Txt: BibStr): LongInt; Virtual;

  Public
  PathSpec, FileName: BibStr;
  Opened, WMode: Boolean;
  Cfg: BibStr;
  Mk: BibMarkup;
  NParent, NFirstChild, NNextSib, NLastChild: PTheWordBokIntArr;   {indexed 0..NodeCount, 0 = the root}
  NTitle, NText: PTheWordBokStrArr;                                {indexed 1..NodeCount}
  NodeCount, NodeCap: LongInt;
  End;

Type TheWordBookPtr = ^TheWordBookObj;

Implementation

Uses SysUtils, MKBibSql, MKBibMkp;

Constructor TheWordBookObj.Init;
  Begin
  AbsBookObj.Init;
  PathSpec := ''; FileName := '';
  Opened := False; WMode := False;
  Cfg := '';
  Mk := bmRTF;
  MetaMarkup := bmRTF;
  NParent := Nil; NFirstChild := Nil; NNextSib := Nil; NLastChild := Nil;
  NTitle := Nil; NText := Nil;
  NodeCount := 0; NodeCap := 0;
  End;

Destructor TheWordBookObj.Done;
  Begin
  If Opened Or WMode Then CloseBible;
  AbsBookObj.Done;
  End;

Procedure TheWordBookObj.SetBibPath(BP: String);
  Begin
  If Opened Or WMode Then CloseBible;
  PathSpec := BP;
  End;

Function TheWordBookObj.BibleExists: Boolean;
  Begin
  BibleExists := Opened Or ((PathSpec <> '') And FileExists(PathSpec));
  End;

Function TheWordBookObj.IsOpen: Boolean;
  Begin
  IsOpen := Opened;
  End;

Function TheWordBookObj.GetConfig(Key: String): BibStr;
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

{ make room for N nodes (1..N; element 0 is the root and always kept); the arrays move by raw copy, so
  the title / text strings are not individually released - the new blocks are zeroed first }
Procedure GrowBokTo(Var ParentArr, FirstChildArr, NextSibArr, LastChildArr: PTheWordBokIntArr;
                     Var TitleArr, TextArr: PTheWordBokStrArr; Var Cap: LongInt; Count, N: LongInt);
  Var
    NewCap: LongInt;
    NP, NF, NS, NL: PTheWordBokIntArr;
    NT, NX: PTheWordBokStrArr;
  Begin
  If N <= Cap Then Exit;
  NewCap := Cap * 2;
  If NewCap < N Then NewCap := N;
  If NewCap < 64 Then NewCap := 64;
  GetMem(NP, (NewCap + 1) * SizeOf(LongInt)); FillChar(NP^, (NewCap + 1) * SizeOf(LongInt), 0);
  GetMem(NF, (NewCap + 1) * SizeOf(LongInt)); FillChar(NF^, (NewCap + 1) * SizeOf(LongInt), 0);
  GetMem(NS, (NewCap + 1) * SizeOf(LongInt)); FillChar(NS^, (NewCap + 1) * SizeOf(LongInt), 0);
  GetMem(NL, (NewCap + 1) * SizeOf(LongInt)); FillChar(NL^, (NewCap + 1) * SizeOf(LongInt), 0);
  GetMem(NT, (NewCap + 1) * SizeOf(BibStr)); FillChar(NT^, (NewCap + 1) * SizeOf(BibStr), 0);
  GetMem(NX, (NewCap + 1) * SizeOf(BibStr)); FillChar(NX^, (NewCap + 1) * SizeOf(BibStr), 0);
  If ParentArr <> Nil Then
    Begin
    Move(ParentArr^, NP^, (Count + 1) * SizeOf(LongInt));
    Move(FirstChildArr^, NF^, (Count + 1) * SizeOf(LongInt));
    Move(NextSibArr^, NS^, (Count + 1) * SizeOf(LongInt));
    Move(LastChildArr^, NL^, (Count + 1) * SizeOf(LongInt));
    Move(TitleArr^, NT^, (Count + 1) * SizeOf(BibStr));
    Move(TextArr^, NX^, (Count + 1) * SizeOf(BibStr));
    FreeMem(ParentArr); FreeMem(FirstChildArr); FreeMem(NextSibArr); FreeMem(LastChildArr);
    FreeMem(TitleArr); FreeMem(TextArr);
    End;
  ParentArr := NP; FirstChildArr := NF; NextSibArr := NS; LastChildArr := NL;
  TitleArr := NT; TextArr := NX;
  Cap := NewCap;
  End;

Procedure ClearBokNodes(Var ParentArr, FirstChildArr, NextSibArr, LastChildArr: PTheWordBokIntArr;
                         Var TitleArr, TextArr: PTheWordBokStrArr; Var Count, Cap: LongInt);
  Var i: LongInt;
  Begin
  If TitleArr <> Nil Then
    Begin
    For i := 1 To Count Do Begin TitleArr^[i] := ''; TextArr^[i] := ''; End;
    FreeMem(TitleArr); FreeMem(TextArr);
    TitleArr := Nil; TextArr := Nil;
    End;
  If ParentArr <> Nil Then
    Begin
    FreeMem(ParentArr); FreeMem(FirstChildArr); FreeMem(NextSibArr); FreeMem(LastChildArr);
    ParentArr := Nil; FirstChildArr := Nil; NextSibArr := Nil; LastChildArr := Nil;
    End;
  Count := 0; Cap := 0;
  End;

{ append NewIdx as the last child of OurParent (0 = the root) }
Procedure LinkChild(FirstChildArr, NextSibArr, LastChildArr: PTheWordBokIntArr; OurParent, NewIdx: LongInt);
  Begin
  If FirstChildArr^[OurParent] = 0 Then FirstChildArr^[OurParent] := NewIdx
  Else NextSibArr^[LastChildArr^[OurParent]] := NewIdx;
  LastChildArr^[OurParent] := NewIdx;
  End;

Function TheWordBookObj.OpenBible: Word;
  Var
    Db: psqlite3;
    St: psqlite3_stmt;
    Blobs, Total, i, TwId, TwPid, OurPar: LongInt;
    Txt, Subj, Sample, CT: BibStr;
    TwIds: PTheWordBokIntArr;          {our node 1..NodeCount -> the theWord topic id, for parent lookup}
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
      Subj := SqlColText(St, 0);
      Txt := SqlColText(St, 1);
      StringReplace(Txt, #10, ' ', [rfReplaceAll]);
      Cfg := Cfg + Subj + '=' + Txt + #10;
      End;
    sqlite3_finalize(St);
    End;
  ClearBokNodes(NParent, NFirstChild, NNextSib, NLastChild, NTitle, NText, NodeCount, NodeCap);
  GetMem(TwIds, 1 * SizeOf(LongInt));          {grown together with the node arrays below}
  TwIds^[0] := 0;
  If sqlite3_prepare_v2(Db, 'SELECT t.id, t.pid, t.subject, c.data FROM topics t ' +
       'LEFT JOIN content c ON c.topic_id = t.id ORDER BY t.rel_order, t.id', -1, @St, Nil) <> SQLITE_OK Then
    Begin
    FreeMem(TwIds);
    sqlite3_close(Db);
    OpenBible := bibErrBadConf;
    Exit;
    End;
  Blobs := 0; Total := 0; Sample := '';
  While sqlite3_step(St) = SQLITE_ROW Do
    Begin
    Inc(Total);
    TwId := sqlite3_column_int(St, 0);
    TwPid := sqlite3_column_int(St, 1);
    Subj := SqlColText(St, 2);
    If SqlColIsBlob(St, 3) Then
      Begin
      Txt := SqlColBlobText(St, 3);               {a "compressed" module: zlib, not encrypted}
      If Txt = '' Then Inc(Blobs);
      End
    Else Txt := SqlColText(St, 3);
    If (Sample = '') And (Txt <> '') Then Sample := Copy(Txt, 1, 400);
    OurPar := 0;
    If TwPid <> 0 Then
      For i := 1 To NodeCount Do
        If TwIds^[i] = TwPid Then
          Begin OurPar := i; Break; End;
    GrowBokTo(NParent, NFirstChild, NNextSib, NLastChild, NTitle, NText, NodeCap, NodeCount, NodeCount + 1);
    ReallocMem(TwIds, (NodeCap + 1) * SizeOf(LongInt));
    Inc(NodeCount);
    TwIds^[NodeCount] := TwId;
    NParent^[NodeCount] := OurPar;
    NTitle^[NodeCount] := Subj;
    NText^[NodeCount] := Txt;
    LinkChild(NFirstChild, NNextSib, NLastChild, OurPar, NodeCount);
    End;
  sqlite3_finalize(St);
  sqlite3_close(Db);
  FreeMem(TwIds);
  If (Total > 0) And (Blobs = Total) Then
    Begin
    ClearBokNodes(NParent, NFirstChild, NNextSib, NLastChild, NTitle, NText, NodeCount, NodeCap);
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
  OpenBible := bibOk;
  End;

Function TheWordBookObj.CloseBible: Word;
  Begin
  If WMode Then
    Begin
    CloseBible := FlushBible;
    Exit;
    End;
  ClearBokNodes(NParent, NFirstChild, NNextSib, NLastChild, NTitle, NText, NodeCount, NodeCap);
  Cfg := '';
  Opened := False;
  CloseBible := bibOk;
  End;

Function TheWordBookObj.GetName: String;
  Begin
  If WMode Then GetName := AbsModObj.GetName
  Else If GetConfig('abbrev') <> '' Then GetName := GetConfig('abbrev')
  Else GetName := ChangeFileExt(ChangeFileExt(ExtractFileName(FileName), ''), '');
  End;

Function TheWordBookObj.GetDescription: String;
  Begin
  If WMode Then GetDescription := AbsModObj.GetDescription
  Else If GetConfig('title') <> '' Then GetDescription := GetConfig('title')
  Else GetDescription := GetConfig('description');
  End;

Function TheWordBookObj.GetAbout: BibStr;
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

Function TheWordBookObj.GetLang: String;
  Begin
  If WMode Then GetLang := AbsModObj.GetLang Else GetLang := GetConfig('lang');
  End;

Function TheWordBookObj.GetVersion: String;
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

Function TheWordBookObj.GetCopyright: String;
  Begin
  If WMode Then GetCopyright := AbsModObj.GetCopyright
  Else If GetConfig('copyright') <> '' Then GetCopyright := GetConfig('copyright')
  Else If GetConfig('creator') <> '' Then GetCopyright := GetConfig('creator')
  Else GetCopyright := GetConfig('author');
  End;

Function TheWordBookObj.GetMarkup: BibMarkup;
  Begin
  If WMode Then GetMarkup := MetaMarkup Else GetMarkup := Mk;
  End;

Function TheWordBookObj.GetNodeCount: LongInt;
  Begin
  GetNodeCount := NodeCount;
  End;

Function TheWordBookObj.GetFirstChild(Node: LongInt): LongInt;
  Begin
  If (Node < 0) Or (Node > NodeCount) Then GetFirstChild := 0
  Else GetFirstChild := NFirstChild^[Node];
  End;

Function TheWordBookObj.GetNextSibling(Node: LongInt): LongInt;
  Begin
  If (Node < 1) Or (Node > NodeCount) Then GetNextSibling := 0
  Else GetNextSibling := NNextSib^[Node];
  End;

Function TheWordBookObj.GetParent(Node: LongInt): LongInt;
  Begin
  If (Node < 1) Or (Node > NodeCount) Then GetParent := 0
  Else GetParent := NParent^[Node];
  End;

Function TheWordBookObj.GetNodeTitle(Node: LongInt): BibStr;
  Begin
  If (Node < 1) Or (Node > NodeCount) Then GetNodeTitle := ''
  Else GetNodeTitle := NTitle^[Node];
  End;

Function TheWordBookObj.GetNodeText(Node: LongInt): BibStr;
  Begin
  If (Node < 1) Or (Node > NodeCount) Then GetNodeText := ''
  Else GetNodeText := NText^[Node];
  End;


{---------------------------------------------------------------- writing}

Function TheWordBookObj.IsWriting: Boolean;
  Begin
  IsWriting := WMode;
  End;

Function TheWordBookObj.IsReadOnly: Boolean;
  Begin
  IsReadOnly := Not WMode;
  End;

Function TheWordBookObj.CreateBible(Name: String): Word;
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
  If Pos('.gbk.twm', LowerCase(PathSpec)) > 0 Then FileName := PathSpec
  Else
    Begin
    Dir := PathSpec;
    If Dir = '' Then Dir := '.';
    If Dir[Length(Dir)] <> '/' Then Dir := Dir + '/';
    If Not ForceDirectories(Dir) Then Exit;
    FileName := Dir + Name + '.gbk.twm';
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
  ClearBokNodes(NParent, NFirstChild, NNextSib, NLastChild, NTitle, NText, NodeCount, NodeCap);
  WMode := True;
  CreateBible := bibOk;
  End;

Function TheWordBookObj.AddNode(Parent: LongInt; Const Title, Txt: BibStr): LongInt;
  Begin
  AddNode := 0;
  If Not WMode Then Exit;
  If (Parent < 0) Or (Parent > NodeCount) Then Exit;
  GrowBokTo(NParent, NFirstChild, NNextSib, NLastChild, NTitle, NText, NodeCap, NodeCount, NodeCount + 1);
  Inc(NodeCount);
  NParent^[NodeCount] := Parent;
  NTitle^[NodeCount] := Title;
  NText^[NodeCount] := Txt;
  LinkChild(NFirstChild, NNextSib, NLastChild, Parent, NodeCount);
  AddNode := NodeCount;
  End;

Function TheWordBookObj.FlushBible: Word;
  Var
    Db: psqlite3;
    StT, StC, StCfg: psqlite3_stmt;
    i, P: LongInt;
    Ok: Boolean;
    V, Ma, Mi, T: BibStr;

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
    ClearBokNodes(NParent, NFirstChild, NNextSib, NLastChild, NTitle, NText, NodeCount, NodeCap);
    FlushBible := bibErrIO;
    Exit;
    End;
  If Not (SqlExec(Db, 'CREATE TABLE content(topic_id integer primary key, data BLOB, data2 blob)') And
          SqlExec(Db, 'CREATE TABLE config(name text, value text)') And
          SqlExec(Db, 'CREATE TABLE topics(id integer primary key, pid integer default 0, subject text, ' +
                      'rel_order, content_type string)') And
          SqlExec(Db, 'CREATE TABLE topics_wordindex(id integer, word text, priority integer)') And
          SqlExec(Db, 'BEGIN')) Then Ok := False;
  If Ok Then
    Begin
    StT := Nil; StC := Nil;
    If sqlite3_prepare_v2(Db, 'INSERT INTO topics (id, pid, subject, rel_order) VALUES (?, ?, ?, ?)',
         -1, @StT, Nil) <> SQLITE_OK Then Ok := False;
    If Ok And (sqlite3_prepare_v2(Db, 'INSERT INTO content (topic_id, data) VALUES (?, ?)', -1, @StC, Nil)
         <> SQLITE_OK) Then Ok := False;
    If Ok Then
      For i := 1 To NodeCount Do
        Begin
        sqlite3_bind_int(StT, 1, i);
        sqlite3_bind_int(StT, 2, NParent^[i]);
        SqlBindText(StT, 3, NTitle^[i]);
        sqlite3_bind_int(StT, 4, i);
        If sqlite3_step(StT) <> SQLITE_DONE Then Ok := False;
        sqlite3_reset(StT);
        sqlite3_bind_int(StC, 1, i);
        SqlBindText(StC, 2, NText^[i]);
        If sqlite3_step(StC) <> SQLITE_DONE Then Ok := False;
        sqlite3_reset(StC);
        End;
    If StT <> Nil Then sqlite3_finalize(StT);
    If StC <> Nil Then sqlite3_finalize(StC);
    StCfg := Nil;
    If sqlite3_prepare_v2(Db, 'INSERT INTO config (name, value) VALUES (?, ?)', -1, @StCfg, Nil) = SQLITE_OK Then
      Begin
      Cfg_('type', '3');
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
  ClearBokNodes(NParent, NFirstChild, NNextSib, NLastChild, NTitle, NText, NodeCount, NodeCap);
  WMode := False;
  If Not Ok Then FlushBible := bibErrIO;
  End;

End.
