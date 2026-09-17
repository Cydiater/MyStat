#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/layout-tests
swiftc Sources/MyStat/StatusPopover.swift Tests/StatusPopover/main.swift -o .build/layout-tests/status-popover-tests
.build/layout-tests/status-popover-tests
