#!/bin/sh
# Regression checks against Sword itself.  Needs: mod2imp + libsword (for mkmod), the modules
# in ~/.sword, and a built tree (./build.sh).   Usage: tools/regress.sh
set -e
cd "$(dirname "$0")/.."
T=$(mktemp -d)
# the Apocrypha tables are not part of the project (src/MKBibVrA.pas is a stand-in unless a local one was made
# with ./build.sh --sword-apocrypha): the Apocrypha checks only run with the real tables
APOC=1; grep -q "NApocKJVA = 0" src/MKBibVrA.pas && APOC=0
echo "== every verse vs mod2imp"
for p in "WEB web" "ASV asv" "LITV litv" "NASB nasb" "engwebu2024eb engwebu2024eb"; do python3 tools/cmpdump.py $p; done
SWORD_PATH=$HOME/.sword python3 tools/cmpdump.py esv esv
echo "== Apocrypha (NRSVA)"
if [ $APOC = 1 ]; then python3 tools/cmpapoc.py engwebu2024eb engwebu2024eb; else echo "skipped: no Apocrypha tables in this build"; fi
echo "== LZSS / bzip2 / cipher: test modules made with libsword"
g++ -I/usr/local/include/sword tools/mkmod.cpp -L/usr/local/lib -lsword -lbz2 -o build/mkmod
build/bibdump web > $T/web.txt
mk() { n=$1; mkdir -p $T/modules/texts/ztext/$n $T/mods.d
  LD_LIBRARY_PATH=/usr/local/lib build/mkmod ~/.sword/modules/texts/ztext/web $T/modules/texts/ztext/$n $2 $3
  printf '[%s]\nDataPath=./modules/texts/ztext/%s/\nModDrv=zText\nBlockType=BOOK\nSourceType=OSIS\nVersification=KJV\nCompressType=%s\n' $n $n $(echo $2 | tr a-z A-Z) > $T/mods.d/$n.conf
  [ -n "$3" ] && echo "CipherKey=" >> $T/mods.d/$n.conf; return 0; }
mk lzss lzss; mk bz bzip2; mk lock lzss "Abcd1-8xxac-HRR6a-X04Aw-MWNo"
for m in lzss bz; do build/bibdump $T/mods.d/$m.conf | cmp - $T/web.txt && echo "$m: identical"; done
build/bibdump $T/mods.d/lock.conf -k "Abcd1-8xxac-HRR6a-X04Aw-MWNo" | cmp - $T/web.txt && echo "locked + key: identical"
build/bibtest $T/mods.d/lock.conf -k wrong | head -1 || true
echo "== writer: bibimp output read back by Sword's own mod2imp"
mod2imp WEB > $T/orig.imp
for m in "zip book" "lzss book" "raw book" "zip chapter" "lzss verse"; do set -- $m; n=T$1$2
  build/bibimp $T/orig.imp -n $n -o $T -d $1 -b $2 -f > /dev/null
  SWORD_PATH=$T mod2imp $n 2>/dev/null | cmp - $T/orig.imp && echo "$n: identical to the original"; done
