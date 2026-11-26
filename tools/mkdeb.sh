#!/bin/sh
# Build a Debian package from the build/ directory:  tools/mkdeb.sh  (or make deb)
#   build/mkbible_<version>_<arch>.deb  with the programs, the documents and, if build/mkbibleg exists
#   (make gui), the GUI reader with its menu entry.  Run ./build.sh (and make gui) first.
set -e
cd "$(dirname "$0")/.."
[ -x build/mkbible ] || { echo "build first: ./build.sh"; exit 1; }
VERSION=$(sed -n "s/^ *VERSION = '\(.*\)';/\1/p" src/mkbible.pas | head -1)
ARCH=$(dpkg --print-architecture)
STAGE=build/deb-stage
OUT=build/mkbible_${VERSION}_${ARCH}.deb
rm -rf "$STAGE"
make install DESTDIR="$STAGE" PREFIX=/usr > /dev/null
# no debug symbols (the GUI binary is 60 MB with them)
for f in "$STAGE"/usr/bin/*; do strip --strip-unneeded "$f"; done
# Debian wants a copyright file next to the documents
cat > "$STAGE/usr/share/doc/mkbible/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: mkbible
Source: https://github.com/mythicalkingdom/mkbible

Files: *
Copyright: 2026 The mkbible authors
License: GPL-3
 This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
 Public License version 3 as published by the Free Software Foundation.
 .
 On Debian systems the full text of the GNU General Public License version 3 is in
 /usr/share/common-licenses/GPL-3.
EOF
rm -f "$STAGE/usr/share/doc/mkbible/LICENSE"
MAINT="${DEBFULLNAME:-mkbible} <${DEBEMAIL:-noreply@users.noreply.github.com}>"
cat > "$STAGE/usr/share/doc/mkbible/changelog" <<EOF
mkbible ($VERSION) unstable; urgency=low

  * Release $VERSION. History: github.com/mythicalkingdom/mkbible

 -- $MAINT  $(date -R)
EOF
gzip -9n "$STAGE/usr/share/doc/mkbible/changelog"
DEPS="libc6"
DESC="Bible module tools and a text mode Bible reader"
if [ -x "$STAGE/usr/bin/mkbibleg" ]; then
  DEPS="$DEPS, libgtk2.0-0t64 | libgtk2.0-0, libssl3t64 | libssl3 | libssl1.1"
  DESC="$DESC, with a GUI reader"
fi
SIZE=$(du -sk "$STAGE" | cut -f1)
mkdir -p "$STAGE/DEBIAN"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: mkbible
Version: $VERSION
Section: text
Priority: optional
Architecture: $ARCH
Depends: $DEPS
Recommends: libsqlite3-0
Installed-Size: $SIZE
Maintainer: $MAINT
Homepage: https://github.com/mythicalkingdom/mkbible
Description: $DESC
 Free Pascal objects and programs for Bible modules: Sword, MySword, theWord,
 STEP, OSIS, Zefania, USFX, USFM, USX, Beblia, Unbound and verse-per-line files.
 Includes converters between the formats (bibconv, dictconv), inspection tools,
 mkbible, a text mode reader, and, when built with Lazarus, mkbibleg.
EOF
find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE/usr/share" -type f -exec chmod 644 {} +
fakeroot dpkg-deb --build --root-owner-group "$STAGE" "$OUT" > /dev/null
rm -rf "$STAGE"
echo "$OUT"
dpkg-deb --info "$OUT" | sed -n '1,/Description/p' | grep -E "Package|Version|Architecture|Depends|Installed|Size"
