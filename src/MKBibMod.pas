Unit MKBibMod;       {Abstract module object: what every kind of module (Bible, dictionary, commentary, book) shares}

{$I MKBib.Def}

{
  MKBibMod - AbsModObj, the base of the abstract objects, in the style of MKMsgAbs.

  It holds what is the same for every kind of module: where the module is (SetBibPath), opening and
  closing it, creating a new one, the module information (name, description, about, language,
  version, copyright, markup of the text), enciphered modules (IsLocked, SetUnlockKey), and the
  error codes.  The kinds of module are descendants:
      AbsBibObj   (MKBibAbs)   Bibles: text addressed by book, chapter, verse
      AbsDictObj  (MKBibDic)   dictionaries, lexicons, topical books: text addressed by a key
      AbsComObj   (MKBibCom)   commentaries: text for verse ranges
      AbsBookObj  (MKBibBok)   books: a tree of titled sections
  The method names (OpenBible, CloseBible, CreateBible, SetBibPath ...) are historical: they open,
  close and create "the module" whatever its kind; OpenMod, CloseMod, CreateMod, FlushMod, SetModPath
  and ModExists are the same calls under neutral names.
}

Interface

Uses MKBibMkp;

Const
  { Result codes of OpenBible / CloseBible / CreateBible (0 = ok) }
  bibOk           = 0;
  bibErrNoPath    = 1;    {SetBibPath was not called}
  bibErrNotFound  = 2;    {module / conf file / data files not found}
  bibErrBadConf   = 3;    {module configuration unreadable}
  bibErrUnsupported = 4;  {driver, compression, cipher or versification not supported}
  bibErrIO        = 5;    {read error}
  bibErrLocked    = 6;    {module is enciphered and no unlock key was given (see SetUnlockKey)}
  bibErrBadKey    = 7;    {the unlock key does not decrypt the module}
  bibErrExists    = 8;    {CreateBible: module already exists and Overwrite is off}
  bibErrCreate    = 9;    {CreateBible: could not create the files}

Type
  BibStr = AnsiString;    {verses and entries can be longer than 255 characters}

  BibMarkup = (bmPlain, bmOSIS, bmThML, bmGBF, bmTEI, bmHTML, bmRTF, bmUnknown, bmMySword, bmSTEP, bmTheWord, bmVPL, bmUSFM, bmUSFX, bmZefania);

Type AbsModObj = Object
  MetaName, MetaDesc, MetaLang, MetaVer, MetaCopy: String;   {for writing; getters return them}
  MetaAbout: BibStr;
  MetaMarkup: BibMarkup;
  Overwrite: Boolean;
  Constructor Init; {Initialize}
  Destructor Done; Virtual; {Done}

  {--- Opening ---}
  Procedure SetBibPath(BP: String); Virtual; {Set module name / path to module}
  Function  OpenBible: Word; Virtual; {Open the Bible, returns bibOk or bibErr...}
  Function  CloseBible: Word; Virtual; {Close the Bible}
  Function  BibleExists: Boolean; Virtual; {Does the module exist}
  Function  IsOpen: Boolean; Virtual; {Is the Bible open}
  Procedure SetName(S: String); Virtual; {Module name (before CreateBible)}
  Procedure SetDescription(S: String); Virtual;
  Procedure SetAbout(S: BibStr); Virtual;
  Procedure SetLang(S: String); Virtual;
  Procedure SetVersion(S: String); Virtual;
  Procedure SetCopyright(S: String); Virtual;
  Procedure SetMarkup(M: BibMarkup); Virtual; {Markup of the verse text that will be written}
  Procedure SetOverwrite(On: Boolean); Virtual; {Allow CreateBible to replace an existing module}
  Function  CreateBible(Name: String): Word; Virtual; {Start a new module; SetVersification first if not KJV}
  Function  FlushBible: Word; Virtual; {Finish writing: write blocks, index and configuration}
  Function  IsWriting: Boolean; Virtual; {A module is being created}
  Function  IsLocked: Boolean; Virtual; {Module is enciphered and needs an unlock key}
  Procedure SetUnlockKey(Key: String); Virtual; {Key to use for an enciphered module (before OpenBible)}
  Function  GetUnlockInfo: String; Virtual; {Where/how to obtain the key, from the module}
  Function  GetName: String; Virtual; {Short module name, e.g. KJV}
  Function  GetDescription: String; Virtual; {One line description}
  Function  GetAbout: BibStr; Virtual; {Long about/copyright text}
  Function  GetLang: String; Virtual; {Language code, e.g. en}
  Function  GetVersion: String; Virtual; {Module version}
  Function  GetCopyright: String; Virtual; {Copyright / license line}
  Function  GetMarkup: BibMarkup; Virtual; {Markup used by the raw text}
  Function  IsReadOnly: Boolean; Virtual; {No writing supported}

  {--- the same calls under neutral names ---}
  Procedure SetModPath(MP: String);
  Function  OpenMod: Word;
  Function  CloseMod: Word;
  Function  CreateMod(Name: String): Word;
  Function  FlushMod: Word;
  Function  ModExists: Boolean;
  End;

