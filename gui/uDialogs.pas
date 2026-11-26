unit uDialogs;
{$mode objfpc}{$H+}
{ small themed dialogs: module paths, reading font, plain information }

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, StdCtrls, ExtCtrls, Dialogs, Math, LCLType, BCButton, uTheme;

function PathsDialog(Owner: TForm; const Th: TTheme; var Paths: TStringArray): Boolean;
function FontDialog(Owner: TForm; const Th: TTheme; var FontName: String; var FontSize: Integer; const SampleText: String): Boolean;
procedure InfoDialog(Owner: TForm; const Th: TTheme; const Title, Text: String);
function StrongsDialog(Owner: TForm; const Th: TTheme; var Greek, Hebrew: String; const GreekNow, HebrewNow: String): Boolean;
procedure StrongsPopup(Owner: TForm; const Th: TTheme; const Title, Body: String; Pt: TPoint);
function DownloadDialog(Owner: TForm; const Th: TTheme): Boolean;
  { the module download list; True if something was installed }

implementation

uses mkbiblerepo, mkbiblecfg;

type
  TDlg = class(TForm)
  public
    Th: TTheme;
    List: TListBox;
    Filter: TEdit;
    Preview: TLabel;
    SizeLbl: TLabel;
    Size: Integer;
    Chosen: String;
    Fonts: TStringList;
    GreekLbl, HebrewLbl: TLabel;
    Greek, Hebrew: String;
    WasActive: Boolean;
    RepoBox, LangBox: TComboBox;
    LangNames: TStringList;
    StatusLbl: TLabel;
    InstBtn: TBCButton;
    Repos: TRepoArray;
    Items: TRepoItems;
    Shown: array of Integer;
    RepoIdx: Integer;
    LangDone: Boolean;
    Busy, Installed: Boolean;
    procedure DlDraw(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
    procedure DlLoad(Sender: TObject);
    procedure DlFillLangs;
    procedure DlShow(Sender: TObject);
    procedure DlFilter(Sender: TObject);
    procedure DlInstall(Sender: TObject);
    procedure DlProgress(Done, Total: Int64);
    procedure DlSetBusy(B: Boolean);
    procedure DlAddPath(const P: String);
    procedure PopupActivate(Sender: TObject);
    procedure ListDraw(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
    procedure FilterChange(Sender: TObject);
    procedure PickChange(Sender: TObject);
    procedure SmallerClick(Sender: TObject);
    procedure BiggerClick(Sender: TObject);
    procedure DefaultClick(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure EditClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure UpdatePreview;
    procedure ChooseGreek(Sender: TObject);
    procedure ChooseHebrew(Sender: TObject);
    procedure ChooseDict(var Spec: String; L: TLabel; const What: String);
    procedure PopupKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure PopupDeactivate(Sender: TObject);
    procedure PopupClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure CloseClick(Sender: TObject);
    procedure OkClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
  end;

function NewDlg(Owner: TForm; const Th: TTheme; const Title: String; W, H: Integer): TDlg;
begin
  Result := TDlg.CreateNew(Owner);
  Result.Th := Th;
  Result.Caption := Title;
  Result.BorderStyle := bsDialog;
  Result.Position := poOwnerFormCenter;
  Result.Scaled := False;
  Result.ClientWidth := S_(W);
  Result.ClientHeight := S_(H);
  Result.Color := Th.Bg;
  Result.Font.Name := Th.SansName;
  Result.Font.Color := Th.Text;
end;

function MakeBtn(D: TDlg; const Cap: String; X, Y, W: Integer; Accent: Boolean; Click: TNotifyEvent; Modal: Integer): TBCButton;
begin
  Result := TBCButton.Create(D);
  Result.Parent := D;
  Result.Caption := Cap;
  Result.SetBounds(S_(X), S_(Y), S_(W), S_(34));
  StyleBtn(Result, D.Th, Accent);
  Result.OnClick := Click;
  if Modal = mrOK then Result.OnClick := @D.OkClick
  else if Modal = mrCancel then Result.OnClick := @D.CancelClick;
end;

function MakeLabel(D: TDlg; const Cap: String; X, Y, Size: Integer; Bold: Boolean; C: TColor): TLabel;
begin
  Result := TLabel.Create(D);
  Result.Parent := D;
  Result.Caption := Cap;
  Result.Left := S_(X);
  Result.Top := S_(Y);
  Result.Font.Name := D.Th.SansName;
  Result.Font.Size := Size;
  Result.Font.Color := C;
  if Bold then Result.Font.Style := [fsBold];
end;

procedure TDlg.OkClick(Sender: TObject);
begin
  ModalResult := mrOK;
end;

procedure TDlg.CancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

{ ---------------------------------------------------------------- module paths }

procedure TDlg.AddClick(Sender: TObject);
var
  Sel: TSelectDirectoryDialog;
begin
  Sel := TSelectDirectoryDialog.Create(Self);
  try
    Sel.Title := 'Add a module folder';
    if Sel.Execute then List.Items.Add(Sel.FileName);
  finally
    Sel.Free;
  end;
end;

procedure TDlg.EditClick(Sender: TObject);
var
  Sel: TSelectDirectoryDialog;
begin
  if List.ItemIndex < 0 then Exit;
  Sel := TSelectDirectoryDialog.Create(Self);
  try
    Sel.Title := 'Change the module folder';
    Sel.InitialDir := List.Items[List.ItemIndex];
    if Sel.Execute then List.Items[List.ItemIndex] := Sel.FileName;
  finally
    Sel.Free;
  end;
end;

procedure TDlg.RemoveClick(Sender: TObject);
begin
  if List.ItemIndex >= 0 then List.Items.Delete(List.ItemIndex);
end;

function PathsDialog(Owner: TForm; const Th: TTheme; var Paths: TStringArray): Boolean;
var
  D: TDlg;
  i: Integer;
begin
  D := NewDlg(Owner, Th, 'Module folders', 560, 360);
  try
    MakeLabel(D, 'Module folders', 20, 16, 13, True, Th.Text);
    MakeLabel(D, 'Folders searched for Bible modules (Sword, theWord, MySword, USFM, USX, OSIS, ...).', 20, 44, 10, False, Th.Muted);
    D.List := TListBox.Create(D);
    D.List.Parent := D;
    D.List.SetBounds(S_(20), S_(72), S_(400), S_(220));
    D.List.Color := Th.Panel;
    D.List.Font.Color := Th.Text;
    D.List.Font.Size := 11;
    D.List.BorderStyle := bsNone;
    for i := 0 to High(Paths) do D.List.Items.Add(Paths[i]);
    MakeBtn(D, 'Add…', 436, 72, 104, False, @D.AddClick, 0);
    MakeBtn(D, 'Change…', 436, 114, 104, False, @D.EditClick, 0);
    MakeBtn(D, 'Remove', 436, 156, 104, False, @D.RemoveClick, 0);
    MakeBtn(D, 'Cancel', 316, 310, 104, False, nil, mrCancel);
    MakeBtn(D, 'OK', 436, 310, 104, True, nil, mrOK);
    Result := D.ShowModal = mrOK;
    if Result then
      begin
      SetLength(Paths, D.List.Items.Count);
      for i := 0 to D.List.Items.Count - 1 do Paths[i] := D.List.Items[i];
      end;
  finally
    D.Free;
  end;
end;

{ ---------------------------------------------------------------- reading font }

procedure TDlg.UpdatePreview;
begin
  if Chosen <> '' then Preview.Font.Name := Chosen else Preview.Font.Name := 'serif';
  Preview.Font.Size := Round(Size * 0.75);
  SizeLbl.Caption := IntToStr(Size) + ' px';
end;

procedure TDlg.ListDraw(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
var
  C: TCanvas;
begin
  C := List.Canvas;
  if odSelected in State then C.Brush.Color := Th.AccentSoft else C.Brush.Color := Th.Panel;
  C.FillRect(ARect);
  C.Font.Name := List.Items[Index];
  C.Font.Size := 12;
  C.Font.Color := Th.Text;
  C.TextOut(ARect.Left + S_(10), ARect.Top + S_(4), List.Items[Index]);
end;

procedure TDlg.FilterChange(Sender: TObject);
var
  i: Integer;
  F: String;
begin
  F := LowerCase(Trim(Filter.Text));
  List.Items.BeginUpdate;
  try
    List.Items.Clear;
    for i := 0 to Fonts.Count - 1 do
      if (F = '') or (Pos(F, LowerCase(Fonts[i])) > 0) then List.Items.Add(Fonts[i]);
    if Chosen <> '' then List.ItemIndex := List.Items.IndexOf(Chosen);
  finally
    List.Items.EndUpdate;
  end;
end;

procedure TDlg.PickChange(Sender: TObject);
begin
  if List.ItemIndex >= 0 then Chosen := List.Items[List.ItemIndex];
  UpdatePreview;
end;

procedure TDlg.SmallerClick(Sender: TObject);
begin
  if Size > 13 then Dec(Size);
  UpdatePreview;
end;

procedure TDlg.BiggerClick(Sender: TObject);
begin
  if Size < 32 then Inc(Size);
  UpdatePreview;
end;

procedure TDlg.DefaultClick(Sender: TObject);
begin
  Chosen := '';
  List.ItemIndex := -1;
  UpdatePreview;
end;

function FontDialog(Owner: TForm; const Th: TTheme; var FontName: String; var FontSize: Integer; const SampleText: String): Boolean;
var
  D: TDlg;
  i: Integer;
begin
  D := NewDlg(Owner, Th, 'Reading font', 640, 470);
  D.Fonts := TStringList.Create;
  try
    D.Fonts.Assign(Screen.Fonts);
    D.Fonts.Sorted := True;
    for i := D.Fonts.Count - 1 downto 0 do
      if (D.Fonts[i] = '') or (D.Fonts[i][1] = '@') then D.Fonts.Delete(i);
    D.Chosen := FontName;
    D.Size := FontSize;
    MakeLabel(D, 'Reading font', 20, 16, 13, True, Th.Text);
    D.Filter := TEdit.Create(D);
    D.Filter.Parent := D;
    D.Filter.SetBounds(S_(20), S_(48), S_(250), S_(28));
    D.Filter.Color := Th.Panel;
    D.Filter.Font.Color := Th.Text;
    D.Filter.TextHint := 'Filter fonts';
    D.Filter.OnChange := @D.FilterChange;
    D.List := TListBox.Create(D);
    D.List.Parent := D;
    D.List.SetBounds(S_(20), S_(84), S_(250), S_(310));
    D.List.Style := lbOwnerDrawFixed;
    D.List.ItemHeight := S_(32);
    D.List.Color := Th.Panel;
    D.List.BorderStyle := bsNone;
    D.List.OnDrawItem := @D.ListDraw;
    D.List.OnSelectionChange := nil;
    D.Preview := TLabel.Create(D);
    D.Preview.Parent := D;
    D.Preview.SetBounds(S_(290), S_(84), S_(330), S_(240));
    D.Preview.AutoSize := False;
    D.Preview.WordWrap := True;
    D.Preview.Font.Color := Th.Text;
    D.Preview.Caption := SampleText;
    D.SizeLbl := MakeLabel(D, '', 290, 336, 11, False, Th.Muted);
    MakeBtn(D, 'A−', 400, 328, 56, False, @D.SmallerClick, 0);
    MakeBtn(D, 'A+', 462, 328, 56, False, @D.BiggerClick, 0);
    MakeBtn(D, 'Default', 524, 328, 96, False, @D.DefaultClick, 0);
    MakeBtn(D, 'Cancel', 400, 420, 104, False, nil, mrCancel);
    MakeBtn(D, 'OK', 516, 420, 104, True, nil, mrOK);
    D.FilterChange(nil);
    D.List.OnClick := @D.PickChange;
    D.UpdatePreview;
    Result := D.ShowModal = mrOK;
    if Result then
      begin
      FontName := D.Chosen;
      FontSize := D.Size;
      end;
  finally
    D.Fonts.Free;
    D.Free;
  end;
end;

{ ---------------------------------------------------------------- information }

procedure InfoDialog(Owner: TForm; const Th: TTheme; const Title, Text: String);
var
  D: TDlg;
  L: TLabel;
begin
  D := NewDlg(Owner, Th, Title, 520, 380);
  try
    MakeLabel(D, Title, 20, 16, 13, True, Th.Text);
    L := MakeLabel(D, Text, 20, 52, 11, False, Th.Text);
    L.AutoSize := False;
    L.WordWrap := True;
    L.Width := S_(480);
    L.Height := S_(270);
    MakeBtn(D, 'OK', 396, 332, 104, True, nil, mrOK);
    D.ShowModal;
  finally
    D.Free;
  end;
end;


{ ---------------------------------------------------------------- Strong's dictionaries }

procedure TDlg.ChooseDict(var Spec: String; L: TLabel; const What: String);
var
  O: TOpenDialog;
begin
  O := TOpenDialog.Create(Self);
  try
    O.Title := 'Choose the Strong''s ' + What + ' dictionary (a Sword .conf, or a theWord / MySword dictionary file)';
    if Spec <> '' then O.InitialDir := ExtractFilePath(Spec);
    if O.Execute then
      begin
      Spec := O.FileName;
      L.Caption := ExtractFileName(Spec);
      end;
  finally
    O.Free;
  end;
end;

procedure TDlg.ChooseGreek(Sender: TObject);
begin
  ChooseDict(Greek, GreekLbl, 'Greek');
end;

procedure TDlg.ChooseHebrew(Sender: TObject);
begin
  ChooseDict(Hebrew, HebrewLbl, 'Hebrew');
end;

function StrongsDialog(Owner: TForm; const Th: TTheme; var Greek, Hebrew: String; const GreekNow, HebrewNow: String): Boolean;
var
  D: TDlg;
  function Shown(const Spec, Now_: String): String;
  begin
    if Spec <> '' then Result := ExtractFileName(Spec)
    else if Now_ <> '' then Result := ExtractFileName(Now_) + ' (found automatically)'
    else Result := 'none found';
  end;
begin
  D := NewDlg(Owner, Th, 'Strong''s dictionaries', 560, 300);
  try
    D.Greek := Greek;
    D.Hebrew := Hebrew;
    MakeLabel(D, 'Strong''s dictionaries', 20, 16, 13, True, Th.Text);
    MakeLabel(D, 'Used when you click a word that carries a Strong''s number.', 20, 44, 10, False, Th.Muted);
    MakeLabel(D, 'Greek', 20, 92, 11, True, Th.Text);
    D.GreekLbl := MakeLabel(D, Shown(Greek, GreekNow), 20, 116, 11, False, Th.Muted);
    MakeBtn(D, 'Change…', 436, 98, 104, False, @D.ChooseGreek, 0);
    MakeLabel(D, 'Hebrew', 20, 160, 11, True, Th.Text);
    D.HebrewLbl := MakeLabel(D, Shown(Hebrew, HebrewNow), 20, 184, 11, False, Th.Muted);
    MakeBtn(D, 'Change…', 436, 166, 104, False, @D.ChooseHebrew, 0);
    MakeBtn(D, 'Cancel', 316, 250, 104, False, nil, mrCancel);
    MakeBtn(D, 'OK', 436, 250, 104, True, nil, mrOK);
    Result := D.ShowModal = mrOK;
    if Result then begin Greek := D.Greek; Hebrew := D.Hebrew; end;
  finally
    D.Free;
  end;
end;

{ ---------------------------------------------------------------- the Strong's pop-up window }

var
  CurPopup: TDlg = nil;

procedure TDlg.PopupKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then Close;
end;

procedure TDlg.PopupActivate(Sender: TObject);
begin
  WasActive := True;
end;

procedure TDlg.PopupDeactivate(Sender: TObject);
begin
  if WasActive then Close;
end;

procedure TDlg.PopupClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  CloseAction := caFree;
  CurPopup := nil;
end;

procedure TDlg.CloseClick(Sender: TObject);
begin
  Close;
end;

procedure StrongsPopup(Owner: TForm; const Th: TTheme; const Title, Body: String; Pt: TPoint);
var
  F: TDlg;
  Inner: TPanel;
  M: TMemo;
  B: TBCButton;
  T: TLabel;
  W, H: Integer;
begin
  if CurPopup <> nil then CurPopup.Close;
  W := S_(440);
  H := S_(300);
  F := TDlg.CreateNew(Owner);
  CurPopup := F;
  F.Th := Th;
  F.Scaled := False;
  F.BorderStyle := bsNone;
  F.FormStyle := fsStayOnTop;
  F.Position := poDesigned;
  F.Color := Th.Line;
  F.Width := W;
  F.Height := H;
  F.Left := Max(0, Min(Pt.X + S_(12), Screen.Width - W - S_(8)));
  F.Top := Max(0, Min(Pt.Y + S_(12), Screen.Height - H - S_(8)));
  F.KeyPreview := True;
  F.OnKeyDown := @F.PopupKey;
  F.OnActivate := @F.PopupActivate;
  F.OnDeactivate := @F.PopupDeactivate;
  F.OnClose := @F.PopupClose;
  Inner := TPanel.Create(F);
  Inner.Parent := F;
  Inner.BevelOuter := bvNone;
  Inner.SetBounds(1, 1, W - 2, H - 2);
  Inner.Color := Th.Bg;
  T := TLabel.Create(F);
  T.Parent := Inner;
  T.Caption := Title;
  T.Left := S_(18);
  T.Top := S_(14);
  T.Font.Name := Th.SansName;
  T.Font.Size := 14;
  T.Font.Style := [fsBold];
  T.Font.Color := Th.Accent;
  M := TMemo.Create(F);
  M.Parent := Inner;
  M.SetBounds(S_(18), S_(48), W - S_(38), H - S_(48) - S_(60));
  M.ReadOnly := True;
  M.BorderStyle := bsNone;
  M.ScrollBars := ssAutoVertical;
  M.WordWrap := True;
  M.Color := Th.Bg;
  M.Font.Name := Th.SansName;
  M.Font.Size := 11;
  M.Font.Color := Th.Text;
  M.Text := Body;
  B := TBCButton.Create(F);
  B.Parent := Inner;
  B.Caption := 'Close';
  B.SetBounds(W - S_(18) - S_(84), H - S_(52), S_(84), S_(34));
  StyleBtn(B, Th, False);
  B.OnClick := @F.CloseClick;
  F.Show;
end;

{ ---------------------------------------------------------------- module downloads }

procedure TDlg.DlSetBusy(B: Boolean);
begin
  Busy := B;
  RepoBox.Enabled := not B;
  LangBox.Enabled := not B;
  Filter.Enabled := not B;
  List.Enabled := not B;
  InstBtn.Enabled := not B;
  if B then Screen.Cursor := crHourGlass else Screen.Cursor := crDefault;
  Application.ProcessMessages;
end;

procedure TDlg.DlProgress(Done, Total: Int64);
begin
  if Total > 0 then StatusLbl.Caption := 'Downloading… ' + IntToStr(Done * 100 div Total) + '%'
  else StatusLbl.Caption := 'Downloading… ' + IntToStr(Done div 1024) + ' KB';
  Application.ProcessMessages;
end;

procedure TDlg.DlShow(Sender: TObject);
begin
  OnShow := nil;
  DlLoad(nil);
end;

{ the language drop-down: every language the list has, with a count; keeps the current pick, else the system language }
procedure TDlg.DlFillLangs;
var
  i, K, Pick: Integer;
  Cnt: TStringList;
  Want: String;
begin
  if LangBox.ItemIndex > 0 then Want := LangNames[LangBox.ItemIndex]
  else if not LangDone then Want := SystemLangName
  else Want := '';
  Cnt := TStringList.Create;
  try
    Cnt.Sorted := True;
    Cnt.CaseSensitive := False;
    for i := 0 to High(Items) do
      begin
      K := Cnt.IndexOf(Items[i].Lang);
      if K < 0 then Cnt.AddObject(Items[i].Lang, TObject(PtrInt(1)))
      else Cnt.Objects[K] := TObject(PtrInt(Cnt.Objects[K]) + 1);
      end;
    LangNames.Clear;
    LangBox.Items.Clear;
    LangNames.Add('');
    LangBox.Items.Add('All languages (' + IntToStr(Length(Items)) + ')');
    Pick := 0;
    for i := 0 to Cnt.Count - 1 do
      begin
      LangNames.Add(Cnt[i]);
      LangBox.Items.Add(Cnt[i] + ' (' + IntToStr(PtrInt(Cnt.Objects[i])) + ')');
      if SameText(Cnt[i], Want) then Pick := LangBox.Items.Count - 1;
      end;
    LangBox.ItemIndex := Pick;
    LangDone := True;
  finally
    Cnt.Free;
  end;
end;

procedure TDlg.DlFilter(Sender: TObject);
var
  i: Integer;
  F, Hay: String;
begin
  F := LowerCase(Trim(Filter.Text));
  SetLength(Shown, 0);
  List.Items.BeginUpdate;
  try
    List.Items.Clear;
    for i := 0 to High(Items) do
      begin
      Hay := LowerCase(Items[i].Id + ' ' + Items[i].Title + ' ' + Items[i].Lang + ' ' + Items[i].Kind);
      if ((F = '') or (Pos(F, Hay) > 0)) and
         ((LangBox.ItemIndex <= 0) or (Items[i].Lang = LangNames[LangBox.ItemIndex])) then
        begin
        SetLength(Shown, Length(Shown) + 1);
        Shown[High(Shown)] := i;
        List.Items.Add(Items[i].Id);
        end;
      end;
  finally
    List.Items.EndUpdate;
  end;
end;

procedure TDlg.DlLoad(Sender: TObject);
var
  Err: String;
begin
  if Busy or (RepoBox.ItemIndex < 0) then Exit;
  DlSetBusy(True);
  try
    StatusLbl.Caption := 'Loading the list from ' + Repos[RepoBox.ItemIndex].Url + ' …';
    SetLength(Items, 0);
    if ListRepo(Repos[RepoBox.ItemIndex], Items, Err) then
      StatusLbl.Caption := IntToStr(Length(Items)) + ' modules available. Select one and press Install.'
    else
      StatusLbl.Caption := 'Could not load the list: ' + Err;
    RepoIdx := RepoBox.ItemIndex;
  finally
    DlSetBusy(False);
  end;
  DlFillLangs;
  DlFilter(nil);
end;

procedure TDlg.DlDraw(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
var
  C: TCanvas;
  It: TRepoItem;
  L2: String;
begin
  C := List.Canvas;
  if odSelected in State then C.Brush.Color := Th.AccentSoft else C.Brush.Color := Th.Panel;
  C.FillRect(ARect);
  if (Index < 0) or (Index > High(Shown)) then Exit;
  It := Items[Shown[Index]];
  C.Font.Name := Th.SansName;
  C.Font.Size := 11;
  C.Font.Style := [fsBold];
  C.Font.Color := Th.Text;
  C.TextOut(ARect.Left + S_(10), ARect.Top + S_(4), It.Title);
  L2 := It.Id;
  if It.Lang <> '' then L2 := L2 + '  ·  ' + It.Lang;
  L2 := L2 + '  ·  ' + It.Kind;
  if It.SizeKB > 0 then L2 := L2 + '  ·  ' + IntToStr(It.SizeKB) + ' KB';
  if IsInstalled(Repos[RepoIdx], It) then L2 := L2 + '  ·  installed';
  C.Font.Style := [];
  C.Font.Size := 9;
  C.Font.Color := Th.Muted;
  C.TextOut(ARect.Left + S_(10), ARect.Top + S_(24), L2);
end;

procedure TDlg.DlAddPath(const P: String);
var
  A: TStringArray;
  i: Integer;
begin
  A := LoadPaths;
  for i := 0 to High(A) do
    if SameText(ExcludeTrailingPathDelimiter(A[i]), ExcludeTrailingPathDelimiter(P)) then Exit;
  SetLength(A, Length(A) + 1);
  A[High(A)] := P;
  SavePaths(A);
end;

procedure TDlg.DlInstall(Sender: TObject);
var
  It: TRepoItem;
  Dest, Err: String;
  R: TRepo;
begin
  if Busy or (List.ItemIndex < 0) or (List.ItemIndex > High(Shown)) then Exit;
  It := Items[Shown[List.ItemIndex]];
  R := Repos[RepoIdx];
  if IsInstalled(R, It) then
    begin
    StatusLbl.Caption := It.Id + ' is already installed (installing again replaces it).';
    end;
  DlSetBusy(True);
  try
    OnProgress := @DlProgress;
    if InstallItem(R, It, Dest, Err) then
      begin
      if R.Kind = rkSword then DlAddPath(Dest) else DlAddPath(ExtractFilePath(ExcludeTrailingPathDelimiter(Dest)));
      Installed := True;
      StatusLbl.Caption := 'Installed ' + It.Id + ' into ' + Dest;
      end
    else StatusLbl.Caption := 'Install failed: ' + Err;
  finally
    OnProgress := nil;
    DlSetBusy(False);
  end;
  List.Invalidate;
end;

function DownloadDialog(Owner: TForm; const Th: TTheme): Boolean;
var
  D: TDlg;
  i: Integer;
begin
  D := NewDlg(Owner, Th, 'Download modules', 700, 560);
  try
    D.RepoIdx := -1;
    D.LangNames := TStringList.Create;
    GetRepos(D.Repos);
    MakeLabel(D, 'Download modules', 20, 16, 13, True, Th.Text);
    MakeLabel(D, 'Sword modules install into ' + SwordInstallDir, 20, 38, 10, False, Th.Muted);
    MakeLabel(D, 'Other kinds (USFM) install into ' + LocalModuleDir, 20, 54, 10, False, Th.Muted);
    D.RepoBox := TComboBox.Create(D);
    D.RepoBox.Parent := D;
    D.RepoBox.SetBounds(S_(20), S_(78), S_(208), S_(30));
    D.RepoBox.Style := csDropDownList;
    for i := 0 to High(D.Repos) do D.RepoBox.Items.Add(D.Repos[i].Name);
    D.RepoBox.ItemIndex := 0;
    D.RepoBox.OnChange := @D.DlLoad;
    D.LangBox := TComboBox.Create(D);
    D.LangBox.Parent := D;
    D.LangBox.SetBounds(S_(240), S_(78), S_(210), S_(30));
    D.LangBox.Style := csDropDownList;
    D.LangBox.OnChange := @D.DlFilter;
    D.LangBox.Items.Add('All languages');
    D.LangBox.ItemIndex := 0;
    D.LangNames.Add('');
    D.Filter := TEdit.Create(D);
    D.Filter.Parent := D;
    D.Filter.SetBounds(S_(462), S_(78), S_(218), S_(30));
    D.Filter.Color := Th.Panel;
    D.Filter.Font.Color := Th.Text;
    D.Filter.TextHint := 'Search the list';
    D.Filter.OnChange := @D.DlFilter;
    D.List := TListBox.Create(D);
    D.List.Parent := D;
    D.List.SetBounds(S_(20), S_(112), S_(660), S_(350));
    D.List.Style := lbOwnerDrawFixed;
    D.List.ItemHeight := S_(46);
    D.List.Color := Th.Panel;
    D.List.BorderStyle := bsNone;
    D.List.OnDrawItem := @D.DlDraw;
    D.StatusLbl := MakeLabel(D, '', 20, 476, 10, False, Th.Muted);
    D.InstBtn := MakeBtn(D, 'Install', 456, 508, 104, True, @D.DlInstall, 0);
    MakeBtn(D, 'Close', 576, 508, 104, False, nil, mrCancel);
    D.OnShow := @D.DlShow;
    D.ShowModal;
    Result := D.Installed;
  finally
    D.LangNames.Free;
    D.Free;
  end;
end;

end.
