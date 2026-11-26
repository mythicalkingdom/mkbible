@echo off
rem Build the Windows installer: installer\Output\mkbible-<version>-setup.exe
rem Needs a 64 bit Free Pascal / Lazarus (see the README, Windows), Inno Setup 6 and the OpenSSL DLLs in installer\redist
rem (installer\README.md).  Run it from anywhere:  installer\build-installer.bat
setlocal
cd /d "%~dp0"

rem the version comes from src\mkbible.pas  (  VERSION = '0.4.1';  )
set VER=
for /f "tokens=2 delims='" %%v in ('findstr /c:"VERSION = " ..\src\mkbible.pas') do if not defined VER set VER=%%v
if not defined VER (
  echo could not read the version from src\mkbible.pas
  exit /b 1
)

rem the installer is 64 bit only: the compiler has to be too
set CPU=
for /f %%p in ('fpc -iTP') do set CPU=%%p
if /i not "%CPU%"=="x86_64" (
  echo The Free Pascal compiler on the PATH builds for "%CPU%", not x86_64.  Put the 64 bit one first on the PATH.
  exit /b 1
)

if not exist redist\libssl-3-x64.dll (
  echo installer\redist\libssl-3-x64.dll is missing: see installer\README.md
  exit /b 1
)
if not exist redist\libcrypto-3-x64.dll (
  echo installer\redist\libcrypto-3-x64.dll is missing: see installer\README.md
  exit /b 1
)

call ..\build.bat gui
if errorlevel 1 exit /b 1

set ISCC=
where ISCC >nul 2>nul && set ISCC=ISCC
if not defined ISCC if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe
if not defined ISCC if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe
if not defined ISCC if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" set ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe
if not defined ISCC (
  echo Inno Setup 6 was not found.  Install it ^(winget install JRSoftware.InnoSetup^) or add ISCC.exe to the PATH.
  exit /b 1
)

"%ISCC%" /DMyVersion=%VER% mkbibleg.iss
if errorlevel 1 exit /b 1
echo.
echo built installer\Output\mkbible-%VER%-setup.exe
endlocal
