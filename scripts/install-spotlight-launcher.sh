#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! shortcuts list | awk '$0 == "Keep Awake" {found=1} END {exit !found}'; then
    echo 'Import Shortcuts/Keep Awake.shortcut into Shortcuts before installing the launcher.' >&2
    exit 1
fi

destination="$HOME/Applications/Keep Awake.app"
identifier="com.cydiater.MyStat.KeepAwakeLauncher"
if [[ -e "$destination" ]]; then
    installed_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist" 2>/dev/null || true)
    if [[ "$installed_identifier" != "$identifier" ]]; then
        echo "Another app already exists at $destination; leaving it untouched." >&2
        exit 1
    fi
fi

stage=".build/keep-awake-launcher/Keep Awake.app"
mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Resources"
xcrun swiftc -O -target "$(uname -m)-apple-macosx13.0" Shortcuts/KeepAwakeLauncher.swift \
    -o "$stage/Contents/MacOS/KeepAwakeLauncher"
cp Assets/AppIcon/AppIcon.icns "$stage/Contents/Resources/AppIcon.icns"
cat > "$stage/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>KeepAwakeLauncher</string>
    <key>CFBundleIdentifier</key><string>com.cydiater.MyStat.KeepAwakeLauncher</string>
    <key>CFBundleName</key><string>Keep Awake</string>
    <key>CFBundleDisplayName</key><string>Keep Awake</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict></plist>
PLIST
# The launcher itself runs the system shortcuts command, not App Intents.
codesign --force --sign - "$stage"
codesign --verify --strict "$stage"
mkdir -p "$HOME/Applications"
ditto "$stage" "$destination"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$destination"
mdimport "$destination"
echo "Installed $destination"
echo 'Search for Keep Awake in Spotlight to toggle MyStat.'