if [ $APOC = 1 ]; then
SWORD_PATH=$HOME/.sword mod2imp engwebu2024eb > $T/n.imp
build/bibimp $T/n.imp -n Tnrsva -o $T -d lzss -v NRSVA -f > /dev/null
SWORD_PATH=$T mod2imp Tnrsva 2>/dev/null | cmp - $T/n.imp && echo "NRSVA + Apocrypha: identical"
fi
K="Abcd1-8xxac-HRR6a-X04Aw-MWNo"
build/bibimp $T/orig.imp -n Tlocked -o $T -d lzss -k "$K" -f > /dev/null
sed -i "s/^CipherKey=.*/CipherKey=$K/" $T/mods.d/tlocked.conf
SWORD_PATH=$T mod2imp Tlocked 2>/dev/null | cmp - $T/orig.imp && echo "enciphered: Sword decrypts it with the key, identical"
echo "== MySword: write with bibimp, read back, check with python's sqlite3"
build/bibimp $T/orig.imp -n WEBmys -o $T -d mysword -l eng -D "World English Bible" -C "Public Domain" -f | grep verified
build/bibdump web > $T/web.txt2
build/bibdump $T/WEBmys.bbl.mybible | cmp - $T/web.txt2 && echo "mysword: raw text identical to the source module"
python3 - "$T/WEBmys.bbl.mybible" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
assert c.execute("pragma integrity_check").fetchone()[0] == "ok"
assert [r[1] for r in c.execute("pragma table_info(Bible)")] == ["Book", "Chapter", "Verse", "Scripture"]
assert c.execute("select Abbreviation, Language, Comments from Details").fetchone() == ("WEBmys", "eng", "Public Domain")
assert c.execute("select count(*) from pragma_index_list('Bible') where name='bible_key' and \"unique\"=1").fetchone()[0] == 1
print("sqlite3 sees a valid MySword schema,", c.execute("select count(*) from Bible where Verse>0").fetchone()[0], "verses")
PY
echo "== MySword: reading MySword markup, no index, bad files"
python3 - "$T" <<'PY'
import sqlite3, sys, os
T = sys.argv[1]
c = sqlite3.connect(T + "/real.bbl.mybible")
c.execute("CREATE TABLE Details (Title,Description,Abbreviation,Comments,Version,Language,Strong,OT,NT)")
c.execute("CREATE TABLE Bible (Book INT, Chapter INT, Verse INT, Scripture TEXT)")
c.execute("INSERT INTO Details VALUES ('T','D','TSB','(c)','1','eng',1,1,1)")
c.executemany("INSERT INTO Bible VALUES (?,?,?,?)", [
 (1,1,1,"In the beginning<RF>Or <FI>when<Fi> God began<Rf> God<WH430> created<WH1254> the heaven<WH8064> and the earth<WH776>.<CM>"),
 (1,1,2,"darkness &lt;was&gt; &amp; <TS>Title<Ts>upon the deep."),
 (1,1,99,"beyond KJV")]); c.commit()
c = sqlite3.connect(T + "/enc.bbl.mybible")
c.execute("CREATE TABLE Details (Title,Encryption)"); c.execute("CREATE TABLE Bible (Book INT, Chapter INT, Verse INT, Scripture TEXT)"); c.execute("INSERT INTO Details VALUES ('x',1)"); c.commit()
open(T + "/junk.bbl.mybible", "wb").write(b"not a database" * 50)
PY
[ "$(build/bibtest $T/real.bbl.mybible 'Gen 1:1' | tail -1)" = "  In the beginning God created the heaven and the earth." ] && echo "markup stripped correctly"
[ "$(build/bibtest $T/real.bbl.mybible 'Gen 1:2' | sed -n 2,3p | tr -d '\n')" = "  darkness <was> & upon the deep." ] && echo "entities decoded, title dropped"
for f in enc junk; do build/bibtest $T/$f.bbl.mybible | head -1; done
echo "== bibconv: plain text conversion, raw copy, refusals"
build/bibdump web -p > $T/web.plain
build/bibconv web -n Cplain -t lzss -m plain -o $T > /dev/null
build/bibdump $T/mods.d/cplain.conf | cmp - $T/web.plain && echo "Sword -> plain Sword: text identical"
build/bibconv web -n Cmys -t mysword -m plain -o $T > /dev/null
build/bibdump $T/Cmys.bbl.mybible | cmp - $T/web.plain && echo "Sword -> plain MySword: text identical"
if [ $APOC = 1 ]; then
build/bibconv engwebu2024eb -n Capoc -t raw -m plain -o $T > /dev/null
build/bibdump engwebu2024eb -p -a > $T/n.plain
build/bibdump $T/mods.d/capoc.conf -a | cmp - $T/n.plain && echo "NRSVA + Apocrypha -> plain Sword: text identical"
fi
build/bibconv web -n Ccopy -t lzss -r -o $T > /dev/null
build/bibdump web > $T/web.raw
build/bibdump $T/mods.d/ccopy.conf | cmp - $T/web.raw && echo "-r raw copy: verse text identical"
SWORD_PATH=$T mod2imp Ccopy 2>/dev/null | grep -c '^[$][$][$].* [0-9]*:[1-9]' | tr -d '\n'; echo " verse entries seen by Sword's mod2imp"
build/bibconv engwebu2024eb -t mysword -o $T > /dev/null && echo "NOT REFUSED (bug)" || echo "NRSVA -> MySword refused"
build/bibconv web -t mysword -r -o $T > /dev/null && echo "NOT REFUSED (bug)" || echo "OSIS -r -> MySword refused"
echo "== markup translator"
for m in web asv; do build/mkpcheck $m | tail -3; done
build/bibconv nasb -n Nmys -t mysword -o $T > /dev/null
build/bibdump nasb -p > $T/nasb.plain
build/bibdump $T/Nmys.bbl.mybible -p | cmp - $T/nasb.plain && echo "OSIS -> MySword (markup translated): plain text identical"
build/bibconv $T/Nmys.bbl.mybible -n Nback -t zip -m osis -o $T > /dev/null
build/bibdump $T/mods.d/nback.conf -p | cmp - $T/nasb.plain && echo "OSIS -> MySword -> OSIS: plain text identical"
for f in gbf thml; do build/bibconv web -n W$f -m $f -o $T > /dev/null; build/bibdump $T/mods.d/w$f.conf -p | cmp - $T/web.plain && echo "OSIS -> $f: plain text identical"; done
echo "== plain text against Sword's own renderer (diatheke -f plain)"
python3 tools/cmpplain.py WEB web | tail -1
echo "== STEP modules (QuickVerse), if present on this machine"
STEPDIR="$HOME/Desktop/Bible"
if [ -d "$STEPDIR/NASBO_u" ] && [ -d "$STEPDIR/QNIVO_u" ]; then
  build/stpdump "$STEPDIR/NASBO_u" > $T/nasb.mine
  # CrossWire's step2vpl, patched for 64-bit (4-byte fields declared as int32_t, array bug): the official algorithm
  perl -pe 's/(?<!unsigned )\blong\b/int32_t/g; s/#include <iostream>/#include <iostream>\n#include <stdint.h>/; s/new VSyncBooksInfo\[bookCount\]/new VSyncBooksInfo[bookCount+1]/' private-samples/sword-master/utilities/step2vpl.cpp > $T/step2vpl32.cpp
  if g++ -I/usr/local/include/sword $T/step2vpl32.cpp -L/usr/local/lib -lsword -o $T/step2vpl32 2>/dev/null; then
    for d in NASBO_u QNIVO_u HSB3O_u; do
      LD_LIBRARY_PATH=/usr/local/lib $T/step2vpl32 "$STEPDIR/$d" > $T/$d.vpl 2>/dev/null
      build/stpdump "$STEPDIR/$d" | cmp - $T/$d.vpl && echo "$d: section text identical to CrossWire's step2vpl"
    done
  fi
  for d in NASBO_u QNIVO_u; do build/mkpcheck "$STEPDIR/$d" | grep "^->" | head -4; done
  build/bibconv "$STEPDIR/NASBO_u" -n QVN -o $T > /dev/null
  build/bibdump "$STEPDIR/NASBO_u" -p > $T/a.plain; build/bibdump $T/mods.d/qvn.conf -p > $T/b.plain
  cmp $T/a.plain $T/b.plain && echo "STEP NASB -> Sword OSIS: plain text identical"
  SWORD_PATH=$T diatheke -b QVN -f plain -k "John 3:16" | head -1
  build/bibconv "$STEPDIR/QNIVO_u" -n QVM -t mysword -o $T > /dev/null
  build/bibdump "$STEPDIR/QNIVO_u" -p > $T/a.plain; build/bibdump $T/QVM.bbl.mybible -p > $T/b.plain
  cmp $T/a.plain $T/b.plain && echo "STEP NIV -> MySword: plain text identical"
