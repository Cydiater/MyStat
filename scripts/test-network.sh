#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage=".build/network-tests"
mkdir -p "$stage"
swiftc -emit-module -emit-library -module-name MyStatCore Sources/MyStatCore/*.swift \
    -emit-module-path "$stage/MyStatCore.swiftmodule" -o "$stage/libMyStatCore.dylib"
swiftc -I "$stage" -L "$stage" -lMyStatCore -Xlinker -rpath -Xlinker @executable_path \
    Sources/MyStat/Network*.swift Sources/MyStat/ProcessIconProvider.swift \
    Sources/MyStat/DashboardStyle.swift Sources/MyStat/KeepAwakeController.swift \
    Sources/MyStat/StatusBarRenderer.swift Tests/Network/main.swift -o "$stage/network-tests"
"$stage/network-tests" "$@"
