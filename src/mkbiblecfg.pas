unit mkbiblecfg;
{$mode objfpc}{$H+}
{ Configuration for mkbible: the module search paths, and where to resume (module, book, chapter).
  Stored as simple "key = value" lines in ~/.config/mkbible/mkbible.cfg; "path" repeats, one per
  configured search path. }

interface

uses SysUtils;

function ConfigDir: String;
function ConfigFile: String;
function LoadPaths: TStringArray;
procedure SavePaths(const Paths: TStringArray);
function LoadLast(out ModSpec: String; out Book, Chapter: Integer): Boolean;
procedure SaveLast(const ModSpec: String; Book, Chapter: Integer);
{ any other "key = value" setting (colors, search options): the value, or Default; PutSetting replaces the
  line of that key or adds one }
function GetSetting(const Key, Default: String): String;
procedure PutSetting(const Key, Value: String);

implementation

uses Classes;

function ConfigDir: String;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) + '.config/mkbible';
  if not DirectoryExists(Result) then ForceDirectories(Result);
end;

function ConfigFile: String;
begin
  Result := IncludeTrailingPathDelimiter(ConfigDir) + 'mkbible.cfg';
end;

{ reads the file once into Lines; the caller's procedure does the rest }
procedure ReadLines(Lines: TStringList);
begin
  if FileExists(ConfigFile) then
    try
      Lines.LoadFromFile(ConfigFile);
    except
    end;
end;

function KeyVal(const Line: String; out K, V: String): Boolean;
var P: Integer;
begin
  K := ''; V := '';
  P := Pos('=', Line);
  Result := P > 0;
  if not Result then Exit;
  K := Trim(Copy(Line, 1, P - 1));
  V := Trim(Copy(Line, P + 1, MaxInt));
end;

function LoadPaths: TStringArray;
var
  Lines: TStringList;
  i: Integer;
  K, V: String;
  N: Integer;
begin
  SetLength(Result, 0);
  N := 0;
  Lines := TStringList.Create;
  try
    ReadLines(Lines);
    for i := 0 to Lines.Count - 1 do
      if KeyVal(Lines[i], K, V) and (LowerCase(K) = 'path') and (V <> '') then
        begin
        SetLength(Result, N + 1);
        Result[N] := V;
        Inc(N);
        end;
  finally
    Lines.Free;
  end;
end;

{ rewrites the file, keeping every line that is not a path/module/book/chapter setting, then the
  given paths, so comments or settings a future version adds are not lost }
procedure RewriteConfig(const Paths: TStringArray; HaveLast: Boolean; const ModSpec: String; Book, Chapter: Integer);
var
  Old, Lines: TStringList;
  i: Integer;
  K, V: String;
  Skip: Boolean;
begin
  Old := TStringList.Create;
  Lines := TStringList.Create;
  try
    ReadLines(Old);
    for i := 0 to Old.Count - 1 do
      begin
      Skip := False;
      if KeyVal(Old[i], K, V) then
        begin
        K := LowerCase(K);
        Skip := (K = 'path') or (K = 'module') or (K = 'book') or (K = 'chapter');
        end;
      if not Skip then Lines.Add(Old[i]);
      end;
    for i := 0 to High(Paths) do
      if Paths[i] <> '' then Lines.Add('path = ' + Paths[i]);
    if HaveLast then
      begin
      Lines.Add('module = ' + ModSpec);
      Lines.Add('book = ' + IntToStr(Book));
      Lines.Add('chapter = ' + IntToStr(Chapter));
      end;
    ConfigDir;
    try
      Lines.SaveToFile(ConfigFile);
    except
    end;
  finally
    Old.Free;
    Lines.Free;
  end;
end;

procedure SavePaths(const Paths: TStringArray);
var
  ModSpec: String;
  Book, Chapter: Integer;
  Have: Boolean;
begin
  Have := LoadLast(ModSpec, Book, Chapter);
  RewriteConfig(Paths, Have, ModSpec, Book, Chapter);
end;

function LoadLast(out ModSpec: String; out Book, Chapter: Integer): Boolean;
var
  Lines: TStringList;
  i: Integer;
  K, V: String;
begin
  ModSpec := ''; Book := 1; Chapter := 1;
  Result := False;
  Lines := TStringList.Create;
  try
    ReadLines(Lines);
    for i := 0 to Lines.Count - 1 do
      if KeyVal(Lines[i], K, V) then
        begin
        K := LowerCase(K);
        if K = 'module' then begin ModSpec := V; Result := True; end
        else if K = 'book' then Book := StrToIntDef(V, 1)
        else if K = 'chapter' then Chapter := StrToIntDef(V, 1);
        end;
  finally
    Lines.Free;
  end;
end;

procedure SaveLast(const ModSpec: String; Book, Chapter: Integer);
begin
  RewriteConfig(LoadPaths, True, ModSpec, Book, Chapter);
end;

function GetSetting(const Key, Default: String): String;
var
  Lines: TStringList;
  i: Integer;
  K, V: String;
begin
  Result := Default;
  Lines := TStringList.Create;
  try
    ReadLines(Lines);
    for i := 0 to Lines.Count - 1 do
      if KeyVal(Lines[i], K, V) and (LowerCase(K) = LowerCase(Key)) then Result := V;
  finally
    Lines.Free;
  end;
end;

procedure PutSetting(const Key, Value: String);
var
  Lines: TStringList;
  i: Integer;
  K, V: String;
  Done: Boolean;
begin
  Lines := TStringList.Create;
  try
    ReadLines(Lines);
    Done := False;
    for i := 0 to Lines.Count - 1 do
      if KeyVal(Lines[i], K, V) and (LowerCase(K) = LowerCase(Key)) then
        begin
        Lines[i] := Key + ' = ' + Value;
        Done := True;
        Break;
        end;
    if not Done then Lines.Add(Key + ' = ' + Value);
    ConfigDir;
    try
      Lines.SaveToFile(ConfigFile);
    except
    end;
  finally
    Lines.Free;
  end;
end;

end.
