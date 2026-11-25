Unit MKBibAbs;       {Abstract Bible Object}

{$I MKBib.Def}

{
  MKBibAbs - abstract Bible object, in the style of MKMsgAbs.

  A descendant (MKBibSwd for Sword modules, others to follow) overrides the
  Virtual methods.  Only a handful are primitives that MUST be supplied by a
  descendant: OpenBible, CloseBible, the module-information getters and
  GetRawVerse.  Everything else (navigation, reference parsing, plain-text
  extraction, word wrapped reading, searching) is implemented here on top of
  those, and a descendant may still override any of it.

  The default structure is the KJV versification (66 books, 1189 chapters,
  31102 verses, MKBibVrs).  A descendant for a module with another
  versification overrides the Structure methods.

  Books are numbered 1..66 (1-39 Old Testament, 40-66 New Testament).
  Chapters and verses are numbered from 1.
}

Interface

Uses MKBibVrs, MKBibMkp, MKBibMod;

Const
  { Levels for PutIntro }
  bilModule    = 0;   {module (Bible) introduction}
  bilTestament = 1;   {testament introduction (Book selects OT / NT)}
  bilBook      = 2;   {book introduction}
  bilChapter   = 3;   {chapter introduction (same as PutVerse with Verse = 0)}

Type
  BibScope  = (bsAll, bsOT, bsNT, bsApoc, bsBook);

  BibRef = Record
    Book, Chapter, Verse: Word;
  End;

