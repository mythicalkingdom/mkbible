Program BibEpub;
{ bibepub - export a Bible module as an EPUB 3 book.

  usage: bibepub <module> [-o file.epub] [-t "Title"] [-a] [-k key] [-s] [-N]
     <module>   anything the other tools open: a Sword module name or .conf, a theWord / MySword file, USFM / USX folder ...
     -o <file>  output file (default <module name>.epub in the current folder)
     -t <text>  the book's title (default: the module's description)
     -a         include the Apocrypha books when the module has them
     -k <key>   unlock key of an enciphered module
     -s         short contents: books only, no chapter entries
     -N         leave the footnotes out

  The book is built for a reader's navigation, not as one long page: a title page, one XHTML file per book, and a
  real nested table of contents (Bible > Old Testament / New Testament / Apocrypha > book > chapter) in EPUB 3's
  nav document, with the EPUB 2 toc.ncx beside it for older readers.  Inside a book the chapters are headings with
  anchors; verse numbers are small superscripts; words of Jesus are red; footnotes are EPUB 3 pop-up notes.  Text,
  paragraphs, poetry lines, italics and headings come from the module's own markup through the same translator the
  converters use.  Strong's numbers, morphology and cross references are not carried. }

{$MODE OBJFPC}{$H+}
{$I-}

Uses SysUtils, Classes, DateUtils, zstream, zipper, MKBibVrs, MKBibMod, MKBibAbs, MKBibAny, MKBibMkp;

Type
  TGroup = (gOT, gNT, gAP);

Var
  Src: AbsBibPtr;
  OutFile, Title, Key: String;
  WithApoc, Short, WithNotes: Boolean;
  Z: TZipper;
  Keep: TList;                       { the streams held by the zip entries, freed after saving }
  Lang, Ident, Stamp: String;
  GroupName: array[TGroup] of String;
  GroupFile: array[TGroup] of String;
  GroupUsed: array[TGroup] of Boolean;
  NavBooks: array[TGroup] of AnsiString;      { the nested <li> entries of each group, EPUB 3 nav }
  NcxBooks: array[TGroup] of AnsiString;
  Manifest, Spine: AnsiString;
  NcxId, NBooks: Integer;
  I: Integer;

Function X(Const S: String): String;      { XML text }
  Var R: String; K: Integer;
  Begin
  R := '';
  For K := 1 To Length(S) Do
    Case S[K] Of
      '&': R := R + '&amp;';
      '<': R := R + '&lt;';
      '>': R := R + '&gt;';
      '"': R := R + '&quot;';
      #0..#8, #11, #12, #14..#31: ;
      Else R := R + S[K];
      End;
  X := R;
  End;

Function Replace(Const S, A, B: String): String;
  Begin
  Replace := StringReplace(S, A, B, [rfReplaceAll]);
  End;

Procedure AddFile(Const Name, Data: AnsiString; Stored: Boolean);
  Var
    M: TStringStream;
    E: TZipFileEntry;
  Begin
  M := TStringStream.Create(Data);
  Keep.Add(M);
  E := Z.Entries.AddFileEntry(M, Name);
  If Stored Then E.CompressionLevel := clnone;
  End;

Function Page(Const Ttl, Body: AnsiString): AnsiString;
  Begin
  Page := '<?xml version="1.0" encoding="UTF-8"?>' + #10 +
    '<!DOCTYPE html>' + #10 +
    '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="' + X(Lang) + '" lang="' + X(Lang) + '">' + #10 +
    '<head><meta charset="utf-8"/><title>' + X(Ttl) + '</title><link rel="stylesheet" type="text/css" href="style.css"/></head>' + #10 +
    '<body>' + #10 + Body + #10 + '</body>' + #10 + '</html>' + #10;
  End;

