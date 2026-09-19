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

# SwiftPM links the binary framework but does not assemble our .app bundle.
# ditto preserves the versioned framework's symlinks and helper permissions.
SPARKLE_FRAMEWORK=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

# Local builds use an ad-hoc signature. Public downloads require Developer ID
# signing and notarization; scripts/release-macos.sh performs the full flow.
if [[ -n "${MYSTAT_SIGNING_IDENTITY:-}" ]]; then
    signing_args=(--options runtime --timestamp --sign "$MYSTAT_SIGNING_IDENTITY")
else
    signing_args=(--sign -)
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
