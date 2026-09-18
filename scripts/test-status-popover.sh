#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/layout-tests
swiftc Sources/MyStat/DashboardStyle.swift Sources/MyStat/KeepAwakeController.swift Sources/MyStat/KeepAwakeView.swift Sources/MyStat/ProcessPanelPlacement.swift Sources/MyStat/StatusPopover.swift Tests/StatusPopover/main.swift -o .build/layout-tests/status-popover-tests
.build/layout-tests/status-popover-tests
