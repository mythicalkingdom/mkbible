Unit MKBibVrA;       {Stand-in for the Apocrypha tables: no Apocrypha books}

{ The Apocrypha books of the KJVA and NRSVA versifications are not part of this project: Sword indexes its
  modules by its own chapter and verse counts for them, and those tables (the canon*.h files of the Sword
  project) are under the GNU General Public License version 2 only, so they are not included.  The 66
  canonical books of a Sword module that has an Apocrypha are read and written as usual (the Apocrypha sits
  after Malachi in the OT file and the NT file is separate); the Apocrypha books themselves are not reachable.

  tools/genvra.py writes a real MKBibVrA.pas from a copy of Sword's include directory, for local use only:
  a build with that file is a combined work under version 2, and the file must not be committed. }

{$I MKBib.Def}

Interface

Const
  NApocKJVA = 0;
  NApocNRSVA = 0;
  MaxApocBooks = 0;

Type
  ApocBookRec = Record Name, OSIS, Abbrev: String[24]; Chaps: Byte; End;

Const
  ApocKJVA: Array[1..1] Of ApocBookRec = ((Name: ''; OSIS: ''; Abbrev: ''; Chaps: 0));
  ApocNRSVA: Array[1..1] Of ApocBookRec = ((Name: ''; OSIS: ''; Abbrev: ''; Chaps: 0));
  ApocVMKJVA: Array[0..0] Of Byte = (0);
  ApocVMNRSVA: Array[0..0] Of Byte = (0);

Implementation

End.
