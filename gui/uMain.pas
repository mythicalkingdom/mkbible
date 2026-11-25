unit uMain;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Graphics, Forms, Controls, StdCtrls, ExtCtrls, Menus, Clipbrd, LCLType, Math, Dialogs,
  BGRABitmap, BGRABitmapTypes, BGRAVirtualScreen, BCButton, BCTypes,
  MKBibMod, MKBibAbs, MKBibAny, MKBibMkp, mkbiblecfg, mkbiblescan;

type
  TTheme = record
    Bg, Panel, Text, Muted, Accent, AccentSoft, Red, Line, Hover, Mark: TColor;
  end;

  TTokKind = (tkWord, tkNum, tkHead, tkBreak, tkGap);
  TTok = record
    Txt: String;
    Kind: TTokKind;
    Red, Ital, Bold, Mark: Boolean;
    Ref: Integer;            { verse number, or the index of a search hit }
  end;
  TRun = record
    X, Y, W: Integer;
    T: TTok;
  end;

  TSideRow = record
    Kind: Integer;           { 0 testament label, 1 book, 2 chapter grid }
    Book, Y, H: Integer;
    Txt: String;
  end;

  THit = record
    B, C, V: Integer;
    Txt: String;
  end;

  { TMainForm }
  TMainForm = class(TForm)
  private
    Top_: TPanel;
    Side, Pane: TBGRAVirtualScreen;
    BtnMod, BtnPrev, BtnNext, BtnCopy, BtnTheme, BtnSmaller, BtnBigger: TBCButton;
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
    SerifName, SansName: String;
    Toks: array of TTok;
    Runs: array of TRun;
    ContentH, ScrollY, SideScroll, SideHover: Integer;
    VerseY: array of Integer;
    SearchMode: Boolean;
    Hits: array of THit;
    HitTerm: String;
    Rows: array of TSideRow;
    procedure ShowOnce(Sender: TObject);
    procedure BuildUI;
    procedure StyleButton(B: TBCButton; Accent: Boolean);
    procedure ApplyTheme;
    procedure DoResize(Sender: TObject);
    procedure PaneRedraw(Sender: TObject; Bitmap: TBGRABitmap);
    procedure SideRedraw(Sender: TObject; Bitmap: TBGRABitmap);
    procedure PaneWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure SideWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure PaneMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure SideMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure SideMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure SideMouseLeave(Sender: TObject);
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
    procedure BuildRows;
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

var
  Sc: Double = 1.0;          { screen scale: PixelsPerInch / 96 (HiDPI) }

{ a size in 96 dpi pixels, scaled to this screen }
function S_(N: Integer): Integer;
begin
  Result := Round(N * Sc);
end;

function SideW: Integer; begin Result := S_(270); end;
function TopH: Integer; begin Result := S_(60); end;
function ColMax: Integer; begin Result := S_(700); end;

var
  Mz: TBGRABitmap;
  Hinting: Boolean = True;

const
  SearchHint = 'Search the Bible…';

function Pix(C: TColor): TBGRAPixel;
begin
  Result := ColorToBGRA(ColorToRGB(C));
end;

function LightTheme: TTheme;
begin
  Result.Bg := RGBToColor($FD, $FC, $F9);
  Result.Panel := RGBToColor($F3, $F1, $EC);
  Result.Text := RGBToColor($26, $26, $2B);
  Result.Muted := RGBToColor($8B, $87, $7E);
  Result.Accent := RGBToColor($3B, $5B, $C9);
  Result.AccentSoft := RGBToColor($E3, $E9, $FB);
  Result.Red := RGBToColor($B0, $2A, $2A);
  Result.Line := RGBToColor($E4, $E0, $D8);
  Result.Hover := RGBToColor($EA, $E7, $E0);
  Result.Mark := RGBToColor($FF, $E8, $8A);
end;

function DarkTheme: TTheme;
begin
  Result.Bg := RGBToColor($1B, $1C, $20);
  Result.Panel := RGBToColor($23, $24, $29);
  Result.Text := RGBToColor($DC, $DA, $D3);
  Result.Muted := RGBToColor($86, $85, $80);
  Result.Accent := RGBToColor($8C, $A8, $FF);
  Result.AccentSoft := RGBToColor($2C, $34, $52);
  Result.Red := RGBToColor($FF, $8A, $80);
  Result.Line := RGBToColor($33, $34, $3A);
  Result.Hover := RGBToColor($2C, $2D, $33);
  Result.Mark := RGBToColor($6B, $5A, $10);
end;

{ ------------------------------------------------------------------ construction }