{ the About text of a Sword module has RTF-ish \par codes: make it plain paragraphs }
Function AboutHtml(S: String): AnsiString;
  Var
    R, Cur: String;
    K: Integer;
    L: TStringList;
  Begin
  S := Replace(S, '\par', #10);
  S := Replace(S, '\pard', '');
  R := '';
  K := 1;
  While K <= Length(S) Do
    Begin
    If (S[K] = '\') And (K < Length(S)) And (S[K + 1] In ['a'..'z', 'A'..'Z']) Then
      Begin
      Inc(K);
      While (K <= Length(S)) And (S[K] In ['a'..'z', 'A'..'Z', '0'..'9', '-']) Do Inc(K);
      If (K <= Length(S)) And (S[K] = ' ') Then Inc(K);
      End
    Else If (S[K] = '\') And (K < Length(S)) And (S[K + 1] = '\') Then Begin R := R + #10; Inc(K, 2); End
    Else Begin R := R + S[K]; Inc(K); End;
    End;
  AboutHtml := '';
  L := TStringList.Create;
  Try
    L.Text := R;
    For K := 0 To L.Count - 1 Do
      Begin
      Cur := Trim(L[K]);
      If Cur <> '' Then AboutHtml := AboutHtml + '<p>' + X(Cur) + '</p>' + #10;
      End;
  Finally
    L.Free;
  End;
  End;

Function GroupOf(Book: Integer): TGroup;
  Begin
  If Src^.IsApocrypha(Book) Then GroupOf := gAP
  Else If VrsInNT(Book) Then GroupOf := gNT
  Else GroupOf := gOT;
  End;

{ one book: its XHTML (or '' when the module has no text in it) }
Function BookPage(Book: Integer; Const Fn: String; Var Nav, Ncx: AnsiString): AnsiString;
  Var
    C, V, NC, NoteCount, Mk: Integer;
    Body, Chap, Notes, Raw, Nm, ChLabel, NavCh, NcxCh: AnsiString;
    Any, ChapAny: Boolean;
    F: MkpFormat;
  Begin
  BookPage := '';
  Nm := Src^.GetBookName(Book);
  F := MarkupToMkp(Src^.GetMarkup);
  NC := Src^.GetChapterCount(Book);
  Body := '<h3 class="book" id="top">' + X(Nm) + '</h3>' + #10;
  NavCh := '';
  NcxCh := '';
  NoteCount := 0;
  Any := False;
  For C := 1 To NC Do
    Begin
    Chap := '';
    Notes := '';
    ChapAny := False;
    For V := 1 To Src^.GetVerseCount(Book, C) Do
      Begin
      Src^.SetRef(Book, C, V);
      If Not Src^.VerseExists Then Continue;
      Raw := Src^.GetRawVerse;
      If Trim(Raw) = '' Then Continue;
      Chap := Chap + MkpToXhtml(Raw, F, V, WithNotes, NoteCount, Notes) + ' ';
      ChapAny := True;
      End;
    If Not ChapAny Then Continue;
    Any := True;
    ChLabel := Nm + ' ' + IntToStr(C);
    Chap := '<p>' + Chap + '</p>';
    Repeat
      Mk := Length(Chap);
      Chap := Replace(Chap, '<p></p>', '');
      Chap := Replace(Chap, '<p> </p>', '');
      Chap := Replace(Chap, '<p><br/>', '<p>');
      Chap := Replace(Chap, ' </p>', '</p>');
      Chap := Replace(Chap, '<p> ', '<p>');
      Chap := Replace(Chap, '<br/></p>', '</p>');
    Until Length(Chap) = Mk;
    Body := Body + '<h4 class="chap" id="c' + IntToStr(C) + '">' + X(ChLabel) + '</h4>' + #10 + Chap + #10 + Notes;
    If Not Short Then
      Begin
      NavCh := NavCh + '<li><a href="' + Fn + '#c' + IntToStr(C) + '">' + X(ChLabel) + '</a></li>' + #10;
      Inc(NcxId);
      NcxCh := NcxCh + '<navPoint id="n' + IntToStr(NcxId) + '" playOrder="0"><navLabel><text>' + X(ChLabel) +
               '</text></navLabel><content src="' + Fn + '#c' + IntToStr(C) + '"/></navPoint>' + #10;
      End;
    End;
  If Not Any Then Exit;
  Nav := '<li><a href="' + Fn + '">' + X(Nm) + '</a>';
  If NavCh <> '' Then Nav := Nav + #10 + '<ol>' + #10 + NavCh + '</ol>' + #10;
  Nav := Nav + '</li>' + #10;
  Inc(NcxId);
  Ncx := '<navPoint id="n' + IntToStr(NcxId) + '" playOrder="0"><navLabel><text>' + X(Nm) + '</text></navLabel><content src="' + Fn + '"/>' + #10 +
         NcxCh + '</navPoint>' + #10;
  BookPage := Page(Nm, Body);
  End;

Function MakeUuid: String;
  Var K: Integer; H: String;
  Begin
  Randomize;
  H := '';
  For K := 1 To 32 Do H := H + LowerCase(IntToHex(Random(16), 1));
  H[13] := '4';
  MakeUuid := 'urn:uuid:' + Copy(H, 1, 8) + '-' + Copy(H, 9, 4) + '-' + Copy(H, 13, 4) + '-' + Copy(H, 17, 4) + '-' + Copy(H, 21, 12);
  End;

{ number the NCX navPoints in document order (playOrder is required to be 1, 2, 3 ...) }
Function NumberNcx(Const S: AnsiString): AnsiString;
  Var P, N: Integer; R: AnsiString;
  Begin
  R := S;
  N := 0;
  P := Pos('playOrder="0"', R);
  While P > 0 Do
    Begin
    Inc(N);
    Delete(R, P, Length('playOrder="0"'));
    Insert('playOrder="' + IntToStr(N) + '"', R, P);
    P := Pos('playOrder="0"', R);
    End;
  NumberNcx := R;
  End;

Const
  Css =
    'body { font-family: serif; line-height: 1.45; margin: 5%; }' + #10 +
    'h1 { text-align: center; font-size: 2em; margin: 25% 0 0.3em; }' + #10 +
    'h2 { text-align: center; font-size: 1.7em; margin: 25% 0 0.3em; }' + #10 +
    'h3.book { text-align: center; font-size: 1.5em; margin: 1.4em 0 0.8em; page-break-before: always; }' + #10 +
    'h4.chap { font-size: 1.1em; margin: 1.6em 0 0.4em; }' + #10 +
    'h5.sh { font-size: 1em; font-style: italic; font-weight: normal; margin: 1em 0 0.3em; }' + #10 +
    'p { margin: 0 0 0.6em; text-align: left; }' + #10 +
    'p.c { text-align: center; }' + #10 +
    'p.small { font-size: 0.85em; color: #555; }' + #10 +
    'sup.vn { font-size: 0.65em; font-weight: bold; color: #666; margin-right: 0.15em; }' + #10 +
    'span.jesus { color: #b00020; }' + #10 +
    'a.fn { font-size: 0.75em; vertical-align: super; text-decoration: none; }' + #10 +
    'aside { font-size: 0.85em; }' + #10 +
    'nav ol { list-style: none; }' + #10;

Var
  Cover, NavXml, NcxXml, Opf, Cm, Ab, ThisFile: AnsiString;
  G: TGroup;
  Book, NBook: Integer;
  Pg, NavB, NcxB, GroupLi, GroupNcx, Desc: AnsiString;
  Nb: AnsiString;

Begin
If ParamCount < 1 Then
  Begin
  WriteLn('usage: bibepub <module> [-o file.epub] [-t "Title"] [-a] [-k key] [-s] [-N]');
  Halt(1);
  End;
OutFile := '';
Title := '';
Key := '';
WithApoc := False;
Short := False;
WithNotes := True;
I := 2;
While I <= ParamCount Do
  Begin
  If (ParamStr(I) = '-o') And (I < ParamCount) Then Begin OutFile := ParamStr(I + 1); Inc(I); End
  Else If (ParamStr(I) = '-t') And (I < ParamCount) Then Begin Title := ParamStr(I + 1); Inc(I); End
  Else If (ParamStr(I) = '-k') And (I < ParamCount) Then Begin Key := ParamStr(I + 1); Inc(I); End
  Else If ParamStr(I) = '-a' Then WithApoc := True
  Else If ParamStr(I) = '-s' Then Short := True
  Else If ParamStr(I) = '-N' Then WithNotes := False
  Else Begin WriteLn('bibepub: unknown option ', ParamStr(I)); Halt(1); End;
  Inc(I);
  End;
Src := NewBibObj(ParamStr(1));
If Key <> '' Then Src^.SetUnlockKey(Key);
If WithApoc Then Src^.SetApocrypha(True);
If Src^.OpenBible <> bibOk Then
  Begin
  If Src^.IsLocked Then WriteLn('bibepub: the module is enciphered, give its key with -k') Else WriteLn('bibepub: cannot open ', ParamStr(1));
  Halt(2);
  End;
If Title = '' Then Title := Src^.GetDescription;
If Title = '' Then Title := Src^.GetName;
If Title = '' Then Title := 'Bible';
If OutFile = '' Then
  Begin
  OutFile := Src^.GetName;
  If OutFile = '' Then OutFile := 'bible';
  OutFile := OutFile + '.epub';
  End;
Lang := Src^.GetLang;
If Lang = '' Then Lang := 'en';
Ident := MakeUuid;
Stamp := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"', LocalTimeToUniversal(Now));
GroupName[gOT] := 'Old Testament'; GroupFile[gOT] := 'ot.xhtml';
GroupName[gNT] := 'New Testament'; GroupFile[gNT] := 'nt.xhtml';
GroupName[gAP] := 'Apocrypha'; GroupFile[gAP] := 'ap.xhtml';
For G := gOT To gAP Do Begin GroupUsed[G] := False; NavBooks[G] := ''; NcxBooks[G] := ''; End;

Z := TZipper.Create;
Keep := TList.Create;
Try
  Z.FileName := OutFile;
  AddFile('mimetype', 'application/epub+zip', True);
  AddFile('META-INF/container.xml',
    '<?xml version="1.0" encoding="UTF-8"?>' + #10 +
    '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">' + #10 +
    '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>' + #10 +
    '</container>' + #10, False);
  AddFile('OEBPS/style.css', Css, False);

  Manifest := '';
  Spine := '';
  NcxId := 0;
  NBooks := 0;

  { title page }
  Cm := Src^.GetCopyright;
  Ab := AboutHtml(Src^.GetAbout);
  Desc := '<h1 id="title">' + X(Title) + '</h1>' + #10;
  If (Src^.GetName <> '') And (Src^.GetName <> Title) Then Desc := Desc + '<p class="c">' + X(Src^.GetName) + '</p>' + #10;
  If Cm <> '' Then Desc := Desc + '<p class="c small">' + X(Cm) + '</p>' + #10;
  If Ab <> '' Then Desc := Desc + '<div class="about">' + #10 + Ab + '</div>' + #10;
  AddFile('OEBPS/title.xhtml', Page(Title, Desc), False);
  Manifest := Manifest + '<item id="title" href="title.xhtml" media-type="application/xhtml+xml"/>' + #10;
  Spine := Spine + '<itemref idref="title"/>' + #10;

  { the books }
  For Book := 1 To Src^.GetBookCount Do
    Begin
    G := GroupOf(Book);
    ThisFile := Format('b%.2d.xhtml', [Book]);
    NavB := ''; NcxB := '';
    Pg := BookPage(Book, ThisFile, NavB, NcxB);
    If Pg = '' Then Continue;
    Inc(NBooks);
    Write(StdErr, #13, Src^.GetBookName(Book), '                    ');
    If Not GroupUsed[G] Then
      Begin
      GroupUsed[G] := True;
      AddFile('OEBPS/' + GroupFile[G], Page(GroupName[G], '<h2 id="g">' + X(GroupName[G]) + '</h2>'), False);
      Manifest := Manifest + '<item id="g' + IntToStr(Ord(G)) + '" href="' + GroupFile[G] + '" media-type="application/xhtml+xml"/>' + #10;
      End;
    AddFile('OEBPS/' + ThisFile, Pg, False);
    Manifest := Manifest + '<item id="b' + IntToStr(Book) + '" href="' + ThisFile + '" media-type="application/xhtml+xml"/>' + #10;
    NavBooks[G] := NavBooks[G] + NavB;
    NcxBooks[G] := NcxBooks[G] + NcxB;
    End;
  If NBooks = 0 Then
    Begin
    WriteLn('bibepub: the module has no text');
    Halt(2);
    End;

  { spine in reading order: title, then each group page followed by its books }
  For G := gOT To gAP Do
    If GroupUsed[G] Then
      Begin
      Spine := Spine + '<itemref idref="g' + IntToStr(Ord(G)) + '"/>' + #10;
      For Book := 1 To Src^.GetBookCount Do
        If (GroupOf(Book) = G) And (Pos('id="b' + IntToStr(Book) + '"', Manifest) > 0) Then
          Spine := Spine + '<itemref idref="b' + IntToStr(Book) + '"/>' + #10;
      End;

  { EPUB 3 navigation document: Bible > testament > book > chapter }
  GroupLi := '';
  GroupNcx := '';
  For G := gOT To gAP Do
    If GroupUsed[G] Then
      Begin
      GroupLi := GroupLi + '<li><a href="' + GroupFile[G] + '">' + X(GroupName[G]) + '</a>' + #10 + '<ol>' + #10 + NavBooks[G] + '</ol>' + #10 + '</li>' + #10;
      Inc(NcxId);
      GroupNcx := GroupNcx + '<navPoint id="n' + IntToStr(NcxId) + '" playOrder="0"><navLabel><text>' + X(GroupName[G]) +
                  '</text></navLabel><content src="' + GroupFile[G] + '"/>' + #10 + NcxBooks[G] + '</navPoint>' + #10;
      End;
  NavXml := '<nav epub:type="toc" id="toc"><h1>Contents</h1>' + #10 + '<ol>' + #10 +
            '<li><a href="title.xhtml">' + X(Title) + '</a>' + #10 + '<ol>' + #10 + GroupLi + '</ol>' + #10 + '</li>' + #10 + '</ol></nav>' + #10;
  For G := gOT To gAP Do
    If GroupUsed[G] Then Begin Nb := GroupFile[G]; Break; End;
  NavXml := NavXml + '<nav epub:type="landmarks" hidden="hidden"><h2>Landmarks</h2><ol>' +
            '<li><a epub:type="titlepage" href="title.xhtml">Title page</a></li>' +
            '<li><a epub:type="bodymatter" href="' + Nb + '">Start of the text</a></li></ol></nav>' + #10;
  AddFile('OEBPS/nav.xhtml', Page('Contents', NavXml), False);
  Manifest := Manifest + '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>' + #10;

  { EPUB 2 table of contents for older readers }
  NcxXml := '<?xml version="1.0" encoding="UTF-8"?>' + #10 +
            '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">' + #10 +
            '<head><meta name="dtb:uid" content="' + X(Ident) + '"/><meta name="dtb:depth" content="4"/>' +
            '<meta name="dtb:totalPageCount" content="0"/><meta name="dtb:maxPageNumber" content="0"/></head>' + #10 +
            '<docTitle><text>' + X(Title) + '</text></docTitle>' + #10 +
            '<navMap>' + #10 +
            '<navPoint id="n0" playOrder="0"><navLabel><text>' + X(Title) + '</text></navLabel><content src="title.xhtml"/>' + #10 +
            GroupNcx + '</navPoint>' + #10 + '</navMap>' + #10 + '</ncx>' + #10;
  AddFile('OEBPS/toc.ncx', NumberNcx(NcxXml), False);
  Manifest := Manifest + '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>' + #10;
  Manifest := Manifest + '<item id="css" href="style.css" media-type="text/css"/>' + #10;

  Opf := '<?xml version="1.0" encoding="UTF-8"?>' + #10 +
         '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="' + X(Lang) + '">' + #10 +
         '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">' + #10 +
         '<dc:identifier id="bookid">' + X(Ident) + '</dc:identifier>' + #10 +
         '<dc:title>' + X(Title) + '</dc:title>' + #10 +
         '<dc:language>' + X(Lang) + '</dc:language>' + #10;
  If Cm <> '' Then Opf := Opf + '<dc:rights>' + X(Cm) + '</dc:rights>' + #10;
  Opf := Opf + '<dc:subject>Bible</dc:subject>' + #10 +
         '<meta property="dcterms:modified">' + Stamp + '</meta>' + #10 +
         '</metadata>' + #10 +
         '<manifest>' + #10 + Manifest + '</manifest>' + #10 +
         '<spine toc="ncx">' + #10 + Spine + '</spine>' + #10 +
         '</package>' + #10;
  AddFile('OEBPS/content.opf', Opf, False);

  Z.SaveToFile(OutFile);
Finally
  For I := 0 To Keep.Count - 1 Do TObject(Keep[I]).Free;
  Keep.Free;
  Z.Free;
End;
Src^.CloseBible;
Write(StdErr, #13, '                                        ', #13);
WriteLn(OutFile, ': ', NBooks, ' books');
End.
