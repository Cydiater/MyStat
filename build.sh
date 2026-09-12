#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

swift build -c release --arch arm64 --arch x86_64

APP="MyStat.app"
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MyStat"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/MyStat"
cp "Sources/MyStat/Info.plist" "$APP/Contents/Info.plist"
cp "Assets/AppIcon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Local builds use an ad-hoc signature. Public downloads require Developer ID
# signing and notarization; scripts/release-macos.sh performs the full flow.
if [[ -n "${MYSTAT_SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$MYSTAT_SIGNING_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP" >/dev/null
fi

echo "Built $APP"
echo "Run with: open $APP"
