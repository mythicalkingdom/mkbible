; Inno Setup 6 script for mkbible: the graphical reader mkbibleg and, as an option, the command line tools.
; Build it with installer\build-installer.bat (see installer\README.md); it needs a 64 bit build in ..\build.
; No OpenSSL is needed: the module downloader uses the HTTPS support Windows has (WinInet).

#ifndef MyVersion
  #define MyVersion "0.0.0"
#endif
#define MyName "mkbible"
#define MyExe "mkbibleg.exe"

#if !FileExists(SourcePath + "..\build\" + MyExe)
  #error "..\build\mkbibleg.exe is missing: run build.bat gui first (a 64 bit compiler)."
#endif

[Setup]
; the id marks this program for upgrades and the uninstaller: never change it
AppId={{D042015C-8CF2-4543-A5D1-9B4578F160BB}
AppName={#MyName}
AppVersion={#MyVersion}
AppVerName={#MyName} {#MyVersion}
AppPublisher=mkbible
AppPublisherURL=https://github.com/mythicalkingdom/mkbible
AppSupportURL=https://github.com/mythicalkingdom/mkbible/issues
AppUpdatesURL=https://github.com/mythicalkingdom/mkbible/releases
DefaultDirName={autopf}\{#MyName}
DefaultGroupName={#MyName}
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
OutputDir=Output
OutputBaseFilename=mkbible-{#MyVersion}-setup
SetupIconFile=..\gui\mkbibleg.ico
UninstallDisplayIcon={app}\{#MyExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; 64 bit Windows only
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; a per user install by default (no administrator needed); the dialog lets the user choose all users
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ChangesEnvironment=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Types]
Name: "full"; Description: "Full installation"
Name: "compact"; Description: "The reader only"
Name: "custom"; Description: "Custom installation"; Flags: iscustom

[Components]
Name: "main"; Description: "mkbible, the Bible reader"; Types: full compact custom; Flags: fixed
Name: "tools"; Description: "Command line tools (bibconv, dictconv, bibimp, bibdump, bibmk, bibepub)"; Types: full

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; Flags: unchecked
Name: "addpath"; Description: "Add the command line tools to the &PATH"; Components: tools; Flags: unchecked

[Files]
Source: "..\build\{#MyExe}"; DestDir: "{app}"; Components: main; Flags: ignoreversion
; any extra DLL put in redist (a sqlite3.dll, say; none is needed otherwise)
Source: "redist\*.dll"; DestDir: "{app}"; Components: main; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Components: main; Flags: ignoreversion
Source: "licenses\*"; DestDir: "{app}\licenses"; Components: main; Flags: ignoreversion
Source: "redist\licenses\*"; DestDir: "{app}\licenses"; Components: main; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\build\bibconv.exe"; DestDir: "{app}"; Components: tools; Flags: ignoreversion
Source: "..\build\dictconv.exe"; DestDir: "{app}"; Components: tools; Flags: ignoreversion
Source: "..\build\bibimp.exe"; DestDir: "{app}"; Components: tools; Flags: ignoreversion
Source: "..\build\bibdump.exe"; DestDir: "{app}"; Components: tools; Flags: ignoreversion
Source: "..\build\bibmk.exe"; DestDir: "{app}"; Components: tools; Flags: ignoreversion
Source: "..\build\bibepub.exe"; DestDir: "{app}"; Components: tools; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyName}"; Filename: "{app}\{#MyExe}"
Name: "{autodesktop}\{#MyName}"; Filename: "{app}\{#MyExe}"; Tasks: desktopicon

[Registry]
; the PATH entry for the command line tools: the user's, or the system's for an all users install
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; Tasks: addpath; Check: NeedsAddPath('HKCU', 'Environment')
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; Tasks: addpath; Check: NeedsAddPath('HKLM', 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment')

[Run]
Filename: "{app}\{#MyExe}"; Description: "Start mkbible"; Flags: nowait postinstall skipifsilent

; The user's settings and modules (%APPDATA%\mkbible, %APPDATA%\Sword) are left alone when uninstalling.

[Code]
{ the registry key for the Path matching how this installer runs; True when {app} is not in it yet }
function NeedsAddPath(Root, Key: string): Boolean;
var
  Paths: string;
  RootKey: Integer;
begin
  { only the entry for this kind of install is wanted: the other one reports False }
  if IsAdminInstallMode then
    begin
    if Root <> 'HKLM' then begin Result := False; Exit; end;
    RootKey := HKEY_LOCAL_MACHINE;
    end
  else
    begin
    if Root <> 'HKCU' then begin Result := False; Exit; end;
    RootKey := HKEY_CURRENT_USER;
    end;
  if not RegQueryStringValue(RootKey, Key, 'Path', Paths) then Paths := '';
  Result := Pos(';' + Uppercase(ExpandConstant('{app}')) + ';', ';' + Uppercase(Paths) + ';') = 0;
end;

{ takes the install folder out of the Path again }
procedure RemoveFromPath(RootKey: Integer; const Key: string);
var
  Paths, Dir: string;
  P: Integer;
begin
  if not RegQueryStringValue(RootKey, Key, 'Path', Paths) then Exit;
  Dir := ExpandConstant('{app}');
  P := Pos(';' + Uppercase(Dir), ';' + Uppercase(Paths));
  if P = 0 then Exit;
  Delete(Paths, P, Length(Dir) + 1);
  if (Length(Paths) > 0) and (Paths[1] = ';') then Delete(Paths, 1, 1);
  RegWriteExpandStringValue(RootKey, Key, 'Path', Paths);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    begin
    if IsAdminInstallMode then RemoveFromPath(HKEY_LOCAL_MACHINE, 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment')
    else RemoveFromPath(HKEY_CURRENT_USER, 'Environment');
    end;
end;