Type AbsBibObj = Object(AbsModObj)
  LastSoft: Boolean;
  VSys: VrsSystem;      {versification in use (set by a descendant when it opens)}
  UseApoc: Boolean;     {Apocrypha requested (SetApocrypha)}
  Constructor Init; {Initialize}
  Destructor Done; Virtual; {Done}

  {--- Creating a module (a descendant that can write overrides these) ---}
  Function  PutVerse(Book, Chap, Verse: Word; Const Txt: BibStr): Boolean; Virtual;
    {Store raw text; Verse 0 = chapter intro.  Increasing order within a testament.}
  Function  PutIntro(Level, Book, Chap: Word; Const Txt: BibStr): Boolean; Virtual; {Module/testament/book/chapter intro}
  Function  PutVerseRef(RefStr: String; Const Txt: BibStr): Boolean; Virtual; {PutVerse by "John 3:16"}


  {--- Module information ---}
  Function  HasOT: Boolean; Virtual; {Module contains the Old Testament}
  Function  HasNT: Boolean; Virtual; {Module contains the New Testament}

  {--- Structure (versification) ---}
  Function  SetApocrypha(On: Boolean): Boolean; Virtual; {Include the Apocrypha books (67..); the result is only meaningful after OpenBible: False = versification has none}
  Function  HasApocrypha: Boolean; Virtual; {Versification defines Apocrypha books}
  Function  ApocryphaOn: Boolean; Virtual; {Apocrypha currently included}
  Function  IsApocrypha(Book: Word): Boolean; Virtual; {Book number is an Apocrypha book}
  Function  SetVersification(Name: String): Boolean; Virtual; {Select versification by Sword name, False if unsupported}
  Function  GetBookCount: Word; Virtual; {Number of books}
  Function  GetChapterCount(Book: Word): Word; Virtual; {Chapters in book}
  Function  GetVerseCount(Book, Chap: Word): Word; Virtual; {Verses in chapter}
  Function  GetTotalVerses: LongInt; Virtual; {Verses in whole Bible}
  Function  GetBookName(Book: Word): String; Virtual; {Full name, John}
  Function  GetBookAbbrev(Book: Word): String; Virtual; {Short name, Jn}
  Function  GetBookOSIS(Book: Word): String; Virtual; {OSIS id, John}
  Function  FindBook(Name: String): Word; Virtual; {Book number by name/abbrev, 0 = none}
  Function  ValidRef(Book, Chap, Verse: Word): Boolean; Virtual; {Does the verse exist}

  {--- Current position ---}
  Function  SetRef(Book, Chap, Verse: Word): Boolean; Virtual; {Go to a verse}
  Procedure SetRefRec(Var R: BibRef); Virtual; {Go to a verse by record}
  Function  SetRefStr(RefStr: String): Boolean; Virtual; {Go to "John 3:16"}
  Function  ParseRef(RefStr: String; Var R: BibRef): Boolean; Virtual; {Parse "1 Cor 13:4"}
  Procedure GetRef(Var R: BibRef); Virtual; {Current reference}
  Function  GetBook: Word; Virtual; {Current book}
  Function  GetChapter: Word; Virtual; {Current chapter}
  Function  GetVerse: Word; Virtual; {Current verse}
  Function  GetRefStr: String; Virtual; {Current reference as text, John 3:16}
  Function  GetRefLoc: LongInt; Virtual; {Verse number 1..GetTotalVerses, to allow reseek}
  Procedure SetRefLoc(RL: LongInt); Virtual; {Reseek to verse number}

  {--- Seeking (like SeekFirst/SeekNext of the message objects) ---}
  Procedure SeekFirst; Virtual; {First verse of the Bible}
  Procedure SeekLast; Virtual; {Last verse of the Bible}
  Procedure SeekNext; Virtual; {Next verse, crosses chapters and books}
  Procedure SeekPrior; Virtual; {Previous verse}
  Procedure SeekNextChapter; Virtual; {Verse 1 of next chapter}
  Procedure SeekPriorChapter; Virtual; {Verse 1 of previous chapter}
  Procedure SeekNextBook; Virtual; {Chapter 1:1 of next book}
  Procedure SeekPriorBook; Virtual; {Chapter 1:1 of previous book}
  Function  SeekFound: Boolean; Virtual; {Last seek landed on a verse (False past either end)}

  {--- Verse text ---}
  Function  GetRawVerse: BibStr; Virtual; {Text of current verse, markup as stored}
  Function  GetVerseText: BibStr; Virtual; {Current verse, markup/notes removed}
  Function  VerseExists: Boolean; Virtual; {Current verse has text in this module}
  Function  GetIntro(Level, Book, Chap: Word): BibStr; Virtual;
    {Introduction text, markup as stored: Level bilModule (Book, Chap ignored), bilTestament (Book selects
     OT / NT), bilBook, bilChapter.  '' when there is none or the format has no such introduction.}
  Function  GetIntroText(Level, Book, Chap: Word): BibStr; Virtual;
    {The same as plain text: markup removed, headings kept, paragraph breaks kept as new lines}
  Function  GetHeading: BibStr; Virtual; {Chapter introduction that comes before verse 1 (markup as stored); '' elsewhere}
  Function  GetMkpFormat: MkpFormat; {GetMarkup as a translator format; mfPlain for markups the translator does not know}
  Function  CanTranslateMarkup: Boolean; {Markup is one the translator reads (plain, OSIS, ThML, GBF, MySword)}

  {--- Reading the text of the current verse, like GetChar/GetString of a message ---}
  Procedure TextStartUp; Virtual; {(Re)start reading the current verse text}
  Function  GetChar: Char; Virtual; {Next text character}
  Function  EOM: Boolean; Virtual; {No more text in this verse}
  Function  GetString(MaxLen: Word): BibStr; Virtual; {Get word wrapped string}
  Function  WasWrap: Boolean; Virtual; {Last line was soft wrapped}
  Function  GetTxtPos: LongInt; Virtual; {Get indicator of text position}
  Procedure SetTxtPos(TP: LongInt); Virtual; {Set text position}

  {--- Searching ---}
  Procedure SetSearchScope(Scope: BibScope); Virtual; {All / OT / NT / current book}
  Procedure SearchFirst(Txt: String; CaseSens: Boolean); Virtual; {Find first verse containing Txt}
  Procedure SearchNext; Virtual; {Find next}
  Function  SearchFound: Boolean; Virtual; {A verse was found (and is current)}

  Public   {state - used by descendants}
  CurRef: BibRef;
  Found: Boolean;
  TxtBuf: BibStr;
  TxtPtr: LongInt;
  TxtLoaded: Boolean;
  SrchScope: BibScope;
  SrchBook: Word;
  SrchTxt: BibStr;
  SrchCase: Boolean;
  SrchFound: Boolean;
  Function  InScope(Book: Word): Boolean;
  Function  NextMatch: Boolean;
  End;


Type AbsBibPtr = ^AbsBibObj;




Implementation

Uses SysUtils;


