#!/usr/bin/env bash
# Prepare a feed locally. Upload the release assets before publishing this feed.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 NOTARIZED_RELEASE.zip RELEASE_NOTES.md" >&2
    exit 1
fi
archive="$1"
notes="$2"
[[ -f "$archive" && -f "$notes" ]] || { echo "Release archive or notes missing." >&2; exit 1; }
tools=".build/artifacts/sparkle/Sparkle/bin"
[[ -x "$tools/generate_appcast" ]] || swift package resolve
account="${MYSTAT_SPARKLE_ACCOUNT:-com.cydiater.MyStat.sparkle}"
public_key=$("$tools/generate_keys" --account "$account" -p)

stage=$(mktemp -d "${TMPDIR:-/tmp}/mystat-appcast.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto -x -k "$archive" "$stage/unpacked"
app="$stage/unpacked/MyStat.app"
plist="$app/Contents/Info.plist"
[[ -f "$plist" ]] || { echo "Archive must contain MyStat.app." >&2; exit 1; }
codesign --verify --deep --strict "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[0-9]+$ ]] || {
    echo "Use a three-part release version and an increasing integer build number." >&2; exit 1;
}
[[ "$public_key" == "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")" ]] || {
    echo "The signing key does not match the public key embedded in this app." >&2; exit 1;
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist")" == 'https://cydiater.github.io/MyStat/appcast.xml' ]] || {
    echo "Release has an unexpected update feed URL." >&2; exit 1;
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SURequireSignedFeed' "$plist")" == true ]] || {
    echo "Release must require a signed feed." >&2; exit 1;
}
# Validate the previous feed before preserving its entries and enforce build order.
"$tools/sign_update" --account "$account" --verify docs/appcast.xml
python3 - "$build" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = {'s': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
items = ET.parse('docs/appcast.xml').findall('./channel/item')
versions = [int(item.findtext('s:version', namespaces=ns)) for item in items]
if versions and int(sys.argv[1]) <= max(versions):
    raise SystemExit('Increment CFBundleVersion before preparing a new update. Do not replace an existing release.')
PY
mkdir "$stage/updates"
cp "$archive" "$stage/updates/MyStat-v$version.zip"
cp "$notes" "$stage/updates/MyStat-v$version.md"
cp docs/appcast.xml "$stage/updates/appcast.xml"
"$tools/generate_appcast" --account "$account" --versions "$build" \
    --maximum-deltas 0 --maximum-versions 0 --embed-release-notes \
    --download-url-prefix "https://github.com/Cydiater/MyStat/releases/download/v$version/" \
    --link 'https://cydiater.github.io/MyStat/' "$stage/updates"
"$tools/sign_update" --account "$account" --verify "$stage/updates/appcast.xml"
cp "$stage/updates/appcast.xml" docs/appcast.xml
echo "Prepared docs/appcast.xml. Upload MyStat-v$version.zip to GitHub release v$version first, then publish the feed."
