# DLLs the installer carries

This folder is git-ignored apart from this file: put the DLLs for the 64 bit Windows installer here before running
`installer\build-installer.bat`.  Nothing here is built by us.

Required (the program asks for exactly these first, see `src/mkbiblerepo.pas`):

* `libssl-3-x64.dll`
* `libcrypto-3-x64.dll`

OpenSSL **3**, 64 bit.  OpenSSL 4 does not work with the Free Pascal 3.2.2 code, and winget's
`ShiningLight.OpenSSL.Light` no longer offers a 3.x download.  The files that worked on the test machine were copied from
Git for Windows (`C:\Program Files\Git\ucrt64\bin`).

Add if the OpenSSL DLLs need them (the installer copies every `*.dll` in this folder):

* `zlib1.dll` (and its licence in `redist\licenses\`)
* `sqlite3.dll`, a 64 bit one from sqlite.org, only if you do not want to rely on the `winsqlite3.dll` that Windows 10
  and 11 include.

Licence texts for anything added go in `installer\redist\licenses\` (copied to the install folder's `licenses`).
After changing this folder, test the installer on a machine that has none of the build tools (Windows Sandbox is
handy): the *Download modules* window is the part that needs these DLLs.
