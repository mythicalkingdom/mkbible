Unit MKBibZip;       {Unzip a .zip file into a folder (for zipped Bible text files)}

{$MODE OBJFPC}{$H+}

Interface

Function UnzipTo(Const ZipFile, Dir: AnsiString): Boolean;
  {extract every file of ZipFile into Dir (which is created); False if it cannot be read}
Procedure RemoveTree(Const Dir: AnsiString);
  {delete a folder and what is in it (only used on the temporary folders made for UnzipTo)}

Implementation

Uses SysUtils, Classes, Zipper;

Function UnzipTo(Const ZipFile, Dir: AnsiString): Boolean;
  Var U: TUnZipper;
  Begin
  Result := False;
  If Not ForceDirectories(Dir) Then Exit;
  U := TUnZipper.Create;
  Try
    Try
      U.FileName := ZipFile;
      U.OutputPath := Dir;
      U.UnZipAllFiles;
      Result := True;
    Except
      Result := False;
    End;
  Finally
    U.Free;
  End;
  End;

Procedure RemoveTree(Const Dir: AnsiString);
  Var
    SR: TSearchRec;
    D: AnsiString;
  Begin
  D := IncludeTrailingPathDelimiter(Dir);
  If FindFirst(D + '*', faAnyFile, SR) = 0 Then
    Begin
    Repeat
      If (SR.Name <> '.') And (SR.Name <> '..') Then
        Begin
        If (SR.Attr And faDirectory) <> 0 Then RemoveTree(D + SR.Name)
        Else DeleteFile(D + SR.Name);
        End;
    Until FindNext(SR) <> 0;
    FindClose(SR);
    End;
  RemoveDir(D);
  End;

End.
