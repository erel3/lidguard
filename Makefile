APP_NAME = LidGuard
BUNDLE = dist/$(APP_NAME).app
BUILD_DIR = .build/release
VERSION_FILE = VERSION
BUMP ?= patch
CODESIGN_ID ?= Developer ID Application: Andrey Kim (73R36N2A46)
CODESIGN_REQ ?= designated => anchor apple generic and certificate leaf[subject.OU] = "73R36N2A46"
NOTARIZE_PROFILE ?= Notarize

.PHONY: compile compile-appstore build build-appstore run run-appstore run-debug install release release-appstore clean version icon lint

VERSION := $(shell cat $(VERSION_FILE) 2>/dev/null || echo "1.0.0")

compile:
	swift build -c release

compile-appstore:
	swift build -c release -Xswiftc -DAPPSTORE

# Build: compile + bundle (dev)
build: compile
	@$(MAKE) _bundle SUFFIX=-dev

build-appstore: compile-appstore
	@$(MAKE) _bundle SUFFIX=-dev ENTITLEMENTS=LidGuard-AppStore.entitlements

# Dev: build and open
run: build
	open $(BUNDLE)

# Dev: build App Store edition and open
run-appstore: build-appstore
	open $(BUNDLE)

# Debug: build debug binary and run directly (no .app bundle)
run-debug:
	swift build && .build/debug/$(APP_NAME)

# Install current bundle to /Applications
install:
	@test -d $(BUNDLE) || (echo "Error: No bundle found. Run 'make run' or 'make release' first." && exit 1)
	@VERSION=$$(plutil -extract CFBundleShortVersionString raw $(BUNDLE)/Contents/Info.plist); \
	echo "Installing $(APP_NAME) v$$VERSION to /Applications"
	rm -rf /Applications/$(APP_NAME).app
	cp -r $(BUNDLE) /Applications/

# Release: bump version, build prod, commit, tag, push, create GH release
#   BUMP=minor make release                          — bump minor
#   TITLE="Big Update" make release                  — custom title
#   Requires RELEASE_NOTES.md (deleted after publish)
release:
	@test -f RELEASE_NOTES.md || (echo "Error: RELEASE_NOTES.md is required. Write release notes first." && exit 1)
	@$(MAKE) _bump
	@$(MAKE) compile
	@$(MAKE) _bundle SUFFIX=
	@$(MAKE) _notarize
	@VERSION=$$(cat $(VERSION_FILE)); \
	TITLE="$${TITLE:-v$$VERSION}"; \
	git add $(VERSION_FILE) && \
	git commit -m "chore: bump version to $$VERSION" && \
	git tag "v$$VERSION" && \
	cd dist && zip -r $(APP_NAME)-$$VERSION.zip $(APP_NAME).app && cd .. && \
	git push origin main --tags && \
	gh release create "v$$VERSION" "dist/$(APP_NAME)-$$VERSION.zip" \
		--title "$$TITLE" --notes-file RELEASE_NOTES.md && \
	rm -f RELEASE_NOTES.md && \
	echo "Released v$$VERSION"

# App Store: build and bundle for upload via Transporter
release-appstore: compile-appstore
	@$(MAKE) _bundle SUFFIX= ENTITLEMENTS=LidGuard-AppStore.entitlements
	@echo "App Store build ready at $(BUNDLE)"
	@echo "Upload via Transporter app"

# Internal: create .app bundle with optional SUFFIX (-dev or empty) and ENTITLEMENTS
ENTITLEMENTS ?= LidGuard.entitlements
_bundle:
	@VERSION=$$(cat $(VERSION_FILE))$(SUFFIX); \
	echo "Bundling $(APP_NAME) v$$VERSION"; \
	rm -rf $(BUNDLE); \
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources; \
	cp $(BUILD_DIR)/$(APP_NAME) $(BUNDLE)/Contents/MacOS/; \
	sed -e "s/<string>1.0.0</<string>$$VERSION</" \
	    -e "s/<string>1</<string>$$(echo $$VERSION | tr -d '.-dev')</" \
	    Info.plist > $(BUNDLE)/Contents/Info.plist; \
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/ 2>/dev/null || true; \
	cp -r $(BUILD_DIR)/*.bundle $(BUNDLE)/Contents/Resources/ 2>/dev/null || true; \
	TIMESTAMP_FLAG=$$(if [ -z "$(SUFFIX)" ]; then echo "--timestamp"; else echo "--timestamp=none"; fi); \
	codesign --force --sign "$(CODESIGN_ID)" --entitlements $(ENTITLEMENTS) \
		-o runtime $$TIMESTAMP_FLAG \
		-r='$(CODESIGN_REQ)' \
		$(BUNDLE); \
	echo "Built: $(BUNDLE) v$$VERSION"

_notarize:
	@echo "Notarizing $(APP_NAME)..."; \
	cd dist && zip -r $(APP_NAME)-notarize.zip $(APP_NAME).app && cd .. && \
	xcrun notarytool submit dist/$(APP_NAME)-notarize.zip \
		--keychain-profile "$(NOTARIZE_PROFILE)" --wait && \
	xcrun stapler staple $(BUNDLE) && \
	rm -f dist/$(APP_NAME)-notarize.zip && \
	echo "Notarization complete"

_bump:
	@VERSION=$$(cat $(VERSION_FILE) | sed 's/-dev//'); \
	MAJOR=$$(echo $$VERSION | cut -d. -f1); \
	MINOR=$$(echo $$VERSION | cut -d. -f2); \
	PATCH=$$(echo $$VERSION | cut -d. -f3); \
	case "$(BUMP)" in \
		major) MAJOR=$$((MAJOR + 1)); MINOR=0; PATCH=0;; \
		minor) MINOR=$$((MINOR + 1)); PATCH=0;; \
		patch) PATCH=$$((PATCH + 1));; \
	esac; \
	echo "$$MAJOR.$$MINOR.$$PATCH" > $(VERSION_FILE); \
	echo "Version bumped to $$MAJOR.$$MINOR.$$PATCH"

lint:
	@TOOLCHAIN_DIR=$$(dirname "$$(dirname "$$(xcrun --find swiftc)")"); \
	DYLD_FRAMEWORK_PATH="$$TOOLCHAIN_DIR/lib" swiftlint lint --strict Sources/

icon:
	swift Scripts/generate_icon.swift

clean:
	rm -rf .build dist

version:
	@cat $(VERSION_FILE)
