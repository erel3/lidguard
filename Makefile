APP_NAME = LidGuard
BUNDLE = dist/$(APP_NAME).app
XCODEBUILD_DIR = .xcodebuild
BUILD_DIR = $(XCODEBUILD_DIR)/Build/Products/Release
VERSION_FILE = VERSION
BUMP ?= patch
CODESIGN_ID ?= Developer ID Application: Andrey Kim (73R36N2A46)
CODESIGN_ID_APPSTORE ?= Apple Distribution: Andrey Kim (73R36N2A46)
INSTALLER_ID_APPSTORE ?= 3rd Party Mac Developer Installer: Andrey Kim (73R36N2A46)
CODESIGN_REQ ?= designated => anchor apple generic and certificate leaf[subject.OU] = "73R36N2A46"
NOTARIZE_PROFILE ?= Notarize

.PHONY: compile compile-appstore build build-appstore run run-appstore run-debug install release release-appstore clean version icon lint

VERSION := $(shell cat $(VERSION_FILE) 2>/dev/null || echo "1.0.0")

compile:
	xcodebuild -scheme $(APP_NAME) -configuration Release -destination 'platform=macOS' \
		-derivedDataPath $(XCODEBUILD_DIR) build 2>&1 | tail -1

compile-appstore:
	xcodebuild -scheme $(APP_NAME) -configuration Release -destination 'platform=macOS' \
		-derivedDataPath $(XCODEBUILD_DIR) build \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='APPSTORE' 2>&1 | tail -1

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

# App Store: build, bundle, sign, and package for Transporter upload
release-appstore: compile-appstore
	@$(MAKE) _bundle SUFFIX= ENTITLEMENTS=LidGuard-AppStore.entitlements CODESIGN_ID="$(CODESIGN_ID_APPSTORE)" CODESIGN_REQ=
	@VERSION=$$(cat $(VERSION_FILE)); \
	productbuild --component $(BUNDLE) /Applications \
		--sign "$(INSTALLER_ID_APPSTORE)" \
		dist/$(APP_NAME)-$$VERSION-AppStore.pkg && \
	echo "App Store pkg ready: dist/$(APP_NAME)-$$VERSION-AppStore.pkg" && \
	xcrun altool --upload-package dist/$(APP_NAME)-$$VERSION-AppStore.pkg \
		--type osx \
		--apple-id "6760257102" \
		--bundle-id "com.akim.lidguard" \
		--bundle-short-version-string "$$VERSION" \
		--bundle-version "$$(echo $$VERSION | sed 's/[-dev.]//g')" \
		--apiKey 37ZNB2LF54 \
		--apiIssuer 6492048a-9214-4cfd-9d50-2b1469375376 && \
	echo "Uploaded to App Store Connect"

# Internal: create .app bundle with optional SUFFIX (-dev or empty) and ENTITLEMENTS
ENTITLEMENTS ?= LidGuard.entitlements
_bundle:
	@VERSION=$$(cat $(VERSION_FILE))$(SUFFIX); \
	echo "Bundling $(APP_NAME) v$$VERSION"; \
	rm -rf $(BUNDLE); \
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources; \
	cp $(BUILD_DIR)/$(APP_NAME) $(BUNDLE)/Contents/MacOS/; \
	sed -e "s/<string>1.0.0</<string>$$VERSION</" \
	    -e "s/<string>1</<string>$$(echo $$VERSION | sed 's/[-dev.]//g')</" \
	    Info.plist > $(BUNDLE)/Contents/Info.plist; \
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/ 2>/dev/null || true; \
	cp PrivacyInfo.xcprivacy $(BUNDLE)/Contents/Resources/ 2>/dev/null || true; \
	for b in $$(find -L $(BUILD_DIR) -maxdepth 1 -name '*.bundle' -type d); do cp -R "$$b" $(BUNDLE)/Contents/Resources/; done; \
	TIMESTAMP_FLAG=$$(if [ -z "$(SUFFIX)" ]; then echo "--timestamp"; else echo "--timestamp=none"; fi); \
	for b in $$(find $(BUNDLE)/Contents/Resources -name '*.bundle' -type d); do \
		codesign --force --sign "$(CODESIGN_ID)" -o runtime $$TIMESTAMP_FLAG "$$b"; \
	done; \
	if [ -n '$(CODESIGN_REQ)' ]; then \
		codesign --force --sign "$(CODESIGN_ID)" --entitlements $(ENTITLEMENTS) \
			-o runtime $$TIMESTAMP_FLAG \
			-r='$(CODESIGN_REQ)' \
			$(BUNDLE); \
	else \
		codesign --force --sign "$(CODESIGN_ID)" --entitlements $(ENTITLEMENTS) \
			-o runtime $$TIMESTAMP_FLAG \
			$(BUNDLE); \
	fi; \
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
	rm -rf .build .xcodebuild dist

version:
	@cat $(VERSION_FILE)
