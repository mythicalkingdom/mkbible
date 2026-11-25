unit uDialogs;
{$mode objfpc}{$H+}
{ small themed dialogs: module paths, reading font, plain information }

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, StdCtrls, ExtCtrls, Dialogs, Math, LCLType, BCButton, uTheme;

function PathsDialog(Owner: TForm; const Th: TTheme; var Paths: TStringArray): Boolean;
function FontDialog(Owner: TForm; const Th: TTheme; var FontName: String; var FontSize: Integer; const SampleText: String): Boolean;
procedure InfoDialog(Owner: TForm; const Th: TTheme; const Title, Text: String);

implementation

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

end.
