unit mkbiblerepo;
{$mode objfpc}{$H+}
{ mkbiblerepo - download and install modules.  Shared by the GUI (and usable from a test program).

  Two kinds of repository are understood:
    rkSword   a Sword repository: <url>/mods.d.tar.gz is the index (one .conf per module) and
              <url>/packages/<Module>.zip is the module.  Installed into a Sword folder (by default ~/.sword,
              %APPDATA%\Sword on Windows), which every Sword front end searches.
    rkEBible  eBible.org's Scriptures folder: <url>/translations.csv is the index and <url>/<id>_usfm.zip is
              the translation as USFM files.  Installed into our own local module folder, one folder per
              translation (the reader's scanner picks up USFM folders).

  Downloads are HTTPS: on Windows with the system's own library (WinInet, see mkbiblewinet), elsewhere with the FPC
  client, which needs OpenSSL (libssl) on the machine. }

interface

type
  TRepoKind = (rkSword, rkEBible);

  TRepo = record
    Name, Url: String;
    Kind: TRepoKind;
  end;
  TRepoArray = array of TRepo;

  TRepoItem = record
    Id: String;          { module name (Sword) or translation id (eBible) }
    Title, Lang, Version, Kind: String;
    SizeKB: LongInt;     { 0 when the repository does not say }
    Extra: String;       { the eBible 'swordName' etc., for display only }
  end;
  TRepoItems = array of TRepoItem;

  TProgressProc = procedure(Done, Total: Int64) of object;

var
  OnProgress: TProgressProc = nil;   { called while a file downloads }

procedure GetRepos(out Repos: TRepoArray);
  { the built in list, then any 'repo.1' ... 'repo.9' = Name | sword|ebible | url lines of the config file }
function SwordInstallDir: String;
function LocalModuleDir: String;
function ListRepo(const R: TRepo; out Items: TRepoItems; out Err: String): Boolean;
function InstallItem(const R: TRepo; const It: TRepoItem; out Dest, Err: String): Boolean;
  { Dest is the folder the module landed in (the Sword root, or the translation's folder) }
function IsInstalled(const R: TRepo; const It: TRepoItem): Boolean;
function LangDisplay(const L: String): String;
  { 'en' or 'en-GB' -> 'English'; names the repository already spelled out are kept; unknown codes are upper cased }
function SystemLangName: String;
  { the language of the LANG / LC_ALL environment, as LangDisplay would name it ('' if unknown) }

implementation

uses
  SysUtils, Classes, zstream, zipper, mkbiblecfg,
{$IFDEF WINDOWS}
  mkbiblewinet;       { Windows brings its own HTTPS: no OpenSSL DLLs }
{$ELSE}
  fphttpclient, opensslsockets, openssl;
{$ENDIF}

{ ------------------------------------------------------------------ OpenSSL (not on Windows, which has its own) }

{$IFNDEF WINDOWS}
{ FPC 3.2.2 knows OpenSSL 1.x names and, on Unix, only the unversioned libssl.so (a developer package link): a normal
  system with libssl.so.3 would fail with "could not initialize openssl library".  Teach it the OpenSSL 3 name, first,
  and keep the 1.x ones as the fallback. }
procedure PrepareSsl;
begin
  DLLVersions[2] := '.3';
  DLLVersions[3] := '.1.1';
end;
{$ENDIF}

{ ------------------------------------------------------------------ language names }

const
  LangTable =
    'en=English;de=German;fr=French;es=Spanish;pt=Portuguese;it=Italian;nl=Dutch;ru=Russian;uk=Ukrainian;pl=Polish;' +
    'cs=Czech;sk=Slovak;sl=Slovenian;hr=Croatian;sr=Serbian;bg=Bulgarian;ro=Romanian;hu=Hungarian;fi=Finnish;' +
    'sv=Swedish;da=Danish;no=Norwegian;nb=Norwegian;nn=Norwegian;is=Icelandic;et=Estonian;lv=Latvian;lt=Lithuanian;' +
    'el=Greek (modern);grc=Greek (ancient);he=Hebrew;hbo=Hebrew (ancient);heb=Hebrew;ar=Arabic;fa=Persian;tr=Turkish;' +
    'hy=Armenian;ka=Georgian;la=Latin;lat=Latin;cop=Coptic;syr=Syriac;arc=Aramaic;got=Gothic;ang=Old English;' +
    'zh=Chinese;ja=Japanese;ko=Korean;vi=Vietnamese;th=Thai;id=Indonesian;ms=Malay;tl=Tagalog;hi=Hindi;bn=Bengali;' +
    'ta=Tamil;te=Telugu;ml=Malayalam;kn=Kannada;mr=Marathi;gu=Gujarati;pa=Punjabi;ur=Urdu;ne=Nepali;si=Sinhala;' +
    'my=Burmese;km=Khmer;lo=Lao;mn=Mongolian;sw=Swahili;am=Amharic;ha=Hausa;yo=Yoruba;ig=Igbo;zu=Zulu;xh=Xhosa;' +
    'af=Afrikaans;st=Sesotho;tn=Tswana;sn=Shona;mg=Malagasy;so=Somali;ga=Irish;gd=Scottish Gaelic;cy=Welsh;' +
    'br=Breton;eu=Basque;ca=Catalan;gl=Galician;mt=Maltese;sq=Albanian;mk=Macedonian;be=Belarusian;eo=Esperanto;' +
    'haw=Hawaiian;mi=Maori;sm=Samoan;to=Tongan;fj=Fijian;qu=Quechua;gn=Guarani;ay=Aymara;nah=Nahuatl;' +
    'ko=Korean;kk=Kazakh;uz=Uzbek;az=Azerbaijani;ky=Kyrgyz;tg=Tajik;tk=Turkmen;ps=Pashto;ku=Kurdish;sd=Sindhi';

function LangDisplay(const L: String): String;
var
  C: String;
  P: Integer;
begin
  C := LowerCase(Trim(L));
  if C = '' then begin Result := 'Other'; Exit; end;
  P := Pos('-', C); if P > 0 then C := Copy(C, 1, P - 1);
  P := Pos('_', C); if P > 0 then C := Copy(C, 1, P - 1);
  P := Pos(';' + C + '=', ';' + LangTable);
  if (Length(C) <= 3) then
    begin
    if P > 0 then
      begin
      Result := Copy(LangTable, P + Length(C) + 1, MaxInt);
      Result := Copy(Result, 1, Pos(';', Result + ';') - 1);
      end
    else Result := UpperCase(C);
    end
  else Result := Trim(L);   { already a name (eBible's list) }
end;

function SystemLangName: String;
var
  S: String;
begin
  S := GetEnvironmentVariable('LC_ALL');
  if S = '' then S := GetEnvironmentVariable('LANG');
  if (S = '') or (S = 'C') or (S = 'POSIX') then Result := '' else Result := LangDisplay(S);
end;

{ ------------------------------------------------------------------ repository list }

procedure AddRepo(var A: TRepoArray; const N, U: String; K: TRepoKind);
begin
  SetLength(A, Length(A) + 1);
  A[High(A)].Name := N;
  A[High(A)].Url := U;
  A[High(A)].Kind := K;
end;

procedure GetRepos(out Repos: TRepoArray);
var
  i, P: Integer;
  S, N, K, U: String;
begin
  SetLength(Repos, 0);
  AddRepo(Repos, 'CrossWire (main)', 'https://www.crosswire.org/ftpmirror/pub/sword/raw', rkSword);
  AddRepo(Repos, 'CrossWire (beta)', 'https://www.crosswire.org/ftpmirror/pub/sword/betaraw', rkSword);
  AddRepo(Repos, 'CrossWire (attic)', 'https://www.crosswire.org/ftpmirror/pub/sword/atticraw', rkSword);
  AddRepo(Repos, 'CrossWire (Wycliffe)', 'https://www.crosswire.org/ftpmirror/pub/sword/wyclifferaw', rkSword);
  AddRepo(Repos, 'eBible.org (Sword)', 'https://ebible.org/sword', rkSword);
  AddRepo(Repos, 'eBible.org (USFM)', 'https://ebible.org/Scriptures', rkEBible);
  for i := 1 to 9 do
    begin
    S := GetSetting('repo.' + IntToStr(i), '');
    if S = '' then Continue;
    P := Pos('|', S); if P = 0 then Continue;
    N := Trim(Copy(S, 1, P - 1)); Delete(S, 1, P);
    P := Pos('|', S); if P = 0 then Continue;
    K := LowerCase(Trim(Copy(S, 1, P - 1))); Delete(S, 1, P);
    U := Trim(S);
    while (U <> '') and (U[Length(U)] = '/') do Delete(U, Length(U), 1);
    if (N = '') or (U = '') then Continue;
    if K = 'sword' then AddRepo(Repos, N, U, rkSword)
    else if K = 'ebible' then AddRepo(Repos, N, U, rkEBible);
    end;
end;

function SwordInstallDir: String;
begin
{$IFDEF WINDOWS}
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('APPDATA')) + 'Sword';
{$ELSE}
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) + '.sword';
{$ENDIF}
end;

function LocalModuleDir: String;
begin
{$IFDEF WINDOWS}
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('APPDATA')) + 'mkbible\modules';
{$ELSE}
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) + '.local/share/mkbible/modules';
{$ENDIF}
end;

{ ------------------------------------------------------------------ http }

{$IFDEF WINDOWS}

function HttpGet(const Url: String; S: TStream; out Err: String): Boolean;
begin
  Result := WinInetGet(Url, S, Err, OnProgress);
end;

{$ELSE}

type
  TGetter = class
    procedure Data(Sender: TObject; const ContentLength, CurrentPos: Int64);
  end;

procedure TGetter.Data(Sender: TObject; const ContentLength, CurrentPos: Int64);
begin
  if Assigned(OnProgress) then OnProgress(CurrentPos, ContentLength);
end;

function HttpGet(const Url: String; S: TStream; out Err: String): Boolean;
var
  C: TFPHTTPClient;
  G: TGetter;
begin
  Result := False; Err := '';
  C := TFPHTTPClient.Create(nil);
  G := TGetter.Create;
  try
    C.AllowRedirect := True;
    C.IOTimeout := 30000;
    C.AddHeader('User-Agent', 'mkbible');
    C.OnDataReceived := @G.Data;
    try
      C.Get(Url, S);
      Result := (C.ResponseStatusCode >= 200) and (C.ResponseStatusCode < 300);
      if not Result then Err := 'HTTP ' + IntToStr(C.ResponseStatusCode) + ' for ' + Url;
    except
      on E: Exception do Err := E.Message;
    end;
  finally
    G.Free;
    C.Free;
  end;
end;

{$ENDIF}

{ ------------------------------------------------------------------ gzip + tar }

function GunzipTo(Src, Dst: TStream; out Err: String): Boolean;
var
  H: array[0..9] of Byte;
  Fl, B: Byte;
  Xl: Word;
  D: TDecompressionStream;
  Buf: array[0..32767] of Byte;
  N: LongInt;
begin
  Result := False; Err := '';
  Src.Position := 0;
  if (Src.Read(H, 10) <> 10) or (H[0] <> $1F) or (H[1] <> $8B) then begin Err := 'not a gzip file'; Exit; end;
  Fl := H[3];
  if (Fl and 4) <> 0 then begin Src.Read(Xl, 2); Src.Seek(Xl, soFromCurrent); end;
  if (Fl and 8) <> 0 then repeat B := 1; Src.Read(B, 1); until B = 0;
  if (Fl and 16) <> 0 then repeat B := 1; Src.Read(B, 1); until B = 0;
  if (Fl and 2) <> 0 then Src.Seek(2, soFromCurrent);
  D := TDecompressionStream.Create(Src, True);
  try
    try
      repeat
        N := D.Read(Buf, SizeOf(Buf));
        if N > 0 then Dst.WriteBuffer(Buf, N);
      until N <= 0;
      Result := True;
    except
      on E: Exception do Err := E.Message;
    end;
  finally
    D.Free;
  end;
end;

{ every regular file of a tar stream, as name -> contents, handed to Each }
type
  TTarFileProc = procedure(const Name, Data: String) of object;

function OctalOf(const P: PChar; Len: Integer): Int64;
var i: Integer;
begin
  Result := 0;
  for i := 0 to Len - 1 do
    if P[i] in ['0'..'7'] then Result := Result * 8 + Ord(P[i]) - 48
    else if Result > 0 then Break;
end;

procedure TarWalk(S: TStream; Each: TTarFileProc);
var
  Hdr: array[0..511] of Char;
  Name, Data: String;
  Size: Int64;
  Pad: Integer;
begin
  S.Position := 0;
  while S.Read(Hdr, 512) = 512 do
    begin
    if Hdr[0] = #0 then Break;
    Name := '';
    Name := PChar(@Hdr[0]);
    if StrLen(PChar(@Hdr[0])) > 100 then Name := Copy(Name, 1, 100);
    Size := OctalOf(@Hdr[124], 12);
    if (Hdr[156] = '0') or (Hdr[156] = #0) then
      begin
      SetLength(Data, Size);
      if Size > 0 then S.ReadBuffer(Data[1], Size);
      Each(Name, Data);
      end
    else S.Seek(Size, soFromCurrent);
    Pad := (512 - (Size mod 512)) mod 512;
    if Pad > 0 then S.Seek(Pad, soFromCurrent);
    end;
end;

{ ------------------------------------------------------------------ sword index }

type
  TSwordIndexer = class
    Items: TRepoItems;
    procedure OnFile(const Name, Data: String);
  end;

function ConfValue(L: TStringList; const Key: String): String;
var
  i, P: Integer;
  K: String;
begin
  Result := '';
  for i := 0 to L.Count - 1 do
    begin
    P := Pos('=', L[i]);
    if P = 0 then Continue;
    K := Trim(Copy(L[i], 1, P - 1));
    if SameText(K, Key) then
      begin
      Result := Trim(Copy(L[i], P + 1, MaxInt));
      Exit;
      end;
    end;
end;

procedure TSwordIndexer.OnFile(const Name, Data: String);
var
  L: TStringList;
  Nm, Drv, Feat, Kind: String;
  i, P: Integer;
  It: TRepoItem;
begin
  if LowerCase(ExtractFileExt(Name)) <> '.conf' then Exit;
  L := TStringList.Create;
  try
    L.Text := Data;
    if L.Count = 0 then Exit;
    Nm := Trim(L[0]);
    if (Length(Nm) < 3) or (Nm[1] = '#') then
      begin
      { a BOM or a comment first: look for the first [Section] line }
      Nm := '';
      for i := 0 to L.Count - 1 do
        if (Length(L[i]) > 2) and (Pos('[', L[i]) > 0) then begin Nm := Trim(L[i]); Break; end;
      end;
    P := Pos('[', Nm);
    if P = 0 then Exit;
    Nm := Copy(Nm, P + 1, MaxInt);
    P := Pos(']', Nm);
    if P = 0 then Exit;
    Nm := Copy(Nm, 1, P - 1);
    Drv := ConfValue(L, 'ModDrv');
    Feat := ConfValue(L, 'Feature');
    if SameText(Drv, 'RawText') or SameText(Drv, 'RawText4') or SameText(Drv, 'zText') or SameText(Drv, 'zText4') then
      Kind := 'Bible'
    else if (SameText(Drv, 'zLD') or SameText(Drv, 'RawLD') or SameText(Drv, 'RawLD4') or SameText(Drv, 'zLD4')) and
            ((Pos('GreekDef', Feat) > 0) or (Pos('HebrewDef', Feat) > 0)) then
      Kind := 'Lexicon'
    else Exit;
    { an empty CipherKey line marks a locked module that needs a purchased key }
    for i := 0 to L.Count - 1 do
      if SameText(Trim(Copy(L[i], 1, Pos('=', L[i] + '=') - 1)), 'CipherKey') and
         (Trim(Copy(L[i], Pos('=', L[i] + '=') + 1, MaxInt)) = '') then Exit;
    It.Id := Nm;
    It.Title := ConfValue(L, 'Description');
    if It.Title = '' then It.Title := Nm;
    It.Lang := ConfValue(L, 'Lang');
    It.Version := ConfValue(L, 'Version');
    It.Kind := Kind;
    It.SizeKB := StrToIntDef(ConfValue(L, 'InstallSize'), 0) div 1024;
    It.Extra := '';
    SetLength(Items, Length(Items) + 1);
    Items[High(Items)] := It;
  finally
    L.Free;
  end;
end;

function ListSword(const R: TRepo; out Items: TRepoItems; out Err: String): Boolean;
var
  Z, T: TMemoryStream;
  X: TSwordIndexer;
begin
  Result := False;
  SetLength(Items, 0);
  Z := TMemoryStream.Create;
  T := TMemoryStream.Create;
  X := TSwordIndexer.Create;
  try
    if not HttpGet(R.Url + '/mods.d.tar.gz', Z, Err) then Exit;
    if not GunzipTo(Z, T, Err) then Exit;
    TarWalk(T, @X.OnFile);
    Items := X.Items;
    Result := True;
  finally
    X.Free; T.Free; Z.Free;
  end;
end;

{ ------------------------------------------------------------------ eBible index }

{ one CSV line into fields (double quote quoting, "" inside a quoted field) }
procedure CsvSplit(const Line: String; F: TStringList);
var
  i: Integer;
  Cur: String;
  Q: Boolean;
begin
  F.Clear;
  Cur := ''; Q := False;
  i := 1;
  while i <= Length(Line) do
    begin
    if Q then
      begin
      if Line[i] = '"' then
        begin
        if (i < Length(Line)) and (Line[i + 1] = '"') then begin Cur := Cur + '"'; Inc(i); end
        else Q := False;
        end
      else Cur := Cur + Line[i];
      end
    else if Line[i] = '"' then Q := True
    else if Line[i] = ',' then begin F.Add(Cur); Cur := ''; end
    else Cur := Cur + Line[i];
    Inc(i);
    end;
  F.Add(Cur);
end;

function ListEBible(const R: TRepo; out Items: TRepoItems; out Err: String): Boolean;
var
  M: TMemoryStream;
  Lines, H, F: TStringList;
  i, cId, cLang, cTitle, cRedis, cDown, cUpd, cSword: Integer;
  It: TRepoItem;
  S: String;
begin
  Result := False;
  SetLength(Items, 0);
  M := TMemoryStream.Create;
  Lines := TStringList.Create;
  H := TStringList.Create;
  F := TStringList.Create;
  try
    if not HttpGet(R.Url + '/translations.csv', M, Err) then Exit;
    SetString(S, PChar(M.Memory), M.Size);
    if Copy(S, 1, 3) = #$EF#$BB#$BF then Delete(S, 1, 3);
    Lines.Text := S;
    if Lines.Count < 2 then begin Err := 'empty translations.csv'; Exit; end;
    CsvSplit(Lines[0], H);
    cId := H.IndexOf('translationId'); cLang := H.IndexOf('languageNameInEnglish');
    cTitle := H.IndexOf('title'); cRedis := H.IndexOf('Redistributable');
    cDown := H.IndexOf('downloadable'); cUpd := H.IndexOf('UpdateDate'); cSword := H.IndexOf('swordName');
    if (cId < 0) or (cTitle < 0) then begin Err := 'unexpected translations.csv'; Exit; end;
    for i := 1 to Lines.Count - 1 do
      begin
      if Trim(Lines[i]) = '' then Continue;
      CsvSplit(Lines[i], F);
      if F.Count <= cTitle then Continue;
      if (cRedis >= 0) and (cRedis < F.Count) and not SameText(F[cRedis], 'True') then Continue;
      if (cDown >= 0) and (cDown < F.Count) and not SameText(F[cDown], 'True') then Continue;
      It.Id := F[cId];
      It.Title := F[cTitle];
      if (cLang >= 0) and (cLang < F.Count) then It.Lang := F[cLang] else It.Lang := '';
      if (cUpd >= 0) and (cUpd < F.Count) then It.Version := F[cUpd] else It.Version := '';
      if (cSword >= 0) and (cSword < F.Count) then It.Extra := F[cSword] else It.Extra := '';
      It.Kind := 'USFM';
      It.SizeKB := 0;
      SetLength(Items, Length(Items) + 1);
      Items[High(Items)] := It;
      end;
    Result := True;
  finally
    F.Free; H.Free; Lines.Free; M.Free;
  end;
end;

function ListRepo(const R: TRepo; out Items: TRepoItems; out Err: String): Boolean;
var i: Integer;
begin
  if R.Kind = rkSword then Result := ListSword(R, Items, Err) else Result := ListEBible(R, Items, Err);
  for i := 0 to High(Items) do Items[i].Lang := LangDisplay(Items[i].Lang);
end;

{ ------------------------------------------------------------------ install }

function SafeName(const N: String): Boolean;
begin
  Result := (N <> '') and (N[1] <> '/') and (N[1] <> '\') and (Pos('..', N) = 0) and (Pos(':', N) = 0);
end;

{ unzips a zip held in memory into Dir, refusing names that would escape it }
function UnzipInto(Z: TMemoryStream; const Dir: String; out Err: String): Boolean;
var
  U: TUnZipper;
  i: Integer;
  Tmp: String;
  FS: TFileStream;
begin
  Result := False; Err := '';
  Tmp := IncludeTrailingPathDelimiter(GetTempDir) + 'mkbible-dl-' + IntToStr(GetProcessID) + '.zip';
  FS := TFileStream.Create(Tmp, fmCreate);
  try
    Z.Position := 0;
    FS.CopyFrom(Z, Z.Size);
  finally
    FS.Free;
  end;
  U := TUnZipper.Create;
  try
    try
      U.FileName := Tmp;
      U.OutputPath := Dir;
      U.Examine;
      for i := 0 to U.Entries.Count - 1 do
        if not SafeName(U.Entries[i].ArchiveFileName) then
          begin Err := 'the archive has an unsafe file name: ' + U.Entries[i].ArchiveFileName; Exit; end;
      ForceDirectories(Dir);
      U.UnZipAllFiles;
      Result := True;
    except
      on E: Exception do Err := E.Message;
    end;
  finally
    U.Free;
    DeleteFile(Tmp);
  end;
end;

function InstallItem(const R: TRepo; const It: TRepoItem; out Dest, Err: String): Boolean;
var
  Z: TMemoryStream;
begin
  Result := False; Dest := ''; Err := '';
  if not SafeName(It.Id) then begin Err := 'bad module name'; Exit; end;
  Z := TMemoryStream.Create;
  try
    if R.Kind = rkSword then
      begin
      Dest := SwordInstallDir;
      if not HttpGet(R.Url + '/packages/' + It.Id + '.zip', Z, Err) then Exit;
      Result := UnzipInto(Z, Dest, Err);
      end
    else
      begin
      Dest := IncludeTrailingPathDelimiter(LocalModuleDir) + It.Id + '-usfm';
      if not HttpGet(R.Url + '/' + It.Id + '_usfm.zip', Z, Err) then Exit;
      Result := UnzipInto(Z, Dest, Err);
      end;
  finally
    Z.Free;
  end;
end;

function IsInstalled(const R: TRepo; const It: TRepoItem): Boolean;
begin
  if R.Kind = rkSword then
    Result := FileExists(IncludeTrailingPathDelimiter(SwordInstallDir) + 'mods.d/' + LowerCase(It.Id) + '.conf') or
              FileExists(IncludeTrailingPathDelimiter(SwordInstallDir) + 'mods.d/' + It.Id + '.conf')
  else
    Result := DirectoryExists(IncludeTrailingPathDelimiter(LocalModuleDir) + It.Id + '-usfm');
end;

initialization
{$IFNDEF WINDOWS}
  PrepareSsl;
{$ENDIF}

end.