constructor TMainForm.Create(TheOwner: TComponent);
var
  Cur: String;
  B, C: Integer;
begin
  inherited CreateNew(TheOwner);
  Scaled := False;
  Caption := 'mkbible';
  Sc := Max(1.0, Screen.PixelsPerInch / 96);
  Width := S_(1120); Height := S_(740);
  Position := poScreenCenter;
  KeyPreview := True;
  OnKeyDown := @FormKey;
  OnResize := @DoResize;
  Mz := TBGRABitmap.Create(1, 1);
  SerifName := PickFont(['Noto Serif', 'Georgia', 'Cambria', 'Liberation Serif', 'DejaVu Serif', 'Times New Roman'], 'serif');
  SansName := PickFont(['Lato', 'Segoe UI', 'Cantarell', 'Noto Sans', 'DejaVu Sans', 'Arial'], 'sans');
  FontBase := Max(13, Min(32, StrToIntDef(GetSetting('gui.fontsize', '19'), 19)));
  FontSize := S_(FontBase);
  Dark := GetSetting('gui.dark', '0') = '1';
  Bib := nil;
  CurBook := 1; CurChap := 1;
  SideHover := -1;
  BuildUI;
  ApplyTheme;
  Cur := GetSetting('gui.module', '');
  B := StrToIntDef(GetSetting('gui.book', '1'), 1);
  C := StrToIntDef(GetSetting('gui.chapter', '1'), 1);
  if Cur = '' then LoadLast(Cur, B, C);
  if (Cur <> '') and OpenModule(Cur) then GoChapter(B, C)
  else BuildRows;
  DoResize(nil);
  OnShow := @ShowOnce;
end;

procedure TMainForm.ShowOnce(Sender: TObject);
var
  B: Integer;
begin
  OnShow := nil;
  if Pane.CanFocus then Pane.SetFocus;
  { options for trying it out: --dark, --search WORD, --chapter BOOK CHAPTER }
  for B := 1 to ParamCount do
    begin
    if ParamStr(B) = '--dark' then begin Dark := True; ApplyTheme; end;
    if (ParamStr(B) = '--search') and (B < ParamCount) then begin Hinting := False; SearchEd.Font.Color := Theme.Text; SearchEd.Text := ParamStr(B + 1); RunSearch(ParamStr(B + 1)); end;
    if (ParamStr(B) = '--chapter') and (B + 1 < ParamCount) then GoChapter(StrToIntDef(ParamStr(B + 1), 1), StrToIntDef(ParamStr(B + 2), 1));
    end;
end;

destructor TMainForm.Destroy;
begin
  SaveState;
  if Bib <> nil then begin Bib^.CloseBible; FreeBibObj(Bib); end;
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
  B.Rounding.RoundX := S_(10);
  B.Rounding.RoundY := S_(10);
  B.StateNormal.Border.Style := bboNone;
  B.StateHover.Border.Style := bboNone;
  B.StateClicked.Border.Style := bboNone;
  B.StateNormal.Background.Style := bbsColor;
  B.StateHover.Background.Style := bbsColor;
  B.StateClicked.Background.Style := bbsColor;
  if Accent then
    begin
    B.StateNormal.Background.Color := Theme.AccentSoft;
    B.StateHover.Background.Color := Theme.Hover;
    B.StateClicked.Background.Color := Theme.Line;
    end
  else
    begin
    B.StateNormal.Background.Color := Theme.Panel;
    B.StateHover.Background.Color := Theme.Hover;
    B.StateClicked.Background.Color := Theme.Line;
    end;
  B.StateNormal.FontEx.Color := Theme.Text;
  B.StateHover.FontEx.Color := Theme.Text;
  B.StateClicked.FontEx.Color := Theme.Text;
  B.StateNormal.FontEx.Name := SansName;
  B.StateHover.FontEx.Name := SansName;
  B.StateClicked.FontEx.Name := SansName;
  B.StateNormal.FontEx.Shadow := False;
  B.StateHover.FontEx.Shadow := False;
  B.StateClicked.FontEx.Shadow := False;
  B.StateNormal.FontEx.Height := S_(15);
  B.StateHover.FontEx.Height := S_(15);
  B.StateClicked.FontEx.Height := S_(15);
  B.Invalidate;
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
  Side := TBGRAVirtualScreen.Create(Self);
  Side.Parent := Self;
  Side.Align := alLeft;
  Side.Width := SideW;
  Side.OnRedraw := @SideRedraw;
  Side.OnMouseWheel := @SideWheel;
  Side.OnMouseUp := @SideMouseUp;
  Side.OnMouseMove := @SideMouseMove;
  Side.OnMouseLeave := @SideMouseLeave;
  Pane := TBGRAVirtualScreen.Create(Self);
  Pane.Parent := Self;
  Pane.Align := alClient;
  Pane.OnRedraw := @PaneRedraw;
  Pane.OnMouseWheel := @PaneWheel;
  Pane.OnMouseUp := @PaneMouseUp;
  BtnMod := MakeBtn('Open module', S_(230), @ModClick);
  BtnPrev := MakeBtn('‹', S_(40), @PrevClick);
  BtnNext := MakeBtn('›', S_(40), @NextClick);
  BtnCopy := MakeBtn('Copy', S_(64), @CopyClick);
  BtnSmaller := MakeBtn('A−', S_(44), @SmallerClick);
  BtnBigger := MakeBtn('A+', S_(44), @BiggerClick);
  BtnTheme := MakeBtn('Dark', S_(64), @ThemeClick);
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
end;

