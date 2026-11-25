# mkbible - Bible module tools and a text mode Bible reader (Free Pascal)
#   make              build everything into ./build (runs build.sh)
#   make install      install the programs and documents   (PREFIX=/usr/local, DESTDIR for packaging)
#   make uninstall    remove them again
#   make gui          build the GUI reader (needs Lazarus, BGRABitmap and BGRAControls, see gui/README.md)
#   make check        run the regression suite (needs Sword and sample files, see tools/regress.sh)
#   make clean
PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
DOCDIR  ?= $(PREFIX)/share/doc/mkbible

# the programs people use; the rest in build/ (bibtest, dicttest, comrt, ...) are test and inspection tools
PROGRAMS = mkbible bibconv dictconv bibimp bibdump bibmk

gui:
	mkdir -p build/gui-units
	lazbuild --ws=gtk2 gui/mkbiblegui.lpi

.PHONY: gui all install uninstall check clean

all:
	./build.sh

build/mkbible:
	./build.sh

install: build/mkbible
	install -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(DOCDIR)
	for p in $(PROGRAMS); do install -m 755 build/$$p $(DESTDIR)$(BINDIR)/$$p; done
	install -m 644 README.md LICENSE $(DESTDIR)$(DOCDIR)/

uninstall:
	for p in $(PROGRAMS); do rm -f $(DESTDIR)$(BINDIR)/$$p; done
	rm -rf $(DESTDIR)$(DOCDIR)

check: build/mkbible
	tools/regress.sh

clean:
	rm -rf build
