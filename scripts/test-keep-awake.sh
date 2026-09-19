#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/keep-awake-tests
swiftc Sources/MyStat/KeepAwakeController.swift Sources/MyStat/StatusBarRenderer.swift Tests/KeepAwake/main.swift -o .build/keep-awake-tests/keep-awake-tests
.build/keep-awake-tests/keep-awake-tests
