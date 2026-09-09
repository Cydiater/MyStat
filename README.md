# MyStat

A small native Mac CPU/memory monitor with an iPhone companion. Use the menu bar for a quick glance, or turn your iPhone into a live desk display.

## Live desk display

1. Run MyStat on your Mac and iPhone, on the same local network. Allow **Local Network** access when iOS asks.
2. The iPhone discovers your Mac automatically. Use the computer menu to choose a different Mac if needed.
3. Tap **Open Desk Display**. Leave MyStat visible in portrait or landscape for live readings approximately every two seconds.
4. If your Mac should keep monitoring while its display sleeps, enable **Keep Awake** in the Mac’s MyStat menu. This prevents idle system sleep; closing a MacBook’s lid can still put it to sleep.

Desk Display shows large CPU and memory readings, memory used/total, three-minute sparklines, and the age of the last measurement. The moon button dims the interface. Auto-lock is disabled only while Desk Display is visible and active; closing it or backgrounding the app restores the previous setting.

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

### macOS

Requires macOS 12+ and an installed Swift/Xcode toolchain. Launch at Login is available on macOS 13+.

```sh
./build.sh     # Universal arm64 + x86_64 release, app bundle, ad-hoc signature
open MyStat.app
```

For development: `swift run`. The app has no Dock icon. Its menu provides larger charts with 3m / 15m / 1h ranges, iPhone sharing status, connected device names, Keep Awake, and Launch at Login.

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

- `Sources/MyStat/`: AppKit menu bar app, Mach CPU/memory sampling, one-hour timestamped history, and Bonjour HTTP server.
- `Sources/MyStatCore/`: Shared payloads, validation, bounded history merging, and cancellable HTTP transport. Compiled by SwiftPM and included in both iOS targets by XcodeGen.
- `MyStat-iOS/MyStat-iOS/`: SwiftUI dashboard, Desk Display, discovery/polling, and local history persistence.
- `MyStat-iOS/Shared/`: App Group server selection and complete cached snapshots.
- `MyStat-iOS/MyStatWidget/`: Widget timeline, direct fetching, and refresh intent.
- `Tests/MyStatCoreTests/`: Protocol and transport regression tests.

CPU usage comes from differences in Mach host CPU tick counters. Memory use is active + wired + compressed memory divided by physical RAM; it is a utilization estimate, not macOS’s memory-pressure metric. There are no third-party runtime dependencies or cloud services. The Mac serves read-only stats over unauthenticated local HTTP (`_mystat._tcp`, port 18735); use it on a trusted local network.

The Mac keeps one hour in memory. The iPhone keeps up to 24 hours / 43,200 samples in `stats_history.json`, with serialized atomic saves and retry on write failure. The widget stores only the latest snapshot and selected Mac in the App Group.

## Tests

```sh
swift test
```

Coverage includes split TCP headers/bodies, truncated and malformed responses, deadlines, cancellation before/during a request, reconnecting with a new request, payload validation, legacy history, sample timestamp round trips, history deduplication and retention. Physical-device StandBy scheduling, local network permission prompts, and extended charging sessions must also be checked on an iPhone; simulator and unit tests cannot verify iOS’s real background/widget scheduling.
