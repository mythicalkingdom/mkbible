unit mkbiblescan;
{$mode objfpc}{$H+}
{ mkbiblescan - finds the Bible modules in a module path (a folder): Sword modules (mods.d/*.conf), USFM / USX
  folders, and single files of the other formats.  Shared by the text mode reader and the GUI. }

interface

type
  TModEntry = record
    Disp, Spec: String;
  end;
  TModEntries = array of TModEntry;

procedure AddModEntry(var Arr: TModEntries; const Disp, Spec: String);
procedure ScanDir(const Dir: String; var Arr: TModEntries);

{ The order of the Open Module list: the modules the user pinned (config lines 'fav = <spec>', in the order they
  were pinned), then the most recently opened ones (lines 'recent = <spec>', newest first, at most MaxRecent),
  then everything else alphabetically. }
const
  MaxRecent = 5;
procedure OrderModules(var Arr: TModEntries; out NFav, NRecent: Integer);
procedure NoteRecent(const Spec: String);
function IsFavorite(const Spec: String): Boolean;
function ToggleFavorite(const Spec: String): Boolean;   { True when the module is now pinned }

implementation

uses
  SysUtils, Classes, MKBibMod, MKBibAbs, MKBibAny, mkbiblecfg;

procedure AddModEntry(var Arr: TModEntries; const Disp, Spec: String);
begin
  SetLength(Arr, Length(Arr) + 1);
  Arr[High(Arr)].Disp := Disp;
  Arr[High(Arr)].Spec := Spec;
end;

const
  SkipExts = '.jpg.jpeg.png.gif.bmp.css.ini.cfg.ico.ttf.ttc.otf.woff.html.htm.exe.dll.so' +
             '.log.md.json.pdf.doc.docx.db.sqlite.idx3.bak.tmp';

procedure ScanDir(const Dir: String; var Arr: TModEntries);
var
  D, Ext: String;
  SR: TSearchRec;
  Cand: array of String;
  HasBookDat, HasUsfm, HasUsx: Boolean;
  i: Integer;
  B: AbsBibPtr;
  Desc: String;

  procedure AddCand(const S: String);
  begin
    SetLength(Cand, Length(Cand) + 1);
    Cand[High(Cand)] := S;
  end;

  { a sub folder that is itself a USFM / USX Bible (the downloader unpacks each translation into its own folder) }
  function SubIsScripture(const Sub: String): Boolean;
  var SR2: TSearchRec; E2: String;
  begin
    Result := False;
    if FindFirst(IncludeTrailingPathDelimiter(Sub) + '*', faAnyFile, SR2) = 0 then
      begin
      repeat
        E2 := LowerCase(ExtractFileExt(SR2.Name));
        if ((SR2.Attr and faDirectory) = 0) and ((E2 = '.usfm') or (E2 = '.sfm') or (E2 = '.usx')) then Result := True;
      until Result or (FindNext(SR2) <> 0);
      FindClose(SR2);
      end;
  end;

begin
  D := IncludeTrailingPathDelimiter(Dir);
  SetLength(Cand, 0);
  if DirectoryExists(D + 'mods.d') then
    begin
    if FindFirst(D + 'mods.d/*.conf', faAnyFile, SR) = 0 then
      begin
      repeat AddCand(D + 'mods.d/' + SR.Name); until FindNext(SR) <> 0;
      FindClose(SR);
      end;
    end
  else
    begin
    HasBookDat := False;
    HasUsfm := False;
    HasUsx := False;
    if FindFirst(D + '*', faAnyFile, SR) = 0 then
      begin
      repeat
        if ((SR.Attr and faDirectory) = 0) and (LowerCase(SR.Name) = 'book.dat') then HasBookDat := True;
        Ext := LowerCase(ExtractFileExt(SR.Name));
        if ((SR.Attr and faDirectory) = 0) and ((Ext = '.usfm') or (Ext = '.sfm')) then HasUsfm := True;
        if ((SR.Attr and faDirectory) = 0) and (Ext = '.usx') then HasUsx := True;
      until FindNext(SR) <> 0;
      FindClose(SR);
      end;
    if HasBookDat or HasUsfm or HasUsx then AddCand(ExcludeTrailingPathDelimiter(Dir))
    else if FindFirst(D + '*', faAnyFile, SR) = 0 then
      begin
      repeat
        if ((SR.Attr and faDirectory) <> 0) and (SR.Name <> '.') and (SR.Name <> '..') then
          begin
          if SubIsScripture(D + SR.Name) then AddCand(D + SR.Name);
          end
        else if (SR.Attr and faDirectory) = 0 then
          begin
          Ext := LowerCase(ExtractFileExt(SR.Name));
          { a .zip is only tried when it looks like a USFM or USX Bible (any other zip would be unpacked for nothing) }
          if (Ext = '.zip') then
            begin
            if (Pos('usfm', LowerCase(SR.Name)) > 0) or (Pos('usx', LowerCase(SR.Name)) > 0) then AddCand(D + SR.Name);
            end
          else if (Ext <> '') and (Pos(Ext, SkipExts) = 0) then AddCand(D + SR.Name);
          end;
      until FindNext(SR) <> 0;
      FindClose(SR);
      end;
    end;
  for i := 0 to High(Cand) do
    begin
    B := NewBibObj(Cand[i]);
    if B^.OpenBible = bibOk then
      begin
      Desc := B^.GetDescription;
      if Desc = '' then Desc := B^.GetName;
      if Desc = '' then Desc := ExtractFileName(Cand[i]);
      B^.CloseBible;
      AddModEntry(Arr, Desc, Cand[i]);
      end;
    FreeBibObj(B);
    end;
end;



function IndexOfSpec(const A: TStringArray; const Spec: String): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to High(A) do if A[i] = Spec then begin Result := i; Exit; end;
end;

procedure OrderModules(var Arr: TModEntries; out NFav, NRecent: Integer);
var
  Fav, Rec: TStringArray;
  Res: TModEntries;
  Used: array of Boolean;
  Rest: TStringList;
  i, j: Integer;
begin
  Fav := LoadList('fav');
  Rec := LoadList('recent');
  SetLength(Used, Length(Arr));
  SetLength(Res, 0);
  NFav := 0; NRecent := 0;
  for j := 0 to High(Fav) do
    for i := 0 to High(Arr) do
      if (not Used[i]) and (Arr[i].Spec = Fav[j]) then
        begin AddModEntry(Res, Arr[i].Disp, Arr[i].Spec); Used[i] := True; Inc(NFav); Break; end;
  for j := 0 to High(Rec) do
    for i := 0 to High(Arr) do
      if (not Used[i]) and (Arr[i].Spec = Rec[j]) then
        begin AddModEntry(Res, Arr[i].Disp, Arr[i].Spec); Used[i] := True; Inc(NRecent); Break; end;
  Rest := TStringList.Create;
  try
    Rest.Sorted := True;
    Rest.Duplicates := dupAccept;
    for i := 0 to High(Arr) do
      if not Used[i] then Rest.AddObject(LowerCase(Arr[i].Disp) + #1 + Format('%.6d', [i]), TObject(PtrInt(i)));
    for j := 0 to Rest.Count - 1 do
      begin
      i := PtrInt(Rest.Objects[j]);
      AddModEntry(Res, Arr[i].Disp, Arr[i].Spec);
      end;
  finally
    Rest.Free;
  end;
  Arr := Res;
end;

procedure NoteRecent(const Spec: String);
var
  Rec, New: TStringArray;
  i: Integer;
begin
  if Spec = '' then Exit;
  Rec := LoadList('recent');
  SetLength(New, 1);
  New[0] := Spec;
  for i := 0 to High(Rec) do
    if (Rec[i] <> Spec) and (Length(New) < MaxRecent) then
      begin
      SetLength(New, Length(New) + 1);
      New[High(New)] := Rec[i];
      end;
  SaveList('recent', New);
end;

function IsFavorite(const Spec: String): Boolean;
begin
  Result := IndexOfSpec(LoadList('fav'), Spec) >= 0;
end;

function ToggleFavorite(const Spec: String): Boolean;
var
  Fav, New: TStringArray;
  i: Integer;
begin
  Fav := LoadList('fav');
  if IndexOfSpec(Fav, Spec) >= 0 then
    begin
    SetLength(New, 0);
    for i := 0 to High(Fav) do
      if Fav[i] <> Spec then
        begin SetLength(New, Length(New) + 1); New[High(New)] := Fav[i]; end;
    SaveList('fav', New);
    Result := False;
    end
  else
    begin
    SetLength(Fav, Length(Fav) + 1);
    Fav[High(Fav)] := Spec;
    SaveList('fav', Fav);
    Result := True;
    end;
end;

end.
