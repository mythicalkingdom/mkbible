program mkbiblegui;
{$mode objfpc}{$H+}
{ mkbiblegui - a GUI Bible reader (Lazarus / LCL, BGRABitmap and BGRAControls) on the same Bible objects as the
  text mode mkbible.  A simple, modern look: sidebar of books, a centered reading column, light and dark. }
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, bgracontrols, uMain;

{$R *.res}

begin
  RequireDerivedFormResource := False;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
