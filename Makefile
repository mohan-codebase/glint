APP := build/Glint.app
ICONS := Artwork/MenuMark.svg Artwork/GitHubMark.svg
SIGN_IDENTITY ?= -
MACOS := $(shell uname -m)-apple-macos13.0
SWIFTC := xcrun swiftc -target $(MACOS) -module-cache-path build/ModuleCache

.PHONY: all test
all: $(APP)/Contents/_CodeSignature/CodeResources

$(APP)/Contents/_CodeSignature/CodeResources: $(wildcard Sources/*.swift) Info.plist Makefile build/Glint.icns $(ICONS)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	$(SWIFTC) -O Sources/*.swift -o $(APP)/Contents/MacOS/Glint
	cp Info.plist $(APP)/Contents/Info.plist
	cp build/Glint.icns $(ICONS) $(APP)/Contents/Resources/
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" $(APP)

build/Glint.icns: Artwork/Glint.svg Artwork/render-icon.swift
	mkdir -p build/Glint.iconset
	xcrun swift -module-cache-path build/ModuleCache Artwork/render-icon.swift $< build/Glint.png
	set -e; for size in 16 32 128 256 512; do \
	    sips -z $$size $$size build/Glint.png --out build/Glint.iconset/icon_$${size}x$${size}.png >/dev/null; \
	    double=$$((size * 2)); sips -z $$double $$double build/Glint.png --out build/Glint.iconset/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	iconutil -c icns build/Glint.iconset -o $@

test: build/layout-tests
	./build/layout-tests

build/layout-tests: Sources/Layout.swift Tests/main.swift Makefile
	mkdir -p build
	$(SWIFTC) Sources/Layout.swift Tests/main.swift -o $@
