.PHONY: all install uninstall build test potfiles
PREFIX ?= /usr

msys_sys ?= mingw64
# Remove the devel headerbar style:
# make release=1
release ?=

all: build

build:
	meson setup builddir --prefix=$(PREFIX)
	meson configure builddir -Ddevel=$(if $(release),false,true)
	meson compile -C builddir

install:
	meson install -C builddir

uninstall:
	sudo ninja uninstall -C builddir

test:
	ninja test -C builddir

potfiles:
	find ./ -not -path '*/.*' -type f -name "*.in" | sort > po/POTFILES
	echo "./data/dev.geopjr.Tuba.gschema.xml" >> po/POTFILES
	echo "" >> po/POTFILES
	find ./ -not -path '*/.*' -type f -name "*.ui" -exec grep -l "translatable=\"yes\"" {} \; | sort >> po/POTFILES
	echo "" >> po/POTFILES
	find ./ -not -path '*/.*' -type f -name "*.vala" -exec grep -l "_(\"\|ngettext" {} \; | sort >> po/POTFILES

xgettext:
	xgettext --files-from=po/POTFILES --output=po/dev.geopjr.Tuba.pot --from-code=UTF-8 --add-comments --keyword=_ --keyword=C_:1c,2

windows: PREFIX = $(PWD)/tuba_windows_portable
windows: __windows_pre build install __windows_set_icon __windows_copy_deps __windows_schemas __windows_copy_icons __windows_cleanup __windows_package

__windows_pre:
	rm -rf $(PREFIX)
	mkdir -p $(PREFIX)/lib/

__windows_set_icon:
ifeq (,$(wildcard ./rcedit-x64.exe))
	wget https://github.com/electron/rcedit/releases/download/v1.1.1/rcedit-x64.exe
endif
	rsvg-convert ./data/icons/color$(if $(release),,-nightly).svg -o ./builddir/color$(if $(release),,-nightly).png -h 256 -w 256
	magick -density "256x256" -background transparent ./builddir/color$(if $(release),,-nightly).png -define icon:auto-resize -colors 256 ./builddir/dev.geopjr.Tuba.ico
	./rcedit-x64.exe $(PREFIX)/bin/dev.geopjr.Tuba.exe --set-icon ./builddir/dev.geopjr.Tuba.ico

__windows_copy_deps:
	ldd $(PREFIX)/bin/dev.geopjr.Tuba.exe | grep '\/$(msys_sys).*\.dll' -o | xargs -I{} cp "{}" $(PREFIX)/bin
	cp -f /$(msys_sys)/bin/gdbus.exe $(PREFIX)/bin && ldd $(PREFIX)/bin/gdbus.exe | grep '\/$(msys_sys).*\.dll' -o | xargs -I{} cp "{}" $(PREFIX)/bin
	cp -f /$(msys_sys)/bin/gspawn-win64-helper.exe $(PREFIX)/bin && ldd $(PREFIX)/bin/gspawn-win64-helper.exe | grep '\/$(msys_sys).*\.dll' -o | xargs -I{} cp "{}" $(PREFIX)/bin
	cp -f /$(msys_sys)/bin/libwebp-7.dll /$(msys_sys)/bin/librsvg-2-2.dll /$(msys_sys)/bin/libgnutls-30.dll /$(msys_sys)/bin/libgthread-2.0-0.dll /$(msys_sys)/bin/libgmp-10.dll /$(msys_sys)/bin/libproxy-1.dll ${PREFIX}/bin
	cp -r /$(msys_sys)/lib/gio/ $(PREFIX)/lib
	cp -r /$(msys_sys)/lib/gdk-pixbuf-2.0 $(PREFIX)/lib/gdk-pixbuf-2.0
	cp -r /$(msys_sys)/lib/gstreamer-1.0 $(PREFIX)/lib/gstreamer-1.0

	ldd $(PREFIX)/lib/gio/*/*.dll | grep '\/$(msys_sys).*\.dll' -o | xargs -I{} cp "{}" $(PREFIX)/bin
	ldd $(PREFIX)/lib/gstreamer-1.0/*.dll | grep '\/$(msys_sys).*\.dll' -o | xargs -I{} cp "{}" $(PREFIX)/bin
	ldd $(PREFIX)/bin/*.dll | grep '\/$(msys_sys).*\.dll' -o | xargs -I{} cp "{}" $(PREFIX)/bin

__windows_schemas:
	cp -r /$(msys_sys)/share/glib-2.0/schemas/*.xml ${PREFIX}/share/glib-2.0/schemas/
	glib-compile-schemas.exe ${PREFIX}/share/glib-2.0/schemas/

__windows_copy_icons:
	cp -r /$(msys_sys)/share/icons/ $(PREFIX)/share/

__windows_cleanup:
	rm -f ${PREFIX}/share/glib-2.0/schemas/*.xml
	rm -rf ${PREFIX}/share/icons/hicolor/scalable/actions/
	find $(PREFIX)/share/icons/ -name *.*.*.svg -not -name *geopjr* -delete
	find $(PREFIX)/lib/gdk-pixbuf-2.0/2.10.0/loaders -name *.a -not -name *geopjr* -delete
	find $(PREFIX)/share/icons/ -name mimetypes -type d  -exec rm -r {} + -depth
	find $(PREFIX)/share/icons/hicolor/ -path */apps/*.png -not -name *geopjr* -delete
	find $(PREFIX) -type d -empty -delete
	gtk-update-icon-cache $(PREFIX)/share/icons/Adwaita/
	gtk-update-icon-cache $(PREFIX)/share/icons/hicolor/

__windows_package:
	zip -r9q tuba_windows_portable.zip tuba_windows_portable/

windows_nsis:
	rm -rf nsis
	mkdir nsis
	cp ./build-aux/dev.geopjr.Tuba-side.bmp nsis/
	cp ./builddir/dev.geopjr.Tuba.ico nsis/
	cp ./builddir/dev.geopjr.Tuba.nsi nsis/
	mv tuba_windows_portable/ nsis/
	magick ./builddir/color$(if $(release),,-nightly).png -modulate 100,100,70 nsis/dev.geopjr.Tuba-uninstall.png
	magick -density "256x256" -background transparent nsis/dev.geopjr.Tuba-uninstall.png -define icon:auto-resize -colors 256 nsis/dev.geopjr.Tuba-uninstall.ico
	rsvg-convert ./data/icons/color$(if $(release),,-nightly).svg -o nsis/dev.geopjr.Tuba-header.png -h 57 -w 57
	magick nsis/dev.geopjr.Tuba-header.png -background white -alpha remove -alpha off -type truecolor -define bmp:format=bmp3 nsis/dev.geopjr.Tuba-header.bmp
	cd nsis && makensis dev.geopjr.Tuba.nsi
