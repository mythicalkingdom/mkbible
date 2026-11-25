Unit MKDicAny;       {Pick the right dictionary object for a path}

{$I MKBib.Def}

Interface

Uses MKBibMod, MKBibDic, MKDicSwd, MKDicMys, MKDicTwd;

Type DictKind = (dkSword, dkMySword, dkTheWord);

Function DetectDictKind(Path: String): DictKind;
  {.dct.mybible -> MySword;  .dct.twm -> theWord;  anything else -> Sword (module name or .conf)}
Function NewDictObj(Path: String): AbsDictPtr;
  {A new object of the right kind with SetBibPath(Path) done.}
Procedure FreeDictObj(Var D: AbsDictPtr);

Implementation

Uses SysUtils;

Function DetectDictKind(Path: String): DictKind;
  Var L: String;
  Begin
  L := LowerCase(Path);
  If Pos('.dct.mybible', L) > 0 Then DetectDictKind := dkMySword
  Else If Pos('.twm', L) > 0 Then DetectDictKind := dkTheWord
  Else DetectDictKind := dkSword;
  End;

Function NewDictObj(Path: String): AbsDictPtr;
  Var
    S: SwordDictPtr;
    M: MySwordDictPtr;
    W: TheWordDictPtr;
  Begin
  If DetectDictKind(Path) = dkMySword Then Begin New(M, Init); NewDictObj := M; End
  Else If DetectDictKind(Path) = dkTheWord Then Begin New(W, Init); NewDictObj := W; End
  Else Begin New(S, Init); NewDictObj := S; End;
  NewDictObj^.SetBibPath(Path);
  End;

Procedure FreeDictObj(Var D: AbsDictPtr);
  Begin
  If D <> Nil Then
    Begin
    D^.Done;
    FreeMem(D);
    D := Nil;
    End;
  End;

End.