Type AbsModPtr = ^AbsModObj;

{ Helpers usable on their own }
Function StripMarkup(Const S: BibStr; MK: BibMarkup): BibStr;
  {Remove tags, notes and headings, decode entities, tidy white space}
Function Latin1ToUtf8(Const S: BibStr): BibStr;
Function MarkupToMkp(M: BibMarkup): MkpFormat;
  {The translator format for a markup; mfPlain for markups the translator does not know}
Function MarkupIsTranslatable(M: BibMarkup): Boolean;

Implementation

Constructor AbsModObj.Init;
  Begin
  MetaName := ''; MetaDesc := ''; MetaLang := ''; MetaVer := ''; MetaCopy := ''; MetaAbout := '';
  MetaMarkup := bmPlain; Overwrite := False;
  End;

Destructor AbsModObj.Done;
  Begin
  End;

Procedure AbsModObj.SetModPath(MP: String);
  Begin
  SetBibPath(MP);
  End;

Function AbsModObj.OpenMod: Word;
  Begin
  OpenMod := OpenBible;
  End;

Function AbsModObj.CloseMod: Word;
  Begin
  CloseMod := CloseBible;
  End;

Function AbsModObj.CreateMod(Name: String): Word;
  Begin
  CreateMod := CreateBible(Name);
  End;

Function AbsModObj.FlushMod: Word;
  Begin
  FlushMod := FlushBible;
  End;

Function AbsModObj.ModExists: Boolean;
  Begin
  ModExists := BibleExists;
  End;

Procedure AbsModObj.SetBibPath(BP: String);
  Begin
  End;

Function AbsModObj.OpenBible: Word;
  Begin
  OpenBible := bibErrUnsupported;
  End;

Procedure AbsModObj.SetName(S: String);
  Begin
  MetaName := S;
  End;

Procedure AbsModObj.SetDescription(S: String);
  Begin
  MetaDesc := S;
  End;

Procedure AbsModObj.SetAbout(S: BibStr);
  Begin
  MetaAbout := S;
  End;

Procedure AbsModObj.SetLang(S: String);
  Begin
  MetaLang := S;
  End;

Procedure AbsModObj.SetVersion(S: String);
  Begin
  MetaVer := S;
  End;

Procedure AbsModObj.SetCopyright(S: String);
  Begin
  MetaCopy := S;
  End;

Procedure AbsModObj.SetMarkup(M: BibMarkup);
  Begin
  MetaMarkup := M;
  End;

Procedure AbsModObj.SetOverwrite(On: Boolean);
  Begin
  Overwrite := On;
  End;

Function AbsModObj.CreateBible(Name: String): Word;
  Begin
  CreateBible := bibErrUnsupported;
  End;

Function AbsModObj.FlushBible: Word;
  Begin
  FlushBible := bibOk;
  End;

Function AbsModObj.IsWriting: Boolean;
  Begin
  IsWriting := False;
  End;

Function AbsModObj.IsLocked: Boolean;
  Begin
  IsLocked := False;
  End;

Procedure AbsModObj.SetUnlockKey(Key: String);
  Begin
  End;

Function AbsModObj.GetUnlockInfo: String;
  Begin
  GetUnlockInfo := '';
  End;

Function AbsModObj.CloseBible: Word;
  Begin
  CloseBible := bibOk;
  End;

Function AbsModObj.BibleExists: Boolean;
  Begin
  BibleExists := False;
  End;

Function AbsModObj.IsOpen: Boolean;
  Begin
  IsOpen := False;
  End;


{---------------------------------------------------------------- information}

Function AbsModObj.GetName: String;
  Begin
  GetName := MetaName;
  End;

Function AbsModObj.GetDescription: String;
  Begin
  GetDescription := MetaDesc;
  End;

Function AbsModObj.GetAbout: BibStr;
  Begin
  GetAbout := MetaAbout;
  End;

Function AbsModObj.GetLang: String;
  Begin
  GetLang := MetaLang;
  End;

