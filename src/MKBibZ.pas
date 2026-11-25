Unit MKBibZ;       {Compressors / decompressors for Sword modules: zlib, LZSS, bzip2 (read only)}

{$MODE OBJFPC}   {exceptions are needed for the bzip2 stream; the interface is plain procedural}
{$I-}{$R-}{$Q-}

Interface

{ All three: compressed bytes at Src -> Dst.  DstLen = room on entry, bytes written on exit.
  Result 0 = ok. }
Function ZUncompress(Src: Pointer; SrcLen: LongWord; Dst: Pointer; Var DstLen: LongWord): Integer;
Function LzssUncompress(Src: Pointer; SrcLen: LongWord; Dst: Pointer; Var DstLen: LongWord): Integer;
Function BzUncompress(Src: Pointer; SrcLen: LongWord; Dst: Pointer; Var DstLen: LongWord): Integer;

{ Compressors: DstLen = room on entry (zlib: at least SrcLen + SrcLen div 10 + 64,
  LZSS: at least SrcLen + SrcLen div 8 + 32), bytes written on exit.  Result 0 = ok. }
Function ZCompress(Src: Pointer; SrcLen: LongWord; Dst: Pointer; Var DstLen: LongWord): Integer;
Function LzssCompress(Src: Pointer; SrcLen: LongWord; Dst: Pointer; Var DstLen: LongWord): Integer;

Implementation

Uses Classes, zuncompr, zcompres, bzip2stream;

Type
  ByteArr = Array[0..0] Of Byte;
  ByteArrPtr = ^ByteArr;

Function ZUncompress(Src: Pointer; SrcLen: LongWord; Dst: Pointer; Var DstLen: LongWord): Integer;
  Begin
  ZUncompress := uncompress(PByte(Dst), DstLen, ByteArrPtr(Src)^, SrcLen);
  End;


{ Sword's LZSS (Haruhiko Okumura): 4096 byte ring buffer pre-filled with blanks,
  flag byte then 8 items, a set bit = literal byte, clear = 2 byte
  <12 bit position, 4 bit length-3> reference. }
Function LzssUncompress(Src: Pointer; SrcLen: LongWord; Dst: Pointer; Var DstLen: LongWord): Integer;
  Const
    N = 4096;
    F = 18;
    Threshold = 3;
  Var
    Ring: Array[0..N - 1] Of Byte;
    S, D: PByte;
    SEnd: PByte;
    Flags: Byte;
    FlagCount: Integer;
    R, Pos, Len, K: Integer;
    C0, C1: Byte;
    Cap: LongWord;
    OutN: LongWord;
  Begin
  FillChar(Ring, N - F, Ord(' '));
  R := N - F;
  S := PByte(Src);
  SEnd := S + SrcLen;
  D := PByte(Dst);
  Cap := DstLen;
  OutN := 0;
  Flags := 0;
  FlagCount := 0;
  LzssUncompress := 0;
  While True Do
    Begin
    If FlagCount > 0 Then
      Begin
      Flags := Flags Shr 1;
      Dec(FlagCount);
      End
    Else
      Begin
      If S >= SEnd Then Break;
      Flags := S^;
      Inc(S);
      FlagCount := 7;
      End;
    If (Flags And 1) <> 0 Then
      Begin
      If S >= SEnd Then Break;
      If OutN >= Cap Then Begin LzssUncompress := 1; Break; End;
      C0 := S^;
      Inc(S);
      D^ := C0;
      Inc(D);
      Inc(OutN);
      Ring[R] := C0;
      R := (R + 1) And (N - 1);
      End
    Else
      Begin
      If S + 1 >= SEnd Then Break;
      C0 := S^; Inc(S);
      C1 := S^; Inc(S);
      Pos := C0 Or ((C1 And $F0) Shl 4);
      Len := (C1 And $0F) + Threshold;
      If OutN + LongWord(Len) > Cap Then Begin LzssUncompress := 1; Break; End;
      For K := 0 To Len - 1 Do
        Begin
        C0 := Ring[(Pos + K) And (N - 1)];
        Ring[R] := C0;
        R := (R + 1) And (N - 1);
        D^ := C0;
        Inc(D);
        End;
      Inc(OutN, Len);
      End;
    End;
  DstLen := OutN;
  End;


