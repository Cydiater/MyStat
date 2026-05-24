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

# Ad-hoc sign so Gatekeeper lets a locally-built binary run.
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
echo "Run with: open $APP"
