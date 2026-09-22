#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# AppKit selects its native control design using the linked SDK version. Some
# Swift toolchains stamp the deployment target into both fields, which keeps
# current macOS releases in the old control appearance. Preserve the minimum
# OS while explicitly recording the SDK this build actually uses.
sdk_version=$(xcrun --sdk macosx --show-sdk-version)
minimum_os=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Sources/MyStat/Info.plist)
build_options=(-c release --arch arm64 --arch x86_64
    -Xlinker -platform_version -Xlinker macos -Xlinker "$minimum_os" -Xlinker "$sdk_version")
swift build "${build_options[@]}"

APP="MyStat.app"
BIN="$(swift build "${build_options[@]}" --show-bin-path)/MyStat"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Frameworks"

cp "$BIN" "$APP/Contents/MacOS/MyStat"
cp "Sources/MyStat/Info.plist" "$APP/Contents/Info.plist"
cp "Assets/AppIcon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
./scripts/build-app-intents.sh "$APP/Contents/Resources"

# SwiftPM links the binary framework but does not assemble our .app bundle.
# ditto preserves the versioned framework's symlinks and helper permissions.
SPARKLE_FRAMEWORK=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

# App Intents rejects ad-hoc processes because they have no signing team ID.
# Prefer an installed development identity for the Xcode project's team for
# local builds. An explicit identity still takes precedence for release builds.
signing_identity="${MYSTAT_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    development_team=$(awk '/^[[:space:]]*DEVELOPMENT_TEAM:/ {print $2; exit}' MyStat-macOS/project.yml)
    while IFS='"' read -r _ candidate _; do
        [[ "$candidate" == "Apple Development: "* ]] || continue
        subject=$(security find-certificate -c "$candidate" -p | openssl x509 -noout -subject -nameopt RFC2253)
        if [[ ",$subject," == *",OU=$development_team,"* ]]; then
            signing_identity="$candidate"
            break
        fi
    done < <(security find-identity -v -p codesigning)
fi
if [[ -n "$signing_identity" && "$signing_identity" != "-" ]]; then
    echo "Signing with $signing_identity"
    signing_args=(--options runtime --timestamp --sign "$signing_identity")
else
    signing_args=(--sign -)
    echo "Warning: ad-hoc signing supports the menu-bar app, but Spotlight/Shortcuts cannot run its actions." >&2
    echo "Set MYSTAT_SIGNING_IDENTITY to an Apple Development or Developer ID Application identity to enable App Intents." >&2
fi

# Sign nested code inside-out; do not use --deep as a signing shortcut.
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
for component in "$FRAMEWORK/Versions/B/Autoupdate" \
    "$FRAMEWORK/Versions/B/Updater.app" \
    "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" \
    "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc" \
    "$FRAMEWORK" "$APP"; do
    codesign --force "${signing_args[@]}" "$component"
done
codesign --verify --deep --strict "$APP"

echo "Built $APP"
echo "Run with: open $APP"
