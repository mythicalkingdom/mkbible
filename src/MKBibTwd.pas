Unit MKBibTwd;       {theWord Bible module object (.ont / .ot / .nt)}

{$I MKBib.Def}

{
  MKBibTwd - descendant of AbsBibObj for theWord Bible modules (theword.net).

  A module is one text file:
      .ont   Old + New Testament: 31102 verse lines
      .ot    Old Testament only: 23145 verse lines
      .nt    New Testament only: 7957 verse lines
  The lines are the verses in KJV order (Genesis 1:1 first, an empty line for a verse the module
  lacks), followed by the module's properties, one per line:
      id=b9   lang=eng   charset=0   short.title=KJV   title=...   description=...
      version.major=2   version.minor=9   version.date=...   publish.date=...   creator=...
      about=text that goes on \
          with a trailing backslash                     keywords=Strongs,Red Letter
  and # comment lines.  Encoding: a UTF-8 byte order mark, else UTF-8 when the text is valid
  UTF-8, else Windows-1252.  Line ends are CR LF.

  The verse text is theWord's markup (reported as bmTheWord): GBF style tags (<FI> italics,
  <FR> words of Jesus, <RF> footnotes, <CM> paragraph, <CL> / <CI> lines, <TS> headings,
  <WG1234> / <WH430> Strong's numbers, <WTN-NSF> morphology, <RX b.c.v> references) and a few HTML
  tags.  It is the markup MySword uses, which comes from theWord.

  Reading   SetBibPath(file), OpenBible
  Writing   SetBibPath(directory), CreateBible(Name), PutVerse (any order), CloseBible; the file
            becomes Name.ont, Name.ot or Name.nt depending on what was written.  Text is stored as
            given (write theWord / MySword markup or plain text); line ends in it become blanks.
            The written properties follow the sample modules, but no module written here has
            been tried in theWord itself.

  Not supported: encrypted modules (.ontx, header TWENCBMOD: OpenBible returns bibErrLocked),
  charsets other than Windows-1252 without a byte order mark, other versifications, introductions
  and the .twm dictionary / commentary / book modules.
}

Interface

Uses MKBibMod, MKBibAbs, MKBibVrs;

