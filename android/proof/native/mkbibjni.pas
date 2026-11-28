library mkbibjni;
{ The Pascal Bible core as an Android native library (JNI), used by the Kotlin app.  Every function is on the
  Kotlin object org.mkbible.proof.Native.  Results are plain strings (tab and line separated) so the Kotlin
  side stays simple; chapter text comes as styled "events", see MkpToEvents in MKBibMkp.pas.

    open(conf): Long          handle of an opened module (0 = failed)      close(h)
    info(h): String           name TAB description TAB language TAB markup
    books(h): String          per book: osis TAB name TAB abbreviation TAB chapters
    chapter(h, book, chap)    the chapter: "V TAB n" before each verse's events, "S TAB 0" starts a section
                              heading that comes before verse 1, then events as in MkpToEvents
    search(h, text, scope, max)   per hit: book TAB chapter TAB verse TAB plain text  (scope 0 all, 1 OT, 2 NT)
    find(h, text): String     book TAB chapter TAB verse of a reference like "1 Cor 13:4", "" if none
    verseText(h, b, c, v)     plain text of one verse }
{$mode objfpc}{$H+}
uses
  SysUtils, jni, MKBibMod, MKBibAbs, MKBibAny, MKBibMkp;

function JStr(Env: PJNIEnv; S: jstring): String;
var P: PChar;
begin
  Result := '';
  if S = nil then Exit;
  P := Env^^.GetStringUTFChars(Env, S, nil);
  if P <> nil then
  begin
    Result := P;
    Env^^.ReleaseStringUTFChars(Env, S, P);
  end;
end;

function Ret(Env: PJNIEnv; const S: String): jstring;
begin
  Result := Env^^.NewStringUTF(Env, PChar(S));
end;

function Bib(H: jlong): AbsBibPtr;
begin
  Result := AbsBibPtr(PtrUInt(H));
end;

function Clean(const S: String): String;
var I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if Result[I] in [#9, #10, #13] then Result[I] := ' ';
end;

function Open(Env: PJNIEnv; Cls: jclass; Conf: jstring): jlong; cdecl;
var B: AbsBibPtr;
begin
  Result := 0;
  try
    B := NewBibObj(JStr(Env, Conf));
    if B = nil then Exit;
    if B^.OpenBible <> bibOk then Exit;
    Result := jlong(PtrUInt(B));
  except
  end;
end;

procedure Close(Env: PJNIEnv; Cls: jclass; H: jlong); cdecl;
begin
  if H <> 0 then
    try
      Bib(H)^.CloseBible;
      Dispose(Bib(H));
    except
    end;
end;

function Info(Env: PJNIEnv; Cls: jclass; H: jlong): jstring; cdecl;
var B: AbsBibPtr;
begin
  B := Bib(H);
  Result := Ret(Env, Clean(B^.GetName) + #9 + Clean(B^.GetDescription) + #9 + Clean(B^.GetLang) + #9 +
    Clean(B^.GetCopyright));
end;

function Books(Env: PJNIEnv; Cls: jclass; H: jlong): jstring; cdecl;
var B: AbsBibPtr; I: Word; Out: String;
begin
  B := Bib(H);
  Out := '';
  for I := 1 to B^.GetBookCount do
    Out := Out + B^.GetBookOSIS(I) + #9 + B^.GetBookName(I) + #9 + B^.GetBookAbbrev(I) + #9 +
      IntToStr(B^.GetChapterCount(I)) + #10;
  Result := Ret(Env, Out);
end;

function Chapter(Env: PJNIEnv; Cls: jclass; H: jlong; Book, Chap: jint): jstring; cdecl;
var
  B: AbsBibPtr;
  Out, V, Hd: String;
  Fmt: MkpFormat;
begin
  Out := '';
  try
    B := Bib(H);
    Fmt := B^.GetMkpFormat;
    if B^.SetRef(Book, Chap, 1) then
      while B^.SeekFound and (B^.GetBook = Book) and (B^.GetChapter = Chap) do
      begin
        if B^.GetVerse = 1 then
        begin
          Hd := B^.GetHeading;
          if Hd <> '' then Out := Out + 'S' + #9 + '0' + #10 + MkpToEvents(Hd, Fmt);
        end;
        V := B^.GetRawVerse;
        if V <> '' then
          Out := Out + 'V' + #9 + IntToStr(B^.GetVerse) + #10 + MkpToEvents(V, Fmt);
        B^.SeekNext;
      end;
  except
    on E: Exception do Out := 'E' + #9 + E.Message + #10;
  end;
  Result := Ret(Env, Out);
end;

function Search(Env: PJNIEnv; Cls: jclass; H: jlong; Txt: jstring; Scope, Max: jint): jstring; cdecl;
var
  B: AbsBibPtr;
  Out: String;
  N: Integer;
begin
  Out := '';
  N := 0;
  try
    B := Bib(H);
    case Scope of
      1: B^.SetSearchScope(bsOT);
      2: B^.SetSearchScope(bsNT);
    else B^.SetSearchScope(bsAll);
    end;
    B^.SearchFirst(JStr(Env, Txt), False);
    while B^.SearchFound and (N < Max) do
    begin
      Out := Out + IntToStr(B^.GetBook) + #9 + IntToStr(B^.GetChapter) + #9 + IntToStr(B^.GetVerse) + #9 +
        Clean(B^.GetVerseText) + #10;
      Inc(N);
      B^.SearchNext;
    end;
  except
    on E: Exception do Out := '';
  end;
  Result := Ret(Env, Out);
end;

function Find(Env: PJNIEnv; Cls: jclass; H: jlong; Ref: jstring): jstring; cdecl;
var B: AbsBibPtr; R: BibRef;
begin
  Result := nil;
  B := Bib(H);
  if B^.ParseRef(JStr(Env, Ref), R) then
    Result := Ret(Env, IntToStr(R.Book) + #9 + IntToStr(R.Chapter) + #9 + IntToStr(R.Verse))
  else
    Result := Ret(Env, '');
end;

function VerseText(Env: PJNIEnv; Cls: jclass; H: jlong; Book, Chap, Verse: jint): jstring; cdecl;
var B: AbsBibPtr;
begin
  B := Bib(H);
  if B^.SetRef(Book, Chap, Verse) then Result := Ret(Env, B^.GetVerseText)
  else Result := Ret(Env, '');
end;

exports
  Open name 'Java_org_mkbible_proof_Native_open',
  Close name 'Java_org_mkbible_proof_Native_close',
  Info name 'Java_org_mkbible_proof_Native_info',
  Books name 'Java_org_mkbible_proof_Native_books',
  Chapter name 'Java_org_mkbible_proof_Native_chapter',
  Search name 'Java_org_mkbible_proof_Native_search',
  Find name 'Java_org_mkbible_proof_Native_find',
  VerseText name 'Java_org_mkbible_proof_Native_verseText';

end.
