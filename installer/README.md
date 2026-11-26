# Windows installer

An [Inno Setup](https://jrsoftware.org/isinfo.php) 6 installer for the 64 bit Windows build: the graphical reader
`mkbibleg.exe`, an optional set of command line tools (`bibconv`, `dictconv`, `bibimp`, `bibdump`, `bibmk`, `bibepub`)
with an optional PATH entry, a Start menu entry (and a desktop shortcut if asked) and an uninstaller.  It installs for
the current user by default (no administrator needed); the first wizard page lets the user choose all users instead.
Settings and downloaded modules (`%APPDATA%\mkbible`, `%APPDATA%\Sword`) are left alone when uninstalling.

## Building it

1. A 64 bit Free Pascal / Lazarus on the PATH (`fpc -iTP` must print `x86_64`) with BGRABitmap and BGRAControls, as for
   `build.bat gui` (see `gui\README.md`).
2. Inno Setup 6: `winget install JRSoftware.InnoSetup`.
3. Nothing else: the module downloader uses Windows' own HTTPS, so no OpenSSL DLLs are carried. (A `sqlite3.dll` can
   be added in `installer\redist`, see its README; it is optional.)
4. Run `installer\build-installer.bat`.  It reads the version from `src\mkbible.pas`, builds the programs with
   `build.bat gui`, and compiles `mkbibleg.iss` into `installer\Output\mkbible-<version>-setup.exe`.

The installer is unsigned, so Windows SmartScreen may warn on first run ("More info", "Run anyway").

## Testing it

Run it on a machine with none of the build tools, for example in Windows Sandbox: install, start mkbible, open
*Settings, Download modules* (this is the part that needs internet access), install a small module, then uninstall and check that the
install folder and the PATH entry are gone.
