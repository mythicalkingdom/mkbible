program mkbible;
{$mode objfpc}{$H+}
{ mkbible - a simple text mode Bible reader with an always visible menu bar (unlike MKEdit's, which
  only appears while a menu is open).

  usage: mkbible [module]
    module   a Sword module name or .conf, a MySword .mybible file, a theWord .ont/.ontx/.ot/.nt
             file, a STEP directory, or a .vpl, OSIS, Zefania, Haggai, USFX, USFM, USX, Beblia or Unbound file.  With none, mkbible resumes where it left off.

  Left/Right        previous / next chapter
  Up/Down/PgUp/PgDn/Home/End   scroll the chapter text
  Alt+B             Book/Chapter... (a pick list of the 66 books, then of that book's chapters)
  Alt+O             Open Module...  (a pick list of the modules found on the configured paths)
  Alt+C             Copy Chapter    (the chapter's text, to the system clipboard)
  F10 or Esc        the menu bar    Alt+<letter> also opens a menu directly
  F1                this key list   q             quit }

uses
  SysUtils, StrUtils, RegExpr, Process, BaseUnix, termio, Math, base64,
  Video, uScreen, uCP437, uKeys, uPick,
  MKBibMod, MKBibAbs, MKBibAny, mkbiblecfg, mkbiblescan;

const
  VERSION = '0.1.0';
  cmNone        = 0;
  cmOpenModule  = 1;
  cmPaths       = 2;
  cmQuit        = 3;
  cmBookChapter = 4;
  cmCopy        = 5;
  cmKeys        = 6;
  cmAbout       = 7;
  cmFind        = 8;
  cmFindNext    = 9;
  cmFindPrev    = 10;
  cmResults     = 11;
  cmClearHi     = 12;
  cmColors      = 13;
  cmCase        = 14;
  cmRegex       = 15;
  MaxHits       = 5000;
  BibOTBooksN   = 39;

  ColorNames: array[0..15] of String = ('Black', 'Blue', 'Green', 'Cyan', 'Red', 'Magenta', 'Brown', 'Light gray',
    'Dark gray', 'Light blue', 'Light green', 'Light cyan', 'Light red', 'Light magenta', 'Yellow', 'White');

type
  THit = record
    B, C, V: Integer;
    Snip: String;
  end;
  TColorItem = record
    Name, Key: String;
    Fg, Bg: PByte;               { Bg = nil: only the foreground is a setting }
    DefFg, DefBg: Byte;
  end;

var
  { colours: foreground 0..15, background 0..7 (the same palette MKEdit defaults to); the menu, dialog and
    list colours are in uPick }
  cTextFg: Byte = 7;   cTextBg: Byte = 1;
  cStatFg: Byte = 0;   cStatBg: Byte = 3;
  cNumFg: Byte = 14;                       { verse numbers }
  cFindFg: Byte = 0;   cFindBg: Byte = 6;  { a search hit }
  Colors: array of TColorItem;
  Hits: array of THit;
  HitCount, HitIdx, LastScope: Integer;
  SearchTerm, LastSearch: String;
  SearchCase, SearchRegex: Boolean;
  HiRegex, HiCase: Boolean;                { how the term on screen was searched for }
  Re: TRegExpr;
  HiBook, HiChap, HiVerse: Integer;        { the verse of the hit being shown }
  LineVerse: array of Integer;
  LineFirst: array of Boolean;
  Menus: TMenuDefs;
  Bib: AbsBibPtr;
  ModSpec: String;
  CurBook, CurChap: Integer;
  Lines: array of String;
  Top: Integer;
  Paths: TStringArray;
  StatusMsg: String;
  Quitting: Boolean;
  Resized: Boolean;

{ ===================================================================== menu bar }

procedure BuildMenus;
var CaseMark: String;
begin
  SetLength(Menus, 6);
  Menus[0].Title := '&File';
  SetLength(Menus[0].Items, 3);
  Menus[0].Items[0].Text := '&Open Module...'; Menus[0].Items[0].Cmd := cmOpenModule;
  Menus[0].Items[1].Text := 'Module &Paths...'; Menus[0].Items[1].Cmd := cmPaths;
  Menus[0].Items[2].Text := '&Quit';            Menus[0].Items[2].Cmd := cmQuit;
  Menus[1].Title := '&Go';
  SetLength(Menus[1].Items, 1);
  Menus[1].Items[0].Text := '&Book/Chapter...  Alt+B'; Menus[1].Items[0].Cmd := cmBookChapter;
  Menus[2].Title := '&Search';
  SetLength(Menus[2].Items, 5);
  Menus[2].Items[0].Text := '&Find...  /';           Menus[2].Items[0].Cmd := cmFind;
  Menus[2].Items[1].Text := 'Find &Next  n  F3';     Menus[2].Items[1].Cmd := cmFindNext;
  Menus[2].Items[2].Text := 'Find &Previous  N';     Menus[2].Items[2].Cmd := cmFindPrev;
  Menus[2].Items[3].Text := '&Results...';           Menus[2].Items[3].Cmd := cmResults;
  Menus[2].Items[4].Text := '&Clear Highlight';      Menus[2].Items[4].Cmd := cmClearHi;
  Menus[3].Title := '&Edit';
  SetLength(Menus[3].Items, 1);
  Menus[3].Items[0].Text := '&Copy Chapter  Alt+C'; Menus[3].Items[0].Cmd := cmCopy;
  Menus[4].Title := 'Se&ttings';
  SetLength(Menus[4].Items, 3);
  if SearchCase then CaseMark := '[x]' else CaseMark := '[ ]';
  Menus[4].Items[0].Text := '&Colors...';                         Menus[4].Items[0].Cmd := cmColors;
  Menus[4].Items[1].Text := CaseMark + ' Case &Sensitive Search'; Menus[4].Items[1].Cmd := cmCase;
  if SearchRegex then CaseMark := '[x]' else CaseMark := '[ ]';
  Menus[4].Items[2].Text := CaseMark + ' &Regular Expression Search'; Menus[4].Items[2].Cmd := cmRegex;
  Menus[5].Title := '&Help';
  SetLength(Menus[5].Items, 2);
  Menus[5].Items[0].Text := '&Keys  F1'; Menus[5].Items[0].Cmd := cmKeys;
  Menus[5].Items[1].Text := '&About';    Menus[5].Items[1].Cmd := cmAbout;
end;

{ ===================================================================== drawing }

function StatusLine: String;
begin
  if Bib = nil then Result := 'mkbible - no module open  (Alt+O to open one)'
  { the reference comes first so it is never crowded out by a long module description }
  else Result := Bib^.GetBookName(CurBook) + ' ' + IntToStr(CurChap) + '   ' + Bib^.GetDescription;
end;

procedure DrawLine(i, y: Integer);
var
  S, Low, Pat: String;
  P, From, VL, Col: Integer;
begin
  S := Lines[i];
  ScrPutsN(1, y, S, ScrW - 2, cTextFg, cTextBg);
  From := 1;
  if LineFirst[i] then
    begin
    VL := Length(IntToStr(LineVerse[i]));
    if (LineVerse[i] = HiVerse) and (HiBook = CurBook) and (HiChap = CurChap) then
      ScrAttr(1, y, VL, cFindFg, cFindBg)
    else ScrAttr(1, y, VL, cNumFg, cTextBg);
    From := VL + 2;
    end;
  if SearchTerm <> '' then
    begin
    if HiRegex then
      begin
      try
        if Re.Exec(S) then
          repeat
            if (Re.MatchPos[0] >= From) and (Re.MatchLen[0] > 0) then
              ScrAttr(1 + Utf8Len(Copy(S, 1, Re.MatchPos[0] - 1)), y, Utf8Len(Copy(S, Re.MatchPos[0], Re.MatchLen[0])),
                      cFindFg, cFindBg);
          until not Re.ExecNext;
      except
        { a pattern that fails on this line is simply not highlighted }
      end;
      end
    else
      begin
      if HiCase then begin Low := S; Pat := SearchTerm; end
      else begin Low := LowerCase(S); Pat := LowerCase(SearchTerm); end;
      repeat
        P := PosEx(Pat, Low, From);
        if P = 0 then Break;
        Col := 1 + Utf8Len(Copy(S, 1, P - 1));
        ScrAttr(Col, y, Utf8Len(Pat), cFindFg, cFindBg);
        From := P + Length(Pat);
      until False;
      end;
    end;
end;

procedure RedrawScreen;
var
  i, h: Integer;
begin
  ScrClear(cTextFg, cTextBg);
  DrawMenuBar(Menus, -1);
  ScrFill(0, 1, ScrW, 32, cStatFg, cStatBg);
  ScrPutsN(1, 1, StatusLine, ScrW - 2, cStatFg, cStatBg);
  h := Max(1, ScrH - 3);
  for i := 0 to h - 1 do
    if Top + i <= High(Lines) then DrawLine(Top + i, 2 + i);
  ScrFill(0, ScrH - 1, ScrW, 32, cStatFg, cStatBg);
  if StatusMsg <> '' then ScrPutsN(1, ScrH - 1, StatusMsg, ScrW - 2, cStatFg, cStatBg)
  else ScrPutsN(1, ScrH - 1,
    'Alt+B:Book  Alt+O:Open  /:Find  n:Next  Alt+C:Copy  F1:Help  Esc:Menu  q:Quit',
    ScrW - 2, cStatFg, cStatBg);
  ScrHideCursor;
  ScrFlush;
end;

{ ===================================================================== chapter text }

function SplitWords(const S: String): TStringArray;
var
  i, Start, N: Integer;
begin
  SetLength(Result, 0);
  N := 0;
  i := 1;
  while i <= Length(S) do begin
    while (i <= Length(S)) and (S[i] = ' ') do Inc(i);
    if i > Length(S) then Break;
    Start := i;
    while (i <= Length(S)) and (S[i] <> ' ') do Inc(i);
    SetLength(Result, N + 1);
    Result[N] := Copy(S, Start, i - Start);
    Inc(N);
  end;
end;

procedure LoadChapter;
var
  v, n: Integer;

  procedure AppendLine(const S: String; First: Boolean);
  begin
    SetLength(Lines, Length(Lines) + 1);
    Lines[High(Lines)] := S;
    SetLength(LineVerse, Length(Lines));
    SetLength(LineFirst, Length(Lines));
    LineVerse[High(Lines)] := v;
    LineFirst[High(Lines)] := First;
  end;

  procedure WrapVerse(VNum: Integer; const Txt: String);
  var
    Prefix, Indent, Cur: String;
    Words: TStringArray;
    i, MaxW: Integer;
    FirstOut: Boolean;
  begin
    Prefix := IntToStr(VNum) + ' ';
    Indent := StringOfChar(' ', Length(Prefix));
    MaxW := Max(10, ScrW - 2);
    Words := SplitWords(Txt);
    Cur := Prefix;
    FirstOut := True;
    for i := 0 to High(Words) do begin
      if (Cur <> Prefix) and (Cur <> Indent) and (Length(Cur) + 1 + Length(Words[i]) > MaxW) then begin
        AppendLine(Cur, FirstOut);
        FirstOut := False;
        Cur := Indent;
      end;
      if (Cur = Prefix) or (Cur = Indent) then Cur := Cur + Words[i]
      else Cur := Cur + ' ' + Words[i];
    end;
    AppendLine(Cur, FirstOut);
  end;

begin
  SetLength(Lines, 0);
  SetLength(LineVerse, 0);
  SetLength(LineFirst, 0);
  Top := 0;
  if Bib = nil then Exit;
  n := Bib^.GetVerseCount(CurBook, CurChap);
  for v := 1 to n do begin
    Bib^.SetRef(CurBook, CurChap, v);
    WrapVerse(v, Bib^.GetVerseText);
  end;
end;

procedure GotoChapter(B, C: Integer);
begin
  if Bib = nil then Exit;
  CurBook := B; CurChap := C;
  LoadChapter;
  SaveLast(ModSpec, CurBook, CurChap);
end;

procedure NextChapter;
begin
  if Bib = nil then Exit;
  if CurChap < Bib^.GetChapterCount(CurBook) then GotoChapter(CurBook, CurChap + 1)
  else if CurBook < Bib^.GetBookCount then GotoChapter(CurBook + 1, 1);
end;

procedure PrevChapter;
begin
  if Bib = nil then Exit;
  if CurChap > 1 then GotoChapter(CurBook, CurChap - 1)
  else if CurBook > 1 then GotoChapter(CurBook - 1, Bib^.GetChapterCount(CurBook - 1));
end;

{ ===================================================================== commands }

procedure GoBookChapter;
var
  Names: array of String;
  i, b, c, sel: Integer;
begin
  if Bib = nil then begin ShowMessage('', ['Open a module first (Alt+O).'], @RedrawScreen); Exit; end;
  SetLength(Names, Bib^.GetBookCount);
  for i := 0 to High(Names) do Names[i] := Bib^.GetBookName(i + 1);
  sel := PickList('Book', Names, CurBook - 1, @RedrawScreen);
  if sel < 0 then Exit;
  b := sel + 1;
  SetLength(Names, Bib^.GetChapterCount(b));
  for i := 0 to High(Names) do Names[i] := 'Chapter ' + IntToStr(i + 1);
  if b = CurBook then sel := CurChap - 1 else sel := 0;
  sel := PickList(Bib^.GetBookName(b), Names, sel, @RedrawScreen);
  if sel < 0 then Exit;
  c := sel + 1;
  GotoChapter(b, c);
end;

procedure DoOpenModule;
var
  Entries: TModEntries;
  Disp: array of String;
  i, sel: Integer;
  NewBib: AbsBibPtr;
begin
  SetLength(Entries, 0);
  for i := 0 to High(Paths) do ScanDir(Paths[i], Entries);
  if Length(Entries) = 0 then
    begin
    ShowMessage('', ['No Bible modules found on the configured paths.',
                      'Use Alt+F, Module Paths... to add one.'], @RedrawScreen);
    Exit;
    end;
  SetLength(Disp, Length(Entries));
  for i := 0 to High(Entries) do Disp[i] := Entries[i].Disp;
  sel := PickList('Open Module', Disp, 0, @RedrawScreen);
  if sel < 0 then Exit;
  NewBib := NewBibObj(Entries[sel].Spec);
  if NewBib^.OpenBible <> bibOk then
    begin
    ShowMessage('', ['Could not open ' + Entries[sel].Disp], @RedrawScreen);
    FreeBibObj(NewBib);
    Exit;
    end;
  if Bib <> nil then begin Bib^.CloseBible; FreeBibObj(Bib); end;
  Bib := NewBib;
  ModSpec := Entries[sel].Spec;
  CurBook := 1; CurChap := 1;
  LoadChapter;
  SaveLast(ModSpec, CurBook, CurChap);
end;

procedure DoPaths;
var
  Disp: array of String;
  i, sel: Integer;
  NewPath: String;
  Deleted: Boolean;
begin
  repeat
    SetLength(Disp, Length(Paths) + 1);
    for i := 0 to High(Paths) do Disp[i] := Paths[i];
    Disp[High(Disp)] := '+ Add a path...';
    sel := PickListDel('Module Paths  (Enter edits, Del removes, Esc when done)', Disp, 0, @RedrawScreen, Deleted);
    if sel < 0 then Break;
    if Deleted then
      begin
      if sel < High(Disp) then
        begin
        for i := sel to High(Paths) - 1 do Paths[i] := Paths[i + 1];
        SetLength(Paths, Length(Paths) - 1);
        SavePaths(Paths);
        end;
      end
    else if sel = High(Disp) then
      begin
      if PromptLine('Directory to search for Bible modules:', '', @RedrawScreen, NewPath) and (NewPath <> '') then
        begin
        SetLength(Paths, Length(Paths) + 1);
        Paths[High(Paths)] := NewPath;
        SavePaths(Paths);
        end;
      end
    else
      begin
      if PromptLine('Directory to search for Bible modules:', Paths[sel], @RedrawScreen, NewPath) and (NewPath <> '') then
        begin
        Paths[sel] := NewPath;
        SavePaths(Paths);
        end;
      end;
  until False;
end;

function RunWithStdin(const Exe: String; const Args: array of String; const Data: String): Boolean;
var
  P: TProcess;
  i: Integer;
begin
  Result := False;
  P := TProcess.Create(nil);
  try
    P.Executable := Exe;
    for i := 0 to High(Args) do P.Parameters.Add(Args[i]);
    P.Options := [poUsePipes];
    try
      P.Execute;
    except
      Exit(False);
    end;
    if Length(Data) > 0 then P.Input.Write(Data[1], Length(Data));
    P.CloseInput;
    P.WaitOnExit;
    Result := P.ExitStatus = 0;
  finally
    P.Free;
  end;
end;

procedure SendOSC52(const S: String);
begin
  Write(#27']52;c;' + EncodeStringBase64(S) + #7);
  Flush(StdOut);
end;

function CopyToClipboard(const S: String): String;
begin
  if RunWithStdin('xclip', ['-selection', 'clipboard'], S) then Exit('Copied to the clipboard (xclip)');
  if RunWithStdin('xsel', ['--clipboard', '--input'], S) then Exit('Copied to the clipboard (xsel)');
  if RunWithStdin('wl-copy', [], S) then Exit('Copied to the clipboard (wl-copy)');
  SendOSC52(S);
  Result := 'Sent to the terminal''s clipboard (OSC 52) - works if your terminal supports it';
end;

procedure DoCopyChapter;
var
  S: String;
  i: Integer;
begin
  if Bib = nil then begin ShowMessage('', ['Nothing to copy - open a module first.'], @RedrawScreen); Exit; end;
  S := Bib^.GetDescription + ' - ' + Bib^.GetBookName(CurBook) + ' ' + IntToStr(CurChap) + LineEnding + LineEnding;
  for i := 1 to Bib^.GetVerseCount(CurBook, CurChap) do
    begin
    Bib^.SetRef(CurBook, CurChap, i);
    S := S + IntToStr(i) + ' ' + Bib^.GetVerseText + LineEnding;
    end;
  StatusMsg := CopyToClipboard(S);
end;

{ ---- colours ---- }
procedure AddColor(const Name, Key: String; Fg, Bg: PByte; DFg, DBg: Byte);
begin
  SetLength(Colors, Length(Colors) + 1);
  Colors[High(Colors)].Name := Name;
  Colors[High(Colors)].Key := Key;
  Colors[High(Colors)].Fg := Fg;
  Colors[High(Colors)].Bg := Bg;
  Colors[High(Colors)].DefFg := DFg;
  Colors[High(Colors)].DefBg := DBg;
end;

procedure InitColors;
begin
  SetLength(Colors, 0);
  AddColor('Text', 'text', @cTextFg, @cTextBg, 7, 1);
  AddColor('Verse numbers', 'numbers', @cNumFg, nil, 14, 0);
  AddColor('Search hit', 'find', @cFindFg, @cFindBg, 0, 6);
  AddColor('Status lines', 'status', @cStatFg, @cStatBg, 0, 3);
  AddColor('Menu bar', 'menu', @cBarFg, @cBarBg, 0, 7);
  AddColor('Selected menu title', 'menuselect', @cBarSelFg, @cBarSelBg, 15, 1);
  AddColor('Menu hot letter', 'menuhot', @cHotFg, nil, 4, 0);
  AddColor('Dialog boxes', 'box', @cBoxFg, @cBoxBg, 15, 1);
  AddColor('Selected list item', 'select', @cSelFg, @cSelBg, 0, 7);
end;

function ColorText(i: Integer): String;
begin
  Result := Colors[i].Name + StringOfChar(' ', Max(1, 22 - Length(Colors[i].Name))) + ColorNames[Colors[i].Fg^];
  if Colors[i].Bg <> nil then Result := Result + ' on ' + ColorNames[Colors[i].Bg^];
end;

{ "color_<key> = fg,bg" lines of the configuration file }
procedure LoadColors;
var
  i, P, F, B: Integer;
  V: String;
begin
  for i := 0 to High(Colors) do
    begin
    V := GetSetting('color_' + Colors[i].Key, '');
    if V = '' then Continue;
    P := Pos(',', V);
    if P = 0 then P := Length(V) + 1;
    F := StrToIntDef(Trim(Copy(V, 1, P - 1)), -1);
    B := StrToIntDef(Trim(Copy(V, P + 1, 10)), -1);
    if (F >= 0) and (F <= 15) then Colors[i].Fg^ := F;
    if (Colors[i].Bg <> nil) and (B >= 0) and (B <= 7) then Colors[i].Bg^ := B;
    end;
end;

procedure SaveColor(i: Integer);
var V: String;
begin
  V := IntToStr(Colors[i].Fg^);
  if Colors[i].Bg <> nil then V := V + ',' + IntToStr(Colors[i].Bg^) else V := V + ',0';
  PutSetting('color_' + Colors[i].Key, V);
end;

procedure DoColors;
var
  Disp: array of String;
  i, sel, f, b: Integer;
begin
  sel := 0;
  repeat
    SetLength(Disp, Length(Colors) + 1);
    for i := 0 to High(Colors) do Disp[i] := ColorText(i);
    Disp[High(Disp)] := 'Reset all colours to the defaults';
    sel := PickList('Colors  (Enter changes one, Esc when done)', Disp, sel, @RedrawScreen);
    if sel < 0 then Break;
    if sel = High(Disp) then
      begin
      for i := 0 to High(Colors) do
        begin
        Colors[i].Fg^ := Colors[i].DefFg;
        if Colors[i].Bg <> nil then Colors[i].Bg^ := Colors[i].DefBg;
        SaveColor(i);
        end;
      Continue;
      end;
    f := PickList(Colors[sel].Name + ' - foreground', ColorNames, Colors[sel].Fg^, @RedrawScreen);
    if f < 0 then Continue;
    Colors[sel].Fg^ := f;
    if Colors[sel].Bg <> nil then
      begin
      b := PickList(Colors[sel].Name + ' - background', Slice(ColorNames, 8), Colors[sel].Bg^, @RedrawScreen);
      if b >= 0 then Colors[sel].Bg^ := b;
      end;
    SaveColor(sel);
  until False;
end;

{ ---- search ---- }
procedure ClearHighlight;
begin
  SearchTerm := '';
  HiBook := 0; HiChap := 0; HiVerse := 0;
end;

{ show hit Idx: its chapter, scrolled so that the verse is in view }
procedure ShowHit(Idx: Integer);
var
  i, h: Integer;
begin
  if (Idx < 0) or (Idx >= HitCount) then Exit;
  HitIdx := Idx;
  HiBook := Hits[Idx].B; HiChap := Hits[Idx].C; HiVerse := Hits[Idx].V;
  GotoChapter(HiBook, HiChap);
  h := Max(1, ScrH - 3);
  for i := 0 to High(Lines) do
    if LineFirst[i] and (LineVerse[i] = HiVerse) then
      begin
      if (i < Top) or (i >= Top + h) then Top := Max(0, i - 1);
      if Top > Max(0, High(Lines) - h + 1) then Top := Max(0, High(Lines) - h + 1);
      Break;
      end;
  StatusMsg := 'Hit ' + IntToStr(Idx + 1) + ' of ' + IntToStr(HitCount) + ':  ' + Bib^.GetBookName(HiBook) + ' ' +
    IntToStr(HiChap) + ':' + IntToStr(HiVerse);
end;

{ False: the regular expression does not compile (the message is in ErrText) }
function RunSearch(const Term: String; Scope: Integer; out ErrText: String): Boolean;
var
  Cap, B, C, V, B1, B2: Integer;
  T: String;

  procedure AddHit(Bk, Ch, Vs: Integer; const Txt: String);
  begin
    if HitCount >= Cap then begin Cap := Cap * 2; SetLength(Hits, Cap); end;
    Hits[HitCount].B := Bk;
    Hits[HitCount].C := Ch;
    Hits[HitCount].V := Vs;
    Hits[HitCount].Snip := Copy(Txt, 1, 200);
    Inc(HitCount);
  end;

begin
  Result := True;
  ErrText := '';
  HitCount := 0; HitIdx := -1;
  Cap := 256;
  SetLength(Hits, Cap);
  if SearchRegex then
    begin
    try
      Re.Expression := Term;
      Re.ModifierI := not SearchCase;
      Re.Exec('');                                   { compiles it; an error is raised here }
    except
      on E: Exception do begin ErrText := E.Message; Result := False; SetLength(Hits, 0); Exit; end;
    end;
    end;
  StatusMsg := 'Searching...';
  RedrawScreen;
  StatusMsg := '';
  Bib^.SetRef(CurBook, CurChap, 1);
  if SearchRegex then
    begin
    B1 := 1; B2 := Bib^.GetBookCount;
    case Scope of
      1: B2 := Min(B2, BibOTBooksN);
      2: B1 := BibOTBooksN + 1;
      3: begin B1 := CurBook; B2 := CurBook; end;
    end;
    for B := B1 to B2 do
      for C := 1 to Bib^.GetChapterCount(B) do
        for V := 1 to Bib^.GetVerseCount(B, C) do
          begin
          if HitCount >= MaxHits then Break;
          Bib^.SetRef(B, C, V);
          T := Bib^.GetVerseText;
          if (T <> '') and Re.Exec(T) then AddHit(B, C, V, T);
          end;
    end
  else
    begin
    case Scope of
      1: Bib^.SetSearchScope(bsOT);
      2: Bib^.SetSearchScope(bsNT);
      3: Bib^.SetSearchScope(bsBook);
      else Bib^.SetSearchScope(bsAll);
    end;
    Bib^.SearchFirst(Term, SearchCase);
    while Bib^.SearchFound and (HitCount < MaxHits) do
      begin
      AddHit(Bib^.GetBook, Bib^.GetChapter, Bib^.GetVerse, Bib^.GetVerseText);
      Bib^.SearchNext;
      end;
    end;
  SetLength(Hits, HitCount);
  Bib^.SetRef(CurBook, CurChap, 1);
end;

procedure ShowResults;
var
  Disp: array of String;
  i, sel: Integer;
begin
  if HitCount = 0 then
    begin ShowMessage('', ['No search results yet - use Search, Find... (/)'], @RedrawScreen); Exit; end;
  SetLength(Disp, HitCount);
  for i := 0 to HitCount - 1 do
    Disp[i] := Bib^.GetBookName(Hits[i].B) + ' ' + IntToStr(Hits[i].C) + ':' + IntToStr(Hits[i].V) + '  ' + Hits[i].Snip;
  sel := PickList('"' + LastSearch + '" - ' + IntToStr(HitCount) + ' verses', Disp, Max(HitIdx, 0), @RedrawScreen);
  if sel >= 0 then ShowHit(sel);
end;

procedure DoFind;
var
  S, Err: String;
  Scopes: array of String;
  sc: Integer;
begin
  if Bib = nil then begin ShowMessage('', ['Open a module first (Alt+O).'], @RedrawScreen); Exit; end;
  if not PromptLine('Find ' + IfThen(SearchRegex, 'regular expression', 'text') + ' (' + IfThen(SearchCase, 'case sensitive', 'any case') + '):',
                    LastSearch, @RedrawScreen, S) then Exit;
  S := Trim(S);
  if S = '' then Exit;
  SetLength(Scopes, 4);
  Scopes[0] := 'The whole Bible'; Scopes[1] := 'Old Testament'; Scopes[2] := 'New Testament';
  Scopes[3] := 'This book: ' + Bib^.GetBookName(CurBook);
  sc := PickList('Search in', Scopes, LastScope, @RedrawScreen);
  if sc < 0 then Exit;
  LastScope := sc;
  LastSearch := S;
  SearchTerm := S;
  PutSetting('search.text', S);
  if not RunSearch(S, sc, Err) then
    begin
    SearchTerm := '';
    ShowMessage('Not a valid regular expression', [Err], @RedrawScreen);
    Exit;
    end;
  HiRegex := SearchRegex;
  HiCase := SearchCase;
  if HitCount = 0 then
    begin
    ShowMessage('', ['No verse contains "' + S + '".'], @RedrawScreen);
    Exit;
    end;
  if HitCount >= MaxHits then StatusMsg := 'Only the first ' + IntToStr(MaxHits) + ' verses are listed.';
  ShowResults;
end;

procedure FindNext(Backwards: Boolean);
begin
  if Bib = nil then Exit;
  if HitCount = 0 then begin DoFind; Exit; end;
  if Backwards then
    begin
    if HitIdx <= 0 then ShowHit(HitCount - 1) else ShowHit(HitIdx - 1);
    end
  else if HitIdx + 1 >= HitCount then ShowHit(0)
  else ShowHit(HitIdx + 1);
  if SearchTerm = '' then SearchTerm := LastSearch;
end;

procedure ToggleRegex;
begin
  SearchRegex := not SearchRegex;
  PutSetting('search.regex', IfThen(SearchRegex, '1', '0'));
  BuildMenus;
  StatusMsg := IfThen(SearchRegex, 'Searches use regular expressions', 'Searches are plain text');
end;

procedure ToggleCase;
begin
  SearchCase := not SearchCase;
  PutSetting('search.case', IfThen(SearchCase, '1', '0'));
  BuildMenus;
  StatusMsg := IfThen(SearchCase, 'Searches are case sensitive', 'Searches ignore case');
end;

procedure ShowKeys;
begin
  ShowMessage('mkbible ' + VERSION + ' - keys', [
    'Left / Right        previous / next chapter',
    'Up / Down            scroll one line',
    'PgUp / PgDn / Home / End   scroll a page / to the top or bottom',
    'Alt+B                Book/Chapter...  (pick a book, then a chapter)',
    'Alt+O                Open Module...',
    'Alt+C                Copy Chapter  (to the system clipboard)',
    '/                    Find text (whole Bible, a testament or this book); lists the verses',
    'n  or  F3            next hit          N  or  Shift+F3    previous hit',
    'Settings menu        Colors...,  case sensitive search,  regular expression search',
    'F10 or Esc           the menu bar          Alt+<letter>  opens a menu directly',
    'F1                   this list             q             quit'],
    @RedrawScreen);
end;

procedure ShowAbout;
begin
  ShowMessage('', [
    'mkbible ' + VERSION,
    'A simple text mode Bible reader, built on this project''s Bible objects',
    '(Sword, MySword, theWord, STEP, .vpl) and on MKEdit''s terminal toolkit.'],
    @RedrawScreen);
end;

procedure DoCmd(Cmd: Integer);
begin
  case Cmd of
    cmOpenModule: DoOpenModule;
    cmPaths: DoPaths;
    cmQuit: Quitting := True;
    cmBookChapter: GoBookChapter;
    cmCopy: DoCopyChapter;
    cmKeys: ShowKeys;
    cmAbout: ShowAbout;
    cmFind: DoFind;
    cmFindNext: FindNext(False);
    cmFindPrev: FindNext(True);
    cmResults: ShowResults;
    cmClearHi: ClearHighlight;
    cmColors: DoColors;
    cmCase: ToggleCase;
    cmRegex: ToggleRegex;
  end;
end;

{ ===================================================================== main loop }

procedure CheckResize;
var
  ws: TWinSize;
  m: TVideoMode;
begin
  if fpIoctl(1, TIOCGWINSZ, @ws) = 0 then
    if (ws.ws_col > 0) and ((ws.ws_col <> ScreenWidth) or (ws.ws_row <> ScreenHeight)) then
      begin
      GetVideoMode(m);
      m.Col := ws.ws_col;
      m.Row := ws.ws_row;
      SetVideoMode(m);
      UpdateScreen(True);
      Resized := True;
      end;
end;

function WaitKey: TKey;
begin
  repeat
    if KeyRead(Result) then Exit;
    if Hangup then begin Result.code := kcChar; Result.mods := []; Result.ch := 'q'; Result.n := 0; Exit; end;
    CheckResize;
    if Resized then begin Resized := False; Result.code := kcNone; Result.mods := []; Result.ch := ''; Exit; end;
    KeyWait(100);
  until False;
end;

procedure RunApp;
var
  k: TKey;
  h, i: Integer;
  c: Char;
  cmd: Integer;
begin
  Quitting := False;
  repeat
    RedrawScreen;
    k := WaitKey;
    h := Max(1, ScrH - 3);
    StatusMsg := '';
    case k.code of
      kcNone: ;
      kcEsc: begin cmd := RunMenuBar(Menus, 0, False, @RedrawScreen); DoCmd(cmd); end;
      kcF: if k.n = 10 then begin cmd := RunMenuBar(Menus, 0, False, @RedrawScreen); DoCmd(cmd); end
           else if k.n = 1 then ShowKeys
           else if k.n = 3 then FindNext(mShift in k.mods);
      kcLeft: PrevChapter;
      kcRight: NextChapter;
      kcUp: if Top > 0 then Dec(Top);
      kcDown: if Top < High(Lines) - h + 1 then Inc(Top);
      kcPgUp: Top := Max(0, Top - h);
      kcPgDn: Top := Max(0, Min(High(Lines) - h + 1, Top + h));
      kcHome: Top := 0;
      kcEnd: Top := Max(0, High(Lines) - h + 1);
      kcChar: if (Length(k.ch) = 1) then
        begin
        c := UpCase(k.ch[1]);
        if mAlt in k.mods then
          begin
          if c = 'B' then GoBookChapter
          else if c = 'O' then DoOpenModule
          else if c = 'C' then DoCopyChapter
          else
            begin
            cmd := cmNone;
            for i := 0 to High(Menus) do
              if MnemonicOf(Menus[i].Title) = c then
                begin cmd := RunMenuBar(Menus, i, True, @RedrawScreen); Break; end;
            DoCmd(cmd);
            end;
          end
        else if (k.mods = []) and (c = 'Q') then Quitting := True
        else if (k.mods = []) and (k.ch = '/') then DoFind
        else if (k.mods = []) and (k.ch = 'n') then FindNext(False)
        else if (k.mods = []) and (k.ch = 'N') then FindNext(True);
        end;
    end;
  until Quitting;
end;

{ ===================================================================== startup }

procedure ClampPosition;
begin
  if Bib = nil then Exit;
  if CurBook < 1 then CurBook := 1;
  if CurBook > Bib^.GetBookCount then CurBook := Bib^.GetBookCount;
  if CurChap < 1 then CurChap := 1;
  if CurChap > Bib^.GetChapterCount(CurBook) then CurChap := Bib^.GetChapterCount(CurBook);
end;

var
  Failure: String;
begin
  if (IsATTY(0) = 0) or (IsATTY(1) = 0) then
    begin
    WriteLn(StdErr, 'mkbible: standard input and output must be a terminal');
    Halt(1);
    end;
  InitColors;
  LoadColors;
  SearchCase := GetSetting('search.case', '0') = '1';
  SearchRegex := GetSetting('search.regex', '0') = '1';
  HiRegex := False; HiCase := False;
  Re := TRegExpr.Create;
  LastSearch := GetSetting('search.text', '');
  LastScope := 0; HitCount := 0; HitIdx := -1; SearchTerm := '';
  BuildMenus;
  Paths := LoadPaths;
  Bib := nil; ModSpec := ''; CurBook := 1; CurChap := 1; StatusMsg := '';
  if ParamCount >= 1 then ModSpec := ParamStr(1) else LoadLast(ModSpec, CurBook, CurChap);
  if ModSpec <> '' then
    begin
    Bib := NewBibObj(ModSpec);
    if Bib^.OpenBible <> bibOk then begin FreeBibObj(Bib); Bib := nil; ModSpec := ''; end;
    end;
  ClampPosition;
  Failure := '';
  InitVideo;
  KeysInit;
  try
    try
      if Bib <> nil then LoadChapter;
      RunApp;
      if Bib <> nil then SaveLast(ModSpec, CurBook, CurChap);
    except
      on E: Exception do Failure := E.ClassName + ': ' + E.Message;
    end;
  finally
    KeysDone;
    DoneVideo;
  end;
  if Bib <> nil then begin Bib^.CloseBible; FreeBibObj(Bib); end;
  if Failure <> '' then begin WriteLn(StdErr, 'mkbible: ', Failure); Halt(2); end;
  Write(#27'[2J'#27'[H');
end.
