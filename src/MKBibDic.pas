Unit MKBibDic;       {Abstract Dictionary Object}

{$I MKBib.Def}

{
  MKBibDic - AbsDictObj: dictionaries, lexicons, topical books and the like: text addressed by a key
  (a word, a topic, a Strong's number).  A descendant for a format (MKDicSwd, MKDicMys, MKDicTwd)
  fills the key table when it opens and supplies the text of an entry; everything else (finding keys,
  navigation, searching, plain text, writing) is here.

  Entries are numbered 1..GetEntryCount in the order the module keeps them.  Key matching ignores case
  and, for Strong's keys, leading zeros and an optional G / H prefix: G0026, G26, 26 and 00026 are the
  same key (if the module is Greek or Hebrew, a prefix for the other language does not match).

  Reading   SetBibPath(module), OpenBible, then FindKey / SeekKey / GetEntry ...
  Writing   SetBibPath(directory), CreateBible(Name), PutEntry in any order, CloseBible.
}

Interface

Uses MKBibMod, MKBibMkp;

Type
  PDictStrArr = ^TDictStrArr;
  TDictStrArr = Array[0..0] Of BibStr;

  DictScope = (dsKeys, dsText, dsBoth);

  AbsDictObj = Object(AbsModObj)
  Constructor Init;
  Destructor Done; Virtual;

  {--- structure ---}
  Function  GetEntryCount: LongInt; Virtual; {entries in the module}
  Function  GetKeyAt(Idx: LongInt): BibStr; Virtual; {key of entry Idx (1..GetEntryCount)}
  Function  GetEntryAt(Idx: LongInt): BibStr; Virtual; {text of entry Idx, markup as stored}
  Function  GetEntryTextAt(Idx: LongInt): BibStr; Virtual; {the same as plain text (breaks kept as new lines)}
  Function  IsStrongs: Boolean; Virtual; {the keys are Strong's numbers}
  Function  GetStrongsPrefix: Char; Virtual; {'G', 'H' or #0 for a Strong's dictionary of that language}
  Function  GetMkpFormat: MkpFormat; {GetMarkup as a translator format}
  Function  CanTranslateMarkup: Boolean;

  {--- finding ---}
  Function  FindKey(Key: String): LongInt; Virtual; {exact key (see above), 0 = none}
  Function  FindKeyPrefix(Prefix: String): LongInt; Virtual; {first entry whose key starts with Prefix, 0 = none}
  Function  KeysMatch(A, B: BibStr): Boolean; Virtual;

  {--- navigation ---}
  Procedure SeekFirst; Virtual;
  Procedure SeekLast; Virtual;
  Procedure SeekNext; Virtual;
  Procedure SeekPrior; Virtual;
  Procedure SeekIndex(Idx: LongInt); Virtual;
  Procedure SeekKey(Key: String); Virtual; {the entry with that key, else the first key starting with it}
  Function  SeekFound: Boolean; Virtual;
  Function  GetCurIndex: LongInt; Virtual;
  Function  GetKey: BibStr; Virtual; {current key}
  Function  GetEntry: BibStr; Virtual; {current entry, markup as stored}
  Function  GetEntryText: BibStr; Virtual; {current entry as plain text}

  {--- searching ---}
  Procedure SearchFirst(Txt: String; CaseSens: Boolean; Scope: DictScope); Virtual;
  Procedure SearchNext; Virtual;
  Function  SearchFound: Boolean; Virtual;

  {--- writing ---}
  Function  PutEntry(Key: String; Const Txt: BibStr): Boolean; Virtual; {adds, or replaces an entry with the same key}
  Procedure SetStrongs(On: Boolean; Prefix: Char); Virtual; {mark the module being written as Strong's keyed}

  Public
  Keys: PDictStrArr;                 {entry keys, 1..KeyCount}
  Texts: PDictStrArr;                {entry texts when a descendant keeps them in memory (else Nil)}
  KeyCount, KeyCap: LongInt;
  CurIdx: LongInt;
  Found: Boolean;
  StrongsKeys: Boolean;
  StrongsPre: Char;
  SrchTxt: BibStr;
  SrchCase: Boolean;
  SrchScope: DictScope;
  SrchFound: Boolean;
  Procedure ClearEntries;
  Procedure AddKey(Const K: BibStr);                  {for a descendant filling the table}
  Procedure AddEntry(Const K, T: BibStr);             {key and text kept in memory}
  Procedure SortEntries;                              {by key, upper case, byte order (what Sword uses)}
  Procedure GrowTo(N: LongInt);
  Function  NextMatch(Start: LongInt): Boolean;
  End;

Type AbsDictPtr = ^AbsDictObj;

Function StrongsKeyParts(Const K: BibStr; Var Pre: Char; Var Num: LongInt; Var Suf: BibStr): Boolean;
  {K as G0026 / g26 / 00026 / 3588a: prefix (#0 if none), number, lower case suffix letters}

Implementation

Uses SysUtils;

Function StrongsKeyParts(Const K: BibStr; Var Pre: Char; Var Num: LongInt; Var Suf: BibStr): Boolean;
  Var
    i, j: Integer;
    S: BibStr;
    Code: LongInt;
  Begin
  StrongsKeyParts := False;
  S := Trim(K);
  Pre := #0; Num := 0; Suf := '';
  If S = '' Then Exit;
  i := 1;
  If S[1] In ['G', 'g', 'H', 'h'] Then
    Begin
    Pre := UpCase(S[1]);
    i := 2;
    End;
  j := i;
  While (j <= Length(S)) And (S[j] In ['0'..'9']) Do Inc(j);
  If j = i Then Exit;
  Val(Copy(S, i, j - i), Num, Code);
  If Code <> 0 Then Exit;
  Suf := LowerCase(Copy(S, j, Length(S)));
  If Length(Suf) > 2 Then Exit;
  StrongsKeyParts := True;
  End;

Constructor AbsDictObj.Init;
  Begin
  AbsModObj.Init;
  Keys := Nil; Texts := Nil;
  KeyCount := 0; KeyCap := 0;
  CurIdx := 0; Found := False;
  StrongsKeys := False; StrongsPre := #0;
  SrchTxt := ''; SrchCase := False; SrchScope := dsBoth; SrchFound := False;
  End;

Destructor AbsDictObj.Done;
  Begin
  ClearEntries;
  AbsModObj.Done;
  End;

Procedure AbsDictObj.ClearEntries;
  Var i: LongInt;
  Begin
  If Keys <> Nil Then
    Begin
    For i := 1 To KeyCount Do Keys^[i] := '';
    FreeMem(Keys);
    Keys := Nil;
    End;
  If Texts <> Nil Then
    Begin
    For i := 1 To KeyCount Do Texts^[i] := '';
    FreeMem(Texts);
    Texts := Nil;
    End;
  KeyCount := 0; KeyCap := 0; CurIdx := 0; Found := False;
  End;

{ make room for N entries; the string arrays move by raw copy, so the old block is freed without
  releasing the strings it held }
Procedure AbsDictObj.GrowTo(N: LongInt);
  Var
    NewCap: LongInt;
    NK, NT: PDictStrArr;
  Begin
  If N <= KeyCap Then Exit;
  NewCap := KeyCap * 2;
  If NewCap < N Then NewCap := N;
  If NewCap < 256 Then NewCap := 256;
  GetMem(NK, (NewCap + 1) * SizeOf(BibStr));
  FillChar(NK^, (NewCap + 1) * SizeOf(BibStr), 0);
  If Keys <> Nil Then
    Begin
    Move(Keys^, NK^, (KeyCount + 1) * SizeOf(BibStr));
    FreeMem(Keys);
    End;
  Keys := NK;
  If Texts <> Nil Then
    Begin
    GetMem(NT, (NewCap + 1) * SizeOf(BibStr));
    FillChar(NT^, (NewCap + 1) * SizeOf(BibStr), 0);
    Move(Texts^, NT^, (KeyCount + 1) * SizeOf(BibStr));
    FreeMem(Texts);
    Texts := NT;
    End;
  KeyCap := NewCap;
  End;

Procedure AbsDictObj.AddKey(Const K: BibStr);
  Begin
  GrowTo(KeyCount + 1);
  Inc(KeyCount);
  Keys^[KeyCount] := K;
  End;

Procedure AbsDictObj.AddEntry(Const K, T: BibStr);
  Begin
  If Texts = Nil Then
    Begin
    GrowTo(KeyCount + 1);
    GetMem(Texts, (KeyCap + 1) * SizeOf(BibStr));
    FillChar(Texts^, (KeyCap + 1) * SizeOf(BibStr), 0);
    End;
  GrowTo(KeyCount + 1);
  Inc(KeyCount);
  Keys^[KeyCount] := K;
  Texts^[KeyCount] := T;
  End;

{ shell sort by upper case key }
Procedure AbsDictObj.SortEntries;
  Var
    Gap, i, j: LongInt;
    UK: PDictStrArr;
    TK, TT, TU: BibStr;
  Begin
  If KeyCount < 2 Then Exit;
  GetMem(UK, (KeyCount + 1) * SizeOf(BibStr));
  FillChar(UK^, (KeyCount + 1) * SizeOf(BibStr), 0);
  For i := 1 To KeyCount Do UK^[i] := UpperCase(Keys^[i]);
  Gap := KeyCount Div 2;
  While Gap > 0 Do
    Begin
    For i := Gap + 1 To KeyCount Do
      Begin
      TK := Keys^[i]; TU := UK^[i];
      If Texts <> Nil Then TT := Texts^[i];
      j := i;
      While (j > Gap) And (UK^[j - Gap] > TU) Do
        Begin
        Keys^[j] := Keys^[j - Gap]; UK^[j] := UK^[j - Gap];
        If Texts <> Nil Then Texts^[j] := Texts^[j - Gap];
        Dec(j, Gap);
        End;
      Keys^[j] := TK; UK^[j] := TU;
      If Texts <> Nil Then Texts^[j] := TT;
      End;
    Gap := Gap Div 2;
    End;
  For i := 1 To KeyCount Do UK^[i] := '';
  FreeMem(UK);
  End;

Function AbsDictObj.GetEntryCount: LongInt;
  Begin
  GetEntryCount := KeyCount;
  End;

Function AbsDictObj.GetKeyAt(Idx: LongInt): BibStr;
  Begin
  If (Idx >= 1) And (Idx <= KeyCount) Then GetKeyAt := Keys^[Idx] Else GetKeyAt := '';
  End;

Function AbsDictObj.GetEntryAt(Idx: LongInt): BibStr;
  Begin
  If (Texts <> Nil) And (Idx >= 1) And (Idx <= KeyCount) Then GetEntryAt := Texts^[Idx] Else GetEntryAt := '';
  End;

Function AbsDictObj.GetMkpFormat: MkpFormat;
  Begin
  GetMkpFormat := MarkupToMkp(GetMarkup);
  End;

Function AbsDictObj.CanTranslateMarkup: Boolean;
  Begin
  CanTranslateMarkup := MarkupIsTranslatable(GetMarkup);
  End;

Function AbsDictObj.GetEntryTextAt(Idx: LongInt): BibStr;
  Var Raw: BibStr;
  Begin
  Raw := GetEntryAt(Idx);
  If Raw = '' Then GetEntryTextAt := ''
  Else If CanTranslateMarkup Then GetEntryTextAt := MkpTranslate(Raw, GetMkpFormat, mfPlain, [moHeadings, moBreaks])
  Else GetEntryTextAt := StripMarkup(Raw, GetMarkup);
  End;

Function AbsDictObj.IsStrongs: Boolean;
  Begin
  IsStrongs := StrongsKeys;
  End;

Function AbsDictObj.GetStrongsPrefix: Char;
  Begin
  GetStrongsPrefix := StrongsPre;
  End;

Procedure AbsDictObj.SetStrongs(On: Boolean; Prefix: Char);
  Begin
  StrongsKeys := On;
  StrongsPre := Prefix;
  End;


{---------------------------------------------------------------- finding}

Function AbsDictObj.KeysMatch(A, B: BibStr): Boolean;
  Var
    PA, PB: Char;
    NA, NB: LongInt;
    SA, SB: BibStr;
  Begin
  KeysMatch := True;
  If UpperCase(Trim(A)) = UpperCase(Trim(B)) Then Exit;
  If StrongsKeys Or (StrongsPre <> #0) Then
    If StrongsKeyParts(A, PA, NA, SA) And StrongsKeyParts(B, PB, NB, SB) Then
      Begin
      If PA = #0 Then PA := StrongsPre;
      If PB = #0 Then PB := StrongsPre;
      If (NA = NB) And (SA = SB) And ((PA = PB) Or (PA = #0) Or (PB = #0)) Then Exit;
      End;
  KeysMatch := False;
  End;

Function AbsDictObj.FindKey(Key: String): LongInt;
  Var i: LongInt;
  Begin
  FindKey := 0;
  For i := 1 To KeyCount Do
    If KeysMatch(Keys^[i], Key) Then
      Begin
      FindKey := i;
      Exit;
      End;
  End;

Function AbsDictObj.FindKeyPrefix(Prefix: String): LongInt;
  Var
    i: LongInt;
    P: BibStr;
  Begin
  FindKeyPrefix := 0;
  P := UpperCase(Prefix);
  For i := 1 To KeyCount Do
    If Copy(UpperCase(Keys^[i]), 1, Length(P)) = P Then
      Begin
      FindKeyPrefix := i;
      Exit;
      End;
  End;


{---------------------------------------------------------------- navigation}

Procedure AbsDictObj.SeekIndex(Idx: LongInt);
  Begin
  If (Idx >= 1) And (Idx <= KeyCount) Then
    Begin
    CurIdx := Idx;
    Found := True;
    End
  Else Found := False;
  End;

Procedure AbsDictObj.SeekFirst;
  Begin
  SeekIndex(1);
  End;

Procedure AbsDictObj.SeekLast;
  Begin
  SeekIndex(KeyCount);
  End;

Procedure AbsDictObj.SeekNext;
  Begin
  If CurIdx + 1 <= KeyCount Then SeekIndex(CurIdx + 1) Else Found := False;
  End;

Procedure AbsDictObj.SeekPrior;
  Begin
  If CurIdx - 1 >= 1 Then SeekIndex(CurIdx - 1) Else Found := False;
  End;

Procedure AbsDictObj.SeekKey(Key: String);
  Var I: LongInt;
  Begin
  I := FindKey(Key);
  If I = 0 Then I := FindKeyPrefix(Key);
  SeekIndex(I);
  End;

Function AbsDictObj.SeekFound: Boolean;
  Begin
  SeekFound := Found;
  End;

Function AbsDictObj.GetCurIndex: LongInt;
  Begin
  GetCurIndex := CurIdx;
  End;

Function AbsDictObj.GetKey: BibStr;
  Begin
  If Found Then GetKey := GetKeyAt(CurIdx) Else GetKey := '';
  End;

Function AbsDictObj.GetEntry: BibStr;
  Begin
  If Found Then GetEntry := GetEntryAt(CurIdx) Else GetEntry := '';
  End;

Function AbsDictObj.GetEntryText: BibStr;
  Begin
  If Found Then GetEntryText := GetEntryTextAt(CurIdx) Else GetEntryText := '';
  End;


{---------------------------------------------------------------- searching}

Function AbsDictObj.NextMatch(Start: LongInt): Boolean;
  Var
    i: LongInt;
    Pat, T: BibStr;
  Begin
  NextMatch := False;
  Pat := SrchTxt;
  If Not SrchCase Then Pat := LowerCase(Pat);
  For i := Start To KeyCount Do
    Begin
    If SrchScope In [dsKeys, dsBoth] Then
      Begin
      T := Keys^[i];
      If Not SrchCase Then T := LowerCase(T);
      If Pos(Pat, T) > 0 Then
        Begin
        SeekIndex(i);
        NextMatch := True;
        Exit;
        End;
      End;
    If SrchScope In [dsText, dsBoth] Then
      Begin
      T := GetEntryTextAt(i);
      If Not SrchCase Then T := LowerCase(T);
      If Pos(Pat, T) > 0 Then
        Begin
        SeekIndex(i);
        NextMatch := True;
        Exit;
        End;
      End;
    End;
  Found := False;
  End;

Procedure AbsDictObj.SearchFirst(Txt: String; CaseSens: Boolean; Scope: DictScope);
  Begin
  SrchTxt := Txt;
  SrchCase := CaseSens;
  SrchScope := Scope;
  If Txt = '' Then SrchFound := False
  Else SrchFound := NextMatch(1);
  End;

Procedure AbsDictObj.SearchNext;
  Begin
  If (SrchTxt = '') Or (Not SrchFound) Then SrchFound := False
  Else SrchFound := NextMatch(CurIdx + 1);
  End;

Function AbsDictObj.SearchFound: Boolean;
  Begin
  SearchFound := SrchFound;
  End;


{---------------------------------------------------------------- writing}

Function AbsDictObj.PutEntry(Key: String; Const Txt: BibStr): Boolean;
  Var I: LongInt;
  Begin
  PutEntry := False;
  If Key = '' Then Exit;
  I := 0;
  While I < KeyCount Do
    Begin
    Inc(I);
    If UpperCase(Keys^[I]) = UpperCase(Key) Then
      Begin
      If Texts <> Nil Then Texts^[I] := Txt;
      PutEntry := True;
      Exit;
      End;
    End;
  AddEntry(Key, Txt);
  PutEntry := True;
  End;

End.
