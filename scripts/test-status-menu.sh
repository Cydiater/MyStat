#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage=".build/native-menu-tests"
mkdir -p "$stage"
swiftc -emit-module -emit-library -module-name MyStatCore Sources/MyStatCore/*.swift \
    -emit-module-path "$stage/MyStatCore.swiftmodule" -o "$stage/libMyStatCore.dylib"
swiftc -I "$stage" -L "$stage" -lMyStatCore -Xlinker -rpath -Xlinker @executable_path \
    Sources/MyStat/DashboardStyle.swift Sources/MyStat/StatsChartView.swift \
    Sources/MyStat/KeepAwakeController.swift Sources/MyStat/KeepAwakeView.swift \
    Sources/MyStat/ProcessIconProvider.swift Sources/MyStat/ProcessMenu.swift \
    Tests/StatusMenu/main.swift -o "$stage/status-menu-tests"
"$stage/status-menu-tests"