Function BzUncompress(Src: Pointer; SrcLen: LongWord; Dst: Pointer; Var DstLen: LongWord): Integer;
  Var
    MS: TMemoryStream;
    BZ: TDecompressBzip2Stream;
    Got, Total: LongInt;
  Begin
  BzUncompress := 0;
  MS := TMemoryStream.Create;
  Try
    MS.Write(Src^, SrcLen);
    MS.Position := 0;
    Try
      BZ := TDecompressBzip2Stream.Create(MS);
      Try
        Total := 0;
        Repeat
          Got := BZ.Read((PByte(Dst) + Total)^, LongInt(DstLen) - Total);
          If Got > 0 Then Inc(Total, Got);
        Until (Got <= 0) Or (Total >= LongInt(DstLen));
        DstLen := Total;
      Finally
        BZ.Free;
      End;
    Except
      BzUncompress := 1;
    End;
  Finally
    MS.Free;
  End;
  End;


Function ZCompress(Src: Pointer; SrcLen: LongWord; Dst: Pointer; Var DstLen: LongWord): Integer;
  Begin
  ZCompress := compress2(PByte(Dst), DstLen, ByteArrPtr(Src)^, SrcLen, 6);   {Sword's level}
  End;


{ Sword's LZSS encoder (port of lzsscomprs.cpp, itself Haruhiko Okumura's): binary
  search trees over a 4096 byte ring buffer find the longest match of up to 18 bytes. }