procedure TMainForm.ApplyTheme;
begin
  if Dark then Theme := DarkTheme else Theme := LightTheme;
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
  StyleButton(BtnNext, False);
  StyleButton(BtnCopy, False);
  StyleButton(BtnSmaller, False);
  StyleButton(BtnBigger, False);
  StyleButton(BtnTheme, False);
  if Dark then BtnTheme.Caption := 'Light' else BtnTheme.Caption := 'Dark';
  Redraw;
end;

procedure TMainForm.DoResize(Sender: TObject);
var
  X, Y, H: Integer;
begin
  H := S_(36);
  Y := (TopH - H) div 2;
  BtnMod.SetBounds(S_(16), Y, SideW - S_(32), H);
  BtnPrev.SetBounds(SideW + S_(24), Y, S_(40), H);
  BtnNext.SetBounds(SideW + S_(68), Y, S_(40), H);
  TitleLbl.Left := SideW + S_(124);
  TitleLbl.Top := (TopH - TitleLbl.Height) div 2;
  X := ClientWidth - S_(16);
  X := X - BtnTheme.Width; BtnTheme.SetBounds(X, Y, BtnTheme.Width, H);
  X := X - S_(8) - BtnBigger.Width; BtnBigger.SetBounds(X, Y, BtnBigger.Width, H);
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
  BtnMod.Caption := ModName;
  SearchMode := False;
  CurBook := 1; CurChap := 1;
  BuildRows;
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
  LoadChapterToks;
  LayoutRuns;
  ScrollY := 0;
  TitleLbl.Caption := Bib^.GetBookName(B) + ' ' + IntToStr(C);
  BuildRows;
  for C := 0 to High(Rows) do
    if (Rows[C].Kind = 1) and (Rows[C].Book = CurBook) then
      SideScroll := Max(0, Rows[C].Y - S_(140));
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

