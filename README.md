# MyStat

A small native Mac system monitor with an iPhone companion. Use the menu bar for a quick glance, or turn your iPhone into a live desk display.

The iPhone app, **MyStat: Desk Monitor**, is not yet available on the App Store. Its initial review requires a physical-device demonstration video; the requested name and subtitle corrections have been saved. It is set to release automatically after approval at **US$5 paid once**, with localized prices elsewhere and a free Mac companion. [Setup & support](https://cydiater.github.io/MyStat/support.html) · [Privacy policy](https://cydiater.github.io/MyStat/privacy.html).

[Download the free Mac companion 1.5.1](https://github.com/Cydiater/MyStat/releases/download/v1.5.1/MyStat-v1.5.1.zip). The universal app supports Apple silicon and Intel Macs and is **Developer ID signed and Apple-notarized**. Existing updater-enabled versions can install it directly through **Check for Updates…**; version 1.3.0 and later place that command under **Settings**.

The iPhone app includes **Explore Demo** for trying the dashboard and Desk Display without a Mac. Sample readings are labeled DEMO, kept only in memory, and never saved into your real history or widgets. **Connect My Mac** restores the real connection.

## Readings

The Mac companion 1.2.0 adds side process panels with app icons, redesigned charts and metric cards, and timed Keep Awake controls that can keep the display on. Version 1.2.1 fixes repeated menu-bar clicks sometimes reopening the dashboard instead of dismissing it. The iPhone implementation is in the current source but is not part of the submitted iOS 1.0.0 (2) build.

The Mac menu and iPhone dashboard show:

- **CPU and memory:** utilization, with used/total memory on the phone's Desk Display.
- **Top processes:** separate top-five CPU and resident-memory lists. On the Mac, **CPU Processes** and **Memory Processes** beneath the charts open native cascading submenus with app icons and usage values. Use standard menu hover, click, arrow-key, and Escape navigation. Long process names and PIDs are available in row tooltips. On the phone, use the dashboard or the list button in Desk Display. Update both apps to use this feature.
- **Network:** download and upload throughput in B/s, KB/s or MB/s, sampled every two seconds. Counts physical Wi-Fi and Ethernet (`en*`) adapters, including LAN traffic. VPN, bridge, loopback and peer-to-peer interfaces are excluded to avoid counting traffic twice. A new adapter, counter reset or gap longer than ten seconds establishes a fresh baseline instead of producing a spike.
- **Power:** AC/battery status, battery percentage, net battery charge/discharge watts, reported adapter rating and battery cycles, where the hardware exposes them. Positive battery flow means charging; negative means discharging. Battery watts are **not whole-system or wall-socket consumption**, and adapter rating is **not measured input**. Desktop Macs and unsupported sensors show unavailable readings. USB power output is not measured.
- **System:** free space and capacity of the home volume, swap used, macOS thermal state and uptime. Storage refreshes every 30 seconds. Thermal state is macOS's assessment, not a temperature sensor reading.
- **Codex tokens today:** input, cached input and output from readable local Codex session logs. Cached input is included in input, and reasoning is included in output; neither is added to the total twice. Counts use the Mac's local calendar day/time zone and refresh every 30 seconds. This covers recorded local sessions, not account quota, billing, remote sessions or other AI apps.

Token collection incrementally reads `sessions` and `archived_sessions` under `CODEX_HOME` (when inherited by the Mac app), otherwise `~/.codex`. It needs no API key or cloud request. Only aggregate counts and their measurement date/time zone are shared with the phone; conversation content, filenames and credentials are never sent. Duplicate cumulative notifications and copied events are ignored. A first event or reset uses the reported last request rather than importing an unknown lifetime total. Local log formats can change, and incomplete/missing logs can undercount; missing or unreadable data displays “No local usage”.

The dashboard's history selector supports CPU, memory, download, upload and battery flow. New fields are optional: old Mac servers, old phone clients and saved CPU/memory history remain compatible. Update both apps to see all the new readings. The current Mac source adds a compact **NET** graph beside CPU and memory: download is above its center line and upload below, sharing an automatic rate scale. The dropdown shows both rates and a two-line network chart, using the same 3m / 15m / 1h selector as CPU and memory. Blue/solid is download and purple/dashed is upload. Missing readings leave gaps instead of drawing zero traffic.

The current Mac source also adds a native **Network Apps** submenu below the network chart. It ranks the top five active apps and system processes by combined download/upload rate, shows both rates and app icons, and combines helpers belonging to the same app. Apple’s built-in `nettop` collects readable TCP/UDP process byte counters every two seconds without administrator privileges. The first reading, process reuse, counter reset, or a gap longer than ten seconds establishes a baseline. Closed connections can reset totals, so short-lived traffic can be missed. No recent activity produces an empty list; unavailable or stale readings are labeled. VPN/proxy attribution and virtual interfaces can make app rates differ from the physical-adapter totals. The matching iPhone source now receives these top-five rankings, containing only app names, representative PIDs, byte rates and sample time. Executable paths and icons stay on the Mac. Rankings are included only in the latest snapshot, not in history. Only process summaries are requested, without addresses, connection details, or packet content.

The current iPhone source adds a combined download/upload chart with 3m / 15m / 1h ranges and a native disclosure for **Top network apps**. Desk Display includes a small three-minute network graph and shows network rankings in its process-list view. Demo mode includes clearly labeled sample network apps. Missing or stale rankings are labeled, and an older Mac companion prompts an update while its existing readings continue to work. Update both apps for network rankings; these changes have not been submitted to the App Store.

Mac companion 1.5.1 uses a native AppKit **NSMenu** for the dropdown. CPU and memory charts remain visible, with **CPU Processes**, **Memory Processes**, **Details**, **iPhone**, and **Settings** opening real cascading submenus. macOS provides their material, selection highlights, arrows, checkmarks, placement, and keyboard navigation. The charts are custom views hosted by the native menu. **Keep Awake** is a single native submenu row showing Off or the remaining time. Its submenu contains the on/off control, duration presets, and **Keep Display On**, with standard checkmarks. Live readings and countdowns continue while a menu is open.

Keep Awake uses an 18-point coffee icon and progress bar that shrinks as time runs out, adding only 23 points including spacing. Hover for the exact remaining time; untimed sessions use a compact ∞ indicator. The indicator disappears when Keep Awake ends.

Process readings are sampled on a background queue approximately every two seconds. CPU is measured between samples, with **100% representing one full CPU core**; a multithreaded process can exceed 100%. The first sample, a reused PID, a reset counter or a long sampling gap needs a new baseline before CPU is ranked. Memory is **resident bytes**, includes potentially shared pages, and differs from Activity Monitor's memory footprint. Processes that exit or cannot be read without extra privileges are omitted; this is a ranking of readable processes, not necessarily every process on the system. Names can be shortened by macOS; PIDs distinguish helpers with the same name.

Only the top-five lists are shared, containing process names, PIDs, CPU percentages, resident bytes and the sampling time. MyStat does not read command arguments or process environments. Mac version 1.2.0 shows app icons beside process names, using executable paths locally to identify helper processes' owning apps; icons and paths are not sent to the phone or stored in history. Processes without an app icon use a system-process symbol. The Mac opens the list beside the dashboard, choosing left or right to fit the screen, and uses compact dashboard cards with labeled chart axes. Process rankings are not added to historical charts; the latest snapshot is cached with the other readings. Old process snapshots are marked stale independently of system readings. Older companions remain usable and show process readings as unavailable.

## Live desk display

1. Run MyStat on your Mac and iPhone, on the same local network. Allow **Local Network** access when iOS asks.
2. The iPhone discovers your Mac automatically. Use the computer menu to choose a different Mac if needed.
3. Tap **Open Desk Display**. Leave MyStat visible in portrait or landscape for live readings approximately every two seconds.
4. Open **Keep Awake** in the Mac’s MyStat menu and enable it to prevent idle sleep. Its submenu includes duration presets (∞, 15m, 30m, 45m, 1h, 4h, 8h), and an “Active until” status. **Keep Display On** is enabled by default; uncheck it to allow display sleep while monitoring continues. Selecting a duration while active restarts the timer; changing the display option preserves the deadline. Sessions end automatically at their deadline, when switched off, or when MyStat quits. Preferences are remembered, but sessions do not restart on launch. macOS also enforces timed expiry independently of the app's UI timer. Manual sleep, lid closure, and low-battery sleep still take priority.

Desk Display shows large CPU and memory readings, memory used/total, three-minute sparklines, network speeds, battery flow and today's Codex tokens, plus free storage and thermal state in portrait. It also shows the age of the last measurement. The moon button dims the interface. Auto-lock is disabled only while Desk Display is visible and active; closing it or backgrounding the app restores the previous setting.

On a lost connection, the last reading stays visible with an **OFFLINE** label and its age. Requests time out and reconnect automatically. Returning to the app fetches the Mac’s rolling history to fill gaps. The regular dashboard supports pinch-to-zoom and panning through up to 24 hours of saved history. Switching Macs clears the displayed history so different computers’ measurements are not mixed.

## Apple StandBy and widgets

The widget and Desk Display have different refresh behavior:

| | Desk Display | Apple StandBy / Home Screen widget |
| --- | --- | --- |
| Updates | About every two seconds while the app is visible | When iOS grants a timeline refresh, or when you tap Refresh |
| Screen | MyStat stays in the foreground | Managed by iOS |
| Connection | Polls and reconnects continuously | Fetches directly from the last selected Mac, with a bounded timeout |
| Old data | OFFLINE label and last reading age | Dimmed values, age label, and stale timeline entry |

Open the iPhone app and connect once before adding the widget. This grants local network access and saves the Mac’s Bonjour service for the widget. The widget resolves that service again when refreshing, so it does not depend on a fixed IP address or on the app continuing to run in the background. Tap its refresh button for a new snapshot; tap the rest of the widget to open Desk Display.

**Apple StandBy is not a continuous live monitor.** WidgetKit owns refresh timing, even when a refresh has been requested. MyStat requests periodic snapshot refreshes and includes a future stale entry, but iOS can delay rendering and reloads. The visible timestamp identifies how old a reading actually is. There is no silent-audio background loop.

Apple’s references: [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date), [Local network privacy for app extensions](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

## Build

### Mac updates

Mac version 1.1.0 includes **About MyStat**, **Check for Updates…**, and an opt-in **Automatically Check for Updates** menu item. Sparkle shows release notes and handles installation/relaunch; automatic checks do not silently install updates. Existing 1.0.0 users need to replace their Mac app manually once to get the updater. The phone can identify a companion that needs upgrading for process rankings.

Updates use signed archives on GitHub Releases and a signed feed on GitHub Pages. No system stats or process data are attached to update checks. See [release and signing instructions](AppStore/mac-updates.md). Version 1.5.1 provides a signed, notarized archive in the feed: Check for Updates offers **Install Update**, then **Install and Relaunch**. Preferences are preserved; an active Keep Awake session ends on relaunch. Older 1.2.0–1.3.0 entries remain historical manual-download notices. The submitted iPhone build is unchanged by this Mac release.

### macOS

The app runs on macOS 12+. Building the current source requires Xcode 27+ for the native menu image-visibility API. Launch at Login is available on macOS 13+.

```sh
./build.sh     # Universal arm64 + x86_64 release, app bundle, ad-hoc signature
open MyStat.app
```

Run `scripts/test-network.sh --live` for network CSV framing, byte-rate calculation, app grouping, resets and gaps, native rows, graph scaling, light/dark render artifacts, and real collector sampling, CPU usage and shutdown. Run `swift test` for core tests and `scripts/test-status-menu.sh` on macOS for native-menu regression checks, including process value badges, empty/stale readings, stable live updates, action validation, nested keyboard shortcuts, chart layout, Keep Awake submenu actions and checkmarks, saved durations, display-option deadline preservation, errors, expiry, and countdown updates during menu tracking. Run `scripts/test-keep-awake.sh` to verify session lifecycle, countdown ticks and boundaries, and real macOS sleep assertions, including timed expiry.

For development: `swift run`. The app has no Dock icon. Its menu provides larger charts with 3m / 15m / 1h ranges, iPhone sharing status, connected device names, Keep Awake, and Launch at Login.

An ordinary `build.sh` output is ad-hoc signed and not notarized. For releases, prefer the Xcode workflow below. If you already have a local Developer ID Application identity and a notarytool keychain profile, `scripts/release-macos.sh` provides another route using `MYSTAT_SIGNING_IDENTITY` and `MYSTAT_NOTARY_PROFILE`; it signs, notarizes, packages, and generates the signed feed.

The Mac Xcode project uses the Apple Developer account signed into **Xcode → Settings → Apple Accounts**. This is the route used for 1.3.1: Xcode can sign with a cloud-managed Developer ID certificate even when no local Developer ID identity is installed. The project archives both architectures and enables hardened runtime. Change the team in the project and export options if building for another account.

```sh
xcodegen generate --spec MyStat-macOS/project.yml
xcodebuild -project MyStat-macOS/MyStat-Mac.xcodeproj -scheme MyStat \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath .build/MyStat-Mac.xcarchive -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath .build/MyStat-Mac.xcarchive \
  -exportPath .build/mac-notarization \
  -exportOptionsPlist MyStat-macOS/ExportOptions.plist -allowProvisioningUpdates
```

After Apple accepts notarization, export the stapled app, verify it, and package the download. If export reports that the archive is still processing, wait and retry `-exportNotarizedApp` without rebuilding or resubmitting:

```sh
xcodebuild -exportNotarizedApp -archivePath .build/MyStat-Mac.xcarchive \
  -exportPath .build/mac-notarized
codesign --verify --deep --strict .build/mac-notarized/MyStat.app
xcrun stapler validate .build/mac-notarized/MyStat.app
spctl --assess --type execute --verbose=2 .build/mac-notarized/MyStat.app
ditto -c -k --keepParent .build/mac-notarized/MyStat.app .build/MyStat-v1.5.1.zip
scripts/generate-appcast.sh .build/MyStat-v1.5.1.zip AppStore/releases/1.5.1.md
```

### iPhone and widget

Requires iOS 17+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The generated Xcode project is ignored by Git; `project.yml` is the source of truth.

```sh
xcodegen generate --spec MyStat-iOS/project.yml
open MyStat-iOS/MyStat-iOS.xcodeproj
```

Select the `MyStat-iOS` scheme and your iPhone. Set the development team and bundle identifiers for your signing account if needed, and use the same App Group identifier in both entitlements and `SharedDefaults.swift`. Build and run. Updating both the Mac and phone is recommended: the new server includes exact sample timestamps and memory byte counts. The client also accepts the older history format.

To check compilation without device signing:

```sh
xcodebuild -project MyStat-iOS/MyStat-iOS.xcodeproj \
  -scheme MyStat-iOS -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Troubleshooting

- **No Mac found:** Check that both devices share a local network, MyStat is running, and iOS Settings → Privacy & Security → Local Network permits MyStat. Guest Wi-Fi or network isolation may block discovery and connections.
- **Readings stopped:** Wake the Mac, then check the iPhone’s connection message. Reconnection is automatic; Retry restarts discovery immediately. Keep Awake on the Mac prevents idle system sleep, not lid-closed or manually requested sleep.
- **Sharing unavailable:** The Mac menu reports the listener state. Check whether another MyStat instance is using TCP port 18735 and whether your firewall allows it. The server retries listener failures automatically.
- **Widget remains old:** Open the app to establish local network permission and choose a Mac. Tap Refresh on the widget. For continuously live readings, use Desk Display.
- **A different Mac is selected:** Choose the intended Mac from the iPhone’s computer menu. The selection persists across launches and network interruptions.

## Code layout

- `Assets/AppIcon/`: editable Pixelmator Pro icon, exported artwork, packaged Mac icon, and design notes. Recreate the platform sizes with `swift scripts/generate-app-icons.swift`.
- `Sources/MyStat/`: AppKit menu bar app, Mach CPU/memory sampling, one-hour timestamped history, and Bonjour HTTP server.
- `Sources/MyStatCore/`: Shared payloads, validation, bounded history merging, and cancellable HTTP transport. Compiled by SwiftPM and included in both iOS targets by XcodeGen.
- `MyStat-iOS/MyStat-iOS/`: SwiftUI dashboard, Desk Display, discovery/polling, and local history persistence.
- `MyStat-iOS/Shared/`: App Group server selection and complete cached snapshots.
- `MyStat-iOS/MyStatWidget/`: Widget timeline, direct fetching, and refresh intent.
- `Tests/MyStatCoreTests/`: Protocol and transport regression tests.

CPU usage comes from differences in Mach host CPU tick counters. Memory use is active + wired + compressed memory divided by physical RAM; it is a utilization estimate, not macOS’s memory-pressure metric. The Mac app uses Sparkle for updates; monitoring requires no cloud service. The Mac serves read-only stats over unauthenticated local HTTP (`_mystat._tcp`, port 18735); use it on a trusted local network.

The Mac keeps one hour in memory. The iPhone keeps up to 24 hours / 43,200 samples (including network and power) in `stats_history.json`, with serialized atomic saves and retry on write failure. The widget stores only the latest snapshot and selected Mac in the App Group. The medium widget adds network speeds, battery flow when available, and Codex tokens to its CPU/memory snapshot.

## Tests

```sh
swift test
```

Coverage includes split TCP headers/bodies, truncated and malformed responses, deadlines, cancellation before/during a request, reconnecting with a new request, payload validation, legacy history, extended sample round trips, history deduplication and retention, payload size, network resets/sleep, token deduplication and day boundaries, and partial/oversized log records. Physical-device StandBy scheduling, local network permission prompts, battery charging/discharging on a MacBook, and extended charging sessions must also be checked on real hardware; simulator and unit tests cannot verify iOS’s real background/widget scheduling.
