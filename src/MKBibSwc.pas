Unit MKBibSwc;       {Sword module configuration: finding a module's .conf and reading its settings}

{$I MKBib.Def}

{
  What the Sword dictionary object needs from a module's conf file: find the conf (a .conf path, a
  module name searched in the usual Sword directories, or a Sword directory plus "|name"), and
  read keys from it.  (MKBibSwd keeps its own copy of this; the two may be merged later.)

  The module directories searched for a name: those in Roots, each entry of $SWORD_PATH, ~/.sword,
  ~/.sword/sword, /usr/share/sword, /usr/local/share/sword.
}

Interface

Uses MKBibMod;

Function SwcFindConf(Spec: String; Var ConfPath, BaseDir, ModName: BibStr; Var Conf: BibStr): Boolean;
  {Spec = a .conf file, a module name, or "<sword dir>|<name>".  Conf = the key=value lines of the
   module's section, ModName = the section name, BaseDir = the directory holding mods.d and modules.}
Function SwcGet(Const Conf, Key: BibStr): BibStr;      {value of Key (any case); repeated keys joined by newlines}
Function SwcHas(Const Conf, Key: BibStr): Boolean;
Function SwcAddSlash(Const D: BibStr): BibStr;

Implementation

Uses SysUtils;

Function SwcAddSlash(Const D: BibStr): BibStr;
  Begin
  If (D <> '') And (D[Length(D)] <> '/') Then SwcAddSlash := D + '/' Else SwcAddSlash := D;
  End;

{ the section called Section (case insensitive) of a conf file, as "Key=Value" lines; multi line values
  (ending in a backslash) are joined with a newline }
Function LoadSection(Const FileName, Section: BibStr; Var Conf, SecName: BibStr): Boolean;
  Var
    F: Text;
    L, Sec: BibStr;
    Acc: BibStr;
    Want: Boolean;
  Begin
  LoadSection := False;
  Assign(F, FileName);
  Reset(F);
  If IOResult <> 0 Then Exit;
  Conf := '';
  Want := False;
  Acc := '';
  While Not Eof(F) Do
    Begin
    ReadLn(F, L);
    If (Length(L) > 0) And (L[Length(L)] = #13) Then Delete(L, Length(L), 1);
    If Acc <> '' Then
      Begin
      Acc := Acc + #10 + L;
      If (L = '') Or (L[Length(L)] <> '\') Then
        Begin
        If Want Then Conf := Conf + Acc + #13#10;
        Acc := '';
        End
      Else Acc := Copy(Acc, 1, Length(Acc) - 1);
      Continue;
      End;
    If (L <> '') And (L[1] = '[') Then
      Begin
      Sec := Copy(L, 2, Pos(']', L) - 2);
      If Want Then Break;
      If (Section = '') Or (LowerCase(Sec) = LowerCase(Section)) Then
        Begin
        Want := True;
        SecName := Sec;
        End;
      Continue;
      End;
    If (Not Want) Or (L = '') Or (L[1] = '#') Or (Pos('=', L) = 0) Then Continue;
    If L[Length(L)] = '\' Then Acc := Copy(L, 1, Length(L) - 1)
    Else Conf := Conf + L + #13#10;
    End;
  Close(F);
  LoadSection := Want;
  End;

Function SwcGet(Const Conf, Key: BibStr): BibStr;
  Var
    P, E: LongInt;
    Line, K, R: BibStr;
    Low: BibStr;
  Begin
  R := '';
  Low := LowerCase(Key);
  P := 1;
  While P <= Length(Conf) Do
    Begin
    E := P;
    While (E <= Length(Conf)) And (Conf[E] <> #13) Do Inc(E);
    Line := Copy(Conf, P, E - P);
    If Pos('=', Line) > 0 Then
      Begin
      K := LowerCase(Trim(Copy(Line, 1, Pos('=', Line) - 1)));
      If K = Low Then
        Begin
        If R <> '' Then R := R + #10;
        R := R + Trim(Copy(Line, Pos('=', Line) + 1, Length(Line)));
        End;
      End;
    P := E + 2;
    End;
  SwcGet := R;
  End;

Function SwcHas(Const Conf, Key: BibStr): Boolean;
  Begin
  SwcHas := Pos(#10 + LowerCase(Key) + '=', #10 + LowerCase(StringReplace(Conf, #13#10, #10, [rfReplaceAll]))) > 0;
  End;

Function SwcFindConf(Spec: String; Var ConfPath, BaseDir, ModName: BibStr; Var Conf: BibStr): Boolean;
  Var
    Wanted, Env, Entry, Home: BibStr;
    SR: TSearchRec;
    P, i: Integer;
    Dirs: Array[1..24] Of BibStr;
    ND: Integer;
    Found: Boolean;

  Procedure AddDir(D: BibStr);
    Begin
    If (D <> '') And (ND < 24) Then
      Begin
      Inc(ND);
      Dirs[ND] := SwcAddSlash(D);
      End;
    End;

  Function TryDir(D: BibStr): Boolean;
    Begin
    TryDir := False;
    If Not DirectoryExists(D + 'mods.d') Then Exit;
    If FileExists(D + 'mods.d/' + LowerCase(Wanted) + '.conf') Then
      If LoadSection(D + 'mods.d/' + LowerCase(Wanted) + '.conf', Wanted, Conf, ModName) Then
        Begin
        ConfPath := D + 'mods.d/' + LowerCase(Wanted) + '.conf';
        BaseDir := D;
        TryDir := True;
        Exit;
        End;
    If FindFirst(D + 'mods.d/*.conf', faAnyFile, SR) = 0 Then
      Begin
      Repeat
        If LoadSection(D + 'mods.d/' + SR.Name, Wanted, Conf, ModName) Then
          Begin
          ConfPath := D + 'mods.d/' + SR.Name;
          BaseDir := D;
          TryDir := True;
          Break;
          End;
      Until FindNext(SR) <> 0;
      FindClose(SR);
      End;
    End;

  Begin
  SwcFindConf := False;
  If Spec = '' Then Exit;
  { a conf file }
  If FileExists(Spec) And (LowerCase(ExtractFileExt(Spec)) = '.conf') Then
    Begin
    If Not LoadSection(Spec, '', Conf, ModName) Then Exit;
    ConfPath := ExpandFileName(Spec);
    BaseDir := SwcAddSlash(ExpandFileName(ExtractFileDir(ExtractFileDir(ConfPath))));
    SwcFindConf := True;
    Exit;
    End;
  { directory|name }
  P := Pos('|', Spec);
  If P > 0 Then
    Begin
    Wanted := Copy(Spec, P + 1, 255);
    SwcFindConf := TryDir(SwcAddSlash(ExpandFileName(Copy(Spec, 1, P - 1))));
    Exit;
    End;
  { a module name }
  Wanted := Spec;
  ND := 0;
  Env := GetEnvironmentVariable('SWORD_PATH');
  While Env <> '' Do
    Begin
    P := Pos(':', Env);
    If P = 0 Then Begin Entry := Env; Env := ''; End
    Else Begin Entry := Copy(Env, 1, P - 1); Env := Copy(Env, P + 1, 255); End;
    AddDir(Entry);
    End;
  Home := GetEnvironmentVariable('HOME');
  If Home <> '' Then
    Begin
    AddDir(SwcAddSlash(Home) + '.sword');
    AddDir(SwcAddSlash(Home) + '.sword/sword');
    End;
  AddDir('/usr/share/sword');
  AddDir('/usr/local/share/sword');
  Found := False;
  For i := 1 To ND Do
    If TryDir(Dirs[i]) Then
      Begin
      Found := True;
      Break;
      End;
  SwcFindConf := Found;
  End;

End.
