# Extra DLLs for the installer

This folder is git-ignored apart from this file.  The installer copies every `*.dll` that is in it, and needs none:

* The module downloader uses Windows' own HTTPS (WinInet), so there are no OpenSSL DLLs to bundle.
* MySword and theWord modules use the `winsqlite3.dll` that Windows 10 and 11 include.  To carry a 64 bit `sqlite3.dll`
  from sqlite.org instead (the program tries `sqlite3.dll` first), put it here.  SQLite is public domain.

Licence texts for anything added go in `installer\redist\licenses\` (copied to the install folder's `licenses`).