Type
  PBibStrArr = ^TBibStrArr;
  TBibStrArr = Array[0..0] Of BibStr;

  TheWordBibObj = Object(AbsBibObj)
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
  Function  GetProperty(Key: String): BibStr;      {any property of the module, e.g. 'keywords'}
  Function  CreateBible(Name: String): Word; Virtual;
  Function  PutVerse(Book, Chap, Verse: Word; Const Txt: BibStr): Boolean; Virtual;
  Function  PutIntro(Level, Book, Chap: Word; Const Txt: BibStr): Boolean; Virtual;
  Function  FlushBible: Word; Virtual;
  Function  IsWriting: Boolean; Virtual;
  Function  IsReadOnly: Boolean; Virtual;

  Public
  PathSpec, FileName: BibStr;
  Opened, WMode: Boolean;
  Lines: PBibStrArr;                 {verse text by linear verse number 1..31102}
  Props: BibStr;                     {key=value lines, continuations joined, one per line (#10)}
  GotOT, GotNT: Boolean;
  Procedure FreeLines;
  Procedure AllocLines;
  Function  Decode(Const B: BibStr): BibStr;
  End;

Type TheWordBibPtr = ^TheWordBibObj;

Implementation

Uses SysUtils, MKBibTxt;

Const
  OTLines = 23145;
  NTLines = 7957;

Constructor TheWordBibObj.Init;
  Begin
  AbsBibObj.Init;
  PathSpec := ''; FileName := '';
  Opened := False; WMode := False;
  Lines := Nil;
  Props := '';
  GotOT := False; GotNT := False;
  MetaMarkup := bmTheWord;
  End;

Destructor TheWordBibObj.Done;
  Begin
  If Opened Or WMode Then CloseBible;
  AbsBibObj.Done;
  End;

Procedure TheWordBibObj.SetBibPath(BP: String);
  Begin
  If Opened Or WMode Then CloseBible;
  PathSpec := BP;
  End;

Procedure TheWordBibObj.AllocLines;
  Begin
  GetMem(Lines, (BibTotalVerses + 1) * SizeOf(BibStr));
  FillChar(Lines^, (BibTotalVerses + 1) * SizeOf(BibStr), 0);
  End;

Procedure TheWordBibObj.FreeLines;
  Var i: LongInt;
  Begin
  If Lines <> Nil Then
    Begin
    For i := 0 To BibTotalVerses Do Lines^[i] := '';
    FreeMem(Lines);
    Lines := Nil;
    End;
  End;

Function TheWordBibObj.BibleExists: Boolean;
  Begin
  BibleExists := Opened Or ((PathSpec <> '') And FileExists(PathSpec));
  End;

Function TheWordBibObj.IsOpen: Boolean;
  Begin
  IsOpen := Opened;
  End;

Function TheWordBibObj.SetVersification(Name: String): Boolean;
  Begin
  SetVersification := AbsBibObj.SetVersification(Name) And (VSys = vsKJV);
  VSys := vsKJV;
  End;

{ Bytes of the file to UTF-8 text }
Function TheWordBibObj.Decode(Const B: BibStr): BibStr;
  Begin
  Decode := DecodeText(B);
  End;

Function TheWordBibObj.OpenBible: Word;
  Var
    F: File;
    Raw, Txt, Ln, Key, Cur: BibStr;
    SaveMode: Byte;
    Sz, P, E, N, First, Last, i, L: LongInt;
    Ext: String;
    Cont: Boolean;
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
  FileName := PathSpec;
  Ext := LowerCase(ExtractFileExt(FileName));
  If Ext = '.ont' Then Begin First := 1; Last := BibTotalVerses; GotOT := True; GotNT := True; End
  Else If Ext = '.ot' Then Begin First := 1; Last := OTLines; GotOT := True; GotNT := False; End
  Else If Ext = '.nt' Then Begin First := OTLines + 1; Last := BibTotalVerses; GotOT := False; GotNT := True; End
  Else If Ext = '.ontx' Then
    Begin
    OpenBible := bibErrLocked;                       {encrypted module}
    Exit;
    End
  Else
    Begin
    OpenBible := bibErrUnsupported;
    Exit;
    End;
  SaveMode := FileMode;
  FileMode := 0;
  Assign(F, FileName);
  Reset(F, 1);
  FileMode := SaveMode;
  If IOResult <> 0 Then
    Begin
    OpenBible := bibErrIO;
    Exit;
    End;
  Sz := FileSize(F);
  SetLength(Raw, Sz);
  If Sz > 0 Then BlockRead(F, Raw[1], Sz);
  Close(F);
  If Copy(Raw, 1, 8) = 'TWENCBMO' Then
    Begin
    OpenBible := bibErrLocked;
    Exit;
    End;
  Txt := Decode(Raw);
  Raw := '';
  AllocLines;
  { the verse lines, then the properties }
  P := 1;
  N := First;
  While (N <= Last) And (P <= Length(Txt)) Do
    Begin
    E := P;
    While (E <= Length(Txt)) And (Txt[E] <> #10) Do Inc(E);
    Ln := Copy(Txt, P, E - P);
    If (Ln <> '') And (Ln[Length(Ln)] = #13) Then SetLength(Ln, Length(Ln) - 1);
    Lines^[N] := Ln;
    Inc(N);
    P := E + 1;
    End;
  If N <= Last Then
    Begin
    FreeLines;
    OpenBible := bibErrBadConf;                      {fewer verse lines than the module type needs}
    Exit;
    End;
  Props := '';
  Cur := '';
  Cont := False;
  While P <= Length(Txt) Do
    Begin
    E := P;
    While (E <= Length(Txt)) And (Txt[E] <> #10) Do Inc(E);
    Ln := Copy(Txt, P, E - P);
    If (Ln <> '') And (Ln[Length(Ln)] = #13) Then SetLength(Ln, Length(Ln) - 1);
    P := E + 1;
    If Cont Then
      Begin
      Ln := TrimLeft(Ln);
      If (Ln <> '') And (Ln[Length(Ln)] = '\') Then SetLength(Ln, Length(Ln) - 1) Else Cont := False;
      Cur := Cur + Ln;
      If Not Cont Then
        Begin
        Props := Props + Cur + #10;
        Cur := '';
        End;
      End
    Else If (Trim(Ln) <> '') And (Ln[1] <> '#') And (Pos('=', Ln) > 0) Then
      Begin
      If Ln[Length(Ln)] = '\' Then
        Begin
        SetLength(Ln, Length(Ln) - 1);
        Cur := Ln;
        Cont := True;
        End
      Else Props := Props + Ln + #10;
      End;
    End;
  If Cur <> '' Then Props := Props + Cur + #10;
  VSys := vsKJV;
  UseApoc := False;
  Opened := True;
  SeekFirst;
  OpenBible := bibOk;
  End;

Function TheWordBibObj.CloseBible: Word;
  Begin
  If WMode Then
    Begin
    CloseBible := FlushBible;
    Exit;
    End;
  FreeLines;
  Props := '';
  Opened := False;
  CloseBible := bibOk;
  End;

Function TheWordBibObj.GetProperty(Key: String): BibStr;
  Var
    P, E: LongInt;
    S, K: BibStr;
  Begin
  GetProperty := '';
  S := #10 + Props;
  K := #10 + LowerCase(Key) + '=';
  P := Pos(K, LowerCase(S));
  If P = 0 Then Exit;
  Inc(P, Length(K));
  E := P;
  While (E <= Length(S)) And (S[E] <> #10) Do Inc(E);
  GetProperty := Trim(Copy(S, P, E - P));
  End;

Function TheWordBibObj.GetName: String;
  Begin
  If WMode Then GetName := AbsBibObj.GetName
  Else If GetProperty('short.title') <> '' Then GetName := GetProperty('short.title')
  Else GetName := ChangeFileExt(ExtractFileName(FileName), '');
  End;

Function TheWordBibObj.GetDescription: String;
  Begin
  If WMode Then GetDescription := AbsBibObj.GetDescription
  Else If GetProperty('title') <> '' Then GetDescription := GetProperty('title')
  Else GetDescription := GetProperty('description');
  End;

Function TheWordBibObj.GetAbout: BibStr;
  Begin
  If WMode Then GetAbout := AbsBibObj.GetAbout Else GetAbout := GetProperty('about');
  End;

Function TheWordBibObj.GetLang: String;
  Begin
  If WMode Then GetLang := AbsBibObj.GetLang Else GetLang := GetProperty('lang');
  End;

Function TheWordBibObj.GetVersion: String;
  Var Ma, Mi: BibStr;
  Begin
  If WMode Then
    Begin
    GetVersion := AbsBibObj.GetVersion;
    Exit;
    End;
  Ma := GetProperty('version.major');
  Mi := GetProperty('version.minor');
  If Ma = '' Then GetVersion := ''
  Else If Mi = '' Then GetVersion := Ma
  Else GetVersion := Ma + '.' + Mi;
  End;

Function TheWordBibObj.GetCopyright: String;
  Begin
  If WMode Then GetCopyright := AbsBibObj.GetCopyright
  Else If GetProperty('copyright') <> '' Then GetCopyright := GetProperty('copyright')
  Else GetCopyright := GetProperty('creator');
  End;

Function TheWordBibObj.GetMarkup: BibMarkup;
  Begin
  GetMarkup := bmTheWord;
  End;

Function TheWordBibObj.HasOT: Boolean;
  Begin
  HasOT := GotOT;
  End;

Function TheWordBibObj.HasNT: Boolean;
  Begin
  HasNT := GotNT;
  End;

Function TheWordBibObj.GetRawVerse: BibStr;
  Var L: LongInt;
  Begin
  GetRawVerse := '';
  If (Not Opened) Or (Not Found) Then Exit;
  L := VrsLinear(vsKJV, GetBook, GetChapter, GetVerse);
  If L > 0 Then GetRawVerse := Lines^[L];
  End;


{---------------------------------------------------------------- writing}

Function TheWordBibObj.IsWriting: Boolean;
  Begin
  IsWriting := WMode;
  End;

Function TheWordBibObj.IsReadOnly: Boolean;
  Begin
  IsReadOnly := Not WMode;
  End;

Function TheWordBibObj.CreateBible(Name: String): Word;
  Var i: Word;
  Begin
  If Opened Or WMode Then CloseBible;
  CreateBible := bibErrCreate;
  If Name = '' Then Exit;
  For i := 1 To Length(Name) Do
    If Not (Name[i] In ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', ' ']) Then Exit;
  If PathSpec = '' Then FileName := './' Else FileName := PathSpec;
  If FileName[Length(FileName)] <> '/' Then FileName := FileName + '/';
  If Not ForceDirectories(FileName) Then Exit;
  FileName := FileName + Name;                        {the extension is chosen when the module is finished}
  MetaName := Name;
  If (FileExists(FileName + '.ont') Or FileExists(FileName + '.ot') Or FileExists(FileName + '.nt')) And
     (Not Overwrite) Then
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

Function TheWordBibObj.PutVerse(Book, Chap, Verse: Word; Const Txt: BibStr): Boolean;
  Var
    L: LongInt;
    T: BibStr;
    i: LongInt;
  Begin
  PutVerse := False;
  If (Not WMode) Or (Verse = 0) Then Exit;           {no chapter introductions}
  If Not ValidRef(Book, Chap, Verse) Then Exit;
  L := VrsLinear(vsKJV, Book, Chap, Verse);
  T := Txt;
  For i := 1 To Length(T) Do
    If T[i] In [#10, #13] Then T[i] := ' ';
  Lines^[L] := T;
  If T <> '' Then
    Begin
    If Book <= BibOTBooks Then GotOT := True Else GotNT := True;
    End;
  PutVerse := True;
  End;

Function TheWordBibObj.PutIntro(Level, Book, Chap: Word; Const Txt: BibStr): Boolean;
  Begin
  PutIntro := False;                                  {theWord Bibles have no introductions}
  End;

Function TheWordBibObj.FlushBible: Word;
  Var
    F: File;
    Ext, Out_, Ln: BibStr;
    First, Last, i, P: LongInt;
    Strongs, Red: Boolean;
    Ma, Mi, V, Ab: BibStr;

  Procedure Prop(Const K, Val_: BibStr);
    Begin
    If Val_ <> '' Then Out_ := Out_ + K + '=' + Val_ + #13#10;
    End;

  Begin
  FlushBible := bibOk;
  If Not WMode Then Exit;
  If GotOT And GotNT Then Begin Ext := '.ont'; First := 1; Last := BibTotalVerses; End
  Else If GotOT Then Begin Ext := '.ot'; First := 1; Last := OTLines; End
  Else If GotNT Then Begin Ext := '.nt'; First := OTLines + 1; Last := BibTotalVerses; End
  Else Begin Ext := '.ont'; First := 1; Last := BibTotalVerses; End;     {empty module}
  Out_ := #$EF#$BB#$BF;
  Strongs := False; Red := False;
  For i := First To Last Do
    Begin
    Ln := Lines^[i];
    If (Pos('<WG', Ln) > 0) Or (Pos('<WH', Ln) > 0) Then Strongs := True;
    If Pos('<FR>', Ln) > 0 Then Red := True;
    Out_ := Out_ + Ln + #13#10;
    End;
  { properties }
  Prop('lang', MetaLang);
  Prop('charset', '0');
  Prop('short.title', MetaName);
  If MetaDesc <> '' Then
    Begin
    Prop('title', MetaDesc);
    Prop('description', MetaDesc);
    End;
  V := MetaVer;
  If V <> '' Then
    Begin
    P := Pos('.', V);
    If P = 0 Then Begin Ma := V; Mi := '0'; End
    Else Begin Ma := Copy(V, 1, P - 1); Mi := Copy(V, P + 1, Length(V)); End;
    Prop('version.major', Ma);
    Prop('version.minor', Mi);
    End;
  Prop('copyright', MetaCopy);
  Ab := '';
  For i := 1 To Length(MetaAbout) Do
    Case MetaAbout[i] Of
      #13: ;
      #10: Ab := Ab + '<br>';
      Else Ab := Ab + MetaAbout[i];
      End;
  If (MetaCopy <> '') And (Ab = '') Then Ab := MetaCopy;
  Prop('about', Ab);
  Ab := '';
  If Strongs Then Ab := 'Strongs';
  If Red Then
    Begin
    If Ab <> '' Then Ab := Ab + ',';
    Ab := Ab + 'Red Letter';
    End;
  Prop('keywords', Ab);
  FileName := FileName + Ext;
  Assign(F, FileName);
  Rewrite(F, 1);
  If IOResult <> 0 Then
    Begin
    FlushBible := bibErrIO;
    FreeLines;
    WMode := False;
    Exit;
    End;
  If Length(Out_) > 0 Then BlockWrite(F, Out_[1], Length(Out_));
  If IOResult <> 0 Then FlushBible := bibErrIO;
  Close(F);
  FreeLines;
  WMode := False;
  End;

End.