else
  echo "(no STEP modules in $STEPDIR: skipped)"
fi
echo "== theWord modules, if present on this machine"
TWD="/media/mmay/6630101A300FEFBB/ProgramData/The Word/Bibles"
if [ -f "$TWD/kjv.ont" ]; then
  for f in kjv.ont asv.ont web.ont; do build/mkpcheck "$TWD/$f" | grep "^->" | head -4; done
  build/bibconv nasb -n NASBtw -t theword -o $T > /dev/null
  build/bibdump nasb -p > $T/a.plain; build/bibdump $T/NASBtw.ont -p > $T/b.plain
  cmp $T/a.plain $T/b.plain && echo "Sword NASB -> theWord: plain text identical"
  build/bibconv "$TWD/kjv.ont" -n TWKJV -o $T > /dev/null
  build/bibdump "$TWD/kjv.ont" -p > $T/a.plain; build/bibdump $T/mods.d/twkjv.conf -p > $T/b.plain
  cmp $T/a.plain $T/b.plain && echo "theWord KJV -> Sword OSIS: plain text identical"
  build/bibtest "$TWD/net.ontx" | head -1
else
  echo "(no theWord modules found: skipped)"
fi
echo "== verse-per-line (.vpl)"
build/bibconv nasb -n NASBv -t vpl -o $T > /dev/null
g++ -I/usr/local/include/sword private-samples/sword-master/utilities/vpl2mod.cpp -L/usr/local/lib -lsword -o $T/vpl2mod 2>/dev/null && {
  mkdir -p $T/sw/modules/texts/rawtext/vtest $T/sw/mods.d
  LD_LIBRARY_PATH=/usr/local/lib $T/vpl2mod $T/NASBv.vpl $T/sw/modules/texts/rawtext/vtest/ 1 > /dev/null 2>&1
  printf '[VTest]\nDataPath=./modules/texts/rawtext/vtest/\nModDrv=RawText\nVersification=KJV\nEncoding=UTF-8\n' > $T/sw/mods.d/vtest.conf
  SWORD_PATH=$T/sw mod2imp VTest 2>/dev/null | grep -c '^[$][$][$].* [0-9]*:[1-9]' | tr -d '\n'; echo " entries listed by Sword (31102 expected: 31100 verses with text, 2 empty) from our .vpl via vpl2mod"; }
