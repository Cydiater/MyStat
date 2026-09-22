#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

output=${1:?Usage: build-app-intents.sh <resources-directory>}
stage=".build/app-intents"
mkdir -p "$stage" "$output"
sdk_path=$(xcrun --sdk macosx --show-sdk-path)
minimum_os=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Sources/MyStat/Info.plist)
target="$(uname -m)-apple-macosx$minimum_os"
sources=(Sources/MyStat/KeepAwakeController.swift Sources/MyStat/KeepAwakeIntents.swift)

# SwiftPM builds an executable, so it doesn't package App Intents metadata.
# Extract these architecture-independent declarations separately, without
# depending on SwiftPM's private intermediate-file layout or build engine.
printf '%s\n' '["AppIntent", "AppShortcutsProvider"]' > "$stage/protocols.json"
xcrun swiftc -c -whole-module-optimization -parse-as-library -module-name MyStat \
    -target "$target" -sdk "$sdk_path" \
    -const-gather-protocols-list "$stage/protocols.json" \
    -emit-const-values-path "$stage/MyStat.swiftconstvalues" \
    "${sources[@]}" -o "$stage/MyStat.o"
printf '%s\n' "${sources[@]}" > "$stage/sources.list"
printf '%s\n' "$stage/MyStat.swiftconstvalues" > "$stage/const-values.list"
xcrun appintentsmetadataprocessor \
    --output "$output" \
    --toolchain-dir "$(dirname "$(dirname "$(xcrun --find swiftc)")")" \
    --module-name MyStat --sdk-root "$sdk_path" \
    --xcode-version "$(xcodebuild -version | awk '/Build version/ {print $3}')" \
    --platform-family macOS --deployment-target "$minimum_os" --target-triple "$target" \
    --source-file-list "$stage/sources.list" --swift-const-vals-list "$stage/const-values.list" \
    --force
test -s "$output/Metadata.appintents/extract.actionsdata"
