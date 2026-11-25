Unit MKBibSql;       {Small SQLite helpers shared by the modules that are SQLite files}

{$I MKBib.Def}

Interface

Uses MKBibMod, sqlite3dyn;

Function SqlReady: Boolean;
  {Loads the SQLite library at run time (libsqlite3.so.0 or libsqlite3.so; sqlite3.dll on Windows); False if there is none}
Function SqlColText(St: psqlite3_stmt; Col: LongInt): BibStr;
Function SqlColName(St: psqlite3_stmt; Col: LongInt): BibStr;
Procedure SqlBindText(St: psqlite3_stmt; Idx: LongInt; Const S: BibStr);
Function SqlExec(Db: psqlite3; Const Sql: AnsiString): Boolean;
Function SqlColIsBlob(St: psqlite3_stmt; Col: LongInt): Boolean;
Function SqlColBlobText(St: psqlite3_stmt; Col: LongInt): BibStr;
  {A blob column, zlib-inflated (theWord's "compressed" modules store their RTF/HTML this way); the
  empty string if the column is not a zlib stream (most likely really encrypted, not just compressed)}

Implementation

Uses Strings, MKBibZ;

{$WARN SYMBOL_DEPRECATED OFF}

Var
  Ready, Tried: Boolean;

Function SqlReady: Boolean;
  Begin
  If Not Tried Then
    Begin
    Tried := True;
{$IFDEF WINDOWS}
    Ready := (InitialiseSQLite('sqlite3.dll') > 0) Or (InitialiseSQLite('winsqlite3.dll') > 0);
{$ELSE}
    Ready := (InitialiseSQLite('libsqlite3.so.0') > 0) Or (InitialiseSQLite('libsqlite3.so') > 0);
{$ENDIF}
    End;
  SqlReady := Ready;
  End;

Function PCharToBib(P: PChar; N: LongInt): BibStr;
  Var R: BibStr;
  Begin
  R := '';
  If P <> Nil Then
    Begin
    If N < 0 Then N := StrLen(P);
    SetLength(R, N);
    If N > 0 Then Move(P^, R[1], N);
    End;
  PCharToBib := R;
  End;

Function SqlColText(St: psqlite3_stmt; Col: LongInt): BibStr;
  Begin
  SqlColText := PCharToBib(PChar(sqlite3_column_text(St, Col)), sqlite3_column_bytes(St, Col));
  End;

Function SqlColName(St: psqlite3_stmt; Col: LongInt): BibStr;
  Begin
  SqlColName := PCharToBib(PChar(sqlite3_column_name(St, Col)), -1);
  End;

Procedure SqlBindText(St: psqlite3_stmt; Idx: LongInt; Const S: BibStr);
  Begin
  If S = '' Then sqlite3_bind_text(St, Idx, '', 0, sqlite3_destructor_type(SQLITE_TRANSIENT))
  Else sqlite3_bind_text(St, Idx, PChar(S), Length(S), sqlite3_destructor_type(SQLITE_TRANSIENT));
  End;

Function SqlExec(Db: psqlite3; Const Sql: AnsiString): Boolean;
  Begin
  SqlExec := sqlite3_exec(Db, PChar(Sql), Nil, Nil, Nil) = SQLITE_OK;
  End;

Function SqlColIsBlob(St: psqlite3_stmt; Col: LongInt): Boolean;
  Begin
  SqlColIsBlob := sqlite3_column_type(St, Col) = SQLITE_BLOB;
  End;

Function SqlColBlobText(St: psqlite3_stmt; Col: LongInt): BibStr;
  Var
    Src: Pointer;
    SrcLen, Cap, L: LongWord;
    R: BibStr;
  Begin
  SqlColBlobText := '';
  Src := sqlite3_column_blob(St, Col);
  SrcLen := sqlite3_column_bytes(St, Col);
  If (Src = Nil) Or (SrcLen < 2) Then Exit;
  {a zlib stream starts 78 01 / 78 5E / 78 9C / 78 DA}
  If PByte(Src)^ <> $78 Then Exit;
  Cap := SrcLen * 8 + 4096;
  While Cap < 64 * 1024 * 1024 Do
    Begin
    SetLength(R, Cap);
    L := Cap;
    If (ZUncompress(Src, SrcLen, @R[1], L) = 0) And (L < Cap) Then
      Begin
      SetLength(R, L);
      SqlColBlobText := R;
      Exit;
      End;
    Cap := Cap * 4;
    End;
  End;

End.
