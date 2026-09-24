# MD Buddy — common tasks. Run `make help` for a list.
PROJECT := MDBuddy.xcodeproj
DERIVED := build/DerivedData
APP     := $(DERIVED)/Build/Products/Release/MD Buddy.app
VERSION := $(shell sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)

.PHONY: help build install uninstall test project dist screenshots clean

help:            ## Show this help
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'

build:           ## Build the Release app
	xcodebuild -project $(PROJECT) -scheme MDBuddy -configuration Release -derivedDataPath $(DERIVED) build -quiet

install:         ## Build, install to /Applications and register the extension
	scripts/install.sh

uninstall:       ## Remove the app and extension
	scripts/uninstall.sh

test:            ## Run the renderer test suite
	cd Core && swift test

project:         ## Regenerate MDBuddy.xcodeproj from project.yml (needs xcodegen)
	xcodegen generate

dist: build      ## Zip the built app into dist/ for sharing
	mkdir -p dist
	ditto -c -k --keepParent "$(APP)" "dist/MD-Buddy-$(VERSION).zip"
	@echo "dist/MD-Buddy-$(VERSION).zip"

screenshots:     ## Capture README screenshots of live Quick Look previews
	scripts/screenshots.sh

clean:           ## Remove build products
	rm -rf build dist Core/.build
