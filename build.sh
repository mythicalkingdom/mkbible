#!/bin/sh
# Build the MK Bible units and the test programs into ./build
#   ./build.sh          build
#   ./build.sh --regen             also regenerate src/MKBibVrs.pas (needs private-samples/open-formats)
#   ./build.sh --sword-apocrypha   write a local src/MKBibVrA.pas with Sword's Apocrypha tables (do not commit it)
set -e
cd "$(dirname "$0")"
mkdir -p build
if [ "$1" = "--regen" ]; then
  # MKBibVrs.pas: counted in a public domain Bible (the ASV, Zefania XML, from the open-bibles collection)
  python3 tools/genvrs.py private-samples/open-formats/eng-asv.zefania.xml src/MKBibVrs.pas
fi
if [ "$1" = "--sword-apocrypha" ]; then
  # LOCAL USE ONLY: MKBibVrA.pas with Sword's Apocrypha tables (GPL version 2 only); do not commit the result
  python3 tools/genvra.py private-samples/sword-master/include src/MKBibVrA.pas
fi
for u in MKBibVrA MKBibVrs MKBibZ MKBibCph MKBibMkp MKBibMod MKBibAbs MKBibTxt MKBibSwd MKBibMys MKBibStp MKBibTwd MKBibVpl MKBibSql MKBibDic MKBibCom MKBibBok MKBibSwc MKDicSwd MKDicMys MKDicTwd MKDicAny MKComTwd MKBokTwd MKBibMem MKBibZef MKBibOsi MKBibUfx MKBibZip MKBibUsf MKBibUsx MKBibBeb MKBibUnb MKBibAny dictdump dicttest dictconv comtest boktest comrt bokrt bibtest bibdump bibimp bibconv bibmk mkpcheck stpdump \
         uCP437 uScreen uKeys uText uPick mkbiblecfg mkbible; do
  fpc -B -Fusrc -Fisrc -FUbuild -FEbuild -vew src/$u.pas
done
