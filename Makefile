# mkbible - Bible module tools and a text mode Bible reader (Free Pascal)
#   make              build everything into ./build (runs build.sh)
#   make install      install the programs and documents (and mkbiblegui if `make gui` built it)   (PREFIX=/usr/local, DESTDIR for packaging)
#   make uninstall    remove them again
#   make gui          build the GUI reader (needs Lazarus, BGRABitmap and BGRAControls, see gui/README.md)
#   make deb          build a Debian package, build/mkbible_<version>_<arch>.deb (includes mkbiblegui if built)
#   make check        run the regression suite (needs Sword and sample files, see tools/regress.sh)
#   make clean
PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
DOCDIR  ?= $(PREFIX)/share/doc/mkbible

# the programs people use; the rest in build/ (bibtest, dicttest, comrt, ...) are test and inspection tools
PROGRAMS = mkbible bibconv dictconv bibimp bibdump bibmk bibepub

deb: build/mkbible
	tools/mkdeb.sh

gui:
	mkdir -p build/gui-units
	lazbuild --ws=gtk2 gui/mkbiblegui.lpi

.PHONY: deb gui all install uninstall check clean

all:
	./build.sh

build/mkbible:
	./build.sh

install: build/mkbible
	install -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(DOCDIR)
	for p in $(PROGRAMS); do install -m 755 build/$$p $(DESTDIR)$(BINDIR)/$$p; done
	@if [ -x build/mkbiblegui ]; then install -m 755 build/mkbiblegui $(DESTDIR)$(BINDIR)/mkbiblegui; echo installed mkbiblegui; \
	install -d $(DESTDIR)$(PREFIX)/share/applications; install -m 644 tools/mkbiblegui.desktop $(DESTDIR)$(PREFIX)/share/applications/mkbiblegui.desktop; \
	install -d $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps; install -m 644 icons/mkbible.svg $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/mkbible.svg; \
	for n in 16 32 48 64 128 256; do install -d $(DESTDIR)$(PREFIX)/share/icons/hicolor/$${n}x$${n}/apps; install -m 644 icons/mkbible-$$n.png $(DESTDIR)$(PREFIX)/share/icons/hicolor/$${n}x$${n}/apps/mkbible.png; done; \
	else echo 'mkbiblegui not installed (not built: run make gui first, it needs Lazarus)'; fi
	install -m 644 README.md LICENSE $(DESTDIR)$(DOCDIR)/

uninstall:
	for p in $(PROGRAMS) mkbiblegui; do rm -f $(DESTDIR)$(BINDIR)/$$p; done
	rm -f $(DESTDIR)$(PREFIX)/share/applications/mkbiblegui.desktop $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/mkbible.svg
	for n in 16 32 48 64 128 256; do rm -f $(DESTDIR)$(PREFIX)/share/icons/hicolor/$${n}x$${n}/apps/mkbible.png; done
	rm -rf $(DESTDIR)$(DOCDIR)

check: build/mkbible
	tools/regress.sh

clean:
	rm -rf build
