Unit MKDicSwd;       {Sword dictionary / lexicon object (zLD modules)}

{$I MKBib.Def}

{
  MKDicSwd - descendant of AbsDictObj for Sword dictionaries (ModDrv=zLD): Strong's Greek and Hebrew,
  Easton, Nave, Smith ... A module is
      mods.d/name.conf      DataPath=./modules/lexdict/zld/name/dict   ModDrv=zLD   SourceType=TEI ...
      dict.idx    one 8 byte entry per key, in key order: start, size of the key's record in dict.dat
      dict.dat    per key:  KEY CR LF  block(4) entry(4)  CR LF     (the key is stored in upper case)
                  or        KEY CR LF  @LINK otherkey
      dict.zdx    one 8 byte entry per block: start, size of the block in dict.zdt
      dict.zdt    the blocks, compressed (ZIP, LZSS or bzip2): a count, (offset, size) pairs, the texts
  (layout from Sword's zstr.cpp / entriesblk.cpp, checked against Strong's Greek and Hebrew).

  Reading   SetBibPath(module name | .conf file | "<sword dir>|<name>"), OpenBible.  Keys are the
            upper case keys of the module; the text is returned as stored (TEI for Strong's).
  Writing   SetBibPath(output root), CreateBible(Name), PutEntry..., CloseBible.  Written modules use
            ZIP blocks of 200 entries, UTF-8, and the markup given by SetMarkup (SourceType).  Keys
            are stored upper case; entries whose keys differ only in case keep the last one.
            Strong's modules get Feature=GreekDef / HebrewDef (SetStrongs).
  Not supported: RawLD modules, enciphered modules, case sensitive modules, upper casing of
  non-ASCII keys (their order may then differ from what Sword sorts).
}

Interface

Uses MKBibMod, MKBibDic;

Type
  SwordDictObj = Object(AbsDictObj)
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
  Function  GetEntryAt(Idx: LongInt): BibStr; Virtual;
  Function  CreateBible(Name: String): Word; Virtual;
  Function  FlushBible: Word; Virtual;
  Function  IsWriting: Boolean; Virtual;
  Function  IsReadOnly: Boolean; Virtual;

  Public
  PathSpec, ConfPath, BaseDir, ModName, DataBase: BibStr;
  Conf: BibStr;
  Opened, WMode: Boolean;
  Comp: Integer;                     {0 zip, 1 lzss, 2 bzip2}
  Mk: BibMarkup;
  IdxData, DatData, ZdxData, ZdtData: Pointer;
  IdxSize, DatSize, ZdxSize, ZdtSize: LongInt;
  CBlk: LongInt;
  CBuf: BibStr;
  WRoot: BibStr;
  Function  LoadAll(Const Name: BibStr; Var P: Pointer; Var Size: LongInt): Boolean;
  Function  DatKeyAt(Start: LongInt): BibStr;
  Function  BlockText(Blk: LongInt): BibStr;
  Function  Inflate(Src: Pointer; Len: LongWord): BibStr;
  Procedure FreeData;
  End;

Type SwordDictPtr = ^SwordDictObj;

Implementation

Uses SysUtils, MKBibSwc, MKBibZ;

Function GetU32(P: Pointer; Ofs: LongInt): LongWord;
  Begin
  GetU32 := LEtoN(PLongWord(PByte(P) + Ofs)^);
  End;

Constructor SwordDictObj.Init;
  Begin
  AbsDictObj.Init;
  PathSpec := ''; ConfPath := ''; BaseDir := ''; ModName := ''; DataBase := ''; Conf := '';
  Opened := False; WMode := False;
  Comp := 0;
  Mk := bmGBF;
  IdxData := Nil; DatData := Nil; ZdxData := Nil; ZdtData := Nil;
  CBlk := -1; CBuf := '';
  MetaMarkup := bmTEI;
  End;

Destructor SwordDictObj.Done;
  Begin
  If Opened Or WMode Then CloseBible;
  AbsDictObj.Done;
  End;

Procedure SwordDictObj.SetBibPath(BP: String);
  Begin
  If Opened Or WMode Then CloseBible;
  PathSpec := BP;
  End;

Function SwordDictObj.LoadAll(Const Name: BibStr; Var P: Pointer; Var Size: LongInt): Boolean;
  Var
    F: File;
    SaveMode: Byte;
  Begin
  LoadAll := False;
  P := Nil; Size := 0;
  SaveMode := FileMode;
  FileMode := 0;
  Assign(F, Name);
  Reset(F, 1);
  FileMode := SaveMode;
  If IOResult <> 0 Then Exit;
  Size := FileSize(F);
  If Size > 0 Then
    Begin
    GetMem(P, Size);
    BlockRead(F, P^, Size);
    If IOResult <> 0 Then
      Begin
      FreeMem(P, Size);
      P := Nil;
      Close(F);
      Exit;
      End;
    End;
  Close(F);
  LoadAll := True;
  End;

Procedure SwordDictObj.FreeData;
  Begin
  If IdxData <> Nil Then FreeMem(IdxData, IdxSize);
  If DatData <> Nil Then FreeMem(DatData, DatSize);
  If ZdxData <> Nil Then FreeMem(ZdxData, ZdxSize);
  If ZdtData <> Nil Then FreeMem(ZdtData, ZdtSize);
  IdxData := Nil; DatData := Nil; ZdxData := Nil; ZdtData := Nil;
  CBlk := -1; CBuf := '';
  End;

Function SwordDictObj.BibleExists: Boolean;
  Var A, B, C, D: BibStr;
  Begin
  BibleExists := Opened Or ((PathSpec <> '') And SwcFindConf(PathSpec, A, B, C, D));
  End;

Function SwordDictObj.IsOpen: Boolean;
  Begin
  IsOpen := Opened;
  End;

{ the key stored at a dat offset: up to a CR, LF or backslash }
Function SwordDictObj.DatKeyAt(Start: LongInt): BibStr;
  Var
    E: LongInt;
    R: BibStr;
    C: Byte;
  Begin
  E := Start;
  While (E < DatSize) Do
    Begin
    C := (PByte(DatData) + E)^;
    If (C = 10) Or (C = 13) Or (C = Ord('\')) Then Break;
    Inc(E);
    End;
  SetLength(R, E - Start);
  If E > Start Then Move((PByte(DatData) + Start)^, R[1], E - Start);
  DatKeyAt := R;
  End;

Function SwordDictObj.OpenBible: Word;
  Var
    DP, Drv, CT, Src, Feat: BibStr;
    i, N: LongInt;
    Start: LongWord;
  Begin
  If Opened Or WMode Then CloseBible;
  If PathSpec = '' Then
    Begin
    OpenBible := bibErrNoPath;
    Exit;
    End;
  If Not SwcFindConf(PathSpec, ConfPath, BaseDir, ModName, Conf) Then
    Begin
    OpenBible := bibErrNotFound;
    Exit;
    End;
  Drv := LowerCase(SwcGet(Conf, 'ModDrv'));
  If Drv <> 'zld' Then
    Begin
    OpenBible := bibErrUnsupported;
    Exit;
    End;
  If SwcHas(Conf, 'CipherKey') Then
    Begin
    OpenBible := bibErrLocked;
    Exit;
    End;
  CT := LowerCase(SwcGet(Conf, 'CompressType'));
  If CT = 'zip' Then Comp := 0
  Else If CT = 'bzip2' Then Comp := 2
  Else If (CT = 'lzss') Or (CT = '') Then Comp := 1
  Else
    Begin
    OpenBible := bibErrUnsupported;
    Exit;
    End;
  Src := LowerCase(SwcGet(Conf, 'SourceType'));
  If Src = 'osis' Then Mk := bmOSIS
  Else If Src = 'thml' Then Mk := bmThML
  Else If Src = 'tei' Then Mk := bmTEI
  Else If Src = 'plain' Then Mk := bmPlain
  Else Mk := bmGBF;
  DP := SwcGet(Conf, 'DataPath');
  If Copy(DP, 1, 2) = './' Then DP := Copy(DP, 3, 255);
  If (DP <> '') And (DP[1] <> '/') Then DataBase := BaseDir + DP Else DataBase := DP;
  If Not (LoadAll(DataBase + '.idx', IdxData, IdxSize) And LoadAll(DataBase + '.dat', DatData, DatSize) And
          LoadAll(DataBase + '.zdx', ZdxData, ZdxSize) And LoadAll(DataBase + '.zdt', ZdtData, ZdtSize)) Then
    Begin
    FreeData;
    OpenBible := bibErrNotFound;
    Exit;
    End;
  ClearEntries;
  N := IdxSize Div 8;
  For i := 0 To N - 1 Do
    Begin
    Start := GetU32(IdxData, i * 8);
    If Start < LongWord(DatSize) Then AddKey(DatKeyAt(Start)) Else AddKey('');
    End;
  Feat := LowerCase(SwcGet(Conf, 'Feature'));
  StrongsKeys := False; StrongsPre := #0;
  If Pos('greekdef', Feat) > 0 Then Begin StrongsKeys := True; StrongsPre := 'G'; End
  Else If Pos('hebrewdef', Feat) > 0 Then Begin StrongsKeys := True; StrongsPre := 'H'; End;
  MetaMarkup := Mk;
  Opened := True;
  SeekFirst;
  OpenBible := bibOk;
  End;

Function SwordDictObj.CloseBible: Word;
  Begin
  If WMode Then
    Begin
    CloseBible := FlushBible;
    Exit;
    End;
  FreeData;
  ClearEntries;
  Opened := False;
  CloseBible := bibOk;
  End;

Function SwordDictObj.GetName: String;
  Begin
  If WMode Then GetName := AbsModObj.GetName Else GetName := ModName;
  End;

Function SwordDictObj.GetDescription: String;
  Begin
  If WMode Then GetDescription := AbsModObj.GetDescription Else GetDescription := SwcGet(Conf, 'Description');
  End;

Function SwordDictObj.GetAbout: BibStr;
  Var A: BibStr;
      i: LongInt;
  Begin
  If WMode Then
    Begin
    GetAbout := AbsModObj.GetAbout;
    Exit;
    End;
  A := SwcGet(Conf, 'About');
  i := Pos('\par', A);
  While i > 0 Do
    Begin
    Delete(A, i, 4);
    Insert(#10, A, i);
    i := Pos('\par', A);
    End;
  GetAbout := A;
  End;

Function SwordDictObj.GetLang: String;
  Begin
  If WMode Then GetLang := AbsModObj.GetLang Else GetLang := SwcGet(Conf, 'Lang');
  End;

Function SwordDictObj.GetVersion: String;
  Begin
  If WMode Then GetVersion := AbsModObj.GetVersion Else GetVersion := SwcGet(Conf, 'Version');
  End;

Function SwordDictObj.GetCopyright: String;
  Var S: String;
  Begin
  If WMode Then
    Begin
    GetCopyright := AbsModObj.GetCopyright;
    Exit;
    End;
  S := SwcGet(Conf, 'ShortCopyright');
  If S = '' Then S := SwcGet(Conf, 'Copyright');
  If S = '' Then S := SwcGet(Conf, 'DistributionLicense');
  GetCopyright := S;
  End;

Function SwordDictObj.GetMarkup: BibMarkup;
  Begin
  If WMode Then GetMarkup := MetaMarkup Else GetMarkup := Mk;
  End;

{ decompress a block; the size is not stored, so retry with a bigger buffer }
Function SwordDictObj.Inflate(Src: Pointer; Len: LongWord): BibStr;
  Var
    Cap, L: LongWord;
    Res: Integer;
    R: BibStr;
  Begin
  Inflate := '';
  Cap := Len * 8 + 4096;
  While Cap < 256 * 1024 * 1024 Do
    Begin
    SetLength(R, Cap);
    L := Cap;
    Case Comp Of
      0: Res := ZUncompress(Src, Len, @R[1], L);
      2: Res := BzUncompress(Src, Len, @R[1], L);
      Else Res := LzssUncompress(Src, Len, @R[1], L);
      End;
    If (Res = 0) And ((Comp <> 0) Or (L < Cap)) And (L < Cap) Then
      Begin
      SetLength(R, L);
      Inflate := R;
      Exit;
      End;
    If (Res <> 0) And (Comp = 0) And (L = 0) And (Cap > Len * 200) Then Exit;     {corrupt, not just too small}
    Cap := Cap * 4;
    End;
  End;

Function SwordDictObj.BlockText(Blk: LongInt): BibStr;
  Var
    S, Z: LongWord;
  Begin
  BlockText := '';
  If (Blk < 0) Or ((Blk + 1) * 8 > ZdxSize) Then Exit;
  If CBlk = Blk Then
    Begin
    BlockText := CBuf;
    Exit;
    End;
  S := GetU32(ZdxData, Blk * 8);
  Z := GetU32(ZdxData, Blk * 8 + 4);
  If (Z = 0) Or (S + Z > LongWord(ZdtSize)) Then Exit;
  CBuf := Inflate(PByte(ZdtData) + S, Z);
  CBlk := Blk;
  BlockText := CBuf;
  End;

Function SwordDictObj.GetEntryAt(Idx: LongInt): BibStr;
  Var
    Start, Size: LongWord;
    P, E, Depth: LongInt;
    Blk, Ent, Off, Sz: LongWord;
    B, Rec, Target: BibStr;
    Cur: LongInt;
  Begin
  GetEntryAt := '';
  If (Not Opened) Or (Idx < 1) Or (Idx > KeyCount) Then Exit;
  Cur := Idx;
  For Depth := 1 To 8 Do                              {@LINK entries point at another key}
    Begin
    Start := GetU32(IdxData, (Cur - 1) * 8);
    Size := GetU32(IdxData, (Cur - 1) * 8 + 4);
    If (Start >= LongWord(DatSize)) Or (Start + Size > LongWord(DatSize)) Then Exit;
    SetLength(Rec, Size);
    If Size > 0 Then Move((PByte(DatData) + Start)^, Rec[1], Size);
    P := Pos(#10, Rec);                               {the key line ends at the LF}
    If P = 0 Then Exit;
    If Copy(Rec, P + 1, 5) = '@LINK' Then
      Begin
      Target := Copy(Rec, P + 7, Length(Rec));
      E := 1;
      While (E <= Length(Target)) And (Not (Target[E] In [#13, #10, #0])) Do Inc(E);
      Target := Copy(Target, 1, E - 1);
      Cur := FindKey(Target);
      If Cur = 0 Then Exit;
      Continue;
      End;
    If Length(Rec) < P + 8 Then Exit;
    Blk := GetU32(@Rec[P + 1], 0);
    Ent := GetU32(@Rec[P + 1], 4);
    B := BlockText(Blk);
    If Length(B) < 4 Then Exit;
    If Ent >= GetU32(@B[1], 0) Then Exit;
    Off := GetU32(@B[1], 4 + Ent * 8);
    Sz := GetU32(@B[1], 4 + Ent * 8 + 4);
    If (Off = 0) Or (Off + Sz > LongWord(Length(B))) Then Exit;
    If Sz > 0 Then Dec(Sz);                           {the stored size counts the closing NUL}
    GetEntryAt := Copy(B, Off + 1, Sz);
    Exit;
    End;
  End;


{---------------------------------------------------------------- writing}

Function SwordDictObj.IsWriting: Boolean;
  Begin
  IsWriting := WMode;
  End;

Function SwordDictObj.IsReadOnly: Boolean;
  Begin
  IsReadOnly := Not WMode;
  End;

Function SwordDictObj.CreateBible(Name: String): Word;
  Var i: Word;
  Begin
  If Opened Or WMode Then CloseBible;
  CreateBible := bibErrCreate;
  If Name = '' Then Exit;
  For i := 1 To Length(Name) Do
    If Not (Name[i] In ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.']) Then Exit;
  If PathSpec = '' Then WRoot := './' Else WRoot := SwcAddSlash(PathSpec);
  ModName := Name;
  MetaName := Name;
  ConfPath := WRoot + 'mods.d/' + LowerCase(Name) + '.conf';
  If FileExists(ConfPath) And (Not Overwrite) Then
    Begin
    CreateBible := bibErrExists;
    Exit;
    End;
  If (Not ForceDirectories(WRoot + 'mods.d')) Or
     (Not ForceDirectories(WRoot + 'modules/lexdict/zld/' + LowerCase(Name))) Then Exit;
  ClearEntries;
  WMode := True;
  CreateBible := bibOk;
  End;

Procedure PutLE32(Var S: BibStr; V: LongWord);
  Begin
  S := S + Chr(V And $FF) + Chr((V Shr 8) And $FF) + Chr((V Shr 16) And $FF) + Chr((V Shr 24) And $FF);
  End;

Function SwordDictObj.FlushBible: Word;
  Const BlockCount = 200;
  Var
    Dat, Idx, Zdx, Zdt, Blk, TxtBlk, Meta, Cmp, Key, Prev, C: BibStr;
    i, j, InBlock, BlockNo: LongInt;
    Last: Array[1..BlockCount] Of LongInt;
    Off: LongWord;
    DL: LongWord;
    Res: Integer;
    Base, SrcT, Feat, Ab: BibStr;
    Fc: File;
    Written: LongInt;

  Procedure FlushBlock;
    Var k: LongInt;
    Begin
    If InBlock = 0 Then Exit;
    { EntriesBlock: count, (offset, size) per entry, then the texts, each ended by a NUL }
    Meta := '';
    TxtBlk := '';
    PutLE32(Meta, InBlock);
    Off := 4 + 8 * InBlock;
    For k := 1 To InBlock Do
      Begin
      PutLE32(Meta, Off);
      PutLE32(Meta, Length(Texts^[Last[k]]) + 1);
      Inc(Off, Length(Texts^[Last[k]]) + 1);
      TxtBlk := TxtBlk + Texts^[Last[k]] + #0;
      End;
    Blk := Meta + TxtBlk;
    SetLength(Cmp, Length(Blk) + Length(Blk) Div 10 + 64);
    DL := Length(Cmp);
    Res := ZCompress(@Blk[1], Length(Blk), @Cmp[1], DL);
    SetLength(Cmp, DL);
    PutLE32(Zdx, Length(Zdt));
    PutLE32(Zdx, DL);
    Zdt := Zdt + Cmp;
    InBlock := 0;
    Inc(BlockNo);
    End;

  Begin
  FlushBible := bibOk;
  If Not WMode Then Exit;
  SortEntries;
  Dat := ''; Idx := ''; Zdx := ''; Zdt := '';
  InBlock := 0; BlockNo := 0;
  Prev := '';
  Written := 0;
  For i := 1 To KeyCount Do
    Begin
    Key := UpperCase(Keys^[i]);
    If (i < KeyCount) And (UpperCase(Keys^[i + 1]) = Key) Then Continue;        {a later entry with the same key wins}
    If InBlock >= BlockCount Then FlushBlock;
    Inc(InBlock);
    Last[InBlock] := i;
    PutLE32(Idx, Length(Dat));
    C := Key + #13#10;
    PutLE32(C, BlockNo);
    PutLE32(C, InBlock - 1);
    PutLE32(Idx, Length(C));
    Dat := Dat + C + #13#10;
    Inc(Written);
    End;
  FlushBlock;
  Base := WRoot + 'modules/lexdict/zld/' + LowerCase(ModName) + '/dict';
  For j := 1 To 4 Do
    Begin
    Case j Of
      1: Begin Assign(Fc, Base + '.dat'); C := Dat; End;
      2: Begin Assign(Fc, Base + '.idx'); C := Idx; End;
      3: Begin Assign(Fc, Base + '.zdx'); C := Zdx; End;
      Else Begin Assign(Fc, Base + '.zdt'); C := Zdt; End;
      End;
    Rewrite(Fc, 1);
    If IOResult <> 0 Then
      Begin
      FlushBible := bibErrIO;
      WMode := False;
      Exit;
      End;
    If Length(C) > 0 Then BlockWrite(Fc, C[1], Length(C));
    Close(Fc);
    End;
  { the conf }
  Case MetaMarkup Of
    bmOSIS: SrcT := 'OSIS';
    bmThML: SrcT := 'ThML';
    bmGBF: SrcT := 'GBF';
    bmTEI: SrcT := 'TEI';
    Else SrcT := 'Plain';
    End;
  Feat := '';
  If StrongsKeys Then
    Begin
    If StrongsPre = 'H' Then Feat := 'HebrewDef' Else Feat := 'GreekDef';
    End;
  C := '[' + ModName + ']'#10'DataPath=./modules/lexdict/zld/' + LowerCase(ModName) + '/dict'#10'ModDrv=zLD'#10 +
       'Encoding=UTF-8'#10'SourceType=' + SrcT + #10'CompressType=ZIP'#10;
  If MetaLang <> '' Then C := C + 'Lang=' + MetaLang + #10;
  If MetaDesc <> '' Then C := C + 'Description=' + MetaDesc + #10;
  If MetaVer <> '' Then C := C + 'Version=' + MetaVer + #10;
  If MetaCopy <> '' Then C := C + 'DistributionLicense=' + MetaCopy + #10;
  If Feat <> '' Then C := C + 'Feature=' + Feat + #10;
  If MetaAbout <> '' Then
    Begin
    Ab := '';
    For i := 1 To Length(MetaAbout) Do
      Case MetaAbout[i] Of
        #13: ;
        #10: Ab := Ab + '\par ';
        Else Ab := Ab + MetaAbout[i];
        End;
    C := C + 'About=' + Ab + #10;
    End;
  Assign(Fc, ConfPath);
  Rewrite(Fc, 1);
  If IOResult <> 0 Then
    Begin
    FlushBible := bibErrIO;
    WMode := False;
    Exit;
    End;
  BlockWrite(Fc, C[1], Length(C));
  Close(Fc);
  ClearEntries;
  WMode := False;
  End;

End.
