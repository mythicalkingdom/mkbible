# mkbible

Bible module objects for Free Pascal (Turbo Pascal style `Object` types, in the manner of MKMsgAbs), the
tools built on them, and `mkbible`, a text mode Bible reader.

## Formats

| Kind | Formats |
|---|---|
| Bibles | Sword (zText, RawText, LZSS / ZIP / bzip2, ciphers; no Apocrypha books, see License), MySword, theWord, STEP / QuickVerse, verse-per-line `.vpl`, OSIS, Zefania XML, USFX, USFM (folder or zip) |
| Dictionaries | Sword zLD, MySword `.dct.mybible`, theWord `.dct.twm` |
| Commentaries, books | theWord `.cmt.twm`, `.gbk.twm` |

The markup translator (`MKBibMkp`) converts verse text between OSIS, ThML, GBF, MySword, theWord, STEP RTF,
USFM, USFX, Zefania, HTML, TEI and plain text, keeping notes, headings, italics, words of Jesus, cross
references, Strong's numbers and morphology wherever the target can carry them.

## Programs (`./build.sh`, output in `build/`)

* `mkbible` - the reader: always visible menu bar, Left/Right for chapters, Alt+B book and chapter lists,
  Alt+O module list from configured paths, Alt+C copy, `/` search (plain or regular expression), colors.
* `bibconv`, `dictconv` - convert modules between formats.  `bibdump`, `bibtest`, `bibimp`, `dicttest`,
  `comtest`, `boktest` - inspect and build modules.  `bibmk` - try the markup translator.
* `tools/regress.sh` - the regression suite: checks against Sword's own `mod2imp`, `diatheke` and
  `vpl2mod`, independent Python readers, and round trips.  Checks that need sample files on the
  author's machine are skipped when the files are not there.

Needs Free Pascal 3.2 and `libsqlite3` at run time (MySword, theWord).  `NOTES` on formats that were looked at and
left alone (vendor-protected libraries) are not part of this repository.

## License

GNU General Public License, version 3: see `LICENSE`.

Nothing in the repository is copied from Sword.  The 66 book tables (`src/MKBibVrs.pas`, from `tools/genvrs.py`) are
counted in a public domain Bible text.  The Apocrypha of the KJVA and NRSVA versifications are not included: Sword
indexes its modules by its own chapter and verse counts for them, and those tables are under version 2 of the GPL
only.  `src/MKBibVrA.pas` is therefore a stand-in with no Apocrypha books; the 66 canonical books of a Sword module
that has an Apocrypha still read and write.  `./build.sh --sword-apocrypha` writes a local `MKBibVrA.pas` from a copy
of Sword's include directory (`tools/genvra.py`) for your own use; a build with it is a combined work under version 2
and the file must not be committed or distributed.

`uScreen`, `uCP437`, `uKeys` and `uText` are shared with the MKEdit editor.
