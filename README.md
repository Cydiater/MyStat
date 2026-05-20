# MyStat

A tiny macOS menu bar app that shows live CPU and memory usage as sparklines, in the style of iStat Menus. Click the menu bar item for larger charts over a configurable window.

## Features

- Vertical `CPU` / `MEM` labels next to per-metric mini sparklines, rendered as a [template image](https://developer.apple.com/documentation/appkit/nsimage/1520017-istemplate) so AppKit tints them to match the menu bar (white on dark, black on light, with proper active-state highlight).
- Click → dropdown with two large charts (orange for CPU, teal for memory), a `3m / 15m / 1h` time-range picker, minute-spaced grid + axis labels, and live numeric readouts (CPU %, memory used / total in GB).
- Pure Swift + AppKit. SwiftPM-buildable, no Xcode project required.
- ~30 KB of in-memory history; no disk persistence, no telemetry, no network.

## Requirements

- macOS 12 or later
- Swift toolchain (Xcode or the Swift.org installer). Verified on Swift 6.3 / Apple Silicon.

## Build & run

```sh
./build.sh         # swift build -c release, bundles into MyStat.app, ad-hoc codesigns
open MyStat.app    # appears in the menu bar; no Dock icon (LSUIElement)
```

Or, to iterate without building an app bundle:

```sh
swift run -c release
```

Quit from the dropdown (`Quit MyStat`) or `pkill -x MyStat`.

## Project layout

```
.
├── Package.swift                  # SwiftPM executable, macOS 12+
├── build.sh                       # release build → MyStat.app + ad-hoc codesign
└── Sources/MyStat/
    ├── main.swift                 # NSApplication bootstrap, .accessory policy
    ├── AppDelegate.swift          # NSStatusItem, timer, menu, range picker
    ├── StatsMonitor.swift         # CPU/memory sampling via Mach host_statistics
    ├── StatsHistory.swift         # Ring buffer of samples (default 1h capacity)
    ├── StatusBarRenderer.swift    # Draws the template image for the status bar
    ├── StatsChartView.swift       # Larger NSView used inside the dropdown menu
    └── Info.plist                 # LSUIElement, bundle identity for the .app
```

## How it works

- **CPU** — `host_statistics(HOST_CPU_LOAD_INFO)` reports user / system / idle / nice tick counters. The monitor stores the previous totals and reports `100 × (totalΔ − idleΔ) / totalΔ` each tick.
- **Memory** — `host_statistics64(HOST_VM_INFO64)` gives `active_count`, `wire_count`, and `compressor_page_count`. Used bytes is `(active + wired + compressed) × vm_kernel_page_size`. Total is `sysctlbyname("hw.memsize")`. The percent matches the "Memory Pressure" denominator macOS uses.
- **Polling** — a single `Timer` on the main run loop in `.common` modes (so it fires while the menu is open), default every 2 seconds.
- **Status bar drawing** — every tick renders a fresh `NSImage` via `NSImage(size:flipped:drawingHandler:)` and assigns it to `statusItem.button.image`. `isTemplate = true` means only the alpha channel is used; AppKit handles tinting and the selection highlight.
- **Dropdown charts** — `StatsChartView` is an `NSView` placed as the `view` of `NSMenuItem`s. The segmented control above them mutates `windowMinutes`; each tick the views are re-fed the right `suffix(N)` slice of the buffer.

## Customization

Most knobs live at the top of `AppDelegate.swift`:

| Constant | Default | Effect |
| --- | --- | --- |
| `pollInterval` | `2.0` s | Sample rate (also drives buffer size) |
| `maxHistoryMinutes` | `60` | Ring buffer length |
| `statusBarMinutes` | `3` | Window for the menu-bar sparklines |
| `availableRanges` | `3m / 15m / 1h` | Segmented picker options for the dropdown |

Status bar geometry (label width, chart width, gaps) is at the top of `StatusBarRenderer.swift`. Dropdown colors are passed in `cpuChartView` / `memChartView` setup — swap `.systemOrange` / `.systemTeal` for whatever you like, or `.labelColor` for a fully monochrome look.
