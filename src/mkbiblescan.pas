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

implementation

uses
  SysUtils, MKBibMod, MKBibAbs, MKBibAny;

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


end.
