Unit MKBibMem;       {Base object for Bible files that are read whole into memory: OSIS, Zefania, USFX, USFM}

{$I MKBib.Def}

{
  MKBibMem - descendant of AbsBibObj that keeps every verse of a Bible file in memory, one raw text per
  verse in KJV order (the 66 books, as MKBibVpl does).  The formats that are text or XML files with
  verses in them (OSIS, Zefania, USFX, USFM) differ only in how the file is split into verses and how
  it is written, so a descendant overrides just two methods:

      LoadSource   read PathSpec (a file or a directory), call SetInfo and StoreVerse for what it finds
      BuildOutput  write the module from Lines^ (verse texts in the file's own markup) to FileName

  and sets, in its Init, FileMarkup (what GetMarkup reports: bmOSIS ...), OutExt (the extension a new
  module gets) and OutIsDir (USFM: a folder with one file per book).

  Verses outside the 66 books of the KJV structure (the Apocrypha, extra verses of other
  versifications) are counted, not stored (GetSkippedRows).  Introductions and section headings
  that sit between verses become part of the text of the verse that follows them.

  The verse text is the file's own markup; bibconv translates it to and from the other markups
  (-m).  The module information found in the file is reported by GetName / GetDescription / ...
}

Interface

Uses MKBibMod, MKBibAbs, MKBibVrs;

Type
  PMemStrArr = ^TMemStrArr;
  TMemStrArr = Array[0..0] Of BibStr;

  MemBibObj = Object(AbsBibObj)
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
  Function  GetSkippedRows: LongInt;
  Function  CreateBible(Name: String): Word; Virtual;
  Function  PutVerse(Book, Chap, Verse: Word; Const Txt: BibStr): Boolean; Virtual;
  Function  PutIntro(Level, Book, Chap: Word; Const Txt: BibStr): Boolean; Virtual;
  Function  FlushBible: Word; Virtual;
  Function  IsWriting: Boolean; Virtual;
  Function  IsReadOnly: Boolean; Virtual;

  { to override }
  Function  LoadSource: Boolean; Virtual;
  Function  BuildOutput: Word; Virtual;

  { for the descendants }
  Function  StoreVerse(Book, Chap, Verse: Word; Const Txt: BibStr): Boolean;
  Procedure SetInfo(Const NameS, DescS, LangS, CopyS, AboutS, VerS: BibStr);
  Function  BookOfName(Const Nm: BibStr): Word;
  Function  VerseText(Book, Chap, Verse: Word): BibStr;
  Function  ReadWholeFile(Const Path: String; Var Txt: BibStr): Boolean;
  Function  WriteWholeFile(Const Path: String; Const Txt: BibStr): Boolean;

  Public
  PathSpec, FileName: BibStr;
  Opened, WMode: Boolean;
  Lines: PMemStrArr;
  GotOT, GotNT: Boolean;
  Skipped: LongInt;
  FileMarkup: BibMarkup;
  OutExt: String;
  OutIsDir: Boolean;
  IName, IDesc, ILang, ICopy, IAbout, IVer: BibStr;
  Procedure AllocLines;
  Procedure FreeLines;
  End;

Type MemBibPtr = ^MemBibObj;

{ small XML helpers for the descendants }
Function XmlAttrOf(Const Tag, Name: BibStr): BibStr;
  {value of Name="..." (or '...') in the text of a tag, '' if absent; the name is matched without regard to case}
Function XmlDecode(Const S: BibStr): BibStr;
  {&amp; &lt; &gt; &quot; &apos; and numeric references -> text (UTF-8)}
Function XmlFirst(Const T, Tag: BibStr): BibStr;
  {the decoded inner text of the first <Tag ...>...</Tag> in T (tags inside it removed), '' if none}
Function XmlTrimAll(Const S: BibStr): BibStr;
  {blank runs and line ends -> one blank, trimmed}
Function XmlEsc(Const S: BibStr): BibStr;
  {& < > " escaped for text and attribute values}

Implementation

Uses SysUtils, MKBibTxt;

Function XmlAttrOf(Const Tag, Name: BibStr): BibStr;
  Var
    L, Key: BibStr;
    P, J, E: LongInt;
    Q: Char;
  Begin
  XmlAttrOf := '';
  L := LowerCase(Tag);
  Key := LowerCase(Name) + '=';
  P := 1;
  While True Do
    Begin
    J := Pos(Key, Copy(L, P, Length(L)));
    If J = 0 Then Exit;
    J := J + P - 1;
    If (J = 1) Or (L[J - 1] In [' ', #9, #10, #13, '<']) Then
      Begin
      J := J + Length(Key);
      If (J <= Length(Tag)) And (Tag[J] In ['"', '''']) Then
        Begin
        Q := Tag[J];
        Inc(J);
        E := J;
        While (E <= Length(Tag)) And (Tag[E] <> Q) Do Inc(E);
        XmlAttrOf := XmlDecode(Copy(Tag, J, E - J));
        End;
      Exit;
      End;
    P := J + 1;
    End;
  End;

Function XmlDecode(Const S: BibStr): BibStr;
  Var
    R, Ent: BibStr;
    i, j, Code: LongInt;
    N: LongInt;
  Begin
  If Pos('&', S) = 0 Then
    Begin
    XmlDecode := S;
    Exit;
    End;
  R := '';
  i := 1;
  While i <= Length(S) Do
    Begin
    If S[i] = '&' Then
      Begin
      j := i + 1;
      While (j <= Length(S)) And (j - i < 10) And (S[j] <> ';') And (S[j] <> '&') Do Inc(j);
      If (j <= Length(S)) And (S[j] = ';') Then
        Begin
        Ent := Copy(S, i + 1, j - i - 1);
        If Ent = 'amp' Then R := R + '&'
        Else If Ent = 'lt' Then R := R + '<'
        Else If Ent = 'gt' Then R := R + '>'
        Else If Ent = 'quot' Then R := R + '"'
        Else If Ent = 'apos' Then R := R + ''''
        Else If (Length(Ent) > 1) And (Ent[1] = '#') Then
          Begin
          If (Ent[2] = 'x') Or (Ent[2] = 'X') Then Val('$' + Copy(Ent, 3, 8), N, Code)
          Else Val(Copy(Ent, 2, 8), N, Code);
          If (Code = 0) And (N > 0) Then
            Begin
            If N < $80 Then R := R + Chr(N)
            Else If N < $800 Then R := R + Chr($C0 Or (N Shr 6)) + Chr($80 Or (N And $3F))
            Else If N < $10000 Then R := R + Chr($E0 Or (N Shr 12)) + Chr($80 Or ((N Shr 6) And $3F)) + Chr($80 Or (N And $3F))
            Else R := R + Chr($F0 Or (N Shr 18)) + Chr($80 Or ((N Shr 12) And $3F)) + Chr($80 Or ((N Shr 6) And $3F)) + Chr($80 Or (N And $3F));
            End
          Else R := R + Copy(S, i, j - i + 1);
          End
        Else R := R + Copy(S, i, j - i + 1);
        i := j + 1;
        Continue;
        End;
      End;
    R := R + S[i];
    Inc(i);
    End;
  XmlDecode := R;
  End;

Function XmlTrimAll(Const S: BibStr): BibStr;
  Var
    R: BibStr;
    i: LongInt;
    Blank: Boolean;
  Begin
  R := '';
  Blank := True;
  For i := 1 To Length(S) Do
    If S[i] In [' ', #9, #10, #13] Then
      Begin
      If Not Blank Then R := R + ' ';
      Blank := True;
      End
    Else
      Begin
      R := R + S[i];
      Blank := False;
      End;
  If (R <> '') And (R[Length(R)] = ' ') Then SetLength(R, Length(R) - 1);
  XmlTrimAll := R;
  End;

Function XmlFirst(Const T, Tag: BibStr): BibStr;
  Var
    U, Inner, R: BibStr;
    P, E, Q: LongInt;
    InTag: Boolean;
    i: LongInt;
  Begin
  XmlFirst := '';
  U := LowerCase(T);
  P := Pos('<' + LowerCase(Tag), U);
  While (P > 0) And (P + Length(Tag) + 1 <= Length(U)) And
        (Not (U[P + Length(Tag) + 1] In [' ', '>', '/', #9, #10, #13])) Do
    Begin
    Q := Pos('<' + LowerCase(Tag), Copy(U, P + 1, Length(U)));
    If Q = 0 Then P := 0 Else P := P + Q;
    End;
  If P = 0 Then Exit;
  E := P;
  While (E <= Length(T)) And (T[E] <> '>') Do Inc(E);
  If (E > P) And (T[E - 1] = '/') Then Exit;
  Q := Pos('</' + LowerCase(Tag) + '>', Copy(U, E, Length(U)));
  If Q = 0 Then Exit;
  Inner := Copy(T, E + 1, Q - 2);
  R := '';
  InTag := False;
  For i := 1 To Length(Inner) Do
    If Inner[i] = '<' Then InTag := True
    Else If Inner[i] = '>' Then InTag := False
    Else If Not InTag Then R := R + Inner[i];
  XmlFirst := XmlTrimAll(XmlDecode(R));
  End;

Function XmlEsc(Const S: BibStr): BibStr;
  Var
    R: BibStr;
    i: LongInt;
  Begin
  If (Pos('&', S) = 0) And (Pos('<', S) = 0) And (Pos('>', S) = 0) And (Pos('"', S) = 0) Then
    Begin
    XmlEsc := S;
    Exit;
    End;
  R := '';
  For i := 1 To Length(S) Do
    Case S[i] Of
      '&': R := R + '&amp;';
      '<': R := R + '&lt;';
      '>': R := R + '&gt;';
      '"': R := R + '&quot;';
      Else R := R + S[i];
    End;
  XmlEsc := R;
  End;

Constructor MemBibObj.Init;
  Begin
  AbsBibObj.Init;
  PathSpec := ''; FileName := '';
  Opened := False; WMode := False;
  Lines := Nil;
  GotOT := False; GotNT := False;
  Skipped := 0;
  FileMarkup := bmPlain;
  OutExt := '.txt'; OutIsDir := False;
  IName := ''; IDesc := ''; ILang := ''; ICopy := ''; IAbout := ''; IVer := '';
  End;

Destructor MemBibObj.Done;
  Begin
  If Opened Or WMode Then CloseBible;
  AbsBibObj.Done;
  End;

Procedure MemBibObj.SetBibPath(BP: String);
  Begin
  If Opened Or WMode Then CloseBible;
  PathSpec := BP;
  End;

Procedure MemBibObj.AllocLines;
  Begin
  GetMem(Lines, (BibTotalVerses + 1) * SizeOf(BibStr));
  FillChar(Lines^, (BibTotalVerses + 1) * SizeOf(BibStr), 0);
  End;

Procedure MemBibObj.FreeLines;
  Var i: LongInt;
  Begin
  If Lines <> Nil Then
    Begin
    For i := 0 To BibTotalVerses Do Lines^[i] := '';
    FreeMem(Lines);
    Lines := Nil;
    End;
  End;

Function MemBibObj.BibleExists: Boolean;
  Begin
  BibleExists := Opened Or ((PathSpec <> '') And (FileExists(PathSpec) Or DirectoryExists(PathSpec)));
  End;

Function MemBibObj.IsOpen: Boolean;
  Begin
  IsOpen := Opened;
  End;

Function MemBibObj.SetVersification(Name: String): Boolean;
  Begin
  SetVersification := AbsBibObj.SetVersification(Name) And (VSys = vsKJV);
  VSys := vsKJV;
  End;

Function MemBibObj.GetName: String;
  Begin
  If WMode Then GetName := AbsBibObj.GetName
  Else If IName <> '' Then GetName := IName
  Else GetName := ChangeFileExt(ChangeFileExt(ExtractFileName(ExcludeTrailingPathDelimiter(FileName)), ''), '');
  End;

Function MemBibObj.GetDescription: String;
  Begin
  If WMode Then GetDescription := AbsBibObj.GetDescription Else GetDescription := IDesc;
  End;

Function MemBibObj.GetAbout: BibStr;
  Begin
  If WMode Then GetAbout := AbsBibObj.GetAbout Else GetAbout := IAbout;
  End;

Function MemBibObj.GetLang: String;
  Begin
  If WMode Then GetLang := AbsBibObj.GetLang Else GetLang := ILang;
  End;

Function MemBibObj.GetVersion: String;
  Begin
  If WMode Then GetVersion := AbsBibObj.GetVersion Else GetVersion := IVer;
  End;

Function MemBibObj.GetCopyright: String;
  Begin
  If WMode Then GetCopyright := AbsBibObj.GetCopyright Else GetCopyright := ICopy;
  End;

Function MemBibObj.GetMarkup: BibMarkup;
  Begin
  GetMarkup := FileMarkup;
  End;

Function MemBibObj.HasOT: Boolean;
  Begin
  HasOT := GotOT;
  End;

Function MemBibObj.HasNT: Boolean;
  Begin
  HasNT := GotNT;
  End;

Function MemBibObj.GetSkippedRows: LongInt;
  Begin
  GetSkippedRows := Skipped;
  End;

Procedure MemBibObj.SetInfo(Const NameS, DescS, LangS, CopyS, AboutS, VerS: BibStr);
  Begin
  If NameS <> '' Then IName := NameS;
  If DescS <> '' Then IDesc := DescS;
  If LangS <> '' Then ILang := LangS;
  If CopyS <> '' Then ICopy := CopyS;
  If AboutS <> '' Then IAbout := AboutS;
  If VerS <> '' Then IVer := VerS;
  End;

Function MemBibObj.StoreVerse(Book, Chap, Verse: Word; Const Txt: BibStr): Boolean;
  Var L: LongInt;
  Begin
  StoreVerse := False;
  If (Book >= 1) And (Book <= BibBooks) Then L := VrsLinear(vsKJV, Book, Chap, Verse) Else L := 0;
  If L <= 0 Then
    Begin
    Inc(Skipped);
    Exit;
    End;
  Lines^[L] := Txt;
  If Txt <> '' Then
    Begin
    If Book <= BibOTBooks Then GotOT := True Else GotNT := True;
    End;
  StoreVerse := True;
  End;

Function MemBibObj.VerseText(Book, Chap, Verse: Word): BibStr;
  Var L: LongInt;
  Begin
  VerseText := '';
  If Lines = Nil Then Exit;
  L := VrsLinear(vsKJV, Book, Chap, Verse);
  If L > 0 Then VerseText := Lines^[L];
  End;

{ the book number for a name as a file spells it: a full name, an abbreviation or an OSIS id }
Function MemBibObj.BookOfName(Const Nm: BibStr): Word;
  Var i: Word;
  Begin
  i := FindBook(Nm);
  If (i < 1) Or (i > BibBooks) Then i := 0;
  BookOfName := i;
  End;

Function MemBibObj.ReadWholeFile(Const Path: String; Var Txt: BibStr): Boolean;
  Var
    F: File;
    Raw: BibStr;
    SaveMode: Byte;
    Sz: LongInt;
  Begin
  ReadWholeFile := False;
  Txt := '';
  SaveMode := FileMode;
  FileMode := 0;
  Assign(F, Path);
  Reset(F, 1);
  FileMode := SaveMode;
  If IOResult <> 0 Then Exit;
  Sz := FileSize(F);
  SetLength(Raw, Sz);
  If Sz > 0 Then BlockRead(F, Raw[1], Sz);
  Close(F);
  If IOResult <> 0 Then Exit;
  Txt := DecodeText(Raw);
  ReadWholeFile := True;
  End;

Function MemBibObj.WriteWholeFile(Const Path: String; Const Txt: BibStr): Boolean;
  Var F: File;
  Begin
  WriteWholeFile := False;
  Assign(F, Path);
  Rewrite(F, 1);
  If IOResult <> 0 Then Exit;
  If Length(Txt) > 0 Then BlockWrite(F, Txt[1], Length(Txt));
  If IOResult <> 0 Then
    Begin
    Close(F);
    Exit;
    End;
  Close(F);
  WriteWholeFile := IOResult = 0;
  End;

Function MemBibObj.LoadSource: Boolean;
  Begin
  LoadSource := False;
  End;

Function MemBibObj.BuildOutput: Word;
  Begin
  BuildOutput := bibErrUnsupported;
  End;

Function MemBibObj.OpenBible: Word;
  Begin
  If Opened Or WMode Then CloseBible;
  If PathSpec = '' Then
    Begin
    OpenBible := bibErrNoPath;
    Exit;
    End;
  If Not (FileExists(PathSpec) Or DirectoryExists(PathSpec)) Then
    Begin
    OpenBible := bibErrNotFound;
    Exit;
    End;
  FileName := PathSpec;
  AllocLines;
  Skipped := 0;
  GotOT := False; GotNT := False;
  IName := ''; IDesc := ''; ILang := ''; ICopy := ''; IAbout := ''; IVer := '';
  If Not LoadSource Then
    Begin
    FreeLines;
    OpenBible := bibErrBadConf;
    Exit;
    End;
  VSys := vsKJV;
  UseApoc := False;
  Opened := True;
  SeekFirst;
  OpenBible := bibOk;
  End;

Function MemBibObj.CloseBible: Word;
  Begin
  If WMode Then
    Begin
    CloseBible := FlushBible;
    Exit;
    End;
  FreeLines;
  Opened := False;
  CloseBible := bibOk;
  End;

Function MemBibObj.GetRawVerse: BibStr;
  Var L: LongInt;
  Begin
  GetRawVerse := '';
  If (Not Opened) Or (Not Found) Or (Lines = Nil) Then Exit;
  L := VrsLinear(vsKJV, GetBook, GetChapter, GetVerse);
  If L > 0 Then GetRawVerse := Lines^[L];
  End;


{---------------------------------------------------------------- writing}

Function MemBibObj.IsWriting: Boolean;
  Begin
  IsWriting := WMode;
  End;

Function MemBibObj.IsReadOnly: Boolean;
  Begin
  IsReadOnly := Not WMode;
  End;

Function MemBibObj.CreateBible(Name: String): Word;
  Var
    i: Word;
    Dir: BibStr;
  Begin
  If Opened Or WMode Then CloseBible;
  CreateBible := bibErrCreate;
  If Name = '' Then Exit;
  For i := 1 To Length(Name) Do
    If Not (Name[i] In ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', ' ']) Then Exit;
  If PathSpec = '' Then Dir := './' Else Dir := PathSpec;
  If Dir[Length(Dir)] <> '/' Then Dir := Dir + '/';
  If Not ForceDirectories(Dir) Then Exit;
  FileName := Dir + Name + OutExt;
  MetaName := Name;
  If (FileExists(FileName) Or DirectoryExists(FileName)) And (Not Overwrite) Then
    Begin
    CreateBible := bibErrExists;
    Exit;
    End;
  VSys := vsKJV;
  UseApoc := False;
  AllocLines;
  GotOT := False; GotNT := False;
  WMode := True;
  CreateBible := bibOk;
  End;

Function MemBibObj.PutVerse(Book, Chap, Verse: Word; Const Txt: BibStr): Boolean;
  Var
    L: LongInt;
    T: BibStr;
    i: LongInt;
  Begin
  PutVerse := False;
  If (Not WMode) Or (Verse = 0) Then Exit;
  If Not ValidRef(Book, Chap, Verse) Then Exit;
  L := VrsLinear(vsKJV, Book, Chap, Verse);
  T := Txt;
  For i := 1 To Length(T) Do
    If T[i] In [#13] Then T[i] := ' ';
  Lines^[L] := T;
  If T <> '' Then
    Begin
    If Book <= BibOTBooks Then GotOT := True Else GotNT := True;
    End;
  PutVerse := True;
  End;

Function MemBibObj.PutIntro(Level, Book, Chap: Word; Const Txt: BibStr): Boolean;
  Begin
  PutIntro := False;
  End;

Function MemBibObj.FlushBible: Word;
  Begin
  FlushBible := bibOk;
  If Not WMode Then Exit;
  FlushBible := BuildOutput;
  FreeLines;
  WMode := False;
  End;

End.
