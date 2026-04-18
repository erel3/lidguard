app_name := "LidGuard"
bundle := "dist/" + app_name + ".app"
xcodebuild_dir := ".xcodebuild"
build_dir := xcodebuild_dir + "/Build/Products/Release"
version_file := "VERSION"
bump := env("BUMP", "patch")
codesign_id := env("CODESIGN_ID", "Developer ID Application: Andrey Kim (73R36N2A46)")
codesign_req := env("CODESIGN_REQ", 'designated => anchor apple generic and certificate leaf[subject.OU] = "73R36N2A46"')
notarize_profile := env("NOTARIZE_PROFILE", "Notarize")

export CODESIGN_REQ := codesign_req

version := `cat VERSION 2>/dev/null || echo "1.0.0"`

# Compile release build only (no .app bundle)
compile:
    xcodebuild -scheme {{app_name}} -configuration Release -destination 'platform=macOS' \
        -derivedDataPath {{xcodebuild_dir}} build 2>&1 | tail -1

# Compile + bundle with -dev suffix (codesigned .app)
build: compile
    just _bundle "-dev"

# Build + open (main dev workflow)
run: build
    open {{bundle}}

# Build debug binary and run directly (fast, no bundle)
run-debug:
    swift build && .build/debug/{{app_name}}

# Copy current dist/.app to /Applications
install:
    #!/usr/bin/env bash
    set -euo pipefail
    test -d {{bundle}} || { echo "Error: No bundle found. Run 'just run' or 'just release' first."; exit 1; }
    VERSION=$(plutil -extract CFBundleShortVersionString raw {{bundle}}/Contents/Info.plist)
    echo "Installing {{app_name}} v$VERSION to /Applications"
    rm -rf /Applications/{{app_name}}.app
    cp -r {{bundle}} /Applications/

# Release: bump version, build prod, notarize, commit, tag, push, create GH release
release:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f RELEASE_NOTES.md || { echo "Error: RELEASE_NOTES.md is required. Write release notes first."; exit 1; }
    just _bump
    just compile
    just _bundle ""
    just _notarize
    VERSION=$(cat {{version_file}})
    TITLE="${TITLE:-v$VERSION}"
    git add {{version_file}}
    git commit -m "chore: bump version to $VERSION"
    git tag "v$VERSION"
    cd dist && zip -r {{app_name}}-$VERSION.zip {{app_name}}.app && cd ..
    git push origin main --tags
    gh release create "v$VERSION" "dist/{{app_name}}-$VERSION.zip" \
        --title "$TITLE" --notes-file RELEASE_NOTES.md
    rm -f RELEASE_NOTES.md
    echo "Released v$VERSION"

# Run swiftlint --strict on Sources/
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    TOOLCHAIN_DIR=$(dirname "$(dirname "$(xcrun --find swiftc)")")
    DYLD_FRAMEWORK_PATH="$TOOLCHAIN_DIR/lib" swiftlint lint --strict Sources/

# Generate app icon
icon:
    swift Scripts/generate_icon.swift

# Remove .build, .xcodebuild and dist
clean:
    rm -rf .build .xcodebuild dist

# Print current version
version:
    @cat {{version_file}}

# Internal: create .app bundle
# codesign_req is read from $CODESIGN_REQ env var (exported at top of justfile)
[private]
_bundle suffix="-dev" entitlements="LidGuard.entitlements" sign_id=codesign_id provision_profile="":
    #!/usr/bin/env bash
    set -euo pipefail
    VERSION=$(cat {{version_file}}){{suffix}}
    echo "Bundling {{app_name}} v$VERSION"
    rm -rf {{bundle}}
    mkdir -p {{bundle}}/Contents/MacOS {{bundle}}/Contents/Resources
    cp {{build_dir}}/{{app_name}} {{bundle}}/Contents/MacOS/
    BUILD_NUM=$(date +%y%m%d%H%M)
    sed -e "s/<string>1.0.0</<string>$VERSION</" \
        -e "s/<string>1</<string>$BUILD_NUM</" \
        Info.plist > {{bundle}}/Contents/Info.plist
    cp Resources/AppIcon.icns {{bundle}}/Contents/Resources/ 2>/dev/null || true
    cp PrivacyInfo.xcprivacy {{bundle}}/Contents/Resources/ 2>/dev/null || true
    if [ -n "{{provision_profile}}" ]; then
        cp "{{provision_profile}}" {{bundle}}/Contents/embedded.provisionprofile
    fi
    for b in $(find -L {{build_dir}} -maxdepth 1 -name '*.bundle' -type d); do
        cp -R "$b" {{bundle}}/Contents/Resources/
    done
    if [ "{{suffix}}" = "" ]; then
        TIMESTAMP_FLAG="--timestamp"
    else
        TIMESTAMP_FLAG="--timestamp=none"
    fi
    for b in $(find {{bundle}}/Contents/Resources -name '*.bundle' -type d); do
        codesign --force --sign "{{sign_id}}" -o runtime $TIMESTAMP_FLAG "$b"
    done
    if [ -n "$CODESIGN_REQ" ]; then
        codesign --force --sign "{{sign_id}}" --entitlements {{entitlements}} \
            -o runtime $TIMESTAMP_FLAG \
            -r="$CODESIGN_REQ" \
            {{bundle}}
    else
        codesign --force --sign "{{sign_id}}" --entitlements {{entitlements}} \
            -o runtime $TIMESTAMP_FLAG \
            {{bundle}}
    fi
    echo "Built: {{bundle}} v$VERSION"

[private]
_notarize:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Notarizing {{app_name}}..."
    cd dist && zip -r {{app_name}}-notarize.zip {{app_name}}.app && cd ..
    xcrun notarytool submit dist/{{app_name}}-notarize.zip \
        --keychain-profile "{{notarize_profile}}" --wait
    xcrun stapler staple {{bundle}}
    rm -f dist/{{app_name}}-notarize.zip
    echo "Notarization complete"

[private]
_bump:
    #!/usr/bin/env bash
    set -euo pipefail
    VERSION=$(cat {{version_file}} | sed 's/-dev//')
    MAJOR=$(echo $VERSION | cut -d. -f1)
    MINOR=$(echo $VERSION | cut -d. -f2)
    PATCH=$(echo $VERSION | cut -d. -f3)
    case "{{bump}}" in
        major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0;;
        minor) MINOR=$((MINOR + 1)); PATCH=0;;
        patch) PATCH=$((PATCH + 1));;
    esac
    echo "$MAJOR.$MINOR.$PATCH" > {{version_file}}
    echo "Version bumped to $MAJOR.$MINOR.$PATCH"