Function AbsModObj.GetVersion: String;
  Begin
  GetVersion := MetaVer;
  End;

Function AbsModObj.GetCopyright: String;
  Begin
  GetCopyright := MetaCopy;
  End;

Function AbsModObj.GetMarkup: BibMarkup;
  Begin
  GetMarkup := MetaMarkup;
  End;

Function AbsModObj.IsReadOnly: Boolean;
  Begin
  IsReadOnly := True;
  End;


{---------------------------------------------------------------- structure}


Function MarkupToMkp(M: BibMarkup): MkpFormat;
  Begin
  Case M Of
    bmOSIS: MarkupToMkp := mfOSIS;
    bmThML: MarkupToMkp := mfThML;
    bmGBF: MarkupToMkp := mfGBF;
    bmMySword: MarkupToMkp := mfMySword;
    bmSTEP: MarkupToMkp := mfSTEP;
    bmTheWord: MarkupToMkp := mfTheWord;
    bmVPL: MarkupToMkp := mfVPL;
    bmHTML: MarkupToMkp := mfHTML;
    bmTEI: MarkupToMkp := mfTEI;
    bmUSFM: MarkupToMkp := mfUSFM;
    bmUSFX: MarkupToMkp := mfUSFX;
    bmZefania: MarkupToMkp := mfZefania;
    bmRTF: MarkupToMkp := mfSTEP;           {general RTF: theWord books, STEP}
    Else MarkupToMkp := mfPlain;
    End;
  End;

Function MarkupIsTranslatable(M: BibMarkup): Boolean;
  Begin
  MarkupIsTranslatable := M In [bmPlain, bmOSIS, bmThML, bmGBF, bmMySword, bmSTEP, bmTheWord, bmVPL, bmHTML, bmTEI, bmRTF, bmUSFM, bmUSFX, bmZefania];
  End;

Function Latin1ToUtf8(Const S: BibStr): BibStr;
  Var
    i: LongInt;
    R: BibStr;
  Begin
  R := '';
  For i := 1 To Length(S) Do
    If Ord(S[i]) < $80 Then R := R + S[i]
    Else R := R + Chr($C0 Or (Ord(S[i]) Shr 6)) + Chr($80 Or (Ord(S[i]) And $3F));
  Latin1ToUtf8 := R;
  End;


Function StripTags(Const S: BibStr; MK: BibMarkup): BibStr; Forward;

Function StripMarkup(Const S: BibStr; MK: BibMarkup): BibStr;
  { Markups the translator reads go through it; the others (none left but unknown ones) use the
    simple tag stripper below }
  Begin
  If MK = bmPlain Then StripMarkup := S
  Else If MarkupIsTranslatable(MK) Then StripMarkup := MkpTranslate(S, MarkupToMkp(MK), mfPlain)
  Else StripMarkup := StripTags(S, MK);
  End;

