@echo off
rem Build the MK Bible units and the programs on Windows into .\build   (the Windows counterpart of build.sh)
rem   build.bat           the command line tools (bibconv, dictconv, bibimp, bibdump, bibmk, ...)
rem   build.bat gui       also the GUI reader, mkbiblegui.exe (needs Lazarus: lazbuild on the PATH, plus the
rem                       BGRABitmap and BGRAControls packages, see gui\README.md)
rem Needs the Free Pascal compiler (fpc) on the PATH; Lazarus installs one.  The text mode reader (mkbible) is Unix
rem only and is not built here.  MySword and theWord modules need sqlite3.dll (64 bit) next to the programs.
setlocal
cd /d "%~dp0"
if not exist build mkdir build
if not exist build\gui-units mkdir build\gui-units
where fpc >nul 2>nul
if errorlevel 1 (
  echo fpc was not found on the PATH.  Install Lazarus or Free Pascal and add its bin folder to the PATH.
  exit /b 1
)
for %%u in (MKBibVrA MKBibVrs MKBibZ MKBibCph MKBibMkp MKBibMod MKBibAbs MKBibTxt MKBibSwd MKBibMys MKBibStp MKBibTwd MKBibVpl MKBibSql MKBibDic MKBibCom MKBibBok MKBibSwc MKDicSwd MKDicMys MKDicTwd MKDicAny MKComTwd MKBokTwd MKBibMem MKBibZef MKBibOsi MKBibUfx MKBibZip MKBibUsf MKBibUsx MKBibBeb MKBibUnb MKBibAny dictdump dicttest dictconv comtest boktest comrt bokrt bibtest bibdump bibimp bibconv bibmk bibepub mkpcheck stpdump mkbiblecfg mkbiblescan) do (
  fpc -B -Fusrc -Fisrc -FUbuild -FEbuild -vew src\%%u.pas
  if errorlevel 1 (
    echo failed: %%u
    exit /b 1
  )
)
echo command line tools built in build\
if /i "%~1"=="gui" (
  where lazbuild >nul 2>nul
  if errorlevel 1 (
    echo lazbuild was not found on the PATH; add the Lazarus folder to the PATH to build the GUI.
    exit /b 1
  )
  lazbuild --ws=win32 gui\mkbiblegui.lpi
  if errorlevel 1 exit /b 1
  echo GUI built: build\mkbiblegui.exe
)
endlocal
