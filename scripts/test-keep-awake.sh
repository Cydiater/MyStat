#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage=".build/keep-awake-tests"
mkdir -p "$stage"
swiftc -emit-module -emit-library -module-name MyStatCore Sources/MyStatCore/*.swift \
    -emit-module-path "$stage/MyStatCore.swiftmodule" -o "$stage/libMyStatCore.dylib"
swiftc -I "$stage" -L "$stage" -lMyStatCore -Xlinker -rpath -Xlinker @executable_path \
    Sources/MyStat/KeepAwakeController.swift Sources/MyStat/KeepAwakeIntents.swift \
    Sources/MyStat/NetworkChartData.swift Sources/MyStat/StatusBarRenderer.swift \
    Tests/KeepAwake/main.swift -o "$stage/keep-awake-tests"
"$stage/keep-awake-tests"
./scripts/build-app-intents.sh "$stage/resources"
swiftc -parse-as-library Sources/MyStat/KeepAwakeController.swift Sources/MyStat/KeepAwakeIntents.swift \
    Tests/KeepAwakeIntents/main.swift -o "$stage/intent-tests"
"$stage/intent-tests" "$stage/resources/Metadata.appintents/extract.actionsdata"
