Unit MKBibVpl;       {Verse-per-line text file object (.vpl)}

{$I MKBib.Def}

{
  MKBibVpl - descendant of AbsBibObj for "verse per line" Bible text files, the format of Sword's
  mod2vpl / vpl2mod tools and of many text exports:

      Gen 1:1 In the beginning, God created the heavens and the earth.
      Gen 1:2 The earth was without form and void ...

  One verse per line: a book name, chapter:verse, a blank, the text.  Verses with no text are
  simply left out.  The file has no module information.

  Book names.  Reading accepts the three letter names used by the ESV file in this project (Gen Exo
  Lev ... Sol ... Jud Rev, with Jdg for Judges), Sword's short names (Gen Exod Judg Song ...), the
  full names (Genesis, I Samuel, Song of Solomon ...) and the OSIS ids.  Writing uses the three
  letter names, or the full names when LongNames is set.

  Markup.  Lines may carry light markup: <red> words of Jesus </red>, <b> bold </b>, <em> italics
  </em>, <br> (reported as bmVPL).  Plain text works too.  Writing stores the text as given;
  translate to bmVPL (bibconv -t vpl does) to keep red letters, italics and bold.

  Encoding.  A UTF-8 byte order mark, else UTF-8 when valid, else Windows-1252.  Writing gives UTF-8
  without a byte order mark and with LF line ends (what Sword's vpl2mod expects); set WriteBom /
  WriteCrLf to match Windows tools (the sample ESV file has both).

  Only the 66 books of the KJV structure are read; other lines are counted (GetSkippedRows).
}

Interface

Uses MKBibMod, MKBibAbs, MKBibVrs;

Type
  PBibStrArr = ^TBibStrArr;
  TBibStrArr = Array[0..0] Of BibStr;

  VplBibObj = Object(AbsBibObj)
  Constructor Init;
  Destructor Done; Virtual;
  Procedure SetBibPath(BP: String); Virtual;
  Function  OpenBible: Word; Virtual;
  Function  CloseBible: Word; Virtual;
  Function  BibleExists: Boolean; Virtual;
  Function  IsOpen: Boolean; Virtual;
  Function  GetName: String; Virtual;
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

  Public
  PathSpec, FileName: BibStr;
  Opened, WMode: Boolean;
  Lines: PBibStrArr;
  GotOT, GotNT: Boolean;
  Skipped: LongInt;
  LongNames, WriteBom, WriteCrLf: Boolean;
  Procedure AllocLines;
  Procedure FreeLines;
  Function  BookOf(Const Nm: BibStr): Word;
  End;

Type VplBibPtr = ^VplBibObj;

Implementation

Uses SysUtils, MKBibTxt;

Const
  Short3: Array[1..66] Of String[3] = (
    'Gen', 'Exo', 'Lev', 'Num', 'Deu', 'Jos', 'Jdg', 'Rut', '1Sa', '2Sa', '1Ki', '2Ki', '1Ch', '2Ch', 'Ezr',
    'Neh', 'Est', 'Job', 'Psa', 'Pro', 'Ecc', 'Sol', 'Isa', 'Jer', 'Lam', 'Eze', 'Dan', 'Hos', 'Joe', 'Amo',
    'Oba', 'Jon', 'Mic', 'Nah', 'Hab', 'Zep', 'Hag', 'Zec', 'Mal', 'Mat', 'Mar', 'Luk', 'Joh', 'Act', 'Rom',
    '1Co', '2Co', 'Gal', 'Eph', 'Phi', 'Col', '1Th', '2Th', '1Ti', '2Ti', 'Tit', 'Phm', 'Heb', 'Jam', '1Pe',
    '2Pe', '1Jo', '2Jo', '3Jo', 'Jud', 'Rev');

Constructor VplBibObj.Init;
  Begin
  AbsBibObj.Init;
  PathSpec := ''; FileName := '';
  Opened := False; WMode := False;
  Lines := Nil;
  GotOT := False; GotNT := False;
  Skipped := 0;
  LongNames := False; WriteBom := False; WriteCrLf := False;
  MetaMarkup := bmVPL;
  End;

Destructor VplBibObj.Done;
  Begin
  If Opened Or WMode Then CloseBible;
  AbsBibObj.Done;
  End;

Procedure VplBibObj.SetBibPath(BP: String);
  Begin
  If Opened Or WMode Then CloseBible;
  PathSpec := BP;
  End;

Procedure VplBibObj.AllocLines;
  Begin
  GetMem(Lines, (BibTotalVerses + 1) * SizeOf(BibStr));
  FillChar(Lines^, (BibTotalVerses + 1) * SizeOf(BibStr), 0);
  End;

Procedure VplBibObj.FreeLines;
  Var i: LongInt;
  Begin
  If Lines <> Nil Then
    Begin
    For i := 0 To BibTotalVerses Do Lines^[i] := '';
    FreeMem(Lines);
    Lines := Nil;
    End;
  End;

Function VplBibObj.BibleExists: Boolean;
  Begin
  BibleExists := Opened Or ((PathSpec <> '') And FileExists(PathSpec));
  End;

Function VplBibObj.IsOpen: Boolean;
  Begin
  IsOpen := Opened;
  End;

Function VplBibObj.SetVersification(Name: String): Boolean;
  Begin
  SetVersification := AbsBibObj.SetVersification(Name) And (VSys = vsKJV);
  VSys := vsKJV;
  End;

Function VplBibObj.GetName: String;
  Begin
  If WMode Then GetName := AbsBibObj.GetName
  Else GetName := ChangeFileExt(ExtractFileName(FileName), '');
  End;

Function VplBibObj.GetMarkup: BibMarkup;
  Begin
  GetMarkup := bmVPL;
  End;

Function VplBibObj.HasOT: Boolean;
  Begin
  HasOT := GotOT;
  End;

Function VplBibObj.HasNT: Boolean;
  Begin
  HasNT := GotNT;
  End;

Function VplBibObj.GetSkippedRows: LongInt;
  Begin
  GetSkippedRows := Skipped;
  End;

{ Book number for a name as it appears in the file: the three letter names first, then anything
  FindBook knows (Sword short names, full names, OSIS ids) }
Function VplBibObj.BookOf(Const Nm: BibStr): Word;
  Var
    i: Word;
    L: String;
  Begin
  BookOf := 0;
  L := LowerCase(Nm);
  For i := 1 To BibBooks Do
    If LowerCase(Short3[i]) = L Then
      Begin
      BookOf := i;
      Exit;
      End;
  i := FindBook(Nm);
  If i > BibBooks Then i := 0;
  BookOf := i;
  End;

Function VplBibObj.OpenBible: Word;
  Var
    F: File;
    Raw, Txt, Ln, Nm, Rest, Tok: BibStr;
    SaveMode: Byte;
    Sz, P, E, i, j, SP, Colon, Code: LongInt;
    B, C, V, L: LongInt;
    Found_: Boolean;
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
  Txt := DecodeText(Raw);
  Raw := '';
  AllocLines;
  Skipped := 0;
  GotOT := False; GotNT := False;
  P := 1;
  While P <= Length(Txt) Do
    Begin
    E := P;
    While (E <= Length(Txt)) And (Txt[E] <> #10) Do Inc(E);
    Ln := Copy(Txt, P, E - P);
    P := E + 1;
    If (Ln <> '') And (Ln[Length(Ln)] = #13) Then SetLength(Ln, Length(Ln) - 1);
    If Trim(Ln) = '' Then Continue;
    { find "chapter:verse" as a token after the book name: the first one that has a name before it }
    Found_ := False;
    SP := 0;
    For i := 2 To Length(Ln) Do
      If Ln[i] = ' ' Then
        Begin
        j := i + 1;
        While (j <= Length(Ln)) And (Ln[j] <> ' ') Do Inc(j);
        Tok := Copy(Ln, i + 1, j - i - 1);
        Colon := Pos(':', Tok);
        If Colon > 1 Then
          Begin
          Val(Copy(Tok, 1, Colon - 1), C, Code);
          If Code = 0 Then
            Begin
            Val(Copy(Tok, Colon + 1, Length(Tok)), V, Code);
            If Code = 0 Then
              Begin
              Nm := Trim(Copy(Ln, 1, i - 1));
              If j <= Length(Ln) Then Rest := Copy(Ln, j + 1, Length(Ln)) Else Rest := '';
              Found_ := True;
              Break;
              End;
            End;
          End;
        End;
    If Found_ Then
      Begin
      B := BookOf(Nm);
      If B > 0 Then L := VrsLinear(vsKJV, B, C, V) Else L := 0;
      If L > 0 Then
        Begin
        Lines^[L] := Trim(Rest);
        If Lines^[L] <> '' Then
          Begin
          If B <= BibOTBooks Then GotOT := True Else GotNT := True;
          End;
        End
      Else Inc(Skipped);
      End
    Else Inc(Skipped);
    End;
  VSys := vsKJV;
  UseApoc := False;
  Opened := True;
  SeekFirst;
  OpenBible := bibOk;
  End;

Function VplBibObj.CloseBible: Word;
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

Function VplBibObj.GetRawVerse: BibStr;
  Var L: LongInt;
  Begin
  GetRawVerse := '';
  If (Not Opened) Or (Not Found) Then Exit;
  L := VrsLinear(vsKJV, GetBook, GetChapter, GetVerse);
  If L > 0 Then GetRawVerse := Lines^[L];
  End;


{---------------------------------------------------------------- writing}

Function VplBibObj.IsWriting: Boolean;
  Begin
  IsWriting := WMode;
  End;

Function VplBibObj.IsReadOnly: Boolean;
  Begin
  IsReadOnly := Not WMode;
  End;

Function VplBibObj.CreateBible(Name: String): Word;
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
  FileName := FileName + Name + '.vpl';
  MetaName := Name;
  If FileExists(FileName) And (Not Overwrite) Then
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

Function VplBibObj.PutVerse(Book, Chap, Verse: Word; Const Txt: BibStr): Boolean;
  Var
    L, i: LongInt;
    T: BibStr;
  Begin
  PutVerse := False;
  If (Not WMode) Or (Verse = 0) Then Exit;
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

Function VplBibObj.PutIntro(Level, Book, Chap: Word; Const Txt: BibStr): Boolean;
  Begin
  PutIntro := False;
  End;

Function VplBibObj.FlushBible: Word;
  Var
    F: File;
    Out_, Nm, EOL: BibStr;
    B, C, V: Word;
    L: LongInt;
  Begin
  FlushBible := bibOk;
  If Not WMode Then Exit;
  If WriteCrLf Then EOL := #13#10 Else EOL := #10;
  Out_ := '';
  If WriteBom Then Out_ := #$EF#$BB#$BF;
  For B := 1 To BibBooks Do
    Begin
    If LongNames Then Nm := BookInfo[B].Name Else Nm := Short3[B];
    For C := 1 To VrsChapters(vsKJV, B) Do
      For V := 1 To VrsVerses(vsKJV, B, C) Do
        Begin
        L := VrsLinear(vsKJV, B, C, V);
        If Lines^[L] <> '' Then
          Out_ := Out_ + Nm + ' ' + IntToStr(C) + ':' + IntToStr(V) + ' ' + Lines^[L] + EOL;
        End;
    End;
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