if [ -f /media/d/esv.vpl ]; then
  build/bibconv /media/d/esv.vpl -n ESVv -o $T > /dev/null
  build/bibdump /media/d/esv.vpl -p > $T/a.plain; build/bibdump $T/mods.d/esvv.conf -p > $T/b.plain
  cmp $T/a.plain $T/b.plain && echo "ESV .vpl -> Sword: plain text identical"
fi
echo "== dictionaries"
SWORD_PATH=/usr/share/sword mod2imp StrongsGreek > $T/sg.sw 2>/dev/null
build/dictdump strongsgreek > $T/sg.mine
python3 tools/cmpdict.py $T/sg.sw $T/sg.mine "Sword zLD reader vs mod2imp (Strong's Greek)"
SWORD_PATH=/usr/share/sword mod2imp StrongsHebrew > $T/sh.sw 2>/dev/null
build/dictdump strongshebrew > $T/sh.mine
python3 tools/cmpdict.py $T/sh.sw $T/sh.mine "Sword zLD reader vs mod2imp (Strong's Hebrew)"
build/dictconv strongsgreek -n SGcopy -t sword -o $T > /dev/null
SWORD_PATH=$T mod2imp SGcopy 2>/dev/null > $T/sgc.sw
python3 tools/cmpdict.py $T/sg.sw $T/sgc.sw "zLD written by dictconv, read by Sword's mod2imp"
SWORD_PATH=$T diatheke -b SGcopy -f plain -k 26 2>/dev/null | head -1 | cut -c1-60
build/dictconv strongsgreek -n SGmys -t mysword -o $T > /dev/null
build/dictdump $T/SGmys.dct.mybible -p > $T/sgmys.plain; build/dictdump strongsgreek -p > $T/sg.plain
python3 tools/cmpdict.py $T/sg.plain $T/sgmys.plain "Sword TEI -> MySword HTML: plain text"
python3 - $T/SGmys.dct.mybible <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
assert c.execute("pragma integrity_check").fetchone()[0] == "ok"
assert c.execute("select count(*) from dictionary").fetchone()[0] == 5624
print("sqlite3 sees a valid MySword dictionary with 5624 entries")
PY
build/dictconv strongsgreek -n SGtw -t theword -o $T > /dev/null
build/dictdump $T/SGtw.dct.twm -p > $T/sgtw.plain
python3 tools/cmpdict.py $T/sg.plain $T/sgtw.plain "Sword TEI -> theWord RTF: plain text"
TW="/media/mmay/6630101A300FEFBB/ProgramData/The Word/Books/Nave's Topical Bible.dct.twm"
if [ -f "$TW" ]; then
  build/dictdump "$TW" -p > $T/nave.plain
  for t in mysword sword theword; do
    build/dictconv "$TW" -n Nave -t $t -o $T -f > /dev/null
    case $t in mysword) o=$T/Nave.dct.mybible;; sword) o=$T/mods.d/nave.conf;; theword) o=$T/Nave.dct.twm;; esac
    build/dictdump "$o" -p > $T/nave.$t
    python3 tools/cmpdict.py $T/nave.plain $T/nave.$t "theWord Nave -> $t: plain text"
  done
fi
MS=/media/d/Downloads/mcgednt.dct.mybible
if [ -f "$MS" ]; then
  build/dictdump $MS -p > $T/m.plain
  build/dictconv $MS -n Mounce -t sword -o $T -f > /dev/null; build/dictdump $T/mods.d/mounce.conf -p > $T/m.sword
  python3 tools/cmpdict.py $T/m.plain $T/m.sword "MySword Mounce -> Sword: plain text"
fi
build/dicttest "/media/mmay/6630101A300FEFBB/ProgramData/The Word/Books/Mickelson's Strong.dct.twm" 2>/dev/null | head -1

