#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

: "${MYSTAT_SIGNING_IDENTITY:?Set MYSTAT_SIGNING_IDENTITY to your Developer ID Application identity}"
: "${MYSTAT_NOTARY_PROFILE:?Set MYSTAT_NOTARY_PROFILE to your existing notarytool keychain profile}"
if [[ "$MYSTAT_SIGNING_IDENTITY" != "Developer ID Application: "* ]]; then
    echo "A Developer ID Application identity is required for the free Mac download." >&2
    exit 1
fi
if ! security find-identity -v -p codesigning | grep -Fq "\"$MYSTAT_SIGNING_IDENTITY\""; then
    echo "The requested Developer ID signing identity is not installed." >&2
    exit 1
fi

# Fail before building/notarizing if this machine lacks the matching update key.
swift package resolve
sparkle_tools=".build/artifacts/sparkle/Sparkle/bin"
sparkle_account="${MYSTAT_SPARKLE_ACCOUNT:-com.cydiater.MyStat.sparkle}"
public_key=$("$sparkle_tools/generate_keys" --account "$sparkle_account" -p)
[[ "$public_key" == "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Sources/MyStat/Info.plist)" ]] || {
    echo "This machine needs the MyStat Sparkle signing key. See AppStore/mac-updates.md." >&2
    exit 1
}

./build.sh
codesign --verify --deep --strict MyStat.app
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' MyStat.app/Contents/Info.plist)
output_dir=".build/distribution"
mkdir -p "$output_dir"
upload_zip="$output_dir/MyStat-notarization.zip"
release_zip="$output_dir/MyStat-v$version.zip"
rm -f "$upload_zip"
ditto -c -k --keepParent MyStat.app "$upload_zip"
xcrun notarytool submit "$upload_zip" --keychain-profile "$MYSTAT_NOTARY_PROFILE" --wait
xcrun stapler staple MyStat.app
xcrun stapler validate MyStat.app
spctl --assess --type execute --verbose=2 MyStat.app
rm -f "$release_zip"
ditto -c -k --keepParent MyStat.app "$release_zip"
shasum -a 256 "$release_zip" > "$release_zip.sha256"
./scripts/generate-appcast.sh "$release_zip" "AppStore/releases/$version.md"
echo "Verified release: $release_zip"
