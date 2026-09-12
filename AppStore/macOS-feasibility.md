# Mac App Store feasibility — September 12, 2026

**Result: feasible with a contained permissions and packaging change.** A local sandbox test passed for the existing monitoring and sharing code. The full native Mac application also archived successfully for Intel and Apple silicon using the iPhone bundle identifier. This is a feasibility result, not an App Review approval or an uploaded Mac release.

## Runtime checks

Tested on an Apple silicon desktop running macOS 26.6.2. The probe compiled the production `StatsMonitor` and `ExtendedMonitor` files directly and used copies of `StatsServer` and `TokenMonitor`. The only changes to those copies were a separate test port/Bonjour service and an optional root URL for the token reader. The production sources remain unchanged.

The app had App Sandbox, incoming/outgoing network access, read-only user-selected file access, and app-scoped bookmarks. No sandbox exceptions, root privileges, or external helper were used. A second probe build used the existing Apple Development signing identity without the debugger entitlement.

| Feature | Result |
| --- | --- |
| CPU and memory | Real, nonzero measurements; physical memory reported correctly |
| Network throughput | Valid download and upload readings from existing interface counters |
| Storage, swap, thermal state, uptime | Available inside the sandbox |
| Power source | AC power detected on this desktop |
| Battery watts, adapter watts, cycles | Not verified: this test machine has no battery |
| Bonjour | Listener and browser ready; the separate test service was discovered |
| HTTP sharing | Live and history endpoints returned valid JSON; aggregate tokens were included after permission was granted |
| Keep Awake | Assertion creation and release both succeeded |
| Launch at Login | Signed probe registration succeeded and reached enabled status; unregister succeeded and returned to not registered |
| Codex logs before permission | Default container path contained no logs; access to the actual logs was denied |
| Codex logs after folder selection | Read-only access succeeded; the existing parser produced valid token totals |
| Folder access after relaunch | Saved security-scoped bookmark restored without becoming stale; token totals remained available |

The temporary listener was on port 18736 with service `_mystatcheck._tcp`, so the normal MyStat service was not replaced. No new phone build or physical-device streaming session was used for this check. The probe was closed after testing and its login registration was removed.

## Smallest production changes

1. Add an App Store build configuration with App Sandbox and the tested entitlements. Keep the direct-download build configuration available.
2. Add an optional “Choose Codex Folder” control, save a read-only security-scoped bookmark, restore it on launch, and handle moved folders or revoked permission. Pass the selected URL to the existing token reader. The prototype confirmed this works without changing the token parser.
3. Set the Mac Store build's bundle identifier to `com.cydiater.MyStat-iOS` through its build-specific Info.plist. The current direct-download identifier is `com.cydiater.MyStat`. The complete native app compiled and archived with the shared identifier and sandbox entitlements for both architectures; no UI conversion was necessary.
4. Prepare the Mac description, screenshots, privacy materials, and App Store distribution signing. Validate the final signed build and test battery charging/discharging on a MacBook before submission.

The local archive is under `.build/sandbox-check/MyStat-StoreCandidate.xcarchive`. It is an ad-hoc-signed feasibility artifact, not a distributable App Store build. Probe projects and raw results are private, ignored build artifacts under `.build/sandbox-check`.

## One purchase for Mac and iPhone

Recommend keeping the total price at **US$5** and adding macOS to the existing App Store record as a **universal purchase**. Apple supports separate native targets under the same record and bundle identifier. Customers purchase access across the supported platforms; existing iPhone customers gain the Mac version when available. Mac-specific descriptions and screenshots can explain its companion role. [Apple: Add platforms](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms), [Apple: Universal purchase](https://developer.apple.com/help/glossary/universal-purchase)

App Store Connect currently offers macOS in the existing record's Add Platform dialog while iOS 1.0.0 remains Waiting for Review. The dialog was inspected and cancelled; no Mac platform or build was added. The current iPhone submission and pricing were not modified.

Once Apple approves at least two platforms, the record becomes a universal purchase and a single platform cannot subsequently be removed from that record. The existing free, notarized Mac download can remain the working companion while the Mac Store version is prepared. [Apple: Add platforms](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms)

## References and limits

- [Configure the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox): required sandbox and network/file entitlements.
- [Access files from App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox): user-selected directories and persistent security-scoped bookmarks.
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): Mac-specific distribution requirements and public API use. The optional battery implementation uses public IOKit calls with hardware-dependent registry properties; its behavior still needs a real MacBook check.
- [Required-reason API documentation](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api): the current overview names iOS, iPadOS, tvOS, visionOS, and watchOS. Do not blindly copy the iPhone's App Group defaults declaration into the Mac build or invent reasons for Mac readings; review the Mac privacy manifest against the final implementation.

No application code changes were committed or published as part of this feasibility check. Apple still makes the final approval decision.