echo "== commentaries and books (Option B)"
BOOKS="/media/mmay/6630101A300FEFBB/ProgramData/The Word/Books"
TSK="$BOOKS/Treasury of Scripture Knowledge.cmt.twm"
HOLE="$BOOKS/F.B.Hole's Commentary on the NT and selected books of OT.cmt.twm"
BUNYAN="$BOOKS/Bunyan - The Pilgrim's Progress.gbk.twm"
SPURGEON="$BOOKS/Spurgeon's All of grace.gbk.twm"
[ -f "$TSK" ] && build/comrt "$TSK" $T TSKcopy
[ -f "$HOLE" ] && build/comrt "$HOLE" $T Holecopy
[ -f "$BUNYAN" ] && build/bokrt "$BUNYAN" $T Bunyancopy        # blobs, zlib "compressed" content
[ -f "$SPURGEON" ] && build/bokrt "$SPURGEON" $T Spurgeoncopy  # plain text content
MICK_CMT="$BOOKS/Mickelson's Strong.cmt.twm"
[ -f "$MICK_CMT" ] && build/comtest "$MICK_CMT" 2>&1 | head -1
echo "== OSIS / Zefania / USFX / USFM files (samples in private-samples/open-formats, if present)"
OF=private-samples/open-formats
if [ -d $OF ]; then
  [ -f $OF/eng-asv.zefania.xml ] && { build/bibdump $OF/eng-asv.zefania.xml -p > $T/o_asv.txt; python3 tools/cmpopen.py zefania $OF/eng-asv.zefania.xml $T/o_asv.txt "Zefania ASV reader vs python"; }
  [ -f $OF/eng-kjv.osis.xml ] && { build/bibdump $OF/eng-kjv.osis.xml -p > $T/o_kjv.txt; python3 tools/cmpopen.py osis $OF/eng-kjv.osis.xml $T/o_kjv.txt "OSIS KJV reader vs python" 31090; }
  [ -f $OF/eng-web.usfx.xml ] && { build/bibdump $OF/eng-web.usfx.xml -p > $T/o_web.txt; python3 tools/cmpopen.py usfx $OF/eng-web.usfx.xml $T/o_web.txt "USFX WEB reader vs python" 31085; }
  [ -f $OF/eng-bbe.usfx.xml ] && { build/bibdump $OF/eng-bbe.usfx.xml -p > $T/o_bbe.txt; python3 tools/cmpopen.py usfx $OF/eng-bbe.usfx.xml $T/o_bbe.txt "USFX BBE reader vs python" 31095; }
  # every format to every other, plain text compared
  conv() {  # <label> <source> <ref dump> <target ext-dir> <target> ...
    lab=$1; src=$2; ref=$3; shift 3
    for t in "$@"; do
      build/bibconv "$src" -n c_$t -t $t -o $T -f > /dev/null 2>&1
      case $t in osis) o=$T/c_osis.osis.xml;; zefania) o=$T/c_zefania.zefania.xml;; usfx) o=$T/c_usfx.usfx.xml;; usfm) o=$T/c_usfm_usfm;; esac
      build/bibdump "$o" -p > $T/c_out.txt 2>/dev/null
      case $t in osis|zefania|usfx) python3 -c "import sys,xml.etree.ElementTree as E; E.parse(sys.argv[1])" "$o" && echo "$lab -> $t: the file is well-formed XML" || echo "$lab -> $t: NOT WELL-FORMED XML"; esac
      python3 tools/cmpdict.py $ref $T/c_out.txt "$lab -> $t: plain text"
    done
  }
  [ -f $OF/eng-asv.zefania.xml ] && conv "Zefania ASV" $OF/eng-asv.zefania.xml $T/o_asv.txt osis usfx usfm
  [ -f $OF/eng-kjv.osis.xml ] && conv "OSIS KJV" $OF/eng-kjv.osis.xml $T/o_kjv.txt zefania usfx usfm
  [ -f $OF/eng-web.usfx.xml ] && conv "USFX WEB" $OF/eng-web.usfx.xml $T/o_web.txt osis zefania usfm
  if [ -d $OF/web_usfm ]; then
    build/bibdump $OF/web_usfm -p > $T/o_webu.txt
    conv "USFM WEB (folder)" $OF/web_usfm $T/o_webu.txt osis zefania usfx
    [ -f $OF/eng-web_usfm.zip ] && { build/bibdump $OF/eng-web_usfm.zip -p > $T/o_webz.txt; python3 tools/cmpdict.py $T/o_webu.txt $T/o_webz.txt "USFM WEB zip vs folder: plain text"; }
  fi
fi
rm -rf $T
