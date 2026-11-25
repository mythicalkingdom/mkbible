# mkbiblegui - a GUI Bible reader

A simple, modern looking Bible reader on the same Bible objects as the text mode `mkbible`: a sidebar of books
with a chapter grid, a centered reading column in a serif face (red letters, italics, verse numbers), search with
highlighted hits, Copy, text size, and light and dark themes.  Drawn with BGRABitmap / BGRAControls on Lazarus (LCL).

Build (Lazarus 4 and its LCL for GTK2 are needed; GTK3 / Qt6 only need a different `--ws`):

    git clone https://github.com/bgrabitmap/bgrabitmap ~/lazarus-packages/bgrabitmap
    git clone https://github.com/bgrabitmap/bgracontrols ~/lazarus-packages/bgracontrols
    lazbuild --add-package-link ~/lazarus-packages/bgrabitmap/bgrabitmap/bgrabitmappack.lpk
    lazbuild --add-package-link ~/lazarus-packages/bgracontrols/bgracontrols.lpk
    make gui          # build/mkbiblegui

It reads the module paths of `mkbible` (`~/.config/mkbible/mkbible.cfg`) and keeps its own `gui.*` settings there.
Strong's numbers: in a module that carries them (for example the Sword KJV with Strong's), words with a number are
underlined when the mouse is over them; a click opens a pop-up with the dictionary entry (Esc or Close dismisses it).
The Sword StrongsGreek / StrongsHebrew modules on the module folders are found automatically; Settings, Strong's
dictionaries picks others (a Sword .conf, a theWord or MySword dictionary).

Menus: File (open module, copy, select text, quit), View (text size, theme, find), Settings (module folders, reading
font, Strong's dictionaries, copy with or without verse numbers), Help.  Text in the reading pane is selected with the mouse (drag, or double-click a word) and copied with Ctrl+C.
Keys: Left / Right chapter, Up / Down / PgUp / PgDn / Home / End scroll, Ctrl+F search, Ctrl+O modules, Ctrl+C copy.
Options for trying it out: `--dark`, `--search WORD`, `--chapter BOOK CHAPTER`, `--menu N`, `--select`, `--dialog font|paths|keys`, `--strong`.

Known limits: no note pop-ups yet, the module list is a native pop-up menu, and search is a plain case-insensitive
substring.

HiDPI: every size is scaled by the screen's dpi / 96 (checked at 96 and 144 dpi).  Windows: nothing in the GUI is
Unix specific, the config goes to `%APPDATA%\\mkbible`, and the font lists include Georgia and Segoe UI; build it
there with Lazarus (`lazbuild --ws=win32 gui/mkbiblegui.lpi`).  That build has not been tried.