Constructor AbsBibObj.Init;
  Begin
  AbsModObj.Init;
  LastSoft := True;
  VSys := vsKJV;
  UseApoc := False;
  CurRef.Book := 1; CurRef.Chapter := 1; CurRef.Verse := 1;
  Found := True;
  TxtBuf := ''; TxtPtr := 0; TxtLoaded := False;
  SrchScope := bsAll; SrchBook := 0; SrchTxt := ''; SrchCase := False; SrchFound := False;
  End;


Destructor AbsBibObj.Done;
  Begin
  AbsModObj.Done;
  End;


{---------------------------------------------------------------- opening}

Function AbsBibObj.PutVerse(Book, Chap, Verse: Word; Const Txt: BibStr): Boolean;
  Begin
  PutVerse := False;
  End;

Function AbsBibObj.PutIntro(Level, Book, Chap: Word; Const Txt: BibStr): Boolean;
  Begin
  PutIntro := False;
  End;

Function AbsBibObj.PutVerseRef(RefStr: String; Const Txt: BibStr): Boolean;
  Var R: BibRef;
  Begin
  If ParseRef(RefStr, R) Then PutVerseRef := PutVerse(R.Book, R.Chapter, R.Verse, Txt)
  Else PutVerseRef := False;
  End;

Function AbsBibObj.HasOT: Boolean;
  Begin
  HasOT := True;
  End;

Function AbsBibObj.HasNT: Boolean;
  Begin
  HasNT := True;
  End;

Function AbsBibObj.SetVersification(Name: String): Boolean;
  Begin
  SetVersification := VrsFind(Name, VSys);
  End;

Function AbsBibObj.SetApocrypha(On: Boolean): Boolean;
  Begin
  UseApoc := On;
  SetApocrypha := VrsHasApoc(VSys) Or (Not On);
  End;

Function AbsBibObj.HasApocrypha: Boolean;
  Begin
  HasApocrypha := VrsHasApoc(VSys);
  End;

Function AbsBibObj.ApocryphaOn: Boolean;
  Begin
  ApocryphaOn := UseApoc And VrsHasApoc(VSys);
  End;

Function AbsBibObj.IsApocrypha(Book: Word): Boolean;
  Begin
  IsApocrypha := Book > BibBooks;
  End;

Function AbsBibObj.GetBookCount: Word;
  Begin
  GetBookCount := VrsBookCount(VSys, ApocryphaOn);
  End;

Function AbsBibObj.GetChapterCount(Book: Word): Word;
  Begin
  GetChapterCount := VrsChapters(VSys, Book);
  End;

Function AbsBibObj.GetVerseCount(Book, Chap: Word): Word;
  Begin
  GetVerseCount := VrsVerses(VSys, Book, Chap);
  End;

Function AbsBibObj.GetTotalVerses: LongInt;
  Begin
  GetTotalVerses := VrsTotal(VSys, ApocryphaOn);
  End;

Function AbsBibObj.GetBookName(Book: Word): String;
  Begin
  If (Book < 1) Or (Book > GetBookCount) Then GetBookName := ''
  Else GetBookName := VrsBook(VSys, Book).Name;
  End;

Function AbsBibObj.GetBookAbbrev(Book: Word): String;
  Begin
  If (Book < 1) Or (Book > GetBookCount) Then GetBookAbbrev := ''
  Else GetBookAbbrev := VrsBook(VSys, Book).Abbrev;
  End;

Function AbsBibObj.GetBookOSIS(Book: Word): String;
  Begin
  If (Book < 1) Or (Book > GetBookCount) Then GetBookOSIS := ''
  Else GetBookOSIS := VrsBook(VSys, Book).OSIS;
  End;


