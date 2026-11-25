unit uMain;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Graphics, Forms, Controls, StdCtrls, ExtCtrls, Menus, Clipbrd, LCLType, Math, Dialogs,
  BGRABitmap, BGRABitmapTypes, BGRAVirtualScreen, BCButton, BCTypes,
  LazUTF8, Types, uTheme, uDialogs,
  MKBibMod, MKBibAbs, MKBibAny, MKBibMkp, MKBibDic, MKDicAny, mkbiblecfg, mkbiblescan;

type
  TTokKind = (tkWord, tkNum, tkHead, tkBreak, tkGap, tkNote);
  TTok = record
    Txt: String;
    Kind: TTokKind;
    Red, Ital, Bold, Mark, Glue: Boolean;   { Glue: no space before it (punctuation right after a word) }
    Strong: String;          { Strong's numbers of the word, 'H7225 G26' }
    Note: String;            { tkNote: the footnote text, or the cross references (separated by ';') }
    NoteX: Boolean;          { tkNote: a cross reference note }
    Ref: Integer;            { verse number, or the index of a search hit }
  end;
  TRun = record
    X, Y, W: Integer;
    Hard: Boolean;           { starts a new line of its own (not a soft wrap) }
    T: TTok;
  end;


  TMenuItemDef = record
    Cap, Key: String;
    Cmd: Integer;
    Sep: Boolean;
  end;
  TSelPos = record
    Run, Ch: Integer;
  end;

  THit = record
    B, C, V: Integer;
    Txt: String;
  end;

  { TMainForm }
  TMainForm = class(TForm)
  private
    Top_: TPanel;
    MenuBar, Drop, LocBox, Pane: TBGRAVirtualScreen;
    BtnMod, BtnPrev, BtnNext, BtnLoc, BtnCopy, BtnSmaller, BtnBigger: TBCButton;
    LocBook, LocHoverB, LocHoverC: Integer;
    LocEntered: Boolean;
    LocBRects: array[1..66] of TRect;
    LocCRects: array of TRect;
    DictG, DictH: AbsDictPtr;
    DictGSpec, DictHSpec: String;
    HoverRun: Integer;
    CopyNums: Boolean;        { include verse numbers when copying }
    MenuTitles: array of String;
    MenuRects: array of TRect;
    MenuOpen, MenuHover, DropHover: Integer;
    DropItems: array of TMenuItemDef;
    DropEntered: Boolean;
    SelA, SelB, SelAnchor: TSelPos;
    HasSel, Selecting, Moved: Boolean;
    DownX, DownY: Integer;
    SearchBox: TPanel;
    SearchEd: TEdit;
    TitleLbl: TLabel;
    Pop: TPopupMenu;
    Mods: TModEntries;
    Theme: TTheme;
    Dark: Boolean;
    Bib: AbsBibPtr;
    ModSpec, ModName: String;
    CurBook, CurChap: Integer;
    FontSize, FontBase: Integer;   { pixels on this screen / at 96 dpi }
    SerifName, SansName, ReadFont: String;
    Toks: array of TTok;
    Runs: array of TRun;
    ContentH, ScrollY: Integer;
    VerseY: array of Integer;
    SearchMode: Boolean;
    Hits: array of THit;
    HitTerm: String;
    procedure ShowOnce(Sender: TObject);
    procedure StrongTimer(Sender: TObject);
    procedure NoteTimer(Sender: TObject);
    procedure OpenLoc;
    procedure LocRedraw(Sender: TObject; Bitmap: TBGRABitmap);
    procedure LocMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure LocLeave(Sender: TObject);
    procedure LocUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure LocLayout;
    procedure LocClick(Sender: TObject);
    procedure BuildMenus;
    procedure OpenMenu(Idx: Integer);
    procedure CloseDrop;
    procedure DoCommand(Cmd: Integer);
    procedure MenuBarRedraw(Sender: TObject; Bitmap: TBGRABitmap);
    procedure MenuBarMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure MenuBarMouseLeave(Sender: TObject);
    procedure MenuBarMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure DropRedraw(Sender: TObject; Bitmap: TBGRABitmap);
    procedure DropMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure DropMouseLeave(Sender: TObject);
    procedure DropMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PaneMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PaneMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure PaneDblClick(Sender: TObject);
    function MeasureRun(const R: TRun; const Txt: String): Integer;
    function HitPos(X, Y: Integer): TSelPos;
    function SelText: String;
    procedure ClearSel;
    procedure CopySelection;
    procedure DoPaths;
    procedure DoStrongsDict;
    procedure CopyChapter;
    procedure ShowStrongs(RunIdx, SX, SY: Integer);
    procedure ShowNote(RunIdx, SX, SY: Integer);
    function RunAt(X, Y: Integer): Integer;
    function AutoDict(const Feature: String): String;
    function OpenDict(var D: AbsDictPtr; var Spec: String; const SettingKey, Feature: String): Boolean;
    procedure DoFont;
    procedure BuildUI;
    procedure StyleButton(B: TBCButton; Accent: Boolean);
    procedure ApplyTheme;
    procedure DoResize(Sender: TObject);
    procedure PaneRedraw(Sender: TObject; Bitmap: TBGRABitmap);
    procedure PaneWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure PaneMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure SearchKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure SearchEnter(Sender: TObject);
    procedure SearchExit(Sender: TObject);
    function SearchText: String;
    procedure ModClick(Sender: TObject);
    procedure ModPicked(Sender: TObject);
    procedure PrevClick(Sender: TObject);
    procedure NextClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure ThemeClick(Sender: TObject);
    procedure SmallerClick(Sender: TObject);
    procedure BiggerClick(Sender: TObject);
    function PickFont(const Wanted: array of String; const Fallback: String): String;
    function OpenModule(const Spec: String): Boolean;
    procedure GoChapter(B, C: Integer);
    procedure GoVerse(B, C, V: Integer);
    procedure LoadChapterToks;
    procedure AddVerseToks(const Raw: String; V: Integer);
    procedure AddPlainToks(const S: String; Ref: Integer);
    procedure LayoutRuns;
    procedure RunSearch(const Term: String);
    procedure ClampScroll;
    procedure Redraw;
    procedure SaveState;
    function MeasureText(const S: String; Size: Integer; Bold, Ital: Boolean; Serif: Boolean): Integer;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MainForm: TMainForm;

implementation

function TopH: Integer; begin Result := S_(60); end;
function ColMax: Integer; begin Result := S_(700); end;

var
  Mz: TBGRABitmap;
  Hinting: Boolean = True;

const
  SearchHint = 'Search the Bible…';

{ ------------------------------------------------------------------ construction }

constructor TMainForm.Create(TheOwner: TComponent);
var
  Cur: String;
  B, C: Integer;
begin
  inherited CreateNew(TheOwner);
  Scaled := False;
  { the application icon (gui/mkbiblegui.ico, built in as MAINICON) for the window }
  try
    Application.Icon.LoadFromResourceName(HInstance, 'MAINICON');
    Icon.Assign(Application.Icon);
  except
    { no built-in icon: the window keeps the default one }
  end;
  Caption := 'mkbible';
  Sc := Max(1.0, Screen.PixelsPerInch / 96);
  Width := S_(1120); Height := S_(740);
  Position := poScreenCenter;
  KeyPreview := True;
  OnKeyDown := @FormKey;
  OnResize := @DoResize;
  Mz := TBGRABitmap.Create(1, 1);
  ReadFont := GetSetting('gui.font', '');
  if (ReadFont <> '') and (Screen.Fonts.IndexOf(ReadFont) >= 0) then SerifName := ReadFont
  else begin ReadFont := ''; SerifName := PickFont(['Noto Serif', 'Georgia', 'Cambria', 'Liberation Serif', 'DejaVu Serif', 'Times New Roman'], 'serif'); end;
  SansName := PickFont(['Lato', 'Segoe UI', 'Cantarell', 'Noto Sans', 'DejaVu Sans', 'Arial'], 'sans');
  FontBase := Max(13, Min(32, StrToIntDef(GetSetting('gui.fontsize', '19'), 19)));
  FontSize := S_(FontBase);
  Dark := GetSetting('gui.dark', '0') = '1';
  Bib := nil;
  DictG := nil; DictH := nil; HoverRun := -1;
  CopyNums := GetSetting('gui.copy.numbers', '1') = '1';
  CurBook := 1; CurChap := 1;
  BuildUI;
  ApplyTheme;
  Cur := GetSetting('gui.module', '');
  B := StrToIntDef(GetSetting('gui.book', '1'), 1);
  C := StrToIntDef(GetSetting('gui.chapter', '1'), 1);
  if Cur = '' then LoadLast(Cur, B, C);
  if (Cur <> '') and OpenModule(Cur) then GoChapter(B, C);
  DoResize(nil);
  OnShow := @ShowOnce;
end;

procedure TMainForm.StrongTimer(Sender: TObject);
var
  CC: Integer;
begin
  (Sender as TTimer).Enabled := False;
  for CC := 0 to High(Runs) do
    if Runs[CC].T.Strong <> '' then begin ShowStrongs(CC, Runs[CC].X, Runs[CC].Y - ScrollY + 40); Break; end;
end;

procedure TMainForm.NoteTimer(Sender: TObject);
var
  CC, Want: Integer;
begin
  (Sender as TTimer).Enabled := False;
  Want := (Sender as TTimer).Tag;
  for CC := 0 to High(Runs) do
    if (Runs[CC].T.Kind = tkNote) and (Runs[CC].T.NoteX = (Want = 2)) then
      begin ShowNote(CC, Runs[CC].X, Runs[CC].Y - ScrollY + 40); Break; end;
end;

procedure TMainForm.ShowOnce(Sender: TObject);
var
  B, CC: Integer;
begin
  OnShow := nil;
  if Pane.CanFocus then Pane.SetFocus;
  { options for trying it out: --dark, --search WORD, --chapter BOOK CHAPTER }
  for B := 1 to ParamCount do
    begin
    if ParamStr(B) = '--dark' then begin Dark := True; ApplyTheme; end;
    if ParamStr(B) = '--goto' then OpenLoc;
    if (ParamStr(B) = '--menu') and (B < ParamCount) then OpenMenu(StrToIntDef(ParamStr(B + 1), 0));
    if ParamStr(B) = '--select' then
      begin
      if Length(Runs) > 10 then
        begin
        SelA.Run := 4; SelA.Ch := 2; SelB.Run := 24; SelB.Ch := 3; HasSel := True; Redraw;
        end;
      end;
    if (ParamStr(B) = '--dialog') and (B < ParamCount) then
      case ParamStr(B + 1) of
        'font': DoFont;
        'paths': DoPaths;
        'keys': DoCommand(10);
      end;
    if ParamStr(B) = '--strong' then
      with TTimer.Create(Self) do
        begin
        Interval := 1500;
        OnTimer := @StrongTimer;
        end;
    if (ParamStr(B) = '--note') or (ParamStr(B) = '--xref') then
      with TTimer.Create(Self) do
        begin
        Interval := 1500;
        if ParamStr(B) = '--xref' then Tag := 2 else Tag := 1;
        OnTimer := @NoteTimer;
        end;
    if (ParamStr(B) = '--search') and (B < ParamCount) then begin Hinting := False; SearchEd.Font.Color := Theme.Text; SearchEd.Text := ParamStr(B + 1); RunSearch(ParamStr(B + 1)); end;
    if (ParamStr(B) = '--chapter') and (B + 1 < ParamCount) then GoChapter(StrToIntDef(ParamStr(B + 1), 1), StrToIntDef(ParamStr(B + 2), 1));
    end;
end;

destructor TMainForm.Destroy;
begin
  SaveState;
  if Bib <> nil then begin Bib^.CloseBible; FreeBibObj(Bib); end;
  FreeDictObj(DictG);
  FreeDictObj(DictH);
  Mz.Free;
  inherited Destroy;
end;

function TMainForm.PickFont(const Wanted: array of String; const Fallback: String): String;
var
  i: Integer;
begin
  Result := Fallback;
  for i := 0 to High(Wanted) do
    if Screen.Fonts.IndexOf(Wanted[i]) >= 0 then begin Result := Wanted[i]; Exit; end;
end;

procedure TMainForm.StyleButton(B: TBCButton; Accent: Boolean);
begin
  StyleBtn(B, Theme, Accent);
end;

procedure TMainForm.BuildUI;

  function MakeBtn(const Cap: String; W: Integer; Click: TNotifyEvent): TBCButton;
  begin
    Result := TBCButton.Create(Self);
    Result.Parent := Top_;
    Result.Caption := Cap;
    Result.Width := W;
    Result.Height := S_(36);
    Result.OnClick := Click;
  end;

begin
  Top_ := TPanel.Create(Self);
  Top_.Parent := Self;
  Top_.Align := alTop;
  Top_.Height := TopH;
  Top_.BevelOuter := bvNone;
  MenuBar := TBGRAVirtualScreen.Create(Self);
  MenuBar.Parent := Self;
  MenuBar.Align := alTop;
  MenuBar.Height := S_(34);
  MenuBar.OnRedraw := @MenuBarRedraw;
  MenuBar.OnMouseMove := @MenuBarMouseMove;
  MenuBar.OnMouseLeave := @MenuBarMouseLeave;
  MenuBar.OnMouseUp := @MenuBarMouseUp;
  Pane := TBGRAVirtualScreen.Create(Self);
  Pane.Parent := Self;
  Pane.Align := alClient;
  Pane.OnRedraw := @PaneRedraw;
  Pane.OnMouseWheel := @PaneWheel;
  Pane.OnMouseUp := @PaneMouseUp;
  Pane.OnMouseDown := @PaneMouseDown;
  Pane.OnMouseMove := @PaneMouseMove;
  Pane.OnDblClick := @PaneDblClick;
  Pane.Cursor := crIBeam;
  BtnMod := MakeBtn('Open module', S_(230), @ModClick);
  BtnPrev := MakeBtn('‹', S_(40), @PrevClick);
  BtnLoc := MakeBtn('Go to…', S_(220), @LocClick);
  BtnNext := MakeBtn('›', S_(40), @NextClick);
  BtnCopy := MakeBtn('Copy', S_(64), @CopyClick);
  BtnSmaller := MakeBtn('A−', S_(44), @SmallerClick);
  BtnBigger := MakeBtn('A+', S_(44), @BiggerClick);
  TitleLbl := TLabel.Create(Self);
  TitleLbl.Parent := Top_;
  TitleLbl.AutoSize := True;
  SearchBox := TPanel.Create(Self);
  SearchBox.Parent := Top_;
  SearchBox.BevelOuter := bvNone;
  SearchBox.Width := S_(230);
  SearchBox.Height := S_(36);
  SearchEd := TEdit.Create(Self);
  SearchEd.Parent := SearchBox;
  SearchEd.BorderStyle := bsNone;
  SearchEd.OnEnter := @SearchEnter;
  SearchEd.OnExit := @SearchExit;
  SearchEd.OnKeyDown := @SearchKey;
  Pop := TPopupMenu.Create(Self);
  Drop := TBGRAVirtualScreen.Create(Self);
  Drop.Parent := Self;
  Drop.Visible := False;
  Drop.OnRedraw := @DropRedraw;
  Drop.OnMouseMove := @DropMouseMove;
  Drop.OnMouseLeave := @DropMouseLeave;
  Drop.OnMouseUp := @DropMouseUp;
  LocBox := TBGRAVirtualScreen.Create(Self);
  LocBox.Parent := Self;
  LocBox.Visible := False;
  LocBox.OnRedraw := @LocRedraw;
  LocBox.OnMouseMove := @LocMove;
  LocBox.OnMouseLeave := @LocLeave;
  LocBox.OnMouseUp := @LocUp;
  MenuOpen := -1; MenuHover := -1; DropHover := -1;
  BuildMenus;
end;

procedure TMainForm.ApplyTheme;
begin
  if Dark then Theme := DarkTheme else Theme := LightTheme;
  Theme.SansName := SansName;
  Color := Theme.Bg;
  Top_.Color := Theme.Bg;
  SearchBox.Color := Theme.Panel;
  SearchEd.Color := Theme.Panel;
  if Hinting then begin SearchEd.Text := SearchHint; SearchEd.Font.Color := Theme.Muted; end else SearchEd.Font.Color := Theme.Text;
  SearchEd.Font.Name := SansName;
  SearchEd.Font.Size := 11;
  TitleLbl.Font.Name := SansName;
  TitleLbl.Font.Size := 15;
  TitleLbl.Font.Style := [fsBold];
  TitleLbl.Font.Color := Theme.Text;
  StyleButton(BtnMod, True);
  StyleButton(BtnPrev, False);
  StyleButton(BtnLoc, False);
  StyleButton(BtnNext, False);
  StyleButton(BtnCopy, False);
  StyleButton(BtnSmaller, False);
  StyleButton(BtnBigger, False);
  Redraw;
end;

procedure TMainForm.DoResize(Sender: TObject);
var
  X, Y, H: Integer;
begin
  H := S_(36);
  Y := (TopH - H) div 2;
  BtnMod.SetBounds(S_(16), Y, S_(230), H);
  BtnPrev.SetBounds(S_(16) + S_(230) + S_(20), Y, S_(40), H);
  BtnLoc.SetBounds(BtnPrev.Left + S_(44), Y, S_(220), H);
  BtnNext.SetBounds(BtnLoc.Left + S_(224), Y, S_(40), H);
  TitleLbl.Left := BtnNext.Left + S_(56);
  TitleLbl.Top := (TopH - TitleLbl.Height) div 2;
  X := ClientWidth - S_(16);
  X := X - BtnBigger.Width; BtnBigger.SetBounds(X, Y, BtnBigger.Width, H);
  X := X - S_(4) - BtnSmaller.Width; BtnSmaller.SetBounds(X, Y, BtnSmaller.Width, H);
  X := X - S_(8) - BtnCopy.Width; BtnCopy.SetBounds(X, Y, BtnCopy.Width, H);
  X := X - S_(12) - SearchBox.Width; SearchBox.SetBounds(X, Y, SearchBox.Width, H);
  SearchEd.SetBounds(S_(14), (H - SearchEd.Height) div 2, SearchBox.Width - S_(28), SearchEd.Height);
  LayoutRuns;
  Redraw;
end;

{ ------------------------------------------------------------------ the module and the chapter }

function TMainForm.OpenModule(const Spec: String): Boolean;
var
  NB: AbsBibPtr;
begin
  Result := False;
  NB := NewBibObj(Spec);
  if NB^.OpenBible <> bibOk then begin FreeBibObj(NB); Exit; end;
  if Bib <> nil then begin Bib^.CloseBible; FreeBibObj(Bib); end;
  Bib := NB;
  ModSpec := Spec;
  ModName := Bib^.GetDescription;
  if ModName = '' then ModName := Bib^.GetName;
  if ModName = '' then ModName := ExtractFileName(Spec);
  if UTF8Length(ModName) > 25 then BtnMod.Caption := UTF8Copy(ModName, 1, 24) + '…' else BtnMod.Caption := ModName;
  BtnMod.Hint := ModName;
  BtnMod.ShowHint := True;
  SearchMode := False;
  CurBook := 1; CurChap := 1;
  Result := True;
end;

procedure TMainForm.GoChapter(B, C: Integer);
begin
  if Bib = nil then Exit;
  if B < 1 then B := 1;
  if B > Bib^.GetBookCount then B := Bib^.GetBookCount;
  if C < 1 then C := 1;
  if C > Bib^.GetChapterCount(B) then C := Bib^.GetChapterCount(B);
  CurBook := B; CurChap := C;
  SearchMode := False;
  ClearSel;
  HoverRun := -1;
  LoadChapterToks;
  LayoutRuns;
  ScrollY := 0;
  TitleLbl.Caption := '';
  BtnLoc.Caption := Bib^.GetBookName(B) + ' ' + IntToStr(C) + '  ▾';
  Redraw;
end;

procedure TMainForm.GoVerse(B, C, V: Integer);
begin
  GoChapter(B, C);
  if (V >= 1) and (V <= High(VerseY) + 1) then
    begin
    ScrollY := Max(0, VerseY[V - 1] - S_(70));
    ClampScroll;
    Redraw;
    end;
end;

{ one verse as tokens: the module's markup is translated to OSIS first, which carries everything we draw
  (words of Jesus, italics, bold, headings, line breaks, Strong's numbers on words) }
procedure TMainForm.AddVerseToks(const Raw: String; V: Integer);
var
  S, W, Tg, Nm, Cur, TitleBuf, NoteBuf, NoteRefs: String;
  i, j, k, NoteDepth: Integer;
  Red, Ital, Bold, InTitle, NumDone, Closing, SelfClose, Gap, WGlue, LastWord, NoteIsX: Boolean;
  QStack: array of Boolean;
  HStack: array of Char;
  T: TTok;

  procedure Push(K: TTokKind; const Txt: String);
  begin
    T.Txt := Txt; T.Kind := K; T.Red := Red; T.Ital := Ital; T.Bold := Bold; T.Mark := False; T.Ref := V;
    T.Strong := Cur;
    T.Glue := False;
    T.Note := '';
    T.NoteX := False;
    SetLength(Toks, Length(Toks) + 1);
    Toks[High(Toks)] := T;
  end;

  procedure EnsureNum;
  var
    SaveCur: String;
  begin
    if NumDone then Exit;
    NumDone := True;
    SaveCur := Cur; Cur := '';
    Push(tkNum, IntToStr(V));
    Cur := SaveCur;
  end;

  function Decode(const X: String): String;
  begin
    Result := StringReplace(StringReplace(StringReplace(StringReplace(X, '&lt;', '<', [rfReplaceAll]), '&gt;', '>', [rfReplaceAll]),
      '&quot;', '"', [rfReplaceAll]), '&amp;', '&', [rfReplaceAll]);
  end;

  function AttrOf(const Tag, Name: String): String;
  var
    P, E: Integer;
  begin
    Result := '';
    P := Pos(' ' + Name + '="', Tag);
    if P = 0 then Exit;
    P := P + Length(Name) + 3;
    E := PosEx('"', Tag, P);
    if E = 0 then E := Length(Tag) + 1;
    Result := Copy(Tag, P, E - P);
  end;

  { lemma="strong:H07225 strong:H0853"  ->  'H7225 H853' }
  function StrongsOf(const Lemma: String): String;
  var
    L, Item: String;
    P, N: Integer;
  begin
    Result := '';
    L := Lemma + ' ';
    while L <> '' do
      begin
      P := Pos(' ', L);
      Item := Copy(L, 1, P - 1);
      Delete(L, 1, P);
      if LowerCase(Copy(Item, 1, 7)) = 'strong:' then
        begin
        Item := Copy(Item, 8, Length(Item));
        if (Item <> '') and (UpCase(Item[1]) in ['G', 'H']) then
          begin
          N := StrToIntDef(Copy(Item, 2, Length(Item)), -1);
          if N >= 0 then
            begin
            if Result <> '' then Result := Result + ' ';
            Result := Result + UpCase(Item[1]) + IntToStr(N);
            end;
          end;
        end;
      end;
  end;

  procedure Flush;
  begin
    if W = '' then Exit;
    if NoteDepth > 0 then
      begin
      if NoteBuf <> '' then NoteBuf := NoteBuf + ' ';
      NoteBuf := NoteBuf + Decode(W);
      W := '';
      Exit;
      end;
    if InTitle then
      begin
      if TitleBuf <> '' then TitleBuf := TitleBuf + ' ';
      TitleBuf := TitleBuf + Decode(W);
      end
    else
      begin
      EnsureNum;
      Push(tkWord, Decode(W));
      Toks[High(Toks)].Glue := WGlue and LastWord;
      LastWord := True;
      Gap := False;
      end;
    W := '';
  end;

begin
  S := MkpTranslate(Raw, Bib^.GetMkpFormat, mfOSIS, [moHeadings]);
  Red := False; Ital := False; Bold := False; InTitle := False; NumDone := False; NoteDepth := 0;
  Cur := ''; W := ''; TitleBuf := ''; NoteBuf := ''; NoteRefs := ''; NoteIsX := False; Gap := True; WGlue := False; LastWord := False;
  SetLength(QStack, 0);
  SetLength(HStack, 0);
  i := 1;
  while i <= Length(S) do
    begin
    if S[i] = '<' then
      begin
      j := PosEx('>', S, i);
      if j = 0 then j := Length(S);
      Flush;
      Tg := Copy(S, i + 1, j - i - 1);
      SelfClose := (Tg <> '') and (Tg[Length(Tg)] = '/');
      Closing := (Tg <> '') and (Tg[1] = '/');
      k := 1;
      if Closing then k := 2;
      Nm := '';
      while (k <= Length(Tg)) and not (Tg[k] in [' ', '/', '>']) do begin Nm := Nm + LowerCase(Tg[k]); Inc(k); end;
      if Nm = 'w' then
        begin
        if Closing then Cur := '' else Cur := StrongsOf(AttrOf(Tg, 'lemma'));
        end
      else if Nm = 'q' then
        begin
        if Closing then
          begin
          if Length(QStack) > 0 then
            begin
            if QStack[High(QStack)] then Red := False;
            SetLength(QStack, Length(QStack) - 1);
            end;
          end
        else if not SelfClose then
          begin
          SetLength(QStack, Length(QStack) + 1);
          QStack[High(QStack)] := Pos('Jesus', AttrOf(Tg, 'who')) > 0;
          if QStack[High(QStack)] then Red := True;
          end;
        end
      else if Nm = 'hi' then
        begin
        if Closing then
          begin
          if Length(HStack) > 0 then
            begin
            if HStack[High(HStack)] = 'i' then Ital := False else if HStack[High(HStack)] = 'b' then Bold := False;
            SetLength(HStack, Length(HStack) - 1);
            end;
          end
        else if not SelfClose then
          begin
          SetLength(HStack, Length(HStack) + 1);
          if AttrOf(Tg, 'type') = 'bold' then begin HStack[High(HStack)] := 'b'; Bold := True; end
          else begin HStack[High(HStack)] := 'i'; Ital := True; end;
          end;
        end
      else if Nm = 'note' then
        begin
        if Closing then
          begin
          if NoteDepth > 0 then Dec(NoteDepth);
          if (NoteDepth = 0) and (Trim(NoteBuf + NoteRefs) <> '') then
            begin
            EnsureNum;
            if NoteIsX then Push(tkNote, '†') else Push(tkNote, '*');
            Toks[High(Toks)].NoteX := NoteIsX;
            Toks[High(Toks)].Glue := True;
            if NoteIsX and (NoteRefs <> '') then Toks[High(Toks)].Note := NoteRefs
            else Toks[High(Toks)].Note := Trim(NoteBuf);
            Toks[High(Toks)].Strong := '';
            end;
          end
        else if not SelfClose then
          begin
          if NoteDepth = 0 then begin NoteBuf := ''; NoteRefs := ''; NoteIsX := AttrOf(Tg, 'type') = 'crossReference'; end;
          Inc(NoteDepth);
          end;
        end
      else if (Nm = 'reference') and (NoteDepth > 0) then
        begin
        if (not Closing) and (AttrOf(Tg, 'osisRef') <> '') then
          begin
          if NoteRefs <> '' then NoteRefs := NoteRefs + ';';
          NoteRefs := NoteRefs + AttrOf(Tg, 'osisRef');
          end;
        end
      else if Nm = 'title' then
        begin
        if Closing then
          begin
          if Trim(TitleBuf) <> '' then Push(tkHead, Trim(TitleBuf));
          InTitle := False; TitleBuf := '';
          end
        else begin InTitle := True; TitleBuf := ''; end;
        end
      else if (Nm = 'lb') or (Nm = 'p') then
        begin
        if (not Closing) then begin if NumDone then Push(tkBreak, ''); LastWord := False; Gap := True; end;
        end;
      i := j + 1;
      end
    else if S[i] in [' ', #9, #10, #13] then
      begin
      Flush;
      Gap := True;
      Inc(i);
      end
    else
      begin
      if W = '' then WGlue := not Gap;
      W := W + S[i];
      Inc(i);
      end;
    end;
  Flush;
end;

procedure TMainForm.AddPlainToks(const S: String; Ref: Integer);
var
  i: Integer;
  W: String;
  T: TTok;
  Term: String;

  procedure Emit;
  begin
    if W = '' then Exit;
    T.Txt := W; T.Kind := tkWord; T.Red := False; T.Ital := False; T.Bold := False; T.Ref := Ref; T.Strong := ''; T.Glue := False; T.Note := ''; T.NoteX := False;
    T.Mark := (HitTerm <> '') and (Pos(Term, LowerCase(W)) > 0);
    SetLength(Toks, Length(Toks) + 1);
    Toks[High(Toks)] := T;
    W := '';
  end;

begin
  Term := LowerCase(HitTerm);
  W := '';
  for i := 1 to Length(S) do
    if S[i] in [' ', #9, #10, #13] then Emit else W := W + S[i];
  Emit;
end;

procedure TMainForm.LoadChapterToks;
var
  V, N: Integer;
begin
  SetLength(Toks, 0);
  if Bib = nil then Exit;
  N := Bib^.GetVerseCount(CurBook, CurChap);
  for V := 1 to N do
    begin
    Bib^.SetRef(CurBook, CurChap, V);
    AddVerseToks(Bib^.GetRawVerse, V);
    end;
  SetLength(VerseY, N);
end;

function TMainForm.MeasureText(const S: String; Size: Integer; Bold, Ital: Boolean; Serif: Boolean): Integer;
begin
  if Serif then Mz.FontName := SerifName else Mz.FontName := SansName;
  Mz.FontHeight := Size;
  Mz.FontStyle := [];
  if Bold then Mz.FontStyle := Mz.FontStyle + [fsBold];
  if Ital then Mz.FontStyle := Mz.FontStyle + [fsItalic];
  Result := Mz.TextSize(S).cx;
end;

{ greedy line breaking of the tokens into a centered column }
procedure TMainForm.LayoutRuns;
var
  ColW, X, Y, i, W, LineH, Sp, NumSz, HeadSz, Left0: Integer;
  T: TTok;
  Lines: Integer;
  NeedSp, PendHard: Boolean;

  procedure NewLine(Extra: Integer);
  begin
    X := 0; Y := Y + LineH + Extra; NeedSp := False;
  end;

  procedure AddRun(var R: TRun);
  begin
    R.Hard := PendHard;
    PendHard := False;
    SetLength(Runs, Length(Runs) + 1);
    Runs[High(Runs)] := R;
  end;

var
  R: TRun;
  CurVerse: Integer;
begin
  SetLength(Runs, 0);
  if Pane = nil then Exit;
  ColW := Min(ColMax, Pane.Width - S_(80));
  if ColW < S_(200) then ColW := S_(200);
  Left0 := (Pane.Width - ColW) div 2;
  LineH := Round(FontSize * 1.7);
  NumSz := Max(S_(10), Round(FontSize * 0.62));
  HeadSz := Max(S_(12), Round(FontSize * 0.85));
  Sp := MeasureText(' ', FontSize, False, False, not SearchMode);
  X := 0; Y := S_(34); NeedSp := False; CurVerse := 0; PendHard := False;
  for i := 0 to High(Toks) do
    begin
    T := Toks[i];
    R.T := T;
    case T.Kind of
      tkNum:
        begin
        CurVerse := T.Ref;
        if (CurVerse >= 1) and (CurVerse <= Length(VerseY)) and not SearchMode then VerseY[CurVerse - 1] := Y;
        W := MeasureText(T.Txt, NumSz, True, False, False);
        if (X > 0) and (X + Sp + W > ColW) then NewLine(0);
        if X > 0 then X := X + Sp;
        R.X := Left0 + X; R.Y := Y; R.W := W;
        AddRun(R);
        X := X + W + Max(3, Sp div 2);
        NeedSp := False;
        end;
      tkNote:
        begin
        W := MeasureText(T.Txt, Max(S_(14), Round(FontSize * 1.0)), True, False, False);
        if (X > 0) and (X + W > ColW) then NewLine(0);
        R.X := Left0 + X; R.Y := Y; R.W := W;
        AddRun(R);
        X := X + W + S_(3);
        NeedSp := True;
        end;
      tkWord:
        begin
        W := MeasureText(T.Txt, FontSize, T.Bold, T.Ital, not SearchMode);
        if T.Glue and (X > 0) then
          { punctuation stays with the word before it }
        else if (X > 0) and NeedSp and (X + Sp + W > ColW) then NewLine(0)
        else if NeedSp then X := X + Sp;
        R.X := Left0 + X; R.Y := Y; R.W := W;
        AddRun(R);
        X := X + W;
        NeedSp := True;
        end;
      tkHead:
        begin
        PendHard := Length(Runs) > 0;
        if X > 0 then NewLine(0);
        if Y > S_(40) then Y := Y + Round(LineH * 0.5);
        W := MeasureText(T.Txt, HeadSz, True, False, False);
        R.X := Left0; R.Y := Y; R.W := W;
        { a heading is one run per word, so that long ones wrap }
        R.T.Kind := tkHead;
        AddRun(R);
        Y := Y + Round(LineH * 0.9);
        X := 0; NeedSp := False; PendHard := True;
        end;
      tkBreak:
        begin
        PendHard := Length(Runs) > 0;
        if X > 0 then NewLine(0);
        end;
      tkGap:
        begin
        PendHard := Length(Runs) > 0;
        if X > 0 then NewLine(0);
        Y := Y + Round(LineH * 0.6);
        end;
    end;
    end;
  Lines := Y + LineH + S_(60);
  ContentH := Lines;
  ClampScroll;
end;

procedure TMainForm.ClampScroll;
begin
  if Pane = nil then Exit;
  ScrollY := Max(0, Min(ScrollY, ContentH - Pane.Height));
end;

procedure TMainForm.Redraw;
begin
  if MenuBar <> nil then MenuBar.DiscardBitmap;
  if Pane <> nil then Pane.DiscardBitmap;
  if LocBox <> nil then LocBox.DiscardBitmap;
end;

{ ------------------------------------------------------------------ drawing }

procedure TMainForm.PaneRedraw(Sender: TObject; Bitmap: TBGRABitmap);
var
  i, NumSz, HeadSz, Y, H, X0, X1: Integer;
  R: TRun;
  C: TBGRAPixel;
  Th: Integer;
begin
  Bitmap.Fill(Pix(Theme.Bg));
  Bitmap.FontQuality := fqFineAntialiasing;
  NumSz := Max(S_(10), Round(FontSize * 0.62));
  HeadSz := Max(S_(12), Round(FontSize * 0.85));
  H := Round(FontSize * 1.7);
  if (Bib = nil) then
    begin
    Bitmap.FontName := SansName;
    Bitmap.FontHeight := S_(20);
    Bitmap.FontStyle := [];
    Bitmap.TextOut(Pane.Width div 2, Pane.Height div 2 - S_(24), 'Choose a module to begin', Pix(Theme.Muted), taCenter);
    Exit;
    end;
  if SearchMode and (Length(Hits) = 0) then
    begin
    Bitmap.FontName := SansName;
    Bitmap.FontHeight := S_(18);
    Bitmap.FontStyle := [];
    Bitmap.TextOut(Pane.Width div 2, S_(120), 'Nothing found for “' + HitTerm + '”', Pix(Theme.Muted), taCenter);
    Exit;
  end;
  if HasSel then
    begin
    C := Pix(Theme.Accent);
    C.alpha := 80;
    for i := SelA.Run to Min(SelB.Run, High(Runs)) do
      begin
      R := Runs[i];
      Y := R.Y - ScrollY;
      if (Y > Pane.Height) or (Y + H < 0) or (R.T.Kind = tkNum) then Continue;
      X0 := R.X;
      X1 := R.X + R.W;
      if i = SelA.Run then X0 := R.X + MeasureRun(R, UTF8Copy(R.T.Txt, 1, SelA.Ch));
      if i = SelB.Run then X1 := R.X + MeasureRun(R, UTF8Copy(R.T.Txt, 1, SelB.Ch))
      else if (i < High(Runs)) and (Runs[i + 1].Y = R.Y) then X1 := Runs[i + 1].X;
      if X1 > X0 then Bitmap.FillRect(X0, Y + S_(2), X1, Y + H - S_(2), C, dmDrawWithTransparency);
      end;
    end;
  for i := 0 to High(Runs) do
    begin
    R := Runs[i];
    Y := R.Y - ScrollY;
    if (Y > Pane.Height) or (Y + H < 0) then Continue;
    case R.T.Kind of
      tkNum:
        begin
        Bitmap.FontName := SansName;
        Bitmap.FontHeight := NumSz;
        Bitmap.FontStyle := [fsBold];
        Bitmap.TextOut(R.X, Y + S_(4), R.T.Txt, Pix(Theme.Accent));
        end;
      tkNote:
        begin
        Bitmap.FontName := SansName;
        Bitmap.FontHeight := Max(S_(14), Round(FontSize * 1.0));
        Bitmap.FontStyle := [fsBold];
        if i = HoverRun then
          Bitmap.FillRoundRectAntialias(R.X - S_(4), Y + S_(3), R.X + R.W + S_(4), Y + H - S_(5), S_(5), S_(5), Pix(Theme.AccentSoft));
        Bitmap.TextOut(R.X, Y + S_(1), R.T.Txt, Pix(Theme.Accent));
        end;
      tkHead:
        begin
        Bitmap.FontName := SansName;
        Bitmap.FontHeight := HeadSz;
        Bitmap.FontStyle := [fsBold];
        if SearchMode then C := Pix(Theme.Accent) else C := Pix(Theme.Muted);
        Bitmap.TextOut(R.X, Y + S_(3), R.T.Txt, C);
        end;
      tkWord:
        begin
        if SearchMode then Bitmap.FontName := SansName else Bitmap.FontName := SerifName;
        Bitmap.FontHeight := FontSize;
        Bitmap.FontStyle := [];
        if R.T.Bold then Bitmap.FontStyle := Bitmap.FontStyle + [fsBold];
        if R.T.Ital then Bitmap.FontStyle := Bitmap.FontStyle + [fsItalic];
        if R.T.Mark then
          Bitmap.FillRoundRectAntialias(R.X - S_(2), Y + S_(3), R.X + R.W + S_(2), Y + H - S_(3), S_(4), S_(4), Pix(Theme.Mark));
        if R.T.Red then C := Pix(Theme.Red) else C := Pix(Theme.Text);
        Bitmap.TextOut(R.X, Y, R.T.Txt, C);
        if i = HoverRun then
          Bitmap.FillRect(R.X, Y + H - S_(8), R.X + R.W, Y + H - S_(8) + Max(1, S_(2)), Pix(Theme.Accent), dmSet);
        end;
    end;
    end;
  { a slim scrollbar }
  if ContentH > Pane.Height then
    begin
    Th := Max(S_(36), Round(Pane.Height * Pane.Height / ContentH));
    Y := Round(ScrollY / (ContentH - Pane.Height) * (Pane.Height - Th));
    Bitmap.FillRoundRectAntialias(Pane.Width - S_(10), Y + 2, Pane.Width - S_(4), Y + Th - 2, S_(3), S_(3), Pix(Theme.Line));
    end;
end;

{ ------------------------------------------------------------------ input }

procedure TMainForm.PaneWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  ScrollY := ScrollY - WheelDelta div 2;
  ClampScroll;
  Redraw;
  Handled := True;
end;

procedure TMainForm.PaneMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  i, H: Integer;
begin
  Selecting := False;
  if Moved then Exit;
  if HasSel then begin ClearSel; Redraw; end;
  if (not SearchMode) and (Button = mbLeft) then
    begin
    i := RunAt(X, Y);
    if (i >= 0) and (Runs[i].T.Kind = tkNote) then ShowNote(i, X, Y)
    else if (i >= 0) and (Runs[i].T.Strong <> '') then ShowStrongs(i, X, Y);
    Exit;
    end;
  if not SearchMode then Exit;
  H := Round(FontSize * 1.7);
  for i := 0 to High(Runs) do
    if (X >= Runs[i].X) and (X <= Runs[i].X + Runs[i].W + S_(40)) and (Y + ScrollY >= Runs[i].Y) and (Y + ScrollY < Runs[i].Y + H) then
      begin
      if (Runs[i].T.Ref >= 0) and (Runs[i].T.Ref < Length(Hits)) then
        begin
        SearchMode := False;
        GoVerse(Hits[Runs[i].T.Ref].B, Hits[Runs[i].T.Ref].C, Hits[Runs[i].T.Ref].V);
        end;
      Exit;
      end;
end;

procedure TMainForm.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if SearchEd.Focused then Exit;
  case Key of
    VK_LEFT: begin PrevClick(nil); Key := 0; end;
    VK_RIGHT: begin NextClick(nil); Key := 0; end;
    VK_DOWN: begin Inc(ScrollY, S_(60)); ClampScroll; Redraw; Key := 0; end;
    VK_UP: begin Dec(ScrollY, S_(60)); ClampScroll; Redraw; Key := 0; end;
    VK_NEXT: begin Inc(ScrollY, Pane.Height - S_(80)); ClampScroll; Redraw; Key := 0; end;
    VK_PRIOR: begin Dec(ScrollY, Pane.Height - S_(80)); ClampScroll; Redraw; Key := 0; end;
    VK_HOME: begin ScrollY := 0; Redraw; Key := 0; end;
    VK_END: begin ScrollY := ContentH; ClampScroll; Redraw; Key := 0; end;
    VK_ESCAPE: if LocBox.Visible then begin CloseDrop; Key := 0; end else if Drop.Visible then begin CloseDrop; Key := 0; end else if HasSel then begin ClearSel; Redraw; Key := 0; end else if SearchMode then begin GoChapter(CurBook, CurChap); Key := 0; end;
    VK_F: if ssCtrl in Shift then begin SearchEd.SetFocus; SearchEd.SelectAll; Key := 0; end;
    VK_C: if ssCtrl in Shift then begin CopyClick(nil); Key := 0; end;
    VK_A: if ssCtrl in Shift then begin DoCommand(13); Key := 0; end;
    VK_Q: if ssCtrl in Shift then begin Close; Key := 0; end;
    VK_T: if ssCtrl in Shift then begin ThemeClick(nil); Key := 0; end;
    VK_ADD, VK_OEM_PLUS: if ssCtrl in Shift then begin BiggerClick(nil); Key := 0; end;
    VK_SUBTRACT, VK_OEM_MINUS: if ssCtrl in Shift then begin SmallerClick(nil); Key := 0; end;
    VK_G: if ssCtrl in Shift then begin OpenLoc; Key := 0; end;
    VK_O: if ssCtrl in Shift then begin ModClick(nil); Key := 0; end;
  end;
end;

procedure TMainForm.SearchEnter(Sender: TObject);
begin
  if Hinting then begin SearchEd.Text := ''; SearchEd.Font.Color := Theme.Text; Hinting := False; end;
end;

procedure TMainForm.SearchExit(Sender: TObject);
begin
  if Trim(SearchEd.Text) = '' then begin Hinting := True; SearchEd.Text := SearchHint; SearchEd.Font.Color := Theme.Muted; end;
end;

function TMainForm.SearchText: String;
begin
  if Hinting then Result := '' else Result := Trim(SearchEd.Text);
end;

procedure TMainForm.SearchKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
    begin
    RunSearch(SearchText);
    Key := 0;
    end
  else if Key = VK_ESCAPE then
    begin
    SearchEd.Text := '';
    if SearchMode then GoChapter(CurBook, CurChap);
    if Pane.CanFocus then Pane.SetFocus;
    Key := 0;
    end;
end;

procedure TMainForm.RunSearch(const Term: String);
var
  B, C, V, N: Integer;
  T, L: String;
  H: THit;
begin
  if (Bib = nil) or (Term = '') then Exit;
  Screen.Cursor := crHourGlass;
  try
    SetLength(Hits, 0);
    L := LowerCase(Term);
    HitTerm := Term;
    for B := 1 to Min(66, Bib^.GetBookCount) do
      for C := 1 to Bib^.GetChapterCount(B) do
        begin
        N := Bib^.GetVerseCount(B, C);
        for V := 1 to N do
          begin
          Bib^.SetRef(B, C, V);
          T := Bib^.GetVerseText;
          if Pos(L, LowerCase(T)) > 0 then
            begin
            H.B := B; H.C := C; H.V := V; H.Txt := T;
            SetLength(Hits, Length(Hits) + 1);
            Hits[High(Hits)] := H;
            if Length(Hits) >= 400 then Break;
            end;
          end;
        if Length(Hits) >= 400 then Break;
        end;
  finally
    Screen.Cursor := crDefault;
  end;
  SearchMode := True;
  ClearSel;
  SetLength(Toks, 0);
  for N := 0 to High(Hits) do
    begin
    SetLength(Toks, Length(Toks) + 1);
    with Toks[High(Toks)] do
      begin
      Txt := Bib^.GetBookName(Hits[N].B) + ' ' + IntToStr(Hits[N].C) + ':' + IntToStr(Hits[N].V);
      Kind := tkHead; Ref := N; Red := False; Ital := False; Bold := True; Mark := False; Strong := ''; Glue := False; Note := ''; NoteX := False;
      end;
    AddPlainToks(Hits[N].Txt, N);
    end;
  TitleLbl.Caption := IntToStr(Length(Hits)) + ' verses for “' + Term + '”';
  LayoutRuns;
  ScrollY := 0;
  Redraw;
  if Pane.CanFocus then Pane.SetFocus;
end;

procedure TMainForm.PrevClick(Sender: TObject);
begin
  if Bib = nil then Exit;
  if SearchMode then begin GoChapter(CurBook, CurChap); Exit; end;
  if CurChap > 1 then GoChapter(CurBook, CurChap - 1)
  else if CurBook > 1 then GoChapter(CurBook - 1, Bib^.GetChapterCount(CurBook - 1));
end;

procedure TMainForm.NextClick(Sender: TObject);
begin
  if Bib = nil then Exit;
  if SearchMode then begin GoChapter(CurBook, CurChap); Exit; end;
  if CurChap < Bib^.GetChapterCount(CurBook) then GoChapter(CurBook, CurChap + 1)
  else if CurBook < Bib^.GetBookCount then GoChapter(CurBook + 1, 1);
end;

procedure TMainForm.CopyClick(Sender: TObject);
begin
  if HasSel then CopySelection else CopyChapter;
end;

procedure TMainForm.CopyChapter;
var
  S: String;
  V: Integer;
begin
  if (Bib = nil) or SearchMode then Exit;
  S := Bib^.GetBookName(CurBook) + ' ' + IntToStr(CurChap) + LineEnding;
  for V := 1 to Bib^.GetVerseCount(CurBook, CurChap) do
    begin
    Bib^.SetRef(CurBook, CurChap, V);
    if CopyNums then S := S + IntToStr(V) + ' ';
    S := S + Bib^.GetVerseText + LineEnding;
    end;
  Clipboard.AsText := S;
end;

procedure TMainForm.ThemeClick(Sender: TObject);
begin
  Dark := not Dark;
  ApplyTheme;
end;

procedure TMainForm.SmallerClick(Sender: TObject);
begin
  if FontBase > 13 then Dec(FontBase);
  FontSize := S_(FontBase);
  LayoutRuns; Redraw;
end;

procedure TMainForm.BiggerClick(Sender: TObject);
begin
  if FontBase < 32 then Inc(FontBase);
  FontSize := S_(FontBase);
  LayoutRuns; Redraw;
end;

procedure TMainForm.ModClick(Sender: TObject);
var
  Paths: TStringArray;
  i: Integer;
  Mi: TMenuItem;
  P: TPoint;
begin
  Paths := LoadPaths;
  SetLength(Mods, 0);
  Screen.Cursor := crHourGlass;
  try
    for i := 0 to High(Paths) do ScanDir(Paths[i], Mods);
  finally
    Screen.Cursor := crDefault;
  end;
  Pop.Items.Clear;
  if Length(Mods) = 0 then
    begin
    Mi := TMenuItem.Create(Pop);
    Mi.Caption := 'No modules found (add paths with mkbible, File, Module Paths)';
    Mi.Enabled := False;
    Pop.Items.Add(Mi);
    end;
  for i := 0 to High(Mods) do
    begin
    Mi := TMenuItem.Create(Pop);
    Mi.Caption := Mods[i].Disp;
    Mi.Tag := i;
    Mi.OnClick := @ModPicked;
    Pop.Items.Add(Mi);
    end;
  P := BtnMod.ClientToScreen(Point(0, BtnMod.Height + 4));
  Pop.PopUp(P.X, P.Y);
end;

procedure TMainForm.ModPicked(Sender: TObject);
var
  I: Integer;
begin
  I := (Sender as TMenuItem).Tag;
  if OpenModule(Mods[I].Spec) then GoChapter(1, 1)
  else ShowMessage('Could not open ' + Mods[I].Disp);
end;



{ ------------------------------------------------------------------ the book and chapter picker }

const
  LocCols = 7;         { books across }
  LocBookW = 88;
  LocBookH = 38;
  LocChapCols = 10;
  LocChapW = 42;

function LocW: Integer; begin Result := S_(16 + LocCols * LocBookW + 24 + LocChapCols * LocChapW + 16); end;
function LocH: Integer; begin Result := S_(560); end;

procedure TMainForm.LocClick(Sender: TObject);
begin
  OpenLoc;
end;

procedure TMainForm.LocLayout;
var
  i, n, rows, cw, ch, X0, Y0: Integer;
begin
  { the books: Old Testament, then New Testament, in a grid }
  for i := 1 to 66 do
    begin
    if i <= 39 then
      LocBRects[i] := Rect(S_(16 + ((i - 1) mod LocCols) * LocBookW), S_(44 + ((i - 1) div LocCols) * LocBookH),
        S_(16 + ((i - 1) mod LocCols) * LocBookW + LocBookW - 4), S_(44 + ((i - 1) div LocCols) * LocBookH + LocBookH - 4))
    else
      LocBRects[i] := Rect(S_(16 + ((i - 40) mod LocCols) * LocBookW), S_(44 + 6 * LocBookH + 52 + ((i - 40) div LocCols) * LocBookH),
        S_(16 + ((i - 40) mod LocCols) * LocBookW + LocBookW - 4), S_(44 + 6 * LocBookH + 52 + ((i - 40) div LocCols) * LocBookH + LocBookH - 4));
    end;
  { the chapters of the chosen book }
  n := 0;
  if (Bib <> nil) and (LocBook >= 1) then n := Bib^.GetChapterCount(LocBook);
  SetLength(LocCRects, n);
  if n = 0 then Exit;
  rows := (n + LocChapCols - 1) div LocChapCols;
  cw := S_(LocChapW);
  ch := Min(S_(40), (LocH - S_(44) - S_(16)) div rows);
  X0 := S_(16 + LocCols * LocBookW + 24);
  Y0 := S_(44);
  for i := 0 to n - 1 do
    LocCRects[i] := Rect(X0 + (i mod LocChapCols) * cw, Y0 + (i div LocChapCols) * ch,
      X0 + (i mod LocChapCols) * cw + cw - S_(4), Y0 + (i div LocChapCols) * ch + ch - S_(4));
end;

procedure TMainForm.OpenLoc;
begin
  if Bib = nil then Exit;
  if LocBox.Visible then begin CloseDrop; Exit; end;
  CloseDrop;
  LocBook := CurBook;
  LocHoverB := 0; LocHoverC := -1;
  LocEntered := False;
  LocLayout;
  LocBox.SetBounds(Max(S_(8), Min(BtnPrev.Left, ClientWidth - LocW - S_(8))), MenuBar.Height + TopH, LocW, LocH);
  LocBox.Visible := True;
  LocBox.BringToFront;
  LocBox.DiscardBitmap;
end;

procedure TMainForm.LocRedraw(Sender: TObject; Bitmap: TBGRABitmap);
var
  i, N: Integer;
  R: TRect;
  Fill, Txt: TColor;
  Ab: String;
begin
  Bitmap.Fill(Pix(Theme.Line));
  Bitmap.FillRect(1, 1, LocBox.Width - 1, LocBox.Height - 1, Pix(Theme.Bg), dmSet);
  Bitmap.FontQuality := fqFineAntialiasing;
  Bitmap.FontName := SansName;
  Bitmap.FontStyle := [fsBold];
  Bitmap.FontHeight := S_(12);
  Bitmap.TextOut(S_(18), S_(16), 'OLD TESTAMENT', Pix(Theme.Muted));
  Bitmap.TextOut(S_(18), S_(44 + 6 * LocBookH + 24), 'NEW TESTAMENT', Pix(Theme.Muted));
  if Bib <> nil then
    Bitmap.TextOut(S_(16 + LocCols * LocBookW + 24), S_(16), UpperCase(Bib^.GetBookName(LocBook)) + ' — CHAPTER', Pix(Theme.Muted));
  { books: the full name is in the hint line at the bottom }
  for i := 1 to Min(66, Bib^.GetBookCount) do
    begin
    R := LocBRects[i];
    if i = LocBook then begin Fill := Theme.Accent; Txt := Theme.Bg; end
    else if i = CurBook then begin Fill := Theme.AccentSoft; Txt := Theme.Accent; end
    else if i = LocHoverB then begin Fill := Theme.Hover; Txt := Theme.Text; end
    else begin Fill := Theme.Panel; Txt := Theme.Text; end;
    Bitmap.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, S_(8), S_(8), Pix(Fill));
    Ab := Bib^.GetBookAbbrev(i);
    if Ab = '' then Ab := Copy(Bib^.GetBookName(i), 1, 4);
    Bitmap.FontHeight := S_(15);
    Bitmap.FontStyle := [];
    Bitmap.TextOut((R.Left + R.Right - Bitmap.TextSize(Ab).cx) div 2, R.Top + S_(8), Ab, Pix(Txt));
    end;
  { chapters }
  N := Length(LocCRects);
  for i := 0 to N - 1 do
    begin
    R := LocCRects[i];
    if (LocBook = CurBook) and (i + 1 = CurChap) then begin Fill := Theme.Accent; Txt := Theme.Bg; end
    else if i = LocHoverC then begin Fill := Theme.AccentSoft; Txt := Theme.Accent; end
    else begin Fill := Theme.Panel; Txt := Theme.Text; end;
    Bitmap.FillRoundRectAntialias(R.Left, R.Top, R.Right, R.Bottom, S_(8), S_(8), Pix(Fill));
    Bitmap.FontHeight := S_(14);
    Bitmap.FontStyle := [];
    Bitmap.TextOut((R.Left + R.Right - Bitmap.TextSize(IntToStr(i + 1)).cx) div 2, (R.Top + R.Bottom) div 2 - S_(9), IntToStr(i + 1), Pix(Txt));
    end;
  { the name of the book under the pointer }
  if (LocHoverB >= 1) and (Bib <> nil) then
    begin
    Bitmap.FontHeight := S_(13);
    Bitmap.FontStyle := [];
    Bitmap.TextOut(S_(18), LocBox.Height - S_(30), Bib^.GetBookName(LocHoverB), Pix(Theme.Muted));
    end;
end;

procedure TMainForm.LocMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  i, HB, HC: Integer;
  P: TPoint;
begin
  LocEntered := True;
  P := Point(X, Y);
  HB := 0; HC := -1;
  for i := 1 to 66 do
    if PtInRect(LocBRects[i], P) then HB := i;
  for i := 0 to High(LocCRects) do
    if PtInRect(LocCRects[i], P) then HC := i;
  if (HB <> LocHoverB) or (HC <> LocHoverC) then
    begin
    LocHoverB := HB; LocHoverC := HC;
    LocBox.DiscardBitmap;
    end;
end;

procedure TMainForm.LocLeave(Sender: TObject);
begin
  if LocEntered then CloseDrop;
end;

procedure TMainForm.LocUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
  P: TPoint;
begin
  if Bib = nil then Exit;
  P := Point(X, Y);
  for i := 1 to Min(66, Bib^.GetBookCount) do
    if PtInRect(LocBRects[i], P) then
      begin
      if Bib^.GetChapterCount(i) = 1 then begin CloseDrop; GoChapter(i, 1); Exit; end;
      LocBook := i;
      LocLayout;
      LocBox.DiscardBitmap;
      Exit;
      end;
  for i := 0 to High(LocCRects) do
    if PtInRect(LocCRects[i], P) then
      begin
      CloseDrop;
      GoChapter(LocBook, i + 1);
      Exit;
      end;
end;

{ ------------------------------------------------------------------ menus }

const
  cmOpen = 1; cmPaths = 2; cmCopySel = 3; cmCopyChap = 4; cmQuit = 5; cmTheme = 6; cmBigger = 7; cmSmaller = 8;
  cmFont = 9; cmStrongs = 14; cmCopyNums = 15; cmGoto = 16; cmKeys = 10; cmAbout = 11; cmFind = 12; cmSelAll = 13;

procedure TMainForm.BuildMenus;
begin
  SetLength(MenuTitles, 4);
  MenuTitles[0] := 'File';
  MenuTitles[1] := 'View';
  MenuTitles[2] := 'Settings';
  MenuTitles[3] := 'Help';
  SetLength(MenuRects, 4);
end;

procedure TMainForm.MenuBarRedraw(Sender: TObject; Bitmap: TBGRABitmap);
var
  i, X, W: Integer;
begin
  Bitmap.Fill(Pix(Theme.Bg));
  Bitmap.FontQuality := fqFineAntialiasing;
  Bitmap.FontName := SansName;
  Bitmap.FontHeight := S_(15);
  Bitmap.FontStyle := [];
  X := S_(10);
  for i := 0 to High(MenuTitles) do
    begin
    W := Bitmap.TextSize(MenuTitles[i]).cx + S_(28);
    MenuRects[i] := Rect(X, S_(4), X + W, MenuBar.Height - S_(2));
    if (i = MenuOpen) or (i = MenuHover) then
      Bitmap.FillRoundRectAntialias(X, S_(4), X + W, MenuBar.Height - S_(2), S_(8), S_(8), Pix(Theme.Hover));
    Bitmap.TextOut(X + S_(14), S_(7), MenuTitles[i], Pix(Theme.Text));
    X := X + W + S_(2);
    end;
end;

procedure TMainForm.MenuBarMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  i, H: Integer;
begin
  H := -1;
  for i := 0 to High(MenuRects) do
    if PtInRect(MenuRects[i], Point(X, Y)) then H := i;
  if H <> MenuHover then begin MenuHover := H; MenuBar.DiscardBitmap; end;
  if (H >= 0) and (MenuOpen >= 0) and (H <> MenuOpen) then OpenMenu(H);
end;

procedure TMainForm.MenuBarMouseLeave(Sender: TObject);
begin
  if MenuHover <> -1 then begin MenuHover := -1; MenuBar.DiscardBitmap; end;
end;

procedure TMainForm.MenuBarMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
begin
  for i := 0 to High(MenuRects) do
    if PtInRect(MenuRects[i], Point(X, Y)) then
      begin
      if MenuOpen = i then CloseDrop else OpenMenu(i);
      Exit;
      end;
  CloseDrop;
end;

procedure TMainForm.OpenMenu(Idx: Integer);

  procedure Add(const Cap, Key: String; Cmd: Integer);
  begin
    SetLength(DropItems, Length(DropItems) + 1);
    DropItems[High(DropItems)].Cap := Cap;
    DropItems[High(DropItems)].Key := Key;
    DropItems[High(DropItems)].Cmd := Cmd;
    DropItems[High(DropItems)].Sep := Cmd = 0;
  end;

var
  i, H: Integer;
begin
  SetLength(DropItems, 0);
  case Idx of
    0: begin
       Add('Open module…', 'Ctrl+O', cmOpen);
       Add('', '', 0);
       Add('Copy (selection, else the chapter)', 'Ctrl+C', cmCopySel);
       Add('Copy the whole chapter', '', cmCopyChap);
       Add('Select chapter text', 'Ctrl+A', cmSelAll);
       Add('', '', 0);
       Add('Quit', 'Ctrl+Q', cmQuit);
       end;
    1: begin
       Add('Larger text', 'Ctrl++', cmBigger);
       Add('Smaller text', 'Ctrl+−', cmSmaller);
       Add('', '', 0);
       if Dark then Add('Light theme', 'Ctrl+T', cmTheme) else Add('Dark theme', 'Ctrl+T', cmTheme);
       Add('', '', 0);
       Add('Go to book and chapter…', 'Ctrl+G', cmGoto);
       Add('Find in the Bible', 'Ctrl+F', cmFind);
       end;
    2: begin
       Add('Module folders…', '', cmPaths);
       Add('Reading font…', '', cmFont);
       Add('Strong''s dictionaries…', '', cmStrongs);
       Add('', '', 0);
       if CopyNums then Add('Copy with verse numbers: on', '', cmCopyNums) else Add('Copy with verse numbers: off', '', cmCopyNums);
       end;
    3: begin
       Add('Keyboard shortcuts', '', cmKeys);
       Add('About mkbible', '', cmAbout);
       end;
  end;
  H := S_(10);
  for i := 0 to High(DropItems) do if DropItems[i].Sep then Inc(H, S_(13)) else Inc(H, S_(34));
  MenuOpen := Idx;
  DropHover := -1;
  DropEntered := False;
  Drop.SetBounds(MenuRects[Idx].Left, MenuBar.Top + MenuBar.Height, S_(300), H);
  Drop.Visible := True;
  Drop.BringToFront;
  Drop.DiscardBitmap;
  MenuBar.DiscardBitmap;
end;

procedure TMainForm.CloseDrop;
begin
  if LocBox.Visible then LocBox.Visible := False;
  if Drop.Visible then Drop.Visible := False;
  if MenuOpen <> -1 then begin MenuOpen := -1; MenuBar.DiscardBitmap; end;
end;

procedure TMainForm.DropRedraw(Sender: TObject; Bitmap: TBGRABitmap);
var
  i, Y, IH: Integer;
begin
  Bitmap.Fill(Pix(Theme.Line));
  Bitmap.FillRect(1, 1, Drop.Width - 1, Drop.Height - 1, Pix(Theme.Bg), dmSet);
  Bitmap.FontQuality := fqFineAntialiasing;
  Bitmap.FontName := SansName;
  Y := S_(5);
  for i := 0 to High(DropItems) do
    begin
    if DropItems[i].Sep then
      begin
      Bitmap.FillRect(S_(12), Y + S_(6), Drop.Width - S_(12), Y + S_(7), Pix(Theme.Line), dmSet);
      Inc(Y, S_(13));
      Continue;
      end;
    IH := S_(34);
    if i = DropHover then Bitmap.FillRoundRectAntialias(S_(6), Y, Drop.Width - S_(6), Y + IH, S_(8), S_(8), Pix(Theme.AccentSoft));
    Bitmap.FontHeight := S_(15);
    Bitmap.FontStyle := [];
    Bitmap.TextOut(S_(18), Y + S_(7), DropItems[i].Cap, Pix(Theme.Text));
    if DropItems[i].Key <> '' then
      begin
      Bitmap.FontHeight := S_(13);
      Bitmap.TextOut(Drop.Width - S_(18), Y + S_(9), DropItems[i].Key, Pix(Theme.Muted), taRightJustify);
      end;
    Inc(Y, IH);
    end;
end;

procedure TMainForm.DropMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  i, YY, Hov: Integer;
begin
  DropEntered := True;
  Hov := -1;
  YY := S_(5);
  for i := 0 to High(DropItems) do
    if DropItems[i].Sep then Inc(YY, S_(13))
    else
      begin
      if (Y >= YY) and (Y < YY + S_(34)) then Hov := i;
      Inc(YY, S_(34));
      end;
  if Hov <> DropHover then begin DropHover := Hov; Drop.DiscardBitmap; end;
end;

procedure TMainForm.DropMouseLeave(Sender: TObject);
begin
  if DropEntered then CloseDrop;
end;

procedure TMainForm.DropMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Cmd: Integer;
begin
  DropMouseMove(Sender, Shift, X, Y);
  if DropHover < 0 then Exit;
  Cmd := DropItems[DropHover].Cmd;
  CloseDrop;
  DoCommand(Cmd);
end;

procedure TMainForm.DoCommand(Cmd: Integer);
var
  i: Integer;
begin
  case Cmd of
    cmOpen: ModClick(nil);
    cmPaths: DoPaths;
    cmCopySel: CopyClick(nil);
    cmCopyChap: CopyChapter;
    cmQuit: Close;
    cmTheme: ThemeClick(nil);
    cmBigger: BiggerClick(nil);
    cmSmaller: SmallerClick(nil);
    cmFont: DoFont;
    cmStrongs: DoStrongsDict;
    cmGoto: OpenLoc;
    cmCopyNums:
      begin
      CopyNums := not CopyNums;
      PutSetting('gui.copy.numbers', IntToStr(Ord(CopyNums)));
      end;
    cmFind: begin SearchEd.SetFocus; SearchEd.SelectAll; end;
    cmSelAll:
      if Length(Runs) > 0 then
        begin
        SelA.Run := 0; SelA.Ch := 0;
        SelB.Run := High(Runs); SelB.Ch := UTF8Length(Runs[High(Runs)].T.Txt);
        HasSel := True;
        Redraw;
        end;
    cmKeys: InfoDialog(Self, Theme, 'Keyboard shortcuts',
      'Left / Right: previous / next chapter' + LineEnding +
      'Up / Down, Page Up / Page Down, Home / End: scroll' + LineEnding +
      'Ctrl+G: go to a book and chapter' + LineEnding + 'Ctrl+F: search, Esc: clear the search or the selection' + LineEnding +
      'Ctrl+O: open a module' + LineEnding +
      'Ctrl+C: copy the selected text (the whole chapter when nothing is selected)' + LineEnding +
      'Ctrl+A: select the chapter text' + LineEnding +
      'Ctrl++ / Ctrl+−: text size' + LineEnding +
      'Ctrl+T: light / dark theme' + LineEnding +
      'Ctrl+Q: quit' + LineEnding + LineEnding +
      'Select text with the mouse (drag, or double-click a word).');
    cmAbout: InfoDialog(Self, Theme, 'About mkbible',
      'mkbible, a simple Bible reader.' + LineEnding + LineEnding +
      'Reads Sword, theWord, MySword, STEP, OSIS, Zefania, USFX, USFM, USX, Beblia, Unbound and verse-per-line ' +
      'modules with the same Bible objects as the text mode reader.' + LineEnding + LineEnding +
      'Drawn with BGRABitmap and BGRAControls on Lazarus.');
  end;
  i := 0;
end;

procedure TMainForm.DoPaths;
var
  P: TStringArray;
begin
  P := LoadPaths;
  if PathsDialog(Self, Theme, P) then SavePaths(P);
end;

procedure TMainForm.DoFont;
var
  N: String;
  Sz: Integer;
begin
  N := ReadFont;
  Sz := FontBase;
  if not FontDialog(Self, Theme, N, Sz,
    'In the beginning God created the heavens and the earth. And the earth was waste and void; and darkness was upon the face of the deep.') then Exit;
  ReadFont := N;
  if (N <> '') and (Screen.Fonts.IndexOf(N) >= 0) then SerifName := N
  else SerifName := PickFont(['Noto Serif', 'Georgia', 'Cambria', 'Liberation Serif', 'DejaVu Serif', 'Times New Roman'], 'serif');
  FontBase := Max(13, Min(32, Sz));
  FontSize := S_(FontBase);
  PutSetting('gui.font', ReadFont);
  ClearSel;
  LayoutRuns;
  Redraw;
end;

{ ------------------------------------------------------------------ selecting text in the reading pane }

function TMainForm.MeasureRun(const R: TRun; const Txt: String): Integer;
begin
  case R.T.Kind of
    tkNum: Result := MeasureText(Txt, Max(S_(10), Round(FontSize * 0.62)), True, False, False);
    tkNote: Result := MeasureText(Txt, Max(S_(14), Round(FontSize * 1.0)), True, False, False);
    tkHead: Result := MeasureText(Txt, Max(S_(12), Round(FontSize * 0.85)), True, False, False);
  else
    Result := MeasureText(Txt, FontSize, R.T.Bold, R.T.Ital, not SearchMode);
  end;
end;

procedure TMainForm.ClearSel;
begin
  HasSel := False;
  Selecting := False;
  Moved := False;
end;

{ the run and the character offset under a point (the nearest one when the point is outside the text) }
function TMainForm.HitPos(X, Y: Integer): TSelPos;
var
  i, H, Line, First, Last, Len, K, WPrev, WK: Integer;
  yy: Integer;
begin
  Result.Run := 0;
  Result.Ch := 0;
  if Length(Runs) = 0 then Exit;
  H := Round(FontSize * 1.7);
  yy := Y + ScrollY;
  Line := -1;
  for i := 0 to High(Runs) do
    if Runs[i].Y <= yy then Line := Runs[i].Y else Break;
  if Line < 0 then Line := Runs[0].Y;
  First := -1; Last := -1;
  for i := 0 to High(Runs) do
    if Runs[i].Y = Line then begin if First < 0 then First := i; Last := i; end;
  if First < 0 then Exit;
  if X <= Runs[First].X then begin Result.Run := First; Exit; end;
  for i := First to Last do
    if (X < Runs[i].X + Runs[i].W) or (i = Last) or (X < Runs[i + 1].X) then
      begin
      Result.Run := i;
      if X >= Runs[i].X + Runs[i].W then begin Result.Ch := UTF8Length(Runs[i].T.Txt); Exit; end;
      Len := UTF8Length(Runs[i].T.Txt);
      WPrev := 0;
      for K := 1 to Len do
        begin
        WK := MeasureRun(Runs[i], UTF8Copy(Runs[i].T.Txt, 1, K));
        if X - Runs[i].X < (WPrev + WK) div 2 then begin Result.Ch := K - 1; Exit; end;
        WPrev := WK;
        end;
      Result.Ch := Len;
      Exit;
      end;
end;

procedure TMainForm.PaneMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  CloseDrop;
  if Pane.CanFocus then Pane.SetFocus;
  if Button <> mbLeft then Exit;
  Selecting := True;
  Moved := False;
  DownX := X; DownY := Y;
  SelAnchor := HitPos(X, Y);
  if HasSel then begin HasSel := False; Redraw; end;
end;

procedure TMainForm.PaneMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  P: TSelPos;
  R: Integer;
begin
  if not Selecting then
    begin
    R := -1;
    if not SearchMode then
      begin
      R := RunAt(X, Y);
      if (R >= 0) and (Runs[R].T.Strong = '') and (Runs[R].T.Kind <> tkNote) then R := -1;
      end;
    if R <> HoverRun then
      begin
      HoverRun := R;
      if R >= 0 then Pane.Cursor := crHandPoint else Pane.Cursor := crIBeam;
      Pane.DiscardBitmap;
      end;
    Exit;
    end;
  if (not Moved) and (Abs(X - DownX) < 4) and (Abs(Y - DownY) < 4) then Exit;
  Moved := True;
  if Y < 0 then Dec(ScrollY, S_(24)) else if Y > Pane.Height then Inc(ScrollY, S_(24));
  ClampScroll;
  P := HitPos(X, Y);
  if (P.Run < SelAnchor.Run) or ((P.Run = SelAnchor.Run) and (P.Ch < SelAnchor.Ch)) then begin SelA := P; SelB := SelAnchor; end
  else begin SelA := SelAnchor; SelB := P; end;
  HasSel := (SelA.Run <> SelB.Run) or (SelA.Ch <> SelB.Ch);
  Pane.DiscardBitmap;
end;

procedure TMainForm.PaneDblClick(Sender: TObject);
var
  P: TSelPos;
begin
  if SearchMode then Exit;
  P := HitPos(DownX, DownY);
  if (P.Run < 0) or (P.Run > High(Runs)) or (Runs[P.Run].T.Kind <> tkWord) then Exit;
  SelA.Run := P.Run; SelA.Ch := 0;
  SelB.Run := P.Run; SelB.Ch := UTF8Length(Runs[P.Run].T.Txt);
  HasSel := True;
  Moved := True;
  Pane.DiscardBitmap;
end;

function TMainForm.SelText: String;
var
  i, C0, C1: Integer;
  T: String;
begin
  Result := '';
  if not HasSel then Exit;
  for i := SelA.Run to Min(SelB.Run, High(Runs)) do
    begin
    if (Runs[i].T.Kind = tkNum) and ((not CopyNums) or ((i = SelA.Run) and (SelA.Ch > 0)) or ((i = SelB.Run) and (SelB.Ch = 0))) then Continue;
    if Runs[i].T.Kind = tkNote then Continue;
    T := Runs[i].T.Txt;
    C0 := 0;
    C1 := UTF8Length(T);
    if i = SelA.Run then C0 := SelA.Ch;
    if i = SelB.Run then C1 := SelB.Ch;
    T := UTF8Copy(T, C0 + 1, C1 - C0);
    if T = '' then Continue;
    if Result <> '' then
      begin
      if Runs[i].Hard or (Runs[i].T.Kind = tkHead) then Result := Result + LineEnding
      else if not Runs[i].T.Glue then Result := Result + ' ';
      end;
    Result := Result + T;
    end;
end;

procedure TMainForm.CopySelection;
begin
  if HasSel then Clipboard.AsText := SelText;
end;


{ ------------------------------------------------------------------ Strong's numbers }

function TMainForm.RunAt(X, Y: Integer): Integer;
var
  i, H: Integer;
begin
  Result := -1;
  H := Round(FontSize * 1.7);
  for i := 0 to High(Runs) do
    if (Runs[i].T.Kind = tkNote) and (X >= Runs[i].X - S_(4)) and (X <= Runs[i].X + Runs[i].W + S_(4)) and
       (Y + ScrollY >= Runs[i].Y) and (Y + ScrollY < Runs[i].Y + H) then
      begin
      Result := i;
      Exit;
      end;
  for i := 0 to High(Runs) do
    if (Runs[i].T.Kind = tkWord) and (X >= Runs[i].X) and (X <= Runs[i].X + Runs[i].W) and
       (Y + ScrollY >= Runs[i].Y) and (Y + ScrollY < Runs[i].Y + H) then
      begin
      Result := i;
      Exit;
      end;
end;

{ the first Sword module on the module paths that has the Feature (GreekDef / HebrewDef) }
function TMainForm.AutoDict(const Feature: String): String;
var
  Paths: TStringArray;
  i: Integer;
  SR: TSearchRec;
  L: TStringList;
  D: String;
begin
  Result := '';
  Paths := LoadPaths;
  L := TStringList.Create;
  try
    for i := 0 to High(Paths) do
      begin
      D := IncludeTrailingPathDelimiter(Paths[i]) + 'mods.d' + PathDelim;
      if FindFirst(D + '*.conf', faAnyFile, SR) = 0 then
        begin
        repeat
          L.LoadFromFile(D + SR.Name);
          if Pos('feature=' + LowerCase(Feature), LowerCase(StringReplace(L.Text, ' ', '', [rfReplaceAll]))) > 0 then
            begin
            Result := D + SR.Name;
            FindClose(SR);
            Exit;
            end;
        until FindNext(SR) <> 0;
        FindClose(SR);
        end;
      end;
  finally
    L.Free;
  end;
end;

function TMainForm.OpenDict(var D: AbsDictPtr; var Spec: String; const SettingKey, Feature: String): Boolean;
var
  Use: String;
begin
  Result := D <> nil;
  if Result then Exit;
  Use := GetSetting(SettingKey, '');
  if (Use = '') or not FileExists(Use) then Use := AutoDict(Feature);
  if Use = '' then Exit;
  D := NewDictObj(Use);
  if D^.OpenBible <> bibOk then begin FreeDictObj(D); Exit; end;
  Spec := Use;
  Result := True;
end;

procedure TMainForm.ShowStrongs(RunIdx, SX, SY: Integer);
var
  Nums: TStringList;
  i, Idx: Integer;
  Body, One, Key: String;
  D: AbsDictPtr;
  Got: Boolean;
  P: TPoint;
begin
  Nums := TStringList.Create;
  try
    Nums.Delimiter := ' ';
    Nums.StrictDelimiter := True;
    Nums.DelimitedText := Runs[RunIdx].T.Strong;
    Body := '';
    for i := 0 to Nums.Count - 1 do
      begin
      Key := Nums[i];
      if Key = '' then Continue;
      if UpCase(Key[1]) = 'G' then
        begin Got := OpenDict(DictG, DictGSpec, 'gui.strongs.greek', 'GreekDef'); D := DictG; end
      else
        begin Got := OpenDict(DictH, DictHSpec, 'gui.strongs.hebrew', 'HebrewDef'); D := DictH; end;
      if Body <> '' then Body := Body + LineEnding + LineEnding;
      if Nums.Count > 1 then Body := Body + Key + LineEnding;
      if not Got then
        begin
        if UpCase(Key[1]) = 'G' then One := 'No Strong''s Greek dictionary found.' else One := 'No Strong''s Hebrew dictionary found.';
        Body := Body + One + LineEnding + 'Add the folder with the Sword StrongsGreek / StrongsHebrew modules under Settings, Module folders, or pick a dictionary under Settings, Strong''s dictionaries.';
        Continue;
        end;
      Idx := D^.FindKey(Key);
      if Idx = 0 then Body := Body + 'No entry for ' + Key + ' in this dictionary.'
      else Body := Body + Trim(D^.GetEntryTextAt(Idx));
      end;
    P := Pane.ClientToScreen(Point(SX, SY));
    StrongsPopup(Self, Theme, Runs[RunIdx].T.Strong + '   ' + Runs[RunIdx].T.Txt, Body, P);
  finally
    Nums.Free;
  end;
end;


{ ------------------------------------------------------------------ footnotes and cross references }

procedure TMainForm.ShowNote(RunIdx, SX, SY: Integer);
var
  Body, Item, Human, Lbl: String;
  Items: TStringList;
  i, V, V2, P: Integer;
  R, R2: BibRef;
  Ok: Boolean;
  Pt: TPoint;

  function Human_(const Ref: String): String;
  begin
    if (Pos('.', Ref) > 0) and (Pos(' ', Ref) = 0) then Result := MkpOsisToHuman(Ref) else Result := Ref;
  end;

begin
  Pt := Pane.ClientToScreen(Point(SX, SY));
  if not Runs[RunIdx].T.NoteX then
    begin
    StrongsPopup(Self, Theme, 'Note', Runs[RunIdx].T.Note, Pt);
    Exit;
    end;
  Items := TStringList.Create;
  try
    Items.Delimiter := ';';
    Items.StrictDelimiter := True;
    Items.DelimitedText := Runs[RunIdx].T.Note;
    Body := '';
    for i := 0 to Items.Count - 1 do
      begin
      Item := Trim(Items[i]);
      if Item = '' then Continue;
      if Body <> '' then Body := Body + LineEnding + LineEnding;
      { a range (Gen.1.1-Gen.1.3, or John 1:1-3) is looked up as its first verse and the verses up to the last }
      V2 := 0;
      Human := Human_(Item);
      P := Pos('-', Item);
      if P > 0 then
        begin
        Human := Human_(Copy(Item, 1, P - 1));
        Lbl := Trim(Copy(Item, P + 1, Length(Item)));
        if StrToIntDef(Lbl, -1) > 0 then V2 := StrToInt(Lbl)
        else if Bib^.ParseRef(Human_(Lbl), R2) then V2 := R2.Verse;
        end;
      Ok := (Bib <> nil) and Bib^.ParseRef(Human, R);
      if Ok and (not Bib^.ValidRef(R.Book, R.Chapter, R.Verse)) then Ok := False;
      if not Ok then begin Body := Body + Item; Continue; end;
      if (V2 < R.Verse) or (V2 > R.Verse + 11) then V2 := R.Verse;
      Lbl := Bib^.GetBookName(R.Book) + ' ' + IntToStr(R.Chapter) + ':' + IntToStr(R.Verse);
      if V2 > R.Verse then Lbl := Lbl + '–' + IntToStr(V2);
      Body := Body + Lbl;
      for V := R.Verse to V2 do
        if Bib^.ValidRef(R.Book, R.Chapter, V) then
          begin
          Bib^.SetRef(R.Book, R.Chapter, V);
          Body := Body + LineEnding + Trim(Bib^.GetVerseText);
          end;
      end;
  finally
    Items.Free;
  end;
  StrongsPopup(Self, Theme, 'Cross references', Body, Pt);
end;

procedure TMainForm.DoStrongsDict;
var
  G, H: String;
begin
  G := GetSetting('gui.strongs.greek', '');
  H := GetSetting('gui.strongs.hebrew', '');
  if StrongsDialog(Self, Theme, G, H, AutoDict('GreekDef'), AutoDict('HebrewDef')) then
    begin
    PutSetting('gui.strongs.greek', G);
    PutSetting('gui.strongs.hebrew', H);
    FreeDictObj(DictG);
    FreeDictObj(DictH);
    end;
end;

procedure TMainForm.SaveState;
begin
  PutSetting('gui.dark', IntToStr(Ord(Dark)));
  PutSetting('gui.fontsize', IntToStr(FontBase));
  if Bib <> nil then
    begin
    PutSetting('gui.module', ModSpec);
    PutSetting('gui.book', IntToStr(CurBook));
    PutSetting('gui.chapter', IntToStr(CurChap));
    end;
end;

end.