{ one verse as tokens: the module's markup is translated to the light VPL markup (<red>, <em>, <b>, <br>) first }
procedure TMainForm.AddVerseToks(const Raw: String; V: Integer);
var
  S: String;
  i, j: Integer;
  Red, Ital, Bold, AtStart: Boolean;
  W: String;
  T: TTok;

  procedure Push(K: TTokKind; const Txt: String);
  begin
    T.Txt := Txt; T.Kind := K; T.Red := Red; T.Ital := Ital; T.Bold := Bold; T.Mark := False; T.Ref := V;
    SetLength(Toks, Length(Toks) + 1);
    Toks[High(Toks)] := T;
  end;

  function Decode(const X: String): String;
  begin
    Result := StringReplace(StringReplace(StringReplace(X, '&lt;', '<', [rfReplaceAll]), '&gt;', '>', [rfReplaceAll]),
      '&amp;', '&', [rfReplaceAll]);
  end;

  procedure Flush;
  begin
    if W <> '' then
      begin
      if AtStart and Bold then Push(tkHead, Decode(W)) else Push(tkWord, Decode(W));
      W := '';
      end;
  end;

begin
  S := MkpTranslate(Raw, Bib^.GetMkpFormat, mfVPL, [moHeadings]);
  Red := False; Ital := False; Bold := False; AtStart := True; W := '';
  Push(tkNum, IntToStr(V));
  i := 1;
  while i <= Length(S) do
    begin
    if S[i] = '<' then
      begin
      j := PosEx('>', S, i);
      if j = 0 then j := Length(S);
      Flush;
      case LowerCase(Copy(S, i + 1, j - i - 1)) of
        'red': Red := True;
        '/red': Red := False;
        'em', 'i': Ital := True;
        '/em', '/i': Ital := False;
        'b': Bold := True;
        '/b': begin Bold := False; end;
        'br', 'br/': begin Push(tkBreak, ''); end;
      end;
      i := j + 1;
      end
    else if S[i] in [' ', #9, #10, #13] then
      begin
      Flush;
      Inc(i);
      end
    else
      begin
      if W = '' then
        if not (Bold and AtStart) then AtStart := False;
      W := W + S[i];
      Inc(i);
      end;
    if (W <> '') and (not Bold) then AtStart := False;
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
    T.Txt := W; T.Kind := tkWord; T.Red := False; T.Ital := False; T.Bold := False; T.Ref := Ref;
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
  NeedSp: Boolean;

  procedure NewLine(Extra: Integer);
  begin
    X := 0; Y := Y + LineH + Extra; NeedSp := False;
  end;

  procedure AddRun(const R: TRun);
  begin
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
  X := 0; Y := S_(34); NeedSp := False; CurVerse := 0;
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
      tkWord:
        begin
        W := MeasureText(T.Txt, FontSize, T.Bold, T.Ital, not SearchMode);
        if (X > 0) and NeedSp and (X + Sp + W > ColW) then NewLine(0)
        else if NeedSp then X := X + Sp;
        R.X := Left0 + X; R.Y := Y; R.W := W;
        AddRun(R);
        X := X + W;
        NeedSp := True;
        end;
      tkHead:
        begin
        if X > 0 then NewLine(0);
        if Y > S_(40) then Y := Y + Round(LineH * 0.5);
        W := MeasureText(T.Txt, HeadSz, True, False, False);
        R.X := Left0; R.Y := Y; R.W := W;
        { a heading is one run per word, so that long ones wrap }
        R.T.Kind := tkHead;
        AddRun(R);
        Y := Y + Round(LineH * 0.9);
        X := 0; NeedSp := False;
        end;
      tkBreak:
        begin
        if X > 0 then NewLine(0);
        end;
      tkGap:
        begin
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
  if Pane <> nil then Pane.DiscardBitmap;
  if Side <> nil then Side.DiscardBitmap;
end;

{ ------------------------------------------------------------------ drawing }

procedure TMainForm.PaneRedraw(Sender: TObject; Bitmap: TBGRABitmap);
var
  i, NumSz, HeadSz, Y, H: Integer;
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

procedure TMainForm.BuildRows;
var
  B, N, Y, G: Integer;

  procedure Add(K, Bk, H: Integer; const T: String);
  begin
    SetLength(Rows, Length(Rows) + 1);
    Rows[High(Rows)].Kind := K;
    Rows[High(Rows)].Book := Bk;
    Rows[High(Rows)].Y := Y;
    Rows[High(Rows)].H := H;
    Rows[High(Rows)].Txt := T;
    Y := Y + H;
  end;

begin
  SetLength(Rows, 0);
  Y := S_(8);
  if Bib = nil then Exit;
  N := Bib^.GetBookCount;
  if N > 66 then N := 66;
  for B := 1 to N do
    begin
    if B = 1 then Add(0, 0, S_(34), 'OLD TESTAMENT');
    if B = 40 then Add(0, 0, S_(40), 'NEW TESTAMENT');
    Add(1, B, S_(34), Bib^.GetBookName(B));
    if B = CurBook then
      begin
      G := (Bib^.GetChapterCount(B) + 5) div 6;
      Add(2, B, G * S_(40) + S_(10), '');
      end;
    end;
  Rows[0].Y := Rows[0].Y;
end;

procedure TMainForm.SideRedraw(Sender: TObject; Bitmap: TBGRABitmap);
var
  i, k, Cx, Cy, NCh: Integer;
  R: TSideRow;
  Y: Integer;
  Sel: Boolean;
begin
  Bitmap.Fill(Pix(Theme.Panel));
  Bitmap.FontQuality := fqFineAntialiasing;
  Bitmap.FontName := SansName;
  for i := 0 to High(Rows) do
    begin
    R := Rows[i];
    Y := R.Y - SideScroll;
    if (Y > Side.Height) or (Y + R.H < 0) then Continue;
    case R.Kind of
      0:
        begin
        Bitmap.FontHeight := S_(12);
        Bitmap.FontStyle := [fsBold];
        Bitmap.TextOut(S_(24), Y + R.H - S_(22), R.Txt, Pix(Theme.Muted));
        end;
      1:
        begin
        Sel := R.Book = CurBook;
        if Sel then Bitmap.FillRoundRectAntialias(S_(12), Y + 2, Side.Width - S_(12), Y + R.H - 2, S_(9), S_(9), Pix(Theme.AccentSoft))
        else if i = SideHover then Bitmap.FillRoundRectAntialias(S_(12), Y + 2, Side.Width - S_(12), Y + R.H - 2, S_(9), S_(9), Pix(Theme.Hover));
        Bitmap.FontHeight := S_(16);
        if Sel then begin Bitmap.FontStyle := [fsBold]; Bitmap.TextOut(S_(26), Y + S_(7), R.Txt, Pix(Theme.Accent)); end
        else begin Bitmap.FontStyle := []; Bitmap.TextOut(S_(26), Y + S_(7), R.Txt, Pix(Theme.Text)); end;
        end;
      2:
        begin
        NCh := Bib^.GetChapterCount(R.Book);
        Bitmap.FontHeight := S_(14);
        Bitmap.FontStyle := [];
        for k := 1 to NCh do
          begin
          Cx := S_(18) + ((k - 1) mod 6) * S_(40);
          Cy := Y + S_(4) + ((k - 1) div 6) * S_(40);
          if k = CurChap then
            begin
            Bitmap.FillRoundRectAntialias(Cx, Cy, Cx + S_(36), Cy + S_(36), S_(9), S_(9), Pix(Theme.Accent));
            Bitmap.TextOut(Cx + S_(18), Cy + S_(9), IntToStr(k), Pix(Theme.Bg), taCenter);
            end
          else
            begin
            Bitmap.FillRoundRectAntialias(Cx, Cy, Cx + S_(36), Cy + S_(36), S_(9), S_(9), Pix(Theme.Bg));
            Bitmap.TextOut(Cx + S_(18), Cy + S_(9), IntToStr(k), Pix(Theme.Text), taCenter);
            end;
          end;
        end;
    end;
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

procedure TMainForm.SideWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  Total: Integer;
begin
  Total := S_(8);
  if Length(Rows) > 0 then Total := Rows[High(Rows)].Y + Rows[High(Rows)].H + S_(16);
  SideScroll := Max(0, Min(SideScroll - WheelDelta div 2, Total - Side.Height));
  Side.DiscardBitmap;
  Handled := True;
end;

procedure TMainForm.SideMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  i, H: Integer;
begin
  H := -1;
  for i := 0 to High(Rows) do
    if (Rows[i].Kind = 1) and (Y + SideScroll >= Rows[i].Y) and (Y + SideScroll < Rows[i].Y + Rows[i].H) then H := i;
  if H <> SideHover then begin SideHover := H; Side.DiscardBitmap; end;
end;

procedure TMainForm.SideMouseLeave(Sender: TObject);
begin
  if SideHover <> -1 then begin SideHover := -1; Side.DiscardBitmap; end;
end;

procedure TMainForm.SideMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  i, k: Integer;
  YY: Integer;
begin
  if Bib = nil then Exit;
  YY := Y + SideScroll;
  for i := 0 to High(Rows) do
    if (YY >= Rows[i].Y) and (YY < Rows[i].Y + Rows[i].H) then
      case Rows[i].Kind of
        1: begin GoChapter(Rows[i].Book, 1); Exit; end;
        2:
          begin
          k := ((YY - Rows[i].Y - S_(4)) div S_(40)) * 6 + (X - S_(18)) div S_(40) + 1;
          if (X >= S_(18)) and (k >= 1) and (k <= Bib^.GetChapterCount(Rows[i].Book)) then GoChapter(Rows[i].Book, k);
          Exit;
          end;
      end;
end;

procedure TMainForm.PaneMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  i, H: Integer;
begin
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
    VK_ESCAPE: if SearchMode then begin GoChapter(CurBook, CurChap); Key := 0; end;
    VK_F: if ssCtrl in Shift then begin SearchEd.SetFocus; SearchEd.SelectAll; Key := 0; end;
    VK_C: if ssCtrl in Shift then begin CopyClick(nil); Key := 0; end;
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
  SetLength(Toks, 0);
  for N := 0 to High(Hits) do
    begin
    SetLength(Toks, Length(Toks) + 1);
    with Toks[High(Toks)] do
      begin
      Txt := Bib^.GetBookName(Hits[N].B) + ' ' + IntToStr(Hits[N].C) + ':' + IntToStr(Hits[N].V);
      Kind := tkHead; Ref := N; Red := False; Ital := False; Bold := True; Mark := False;
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
var
  S: String;
  V: Integer;
begin
  if (Bib = nil) or SearchMode then Exit;
  S := Bib^.GetBookName(CurBook) + ' ' + IntToStr(CurChap) + LineEnding;
  for V := 1 to Bib^.GetVerseCount(CurBook, CurChap) do
    begin
    Bib^.SetRef(CurBook, CurChap, V);
    S := S + IntToStr(V) + ' ' + Bib^.GetVerseText + LineEnding;
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