Function LzssCompress(Src: Pointer; SrcLen: LongWord; Dst: Pointer; Var DstLen: LongWord): Integer;
  Const
    N = 4096;
    F = 18;
    Threshold = 3;
    NotUsed = N;
  Var
    Ring: Array[0..N + F - 2] Of Byte;
    LSon: Array[0..N] Of LongInt;
    RSon: Array[0..N + 256] Of LongInt;
    Dad: Array[0..N] Of LongInt;
    MatchPos, MatchLen: LongInt;
    InP: PByte;
    InLeft: LongWord;
    OutP: PByte;
    OutN, Cap: LongWord;
    CodeBuf: Array[0..16] Of Byte;
    CodePos: Integer;
    Mask, C: Byte;
    I, R, S, LastMatch: LongInt;
    Len: LongInt;
    Overflow: Boolean;

  Procedure InitTree;
    Var K: LongInt;
    Begin
    For K := 0 To N - 1 Do
      Begin
      LSon[K] := NotUsed; RSon[K] := NotUsed; Dad[K] := NotUsed;
      End;
    LSon[N] := NotUsed; Dad[N] := NotUsed;
    For K := N + 1 To N + 256 Do RSon[K] := NotUsed;
    RSon[N] := NotUsed;
    End;

  Procedure InsertNode(Pos: LongInt);
    Var
      K, P, Cmp: LongInt;
    Begin
    Cmp := 1;
    P := N + 1 + Ring[Pos];
    LSon[Pos] := NotUsed;
    RSon[Pos] := NotUsed;
    MatchLen := 0;
    While True Do
      Begin
      If Cmp >= 0 Then
        Begin
        If RSon[P] <> NotUsed Then P := RSon[P]
        Else
          Begin
          RSon[P] := Pos; Dad[Pos] := P;
          Exit;
          End;
        End
      Else
        Begin
        If LSon[P] <> NotUsed Then P := LSon[P]
        Else
          Begin
          LSon[P] := Pos; Dad[Pos] := P;
          Exit;
          End;
        End;
      K := 1;
      While K < F Do
        Begin
        Cmp := LongInt(Ring[Pos + K]) - LongInt(Ring[P + K]);
        If Cmp <> 0 Then Break;
        Inc(K);
        End;
      If K > MatchLen Then
        Begin
        MatchPos := P;
        MatchLen := K;
        If K >= F Then Break;
        End;
      End;
    Dad[Pos] := Dad[P];
    LSon[Pos] := LSon[P];
    RSon[Pos] := RSon[P];
    Dad[LSon[P]] := Pos;
    Dad[RSon[P]] := Pos;
    If RSon[Dad[P]] = P Then RSon[Dad[P]] := Pos
    Else LSon[Dad[P]] := Pos;
    Dad[P] := NotUsed;
    End;

  Procedure DeleteNode(Node: LongInt);
    Var Q: LongInt;
    Begin
    If Dad[Node] = NotUsed Then Exit;
    If RSon[Node] = NotUsed Then Q := LSon[Node]
    Else If LSon[Node] = NotUsed Then Q := RSon[Node]
    Else
      Begin
      Q := LSon[Node];
      If RSon[Q] <> NotUsed Then
        Begin
        Repeat
          Q := RSon[Q];
        Until RSon[Q] = NotUsed;
        RSon[Dad[Q]] := LSon[Q];
        Dad[LSon[Q]] := Dad[Q];
        LSon[Q] := LSon[Node];
        Dad[LSon[Node]] := Q;
        End;
      RSon[Q] := RSon[Node];
      Dad[RSon[Node]] := Q;
      End;
    Dad[Q] := Dad[Node];
    If RSon[Dad[Node]] = Node Then RSon[Dad[Node]] := Q
    Else LSon[Dad[Node]] := Q;
    Dad[Node] := NotUsed;
    End;

  Procedure Send(Const B: Array Of Byte; Cnt: Integer);
    Var K: Integer;
    Begin
    For K := 0 To Cnt - 1 Do
      Begin
      If OutN >= Cap Then Begin Overflow := True; Exit; End;
      OutP^ := B[K];
      Inc(OutP);
      Inc(OutN);
      End;
    End;

  Function GetChars(P: PByte; Cnt: LongInt): LongInt;
    Var K: LongInt;
    Begin
    K := 0;
    While (K < Cnt) And (InLeft > 0) Do
      Begin
      P[K] := InP^;
      Inc(InP);
      Dec(InLeft);
      Inc(K);
      End;
    GetChars := K;
    End;

  Begin
  LzssCompress := 0;
  Cap := DstLen;
  OutN := 0;
  Overflow := False;
  If SrcLen = 0 Then
    Begin
    DstLen := 0;
    Exit;
    End;
  InP := PByte(Src);
  InLeft := SrcLen;
  OutP := PByte(Dst);
  MatchPos := 0;
  InitTree;
  CodeBuf[0] := 0;
  CodePos := 1;
  Mask := 1;
  S := 0;
  R := N - F;
  FillChar(Ring, N - F, Ord(' '));
  Len := GetChars(@Ring[R], F);
  For I := 1 To F Do InsertNode(R - I);
  InsertNode(R);
  Repeat
    If MatchLen > Len Then MatchLen := Len;
    If MatchLen < Threshold Then
      Begin
      MatchLen := 1;
      CodeBuf[0] := CodeBuf[0] Or Mask;
      CodeBuf[CodePos] := Ring[R];
      Inc(CodePos);
      End
    Else
      Begin
      CodeBuf[CodePos] := Byte(MatchPos);
      Inc(CodePos);
      CodeBuf[CodePos] := Byte(((MatchPos Shr 4) And $F0) Or (MatchLen - Threshold));
      Inc(CodePos);
      End;
    Mask := Byte(Mask Shl 1);
    If Mask = 0 Then
      Begin
      Send(CodeBuf, CodePos);
      CodeBuf[0] := 0;
      CodePos := 1;
      Mask := 1;
      End;
    LastMatch := MatchLen;
    I := 0;
    While I < LastMatch Do
      Begin
      If GetChars(@C, 1) <> 1 Then Break;
      DeleteNode(S);
      Ring[S] := C;
      If S < F - 1 Then Ring[S + N] := C;
      S := (S + 1) And (N - 1);
      R := (R + 1) And (N - 1);
      InsertNode(R);
      Inc(I);
      End;
    While I < LastMatch Do
      Begin
      Inc(I);
      DeleteNode(S);
      S := (S + 1) And (N - 1);
      R := (R + 1) And (N - 1);
      Dec(Len);
      If Len > 0 Then InsertNode(R);
      End;
  Until Len <= 0;
  If CodePos > 1 Then Send(CodeBuf, CodePos);
  If Overflow Then LzssCompress := 1;
  DstLen := OutN;
  End;

End.
