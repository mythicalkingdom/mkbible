Program BibMk;
{ Try the markup translator.   bibmk <from> <to> [-h] [-b] [-s] "text"      (text: "-" reads stdin)
  formats: plain osis thml gbf mysword step theword vpl html tei usfm usfx zefania rtf (step, tei: read only);  -h keep headings, -b keep breaks (plain), -s print a summary too }
{$MODE OBJFPC}{$H+}
Uses SysUtils, MKBibMkp;

Function Fmt(Const S: String): MkpFormat;
  Begin
  If S = 'osis' Then Fmt := mfOSIS
  Else If S = 'thml' Then Fmt := mfThML
  Else If S = 'gbf' Then Fmt := mfGBF
  Else If S = 'mysword' Then Fmt := mfMySword
  Else If S = 'step' Then Fmt := mfSTEP
  Else If S = 'theword' Then Fmt := mfTheWord
  Else If S = 'vpl' Then Fmt := mfVPL
  Else If S = 'html' Then Fmt := mfHTML
  Else If S = 'tei' Then Fmt := mfTEI
  Else If S = 'usfm' Then Fmt := mfUSFM
  Else If S = 'usfx' Then Fmt := mfUSFX
  Else If S = 'zefania' Then Fmt := mfZefania
  Else If S = 'rtf' Then Fmt := mfSTEP
  Else If S = 'plain' Then Fmt := mfPlain
  Else Begin WriteLn('unknown format ', S); Halt(1); End;
  End;

Var
  Opts: MkpOpts;
  Summ: Boolean;
  i: Integer;
  Txt, L: AnsiString;
  F, T: MkpFormat;
Begin
If ParamCount < 3 Then Begin WriteLn('usage: bibmk <from> <to> [-h] [-b] [-s] "text"'); Halt(1); End;
F := Fmt(LowerCase(ParamStr(1)));
T := Fmt(LowerCase(ParamStr(2)));
Opts := []; Summ := False; Txt := '';
For i := 3 To ParamCount Do
  If ParamStr(i) = '-h' Then Include(Opts, moHeadings)
  Else If ParamStr(i) = '-b' Then Include(Opts, moBreaks)
  Else If ParamStr(i) = '-s' Then Summ := True
  Else Txt := ParamStr(i);
If Txt = '-' Then
  Begin
  Txt := '';
  While Not Eof(Input) Do Begin ReadLn(L); Txt := Txt + L + #10; End;
  End;
WriteLn(MkpTranslate(Txt, F, T, Opts));
If Summ Then
  Begin
  WriteLn('  in : ', MkpSummary(Txt, F));
  WriteLn('  out: ', MkpSummary(MkpTranslate(Txt, F, T, Opts), T));
  End;
End.
