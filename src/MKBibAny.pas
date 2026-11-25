Unit MKBibAny;       {Pick the right Bible object for a path}

{$I MKBib.Def}

Interface

Uses MKBibMod, MKBibAbs, MKBibSwd, MKBibMys, MKBibStp, MKBibTwd, MKBibVpl, MKBibOsi, MKBibZef, MKBibUfx, MKBibUsf;

Type BibKind = (bkSword, bkMySword, bkStep, bkTheWord, bkVpl, bkOsis, bkZefania, bkUsfx, bkUsfm);

Function DetectBibKind(Path: String): BibKind;
  {.mybible file -> MySword;  .ont / .ot / .nt / .ontx file -> theWord;  .vpl file -> verse per line;
   directory holding Book.dat (any case) -> STEP;  directory with .usfm / .sfm files, one such file or a
   .zip -> USFM;  an .xml / .osis file whose start has <osis, <XMLBIBLE or <usfx -> OSIS / Zefania / USFX;
   anything else -> Sword}
Function NewBibObj(Path: String): AbsBibPtr;
  {A new, initialised object of the right kind with SetBibPath(Path) done.  Dispose with FreeBibObj.}
Procedure FreeBibObj(Var B: AbsBibPtr);

Implementation

Uses SysUtils;

{ the first 3 KB of a file, lower case, for telling the XML Bible formats apart }
Function Sniff(Const Path: String): BibStr;
  Var
    F: File;
    Buf: BibStr;
    N: LongInt;
    SaveMode: Byte;
  Begin
  Sniff := '';
  SaveMode := FileMode;
  FileMode := 0;
  Assign(F, Path);
  Reset(F, 1);
  FileMode := SaveMode;
  If IOResult <> 0 Then Exit;
  SetLength(Buf, 3000);
  BlockRead(F, Buf[1], 3000, N);
  Close(F);
  SetLength(Buf, N);
  Sniff := LowerCase(Buf);
  End;

Function HasUsfmFiles(Dir: String): Boolean;
  Var
    SR: TSearchRec;
    E: String;
    Hit: Boolean;
  Begin
  Hit := False;
  If Dir[Length(Dir)] <> '/' Then Dir := Dir + '/';
  If FindFirst(Dir + '*', faAnyFile, SR) = 0 Then
    Begin
    Repeat
      E := LowerCase(ExtractFileExt(SR.Name));
      If (E = '.usfm') Or (E = '.sfm') Then Hit := True;
    Until Hit Or (FindNext(SR) <> 0);
    FindClose(SR);
    End;
  HasUsfmFiles := Hit;
  End;

Function DetectBibKind(Path: String): BibKind;
  Var
    SR: TSearchRec;
    Head: BibStr;
    Kind: BibKind;
  Begin
  Kind := bkSword;
  If Pos('mybible', LowerCase(Path)) > 0 Then
    Kind := bkMySword
  Else If (Not DirectoryExists(Path)) And (Pos(LowerCase(ExtractFileExt(Path)), '.ont.ontx.ot.nt') > 0) And (ExtractFileExt(Path) <> '') Then
    Kind := bkTheWord
  Else If (Not DirectoryExists(Path)) And (LowerCase(ExtractFileExt(Path)) = '.vpl') Then
    Kind := bkVpl
  Else If (Not DirectoryExists(Path)) And ((LowerCase(ExtractFileExt(Path)) = '.usfm') Or (LowerCase(ExtractFileExt(Path)) = '.sfm') Or
          (LowerCase(ExtractFileExt(Path)) = '.zip')) Then
    Kind := bkUsfm
  Else If (Not DirectoryExists(Path)) And FileExists(Path) And
          ((LowerCase(ExtractFileExt(Path)) = '.xml') Or (LowerCase(ExtractFileExt(Path)) = '.osis')) Then
    Begin
    Head := Sniff(Path);
    If Pos('<osis', Head) > 0 Then Kind := bkOsis
    Else If Pos('<xmlbible', Head) > 0 Then Kind := bkZefania
    Else If Pos('<usfx', Head) > 0 Then Kind := bkUsfx;
    End
  Else If DirectoryExists(Path) Then
    Begin
    If Path[Length(Path)] <> '/' Then Path := Path + '/';
    If FindFirst(Path + '*', faAnyFile, SR) = 0 Then
      Begin
      Repeat
        If LowerCase(SR.Name) = 'book.dat' Then
          Begin
          Kind := bkStep;
          Break;
          End;
      Until FindNext(SR) <> 0;
      FindClose(SR);
      End;
    If (Kind = bkSword) And (Not DirectoryExists(Path + 'mods.d')) And HasUsfmFiles(Path) Then Kind := bkUsfm;
    End;
  DetectBibKind := Kind;
  End;

Function NewBibObj(Path: String): AbsBibPtr;
  Var
    S: SwordBibPtr;
    M: MySwordBibPtr;
    T: StepBibPtr;
    W: TheWordBibPtr;
    P: VplBibPtr;
    O: OsisBibPtr;
    Z: ZefaniaBibPtr;
    X: UsfxBibPtr;
    U: UsfmBibPtr;
  Begin
  Case DetectBibKind(Path) Of
    bkMySword: Begin New(M, Init); NewBibObj := M; End;
    bkStep: Begin New(T, Init); NewBibObj := T; End;
    bkTheWord: Begin New(W, Init); NewBibObj := W; End;
    bkVpl: Begin New(P, Init); NewBibObj := P; End;
    bkOsis: Begin New(O, Init); NewBibObj := O; End;
    bkZefania: Begin New(Z, Init); NewBibObj := Z; End;
    bkUsfx: Begin New(X, Init); NewBibObj := X; End;
    bkUsfm: Begin New(U, Init); NewBibObj := U; End;
    Else Begin New(S, Init); NewBibObj := S; End;
    End;
  NewBibObj^.SetBibPath(Path);
  End;

Procedure FreeBibObj(Var B: AbsBibPtr);
  Begin
  If B <> Nil Then
    Begin
    B^.Done;
    FreeMem(B);
    B := Nil;
    End;
  End;

End.