{ Lower case, drop blanks and dots, roman numeral prefixes (I, II, III) to digits }
Function NormName(S: String): String;
  Var
    T, L: String;
    i: Word;
  Begin
  L := '';
  For i := 1 To Length(S) Do
    If S[i] In ['A'..'Z'] Then L := L + Chr(Ord(S[i]) + 32) Else L := L + S[i];
  If Copy(L, 1, 4) = 'iii ' Then L := '3' + Copy(L, 4, 255)
  Else If Copy(L, 1, 3) = 'ii ' Then L := '2' + Copy(L, 3, 255)
  Else If Copy(L, 1, 2) = 'i ' Then L := '1' + Copy(L, 2, 255);
  T := '';
  For i := 1 To Length(L) Do
    If L[i] In ['a'..'z', '0'..'9', #128..#255] Then T := T + L[i];
  NormName := T;
  End;


Function AbsBibObj.FindBook(Name: String): Word;
  Const
    NAlias = 12;
    Alias: Array[1..NAlias, 0..1] Of String[20] = (
      ('jn', 'john'), ('mt', 'matthew'), ('mk', 'mark'), ('lk', 'luke'),
      ('ps', 'psalms'), ('psalm', 'psalms'), ('song', 'songofsolomon'),
      ('songofsongs', 'songofsolomon'), ('canticles', 'songofsolomon'),
      ('revelations', 'revelationofjohn'), ('rev', 'revelationofjohn'),
      ('apocalypse', 'revelationofjohn'));
  Var
    N, M: String;
    i, Cnt, Hit: Word;
  Begin
  FindBook := 0;
  N := NormName(Name);
  If N = '' Then Exit;
  For i := 1 To NAlias Do
    If N = Alias[i, 0] Then N := Alias[i, 1];
  For i := 1 To GetBookCount Do
    If (N = NormName(GetBookName(i))) Or (N = NormName(GetBookAbbrev(i))) Or
       (N = NormName(GetBookOSIS(i))) Then
      Begin
      FindBook := i;
      Exit;
      End;
  {unique prefix of a full name}
  Cnt := 0; Hit := 0;
  For i := 1 To GetBookCount Do
    Begin
    M := NormName(GetBookName(i));
    If (Length(N) <= Length(M)) And (Copy(M, 1, Length(N)) = N) Then
      Begin
      Inc(Cnt);
      Hit := i;
      End;
    End;
  If Cnt = 1 Then FindBook := Hit;
  End;

Function AbsBibObj.ValidRef(Book, Chap, Verse: Word): Boolean;
  Begin
  ValidRef := (Book >= 1) And (Book <= GetBookCount) And (Chap >= 1) And
              (Chap <= GetChapterCount(Book)) And (Verse >= 1) And
              (Verse <= GetVerseCount(Book, Chap));
  End;


{---------------------------------------------------------------- position}

Function AbsBibObj.SetRef(Book, Chap, Verse: Word): Boolean;
  Begin
  TxtLoaded := False;
  If ValidRef(Book, Chap, Verse) Then
    Begin
    CurRef.Book := Book; CurRef.Chapter := Chap; CurRef.Verse := Verse;
    Found := True;
    SetRef := True;
    End
  Else
    Begin
    Found := False;
    SetRef := False;
    End;
  End;

Procedure AbsBibObj.SetRefRec(Var R: BibRef);
  Begin
  SetRef(R.Book, R.Chapter, R.Verse);
  End;

Function AbsBibObj.ParseRef(RefStr: String; Var R: BibRef): Boolean;
  { Accepts "John 3:16", "1 Cor 13", "Genesis" (chapter 1 verse 1 assumed),
    "Ps 23.1", "jn3:16" }
  Var
    S, NamePart: String;
    i, P: Word;
    N1, N2: LongInt;
    Code: Integer;
  Begin
  ParseRef := False;
  S := RefStr;
  While (Length(S) > 0) And (S[Length(S)] = ' ') Do Dec(S[0]);
  While (Length(S) > 0) And (S[1] = ' ') Do Delete(S, 1, 1);
  If S = '' Then Exit;
  {split at the last blank/letter-to-digit boundary that begins the chapter number}
  P := Length(S);
  While (P > 0) And (S[P] In ['0'..'9', ':', '.', ',']) Do Dec(P);
  NamePart := Copy(S, 1, P);
  S := Copy(S, P + 1, 255);
  R.Book := FindBook(NamePart);
  If R.Book = 0 Then
    Begin
    {"1 Cor"-style names that end in a digit with no chapter: try the whole text}
    R.Book := FindBook(RefStr);
    If R.Book = 0 Then Exit;
    S := '';
    End;
  R.Chapter := 1; R.Verse := 1;
  If S <> '' Then
    Begin
    P := 1;
    While (P <= Length(S)) And (S[P] In ['0'..'9']) Do Inc(P);
    Val(Copy(S, 1, P - 1), N1, Code);
    If (P = 1) Or (Code <> 0) Then Exit;
    R.Chapter := N1;
    If (P > Length(S)) And (GetChapterCount(R.Book) = 1) Then
      Begin
      R.Verse := N1;       {"Jude 5" means Jude 1:5}
      R.Chapter := 1;
      End
    Else If P <= Length(S) Then
      Begin
      Inc(P);   {skip separator}
      i := P;
      While (i <= Length(S)) And (S[i] In ['0'..'9']) Do Inc(i);
      Val(Copy(S, P, i - P), N2, Code);
      If (i = P) Or (Code <> 0) Then Exit;
      R.Verse := N2;
      End;
    End;
  ParseRef := ValidRef(R.Book, R.Chapter, R.Verse);
  End;

Function AbsBibObj.SetRefStr(RefStr: String): Boolean;
  Var R: BibRef;
  Begin
  If ParseRef(RefStr, R) Then SetRefStr := SetRef(R.Book, R.Chapter, R.Verse)
  Else
    Begin
    Found := False;
    SetRefStr := False;
    End;
  End;

Procedure AbsBibObj.GetRef(Var R: BibRef);
  Begin
  R := CurRef;
  End;

Function AbsBibObj.GetBook: Word;
  Begin
  GetBook := CurRef.Book;
  End;

Function AbsBibObj.GetChapter: Word;
  Begin
  GetChapter := CurRef.Chapter;
  End;

Function AbsBibObj.GetVerse: Word;
  Begin
  GetVerse := CurRef.Verse;
  End;

Function AbsBibObj.GetRefStr: String;
  Var C, V: String;
  Begin
  Str(CurRef.Chapter, C);
  Str(CurRef.Verse, V);
  GetRefStr := GetBookName(CurRef.Book) + ' ' + C + ':' + V;
  End;

Function AbsBibObj.GetRefLoc: LongInt;
  Var
    B, C: Word;
    L: LongInt;
  Begin
  L := 0;
  For B := 1 To CurRef.Book - 1 Do
    For C := 1 To GetChapterCount(B) Do
      Inc(L, GetVerseCount(B, C));
  For C := 1 To CurRef.Chapter - 1 Do
    Inc(L, GetVerseCount(CurRef.Book, C));
  GetRefLoc := L + CurRef.Verse;
  End;

Procedure AbsBibObj.SetRefLoc(RL: LongInt);
  Var
    B, C: Word;
    N: LongInt;
  Begin
  If RL >= 1 Then
    For B := 1 To GetBookCount Do
      For C := 1 To GetChapterCount(B) Do
        Begin
        N := GetVerseCount(B, C);
        If RL <= N Then
          Begin
          SetRef(B, C, RL);
          Exit;
          End;
        Dec(RL, N);
        End;
  SetRef(0, 0, 0);       {not found: Found := False}
  End;


{---------------------------------------------------------------- seeking}

Procedure AbsBibObj.SeekFirst;
  Begin
  SetRef(1, 1, 1);
  End;

Procedure AbsBibObj.SeekLast;
  Var B, C: Word;
  Begin
  B := GetBookCount;
  C := GetChapterCount(B);
  SetRef(B, C, GetVerseCount(B, C));
  End;

Procedure AbsBibObj.SeekNext;
  Var B, C, V: Word;
  Begin
  B := CurRef.Book; C := CurRef.Chapter; V := CurRef.Verse + 1;
  If V > GetVerseCount(B, C) Then
    Begin
    V := 1; Inc(C);
    If C > GetChapterCount(B) Then
      Begin
      C := 1; Inc(B);
      End;
    End;
  If B > GetBookCount Then
    Begin
    Found := False;     {stay on the last verse}
    TxtLoaded := False;
    End
  Else SetRef(B, C, V);
  End;

Procedure AbsBibObj.SeekPrior;
  Var B, C, V: Word;
  Begin
  B := CurRef.Book; C := CurRef.Chapter; V := CurRef.Verse;
  If V > 1 Then Dec(V)
  Else If C > 1 Then
    Begin
    Dec(C);
    V := GetVerseCount(B, C);
    End
  Else If B > 1 Then
    Begin
    Dec(B);
    C := GetChapterCount(B);
    V := GetVerseCount(B, C);
    End
  Else
    Begin
    Found := False;     {stay on the first verse}
    TxtLoaded := False;
    Exit;
    End;
  SetRef(B, C, V);
  End;

Procedure AbsBibObj.SeekNextChapter;
  Var B, C: Word;
  Begin
  B := CurRef.Book; C := CurRef.Chapter + 1;
  If C > GetChapterCount(B) Then
    Begin
    C := 1; Inc(B);
    End;
  If B > GetBookCount Then
    Begin
    Found := False;
    TxtLoaded := False;
    End
  Else SetRef(B, C, 1);
  End;

Procedure AbsBibObj.SeekPriorChapter;
  Var B, C: Word;
  Begin
  B := CurRef.Book; C := CurRef.Chapter;
  If C > 1 Then Dec(C)
  Else If B > 1 Then
    Begin
    Dec(B);
    C := GetChapterCount(B);
    End
  Else
    Begin
    Found := False;
    TxtLoaded := False;
    Exit;
    End;
  SetRef(B, C, 1);
  End;

Procedure AbsBibObj.SeekNextBook;
  Begin
  If CurRef.Book >= GetBookCount Then
    Begin
    Found := False;
    TxtLoaded := False;
    End
  Else SetRef(CurRef.Book + 1, 1, 1);
  End;

Procedure AbsBibObj.SeekPriorBook;
  Begin
  If CurRef.Book <= 1 Then
    Begin
    Found := False;
    TxtLoaded := False;
    End
  Else SetRef(CurRef.Book - 1, 1, 1);
  End;

Function AbsBibObj.SeekFound: Boolean;
  Begin
  SeekFound := Found;
  End;


{---------------------------------------------------------------- text}

Function AbsBibObj.GetRawVerse: BibStr;
  Begin
  GetRawVerse := '';
  End;

Function AbsBibObj.GetVerseText: BibStr;
  Begin
  GetVerseText := StripMarkup(GetRawVerse, GetMarkup);
  End;

Function AbsBibObj.VerseExists: Boolean;
  Begin
  VerseExists := GetVerseText <> '';
  End;

Function AbsBibObj.GetIntro(Level, Book, Chap: Word): BibStr;
  Begin
  GetIntro := '';
  End;

Function AbsBibObj.GetMkpFormat: MkpFormat;
  Begin
  GetMkpFormat := MarkupToMkp(GetMarkup);
  End;

Function AbsBibObj.CanTranslateMarkup: Boolean;
  Begin
  CanTranslateMarkup := MarkupIsTranslatable(GetMarkup);
  End;

Function AbsBibObj.GetIntroText(Level, Book, Chap: Word): BibStr;
  Var Raw: BibStr;
  Begin
  Raw := GetIntro(Level, Book, Chap);
  If Raw = '' Then GetIntroText := ''
  Else If CanTranslateMarkup Then GetIntroText := MkpTranslate(Raw, GetMkpFormat, mfPlain, [moHeadings, moBreaks])
  Else GetIntroText := StripMarkup(Raw, GetMarkup);
  End;

Function AbsBibObj.GetHeading: BibStr;
  Begin
  If (CurRef.Verse = 1) And Found Then GetHeading := GetIntro(bilChapter, CurRef.Book, CurRef.Chapter)
  Else GetHeading := '';
  End;


{---------------------------------------------------------------- reading}

Procedure AbsBibObj.TextStartUp;
  Begin
  TxtBuf := GetVerseText;
  TxtPtr := 0;
  TxtLoaded := True;
  LastSoft := True;
  End;

Function AbsBibObj.GetChar: Char;
  Begin
  If Not TxtLoaded Then TextStartUp;
  If TxtPtr < Length(TxtBuf) Then
    Begin
    Inc(TxtPtr);
    GetChar := TxtBuf[TxtPtr];
    End
  Else GetChar := #0;
  End;

Function AbsBibObj.EOM: Boolean;
  Begin
  If Not TxtLoaded Then TextStartUp;
  EOM := TxtPtr >= Length(TxtBuf);
  End;

Function AbsBibObj.GetString(MaxLen: Word): BibStr;
  { Word wrapped string of at most MaxLen characters.  Breaks at a blank when
    the line is full, or at a hard return (#13/#10).  The blank at the wrap is
    consumed.  WasWrap says whether the line ended by wrapping/end of text
    (True) or at a hard return (False). }
  Var
    Start, Last, Brk: LongInt;
    Ch: Char;
  Begin
  If EOM Then
    Begin
    GetString := '';
    Exit;
    End;
  If MaxLen < 1 Then MaxLen := 1;
  Start := TxtPtr + 1;
  Last := Start;
  Brk := 0;
  LastSoft := True;
  While (Last <= Length(TxtBuf)) And ((Last - Start) < MaxLen) Do
    Begin
    Ch := TxtBuf[Last];
    If (Ch = #13) Or (Ch = #10) Then
      Begin
      GetString := Copy(TxtBuf, Start, Last - Start);
      TxtPtr := Last;
      If (Ch = #13) And (TxtPtr < Length(TxtBuf)) And (TxtBuf[TxtPtr + 1] = #10) Then Inc(TxtPtr);
      LastSoft := False;
      Exit;
      End;
    If Ch = ' ' Then Brk := Last;
    Inc(Last);
    End;
  If Last > Length(TxtBuf) Then                  {rest of the text fits}
    Begin
    GetString := Copy(TxtBuf, Start, Last - Start);
    TxtPtr := Length(TxtBuf);
    End
  Else If TxtBuf[Last] = ' ' Then                {line exactly full, blank follows}
    Begin
    GetString := Copy(TxtBuf, Start, Last - Start);
    TxtPtr := Last;
    End
  Else If Brk > Start Then                       {wrap at last blank}
    Begin
    GetString := Copy(TxtBuf, Start, Brk - Start);
    TxtPtr := Brk;
    End
  Else                                           {one long word: hard split}
    Begin
    GetString := Copy(TxtBuf, Start, Last - Start);
    TxtPtr := Last - 1;
    End;
  End;

Function AbsBibObj.WasWrap: Boolean;
  Begin
  WasWrap := LastSoft;
  End;

Function AbsBibObj.GetTxtPos: LongInt;
  Begin
  If Not TxtLoaded Then TextStartUp;
  GetTxtPos := TxtPtr;
  End;

Procedure AbsBibObj.SetTxtPos(TP: LongInt);
  Begin
  If Not TxtLoaded Then TextStartUp;
  If TP < 0 Then TP := 0;
  If TP > Length(TxtBuf) Then TP := Length(TxtBuf);
  TxtPtr := TP;
  End;


{---------------------------------------------------------------- searching}

Procedure AbsBibObj.SetSearchScope(Scope: BibScope);
  Begin
  SrchScope := Scope;
  SrchBook := CurRef.Book;
  End;

Function AbsBibObj.InScope(Book: Word): Boolean;
  Begin
  Case SrchScope Of
    bsOT: InScope := Book <= BibOTBooks;
    bsNT: InScope := (Book > BibOTBooks) And (Book <= BibBooks);
    bsApoc: InScope := Book > BibBooks;
    bsBook: InScope := Book = SrchBook;
    Else InScope := True;
    End;
  End;

Function AbsBibObj.NextMatch: Boolean;
  { Advance from the current verse until a match or the end of the scope }
  Var T, Pat: BibStr;
  Begin
  NextMatch := False;
  Pat := SrchTxt;
  If Not SrchCase Then Pat := LowerCase(Pat);
  While True Do
    Begin
    SeekNext;
    If (Not Found) Or (Not InScope(CurRef.Book)) Then Exit;
    T := GetVerseText;
    If Not SrchCase Then T := LowerCase(T);
    If Pos(Pat, T) > 0 Then
      Begin
      NextMatch := True;
      Exit;
      End;
    End;
  End;

Procedure AbsBibObj.SearchFirst(Txt: String; CaseSens: Boolean);
  Var T, Pat: BibStr;
  Begin
  SrchTxt := Txt;
  SrchCase := CaseSens;
  SrchFound := False;
  If Txt = '' Then Exit;
  Case SrchScope Of
    bsOT: SetRef(1, 1, 1);
    bsNT: SetRef(BibOTBooks + 1, 1, 1);
    bsApoc: SetRef(BibBooks + 1, 1, 1);
    bsBook: SetRef(SrchBook, 1, 1);
    Else SetRef(1, 1, 1);
    End;
  {the first verse of the scope is a candidate too}
  T := GetVerseText;
  Pat := Txt;
  If Not CaseSens Then
    Begin
    T := LowerCase(T);
    Pat := LowerCase(Pat);
    End;
  If Pos(Pat, T) > 0 Then SrchFound := True
  Else SrchFound := NextMatch;
  End;

Procedure AbsBibObj.SearchNext;
  Begin
  If SrchTxt = '' Then
    SrchFound := False
  Else
    SrchFound := NextMatch;
  End;

Function AbsBibObj.SearchFound: Boolean;
  Begin
  SearchFound := SrchFound;
  End;


{---------------------------------------------------------------- helpers}


End.