Function StripTags(Const S: BibStr; MK: BibMarkup): BibStr;
  Var
    R, Tag, TagLow, Ent: BibStr;
    OL: LongInt;           {used length of R}
    i, j, N: LongInt;
    Skip: Integer;          {>0 while inside an element whose content is dropped}
    IsClose, IsEmpty: Boolean;
    Code: Integer;

  Procedure Put(Const X: BibStr);
    Var k: LongInt;
    Begin
    For k := 1 To Length(X) Do
      Begin
      Inc(OL);
      R[OL] := X[k];
      End;
    End;

  Function TagName(Const T: BibStr): BibStr;
    Var k: LongInt; U: BibStr;
    Begin
    U := '';
    k := 1;
    If (k <= Length(T)) And (T[k] = '/') Then Inc(k);
    While (k <= Length(T)) And (Not (T[k] In [' ', '/', #9, #10, #13])) Do
      Begin
      If T[k] In ['A'..'Z'] Then U := U + Chr(Ord(T[k]) + 32) Else U := U + T[k];
      Inc(k);
      End;
    TagName := U;
    End;

  Function DropsContent(Const Nm: BibStr): Boolean;
    Begin
    {elements whose text is not part of the verse: notes, headings, glosses}
    DropsContent := (Nm = 'note') Or (Nm = 'title') Or (Nm = 'rf') Or (Nm = 'rx') Or
                    (Nm = 'tn') Or (Nm = 'tt') Or (Nm = 'fn') Or (Nm = 'head') Or
                    (Nm = 'sync') Or (Nm = 'hi_dummy');
    End;

  Begin
  If (Pos('<', S) = 0) And (Pos('&', S) = 0) And (Pos('  ', S) = 0) And
     (Pos(#10, S) = 0) And (Pos(#13, S) = 0) And (Pos(#9, S) = 0) And
     ((S = '') Or ((S[1] <> ' ') And (S[Length(S)] <> ' '))) Then
    Begin
    StripTags := S;       {nothing to strip}
    Exit;
    End;
  SetLength(R, Length(S) + 4);   {output is never longer than the input}
  OL := 0;
  Skip := 0;
  i := 1;
  N := Length(S);
  While i <= N Do
    Begin
    If S[i] = '<' Then
      Begin
      j := i + 1;
      While (j <= N) And (S[j] <> '>') Do Inc(j);
      Tag := Copy(S, i + 1, j - i - 1);
      TagLow := TagName(Tag);
      IsClose := (Length(Tag) > 0) And (Tag[1] = '/');
      IsEmpty := (Length(Tag) > 0) And (Tag[Length(Tag)] = '/');
      If MK In [bmGBF, bmMySword] Then
        Begin
        {GBF: <RF>..<Rf> footnote, <TS>..<Ts> heading}
        If Copy(Tag, 1, 2) = 'RF' Then Inc(Skip)
        Else If Copy(Tag, 1, 2) = 'Rf' Then Begin If Skip > 0 Then Dec(Skip); End
        Else If Copy(Tag, 1, 2) = 'TS' Then Inc(Skip)
        Else If Copy(Tag, 1, 2) = 'Ts' Then Begin If Skip > 0 Then Dec(Skip); End
        Else If (Skip = 0) And ((Tag = 'CM') Or (Tag = 'CL') Or (TagLow = 'br') Or (TagLow = 'p')) Then Put(' ');
        End
      Else If DropsContent(TagLow) And (Not IsEmpty) Then
        Begin
        If IsClose Then Begin If Skip > 0 Then Dec(Skip); End
        Else Inc(Skip);
        End
      Else If (Skip = 0) And ((TagLow = 'lb') Or (TagLow = 'br') Or (TagLow = 'p')) Then
        Put(' ');
      i := j + 1;
      Continue;
      End;
    If Skip = 0 Then
      Begin
      If S[i] = '&' Then
        Begin
        j := i + 1;
        While (j <= N) And (j - i < 10) And (S[j] <> ';') Do Inc(j);
        If (j <= N) And (S[j] = ';') Then
          Begin
          Ent := Copy(S, i + 1, j - i - 1);
          If Ent = 'amp' Then Put('&')
          Else If Ent = 'lt' Then Put('<')
          Else If Ent = 'gt' Then Put('>')
          Else If Ent = 'quot' Then Put('"')
          Else If Ent = 'apos' Then Put('''')
          Else If Ent = 'nbsp' Then Put(' ')
          Else If (Length(Ent) > 1) And (Ent[1] = '#') Then
            Begin
            If (Ent[2] = 'x') Or (Ent[2] = 'X') Then Val('$' + Copy(Ent, 3, 8), N, Code)
            Else Val(Copy(Ent, 2, 8), N, Code);
            If (Code = 0) And (N > 0) Then
              Begin
              If N < $80 Then Put(Chr(N))
              Else If N < $800 Then Put(Chr($C0 Or (N Shr 6)) + Chr($80 Or (N And $3F)))
              Else If N < $10000 Then
                Put(Chr($E0 Or (N Shr 12)) + Chr($80 Or ((N Shr 6) And $3F)) + Chr($80 Or (N And $3F)))
              Else
                Put(Chr($F0 Or (N Shr 18)) + Chr($80 Or ((N Shr 12) And $3F)) +
                     Chr($80 Or ((N Shr 6) And $3F)) + Chr($80 Or (N And $3F)));
              End;
            N := Length(S);
            End
          Else Put(Copy(S, i, j - i + 1));
          i := j + 1;
          Continue;
          End;
        End;
      Put(S[i]);
      End;
    Inc(i);
    End;
  {collapse white space, trim}
  SetLength(R, OL);
  j := 0;
  For i := 1 To OL Do
    If R[i] In [#9, #10, #13, ' '] Then
      Begin
      If (j > 0) And (R[j] <> ' ') Then
        Begin
        Inc(j);
        R[j] := ' ';
        End;
      End
    Else
      Begin
      Inc(j);
      R[j] := R[i];
      End;
  While (j > 0) And (R[j] = ' ') Do Dec(j);
  SetLength(R, j);
  StripTags := R;
  End;


End.
