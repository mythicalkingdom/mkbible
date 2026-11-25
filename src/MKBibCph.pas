Unit MKBibCph;       {Sword module cipher: Sapphire II stream cipher + key personalization}

{$I MKBib.Def}

{
  Enciphered ("locked") Sword modules encrypt every compressed block with the
  Sapphire II stream cipher (Michael Paul Johnson, public domain).  The key is the
  module's CipherKey, which for purchased modules is an "unlock key" of the form
  AAAA-BBBB-CCCC-DDDD-CHECK that Sword "personalizes" before using it.  A key that
  is not in that form (wrong segment count, bad checksum) is used as it is.
  Ported from sapphire.cpp and swcipher.cpp of the Sword project.
}

Interface

Type
  SapphireRec = Record
    Cards: Array[0..255] Of Byte;
    Rotor, Ratchet, Avalanche, LastPlain, LastCipher: Byte;
  End;

Procedure SapInit(Var Z: SapphireRec; Const Key: String);   {key may be up to 255 bytes}
Function  SapEncrypt(Var Z: SapphireRec; B: Byte): Byte;
Function  SapDecrypt(Var Z: SapphireRec; B: Byte): Byte;

Function  CipherPersonalize(Const Key: String; Encode: Boolean): String;
  {Sword's SWCipher::personalize; when decoding, an invalid key is returned unchanged}
Procedure CipherSetKey(Var Master: SapphireRec; Const UnlockKey: String);
  {Master := state for this unlock key (personalized as Sword does)}
Procedure CipherDecryptBuf(Const Master: SapphireRec; Buf: PByte; Len: LongWord);
Procedure CipherEncryptBuf(Const Master: SapphireRec; Buf: PByte; Len: LongWord);
  {each call starts from the Master state, as Sword does for each buffer}

Implementation

Const
  Lats: String[62] = 'bceafgijkl' + 'hmpqBrHost' + 'TuwxyAdCDz' + 'EFIJKGLNO7' + 'PQMRSUVWXY' +
                     '9012Z364n8' + 'v5';

Function KeyRand(Var Z: SapphireRec; Limit: Integer; Const UKey: String; KeySize: Integer;
                 Var RSum: Byte; Var KeyPos: Integer): Byte;
  Var
    U, Retry, Mask: LongWord;
  Begin
  If Limit = 0 Then
    Begin
    KeyRand := 0;
    Exit;
    End;
  Retry := 0;
  Mask := 1;
  While Mask < LongWord(Limit) Do Mask := (Mask Shl 1) + 1;
  Repeat
    RSum := Byte(Z.Cards[RSum] + Ord(UKey[KeyPos + 1]));
    Inc(KeyPos);
    If KeyPos >= KeySize Then
      Begin
      KeyPos := 0;
      RSum := Byte(RSum + KeySize);
      End;
    U := Mask And RSum;
    Inc(Retry);
    If Retry > 11 Then U := U Mod LongWord(Limit);
  Until U <= LongWord(Limit);
  KeyRand := Byte(U);
  End;

Procedure SapInit(Var Z: SapphireRec; Const Key: String);
  Var
    I: Integer;
    ToSwap, SwapTemp, RSum: Byte;
    KeyPos: Integer;
  Begin
  If Length(Key) < 1 Then
    Begin
    Z.Rotor := 1; Z.Ratchet := 3; Z.Avalanche := 5; Z.LastPlain := 7; Z.LastCipher := 11;
    For I := 0 To 255 Do Z.Cards[I] := 255 - I;
    Exit;
    End;
  For I := 0 To 255 Do Z.Cards[I] := I;
  KeyPos := 0;
  RSum := 0;
  For I := 255 DownTo 0 Do
    Begin
    ToSwap := KeyRand(Z, I, Key, Length(Key), RSum, KeyPos);
    SwapTemp := Z.Cards[I];
    Z.Cards[I] := Z.Cards[ToSwap];
    Z.Cards[ToSwap] := SwapTemp;
    End;
  Z.Rotor := Z.Cards[1];
  Z.Ratchet := Z.Cards[3];
  Z.Avalanche := Z.Cards[5];
  Z.LastPlain := Z.Cards[7];
  Z.LastCipher := Z.Cards[RSum];
  End;

Procedure Shuffle(Var Z: SapphireRec);
  Var SwapTemp: Byte;
  Begin
  Z.Ratchet := Byte(Z.Ratchet + Z.Cards[Z.Rotor]);
  Z.Rotor := Byte(Z.Rotor + 1);
  SwapTemp := Z.Cards[Z.LastCipher];
  Z.Cards[Z.LastCipher] := Z.Cards[Z.Ratchet];
  Z.Cards[Z.Ratchet] := Z.Cards[Z.LastPlain];
  Z.Cards[Z.LastPlain] := Z.Cards[Z.Rotor];
  Z.Cards[Z.Rotor] := SwapTemp;
  Z.Avalanche := Byte(Z.Avalanche + Z.Cards[SwapTemp]);
  End;

Function SapEncrypt(Var Z: SapphireRec; B: Byte): Byte;
  Begin
  Shuffle(Z);
  Z.LastCipher := B Xor Z.Cards[Byte(Z.Cards[Z.Ratchet] + Z.Cards[Z.Rotor])] Xor
    Z.Cards[Z.Cards[Byte(Z.Cards[Z.LastPlain] + Z.Cards[Z.LastCipher] + Z.Cards[Z.Avalanche])]];
  Z.LastPlain := B;
  SapEncrypt := Z.LastCipher;
  End;

Function SapDecrypt(Var Z: SapphireRec; B: Byte): Byte;
  Begin
  Shuffle(Z);
  Z.LastPlain := B Xor Z.Cards[Byte(Z.Cards[Z.Ratchet] + Z.Cards[Z.Rotor])] Xor
    Z.Cards[Z.Cards[Byte(Z.Cards[Z.LastPlain] + Z.Cards[Z.LastCipher] + Z.Cards[Z.Avalanche])]];
  Z.LastCipher := B;
  SapDecrypt := Z.LastPlain;
  End;


Function CipherPersonalize(Const Key: String; Encode: Boolean): String;
  Var
    Segs: Array[0..4] Of String;
    SegN, I, J, CSum: Integer;
    Hash, Obfus: Integer;
    Result_, ChkSum: String;
    Hashes: Array[Char] Of ShortInt;
    P: Integer;
  Begin
  FillChar(Hashes, SizeOf(Hashes), 0);
  For I := 0 To 61 Do Hashes[Lats[I + 1]] := I;     {a later duplicate would win, as std::map does}
  For I := 0 To 4 Do Segs[I] := '';
  SegN := 0;
  I := 1;
  While (I <= Length(Key)) And (SegN < 5) Do
    Begin
    If Key[I] = '-' Then Inc(SegN)
    Else Segs[SegN] := Segs[SegN] + Key[I];
    Inc(I);
    End;
  Result_ := '';
  ChkSum := Segs[4];
  If Length(Segs[4]) < 5 Then
    Begin
    While Length(Segs[4]) < 4 Do Segs[4] := Segs[4] + #0;
    SetLength(Segs[4], 4);
    End;
  For I := 0 To 3 Do
    Begin
    CSum := 0;
    For J := 1 To Length(Segs[I]) Do
      Begin
      If J > Length(Segs[0]) Then Break;
      Hash := Hashes[Segs[I][J]];
      P := ((J - 1) Mod Length(Segs[0])) + 1;
      Obfus := Hashes[Segs[0][P]];
      If Encode Then
        Begin
        If I > 0 Then Obfus := Hash - Obfus Else Obfus := Hash;
        If Obfus < 0 Then Obfus := 62 + Obfus;
        End
      Else
        Begin
        If I > 0 Then Obfus := Hash + Obfus Else Obfus := Hash;
        Obfus := Obfus Mod 62;
        End;
      If I > 0 Then Segs[I][J] := Lats[Obfus + 1];
      If Encode Then Inc(CSum, Obfus) Else Inc(CSum, Hash);
      End;
    Segs[4][I + 1] := Lats[(CSum Mod 62) + 1];
    If Result_ <> '' Then Result_ := Result_ + '-';
    If Encode Or (I > 0) Then Result_ := Result_ + Segs[I];
    End;
  If Encode Then Result_ := Result_ + '-' + Segs[4];
  If (Not Encode) And (ChkSum <> Segs[4]) Then CipherPersonalize := Key
  Else CipherPersonalize := Result_;
  End;

Procedure CipherSetKey(Var Master: SapphireRec; Const UnlockKey: String);
  Begin
  SapInit(Master, CipherPersonalize(UnlockKey, False));
  End;

Procedure CipherDecryptBuf(Const Master: SapphireRec; Buf: PByte; Len: LongWord);
  Var
    Work: SapphireRec;
    I: LongWord;
  Begin
  Work := Master;
  For I := 0 To Len - 1 Do
    Begin
    Buf^ := SapDecrypt(Work, Buf^);
    Inc(Buf);
    End;
  End;

Procedure CipherEncryptBuf(Const Master: SapphireRec; Buf: PByte; Len: LongWord);
  Var
    Work: SapphireRec;
    I: LongWord;
  Begin
  Work := Master;
  For I := 0 To Len - 1 Do
    Begin
    Buf^ := SapEncrypt(Work, Buf^);
    Inc(Buf);
    End;
  End;

End.
