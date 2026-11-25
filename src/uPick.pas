unit uPick;
{$mode objfpc}{$H+}
{ A small, generic text mode UI toolkit built on uScreen/uKeys: an always visible top menu bar, a
  scrolling pick list, and a one line text prompt. None of this knows anything about a Bible reader
  or any other particular program; RedrawBG is a plain parameter-less procedure the caller supplies
  to redraw whatever sits behind the dialog (its own screen, read from the caller's own globals -
  there is one Bible open and one screen, so a plain global state is simplest here). }

interface

uses uScreen, uKeys, SysUtils, Math;

type
  TRedraw = procedure;

  TMenuItem = record
    Text: String;        { '&' before a letter marks it as that item's mnemonic }
    Cmd: Integer;         { an opaque code the caller defines; 0 is never a real command }
  end;
  TMenuItems = array of TMenuItem;
  TMenuDef = record
    Title: String;        { '&' before a letter marks the menu's own Alt- mnemonic }
    Items: TMenuItems;
  end;
  TMenuDefs = array of TMenuDef;

var
  { the colours (foreground 0..15, background 0..7); a program may change them }
  cBarFg: Byte = 0;      cBarBg: Byte = 7;
  cBarSelFg: Byte = 15;  cBarSelBg: Byte = 1;
  cHotFg: Byte = 4;
  cBoxFg: Byte = 15;     cBoxBg: Byte = 1;
  cSelFg: Byte = 0;      cSelBg: Byte = 7;

{ draws the menu bar at row 0 - always, whether or not a menu is open; Sel < 0 = no title highlighted }
procedure DrawMenuBar(const Menus: TMenuDefs; Sel: Integer);
{ runs the bar as a modal menu: Left/Right move between titles, Down/Enter open one, a mnemonic
  letter (with Alt, or alone once a menu is open) jumps straight to it, Esc backs out.  Returns the
  chosen item's Cmd, or 0 if the user cancelled. StartOpen: drop the first menu down right away
  (used when an Alt- mnemonic is what opened the bar). }
function RunMenuBar(const Menus: TMenuDefs; StartSel: Integer; StartOpen: Boolean; RedrawBG: TRedraw): Integer;
{ a scrolling list of Items in a centered box; returns the chosen 0 based index, or -1 on Esc.
  Typing a character jumps to the next item starting with it. }
function PickList(const Title: String; const Items: array of String; StartSel: Integer; RedrawBG: TRedraw): Integer;
{ as above, but Del is also a way out: Deleted is set True and Result is the item Del was pressed on }
function PickListDel(const Title: String; const Items: array of String; StartSel: Integer; RedrawBG: TRedraw;
                      out Deleted: Boolean): Integer;
{ a one line text input in a centered box; returns False on Esc }
function PromptLine(const Title, Initial: String; RedrawBG: TRedraw; out Res: String): Boolean;
{ a short message in a centered box, dismissed by any key }
procedure ShowMessage(const Title: String; const Lines: array of String; RedrawBG: TRedraw);
{ the letter after a lone '&' in S, upper cased; #0 if there is none.  PlainText strips the '&'. }
function MnemonicOf(const S: String): Char;
function PlainText(const S: String): String;
{ blocks until a key arrives (or the terminal hangs up, delivered as Esc) }
function GetKey: TKey;

implementation

{ blocks until a key arrives (or the terminal hangs up / is resized - the caller's RedrawBG runs
  again on the next loop either way, so this just needs to return) }
function GetKey: TKey;
begin
  repeat
    if KeyRead(Result) then Exit;
    if Hangup then begin Result.code := kcEsc; Result.mods := []; Result.ch := ''; Exit; end;
    KeyWait(100);
  until False;
end;

function MnemonicOf(const S: String): Char;
var i: Integer;
begin
  Result := #0;
  for i := 1 to Length(S) - 1 do
    if S[i] = '&' then begin Result := UpCase(S[i + 1]); Exit; end;
end;

function PlainText(const S: String): String;
begin
  Result := S;
  Delete(Result, Pos('&', Result), 1);
end;

{ draw S at x,y, the mnemonic letter (if any) in HotFg/bg }
procedure PutMnemonic(x, y: Integer; const S: String; fg, bg, hotfg: Byte; MaxW: Integer);
var
  P: Integer;
  Plain: String;
begin
  Plain := PlainText(S);
  ScrPutsN(x, y, Plain, MaxW, fg, bg);
  P := Pos('&', S);
  if P > 0 then ScrAttr(x + P - 1, y, 1, hotfg, bg);
end;

procedure DrawMenuBar(const Menus: TMenuDefs; Sel: Integer);
var
  i, x: Integer;
begin
  ScrFill(0, 0, ScrW, 32, cBarFg, cBarBg);
  x := 1;
  for i := 0 to High(Menus) do
    begin
    if i = Sel then
      begin
      ScrFill(x - 1, 0, Length(PlainText(Menus[i].Title)) + 2, 32, cBarSelFg, cBarSelBg);
      PutMnemonic(x, 0, Menus[i].Title, cBarSelFg, cBarSelBg, cHotFg, ScrW);
      end
    else PutMnemonic(x, 0, Menus[i].Title, cBarFg, cBarBg, cHotFg, ScrW);
    Inc(x, Length(PlainText(Menus[i].Title)) + 2);
    end;
end;

function RunMenuBar(const Menus: TMenuDefs; StartSel: Integer; StartOpen: Boolean; RedrawBG: TRedraw): Integer;
var
  Sel, Item, i, x, y, w, wmax: Integer;
  Open: Boolean;
  k: TKey;
  c: Char;
  mx: array of Integer;
begin
  Result := 0;
  SetLength(mx, Length(Menus));
  x := 1;
  for i := 0 to High(Menus) do begin mx[i] := x; Inc(x, Length(PlainText(Menus[i].Title)) + 2); end;
  Sel := StartSel; Open := StartOpen; Item := 0;
  repeat
    RedrawBG;
    DrawMenuBar(Menus, Sel);
    if Open then
      begin
      wmax := 0;
      for i := 0 to High(Menus[Sel].Items) do
        wmax := Max(wmax, Length(PlainText(Menus[Sel].Items[i].Text)));
      w := wmax + 4;
      x := mx[Sel] - 1;
      if x + w > ScrW then x := Max(0, ScrW - w);
      y := 1;
      ScrBox(x, y, w, Length(Menus[Sel].Items) + 2, cBoxFg, cBoxBg, False);
      for i := 0 to High(Menus[Sel].Items) do
        if i = Item then
          begin
          ScrFill(x + 1, y + 1 + i, w - 2, 32, cSelFg, cSelBg);
          PutMnemonic(x + 2, y + 1 + i, Menus[Sel].Items[i].Text, cSelFg, cSelBg, cHotFg, w - 4);
          end
        else PutMnemonic(x + 2, y + 1 + i, Menus[Sel].Items[i].Text, cBoxFg, cBoxBg, cHotFg, w - 4);
      end;
    ScrHideCursor;
    ScrFlush;
    k := GetKey;
    case k.code of
      kcEsc: begin if Open then Open := False else Exit(0); end;
      kcLeft: begin Sel := (Sel + Length(Menus) - 1) mod Length(Menus); Item := 0; end;
      kcRight: begin Sel := (Sel + 1) mod Length(Menus); Item := 0; end;
      kcDown: if not Open then begin Open := True; Item := 0; end
              else Item := (Item + 1) mod Length(Menus[Sel].Items);
      kcUp: if Open then Item := (Item + Length(Menus[Sel].Items) - 1) mod Length(Menus[Sel].Items);
      kcHome: Item := 0;
      kcEnd: if Open then Item := High(Menus[Sel].Items);
      kcEnter: begin
        if not Open then begin Open := True; Item := 0; end
        else Exit(Menus[Sel].Items[Item].Cmd);
        end;
      kcChar: if (k.mods = []) and (Length(k.ch) = 1) then
        begin
        c := UpCase(k.ch[1]);
        if Open then
          begin
          for i := 0 to High(Menus[Sel].Items) do
            if MnemonicOf(Menus[Sel].Items[i].Text) = c then Exit(Menus[Sel].Items[i].Cmd);
          end
        else
          for i := 0 to High(Menus) do
            if MnemonicOf(Menus[i].Title) = c then begin Sel := i; Open := True; Item := 0; Break; end;
        end;
    end;
  until False;
end;

function PickList(const Title: String; const Items: array of String; StartSel: Integer; RedrawBG: TRedraw): Integer;
var Deleted: Boolean;
begin
  Result := PickListDel(Title, Items, StartSel, RedrawBG, Deleted);
end;

function PickListDel(const Title: String; const Items: array of String; StartSel: Integer; RedrawBG: TRedraw;
                      out Deleted: Boolean): Integer;
var
  Sel, Top, bw, bh, x, y, rows, i: Integer;
  k: TKey;
begin
  Deleted := False;
  Result := -1;
  if Length(Items) = 0 then Exit;
  Sel := StartSel;
  if (Sel < 0) or (Sel > High(Items)) then Sel := 0;
  Top := 0;
  repeat
    RedrawBG;
    bw := Min(ScrW - 4, 70);
    bh := Min(ScrH - 4, Length(Items) + 2);
    if bh < 5 then bh := Min(ScrH, 5);
    x := (ScrW - bw) div 2;
    y := (ScrH - bh) div 2;
    rows := bh - 2;
    if Sel < Top then Top := Sel;
    if Sel >= Top + rows then Top := Sel - rows + 1;
    ScrBox(x, y, bw, bh, cBoxFg, cBoxBg, True);
    ScrPutsN(x + 2, y, ' ' + Title + ' ', bw - 4, cBoxFg, cBoxBg);
    for i := 0 to rows - 1 do
      if Top + i <= High(Items) then
        if Top + i = Sel then
          begin
          ScrFill(x + 1, y + 1 + i, bw - 2, 32, cSelFg, cSelBg);
          ScrPutsN(x + 2, y + 1 + i, Items[Top + i], bw - 4, cSelFg, cSelBg);
          end
        else ScrPutsN(x + 2, y + 1 + i, Items[Top + i], bw - 4, cBoxFg, cBoxBg);
    ScrHideCursor;
    ScrFlush;
    k := GetKey;
    case k.code of
      kcEsc: Exit(-1);
      kcUp: if Sel > 0 then Dec(Sel);
      kcDown: if Sel < High(Items) then Inc(Sel);
      kcPgUp: Sel := Max(0, Sel - rows);
      kcPgDn: Sel := Min(High(Items), Sel + rows);
      kcHome: Sel := 0;
      kcEnd: Sel := High(Items);
      kcEnter: Exit(Sel);
      kcDel: begin Deleted := True; Exit(Sel); end;
      kcChar: if Length(k.ch) = 1 then
        for i := 0 to High(Items) do
          if (Items[i] <> '') and (UpCase(Items[i][1]) = UpCase(k.ch[1])) then begin Sel := i; Break; end;
    end;
  until False;
end;

function PromptLine(const Title, Initial: String; RedrawBG: TRedraw; out Res: String): Boolean;
var
  s: String;
  p, w, x, y, fw: Integer;
  k: TKey;
begin
  s := Initial;
  p := Length(s) + 1;
  repeat
    RedrawBG;
    w := Min(ScrW - 2, 76);
    if w < 24 then w := ScrW;
    x := (ScrW - w) div 2;
    y := ScrH div 2 - 2;
    if y < 0 then y := 0;
    ScrBox(x, y, w, 4, cBoxFg, cBoxBg, False);
    ScrPutsN(x + 2, y + 1, Title, w - 4, cBoxFg, cBoxBg);
    fw := w - 4;
    ScrFill(x + 2, y + 2, fw, 32, cSelFg, cSelBg);
    ScrPutsN(x + 2, y + 2, s, fw, cSelFg, cSelBg);
    ScrCursor(x + 2 + Min(p - 1, fw - 1), y + 2, False);
    ScrFlush;
    k := GetKey;
    case k.code of
      kcEnter: begin Res := s; Exit(True); end;
      kcEsc: Exit(False);
      kcBack: if p > 1 then begin Delete(s, p - 1, 1); Dec(p); end;
      kcDel: if p <= Length(s) then Delete(s, p, 1);
      kcLeft: if p > 1 then Dec(p);
      kcRight: if p <= Length(s) then Inc(p);
      kcHome: p := 1;
      kcEnd: p := Length(s) + 1;
      kcChar: if (k.mods = []) and (Length(k.ch) >= 1) then begin Insert(k.ch, s, p); Inc(p, Length(k.ch)); end;
    end;
  until False;
end;

procedure ShowMessage(const Title: String; const Lines: array of String; RedrawBG: TRedraw);
var
  i, w, h, x, y: Integer;
  k: TKey;
begin
  RedrawBG;
  w := Length(Title) + 4;
  for i := 0 to High(Lines) do w := Max(w, Length(Lines[i]) + 4);
  w := Min(w, ScrW - 2);
  h := Length(Lines) + 2;
  if Title <> '' then Inc(h);
  x := (ScrW - w) div 2;
  y := (ScrH - h) div 2;
  ScrBox(x, y, w, h, cBoxFg, cBoxBg, False);
  if Title <> '' then ScrPutsN(x + 2, y + 1, Title, w - 4, cBoxFg, cBoxBg);
  for i := 0 to High(Lines) do ScrPutsN(x + 2, y + 1 + i + Ord(Title <> ''), Lines[i], w - 4, cBoxFg, cBoxBg);
  ScrHideCursor;
  ScrFlush;
  GetKey;
end;

end.
