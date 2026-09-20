# Mac updates

MyStat 1.1.0 (build 2) introduces Sparkle 2.10.0. This is the first updater-enabled release; users of 1.0.0 and earlier must manually install it once. The iOS build remains separate and updates through Apple.

## User experience

- **About MyStat** shows the installed version and build.
- **Check for Updates…** opens Sparkle's update UI with release notes. Notarized updates support installation/relaunch; GitHub-only manual releases offer “Learn More…” to open the GitHub download page.
- **Automatically Check for Updates** is off initially and can be enabled in the menu. Checks use Sparkle's daily default schedule; silent installation is disabled.
- The iPhone shows an upgrade prompt for companions missing process rankings. Capability reporting prevents an unreadable sensor or CPU warm-up from being mistaken for an outdated companion.
- Existing saved preferences and local histories are not migrated or deleted by the updater.

## Signing and hosting

The update feed is `https://cydiater.github.io/MyStat/appcast.xml`. Archives are release assets under `https://github.com/Cydiater/MyStat/releases/download/vVERSION/MyStat-vVERSION.zip`.

Sparkle verifies the signed feed and archive before extraction. The public Ed25519 key is embedded in `Sources/MyStat/Info.plist`. The matching private key was generated with Sparkle's `generate_keys` and stored in the login Keychain under account **com.cydiater.MyStat.sparkle**. It is not in this repository. Keep a secure backup using Sparkle's documented export/import process; never commit the private key or put it on the hosting server. A new release machine must import the same key, not generate a replacement.

`docs/appcast.xml` contains signed release entries. Version 1.6.0 provides an installable, notarized archive; 1.2.0 through 1.3.0 remain historical manual-download notices. Do not edit a signed feed manually; changes invalidate its signature. The release script preserves prior entries and signs the completed feed. Back up the key before shipping because requiring verification before extraction restricts recovery if the key is lost; consult Sparkle's key-rotation documentation.

Developer ID signing/notarization and Sparkle signatures are separate. Automatically installable production updates require both. Ad-hoc builds may appear only as signed informational notices with a GitHub release link and no enclosure. Existing Sparkle clients show “Learn More…” for these notices; they never automatically download or install them. The notarization checks for installable feed entries remain in place.

Prefer Xcode's automatic Developer ID archive/export workflow below when the account is signed in. Xcode can use a cloud-managed Developer ID certificate even when `security find-identity` lists no local Developer ID identity. An empty local identity list alone is not a reason to fall back to a manual release. If export reports **No Accounts**, sign in through **Xcode → Settings → Apple Accounts** and retry export with the existing archive.

If the account is already signed in but command-line export still reports **No Accounts**, open the archive in Xcode Organizer and use **Distribute App → Direct Distribution**. This signs and submits the archive using Xcode's active account session. Organizer imports the archive into `~/Library/Developer/Xcode/Archives`; use that imported archive for `-exportNotarizedApp`, or click **Export Notarized App** when it is ready. Keep the same submitted archive instead of rebuilding or resubmitting.

## Build and prepare a release

1. Increment `CFBundleShortVersionString` and the integer `CFBundleVersion` in `Sources/MyStat/Info.plist`. Build numbers must increase across every update, even if the display version changes.
2. Add `AppStore/releases/VERSION.md` with release notes. Test the Mac app and matching phone features.
3. Run `./build.sh` for a local universal app. It embeds Sparkle and signs nested code inside-out. `swift run` is useful for monitoring development, but a bare executable cannot use in-app updates.
4. Prefer the Xcode Developer ID archive/export commands in the README. `-allowProvisioningUpdates` lets Xcode use the signed-in team's signing resources; `MyStat-macOS/ExportOptions.plist` selects Developer ID distribution and upload for notarization. After upload, `xcodebuild -exportNotarizedApp` exports the stapled app. If Apple reports that the archive is still processing, wait and retry that final export; do not rebuild or resubmit it.
5. Verify the exported app with `codesign --verify --deep --strict`, `xcrun stapler validate`, and `spctl --assess --type execute --verbose=2`, package it, then run `scripts/generate-appcast.sh PATH_TO_NOTARIZED_ZIP AppStore/releases/VERSION.md`. The XcodeGen Mac project embeds and signs the pinned Sparkle framework. Alternatively, `scripts/release-macos.sh` automates the local-certificate route when both `MYSTAT_SIGNING_IDENTITY` and `MYSTAT_NOTARY_PROFILE` are configured.

For an explicitly requested GitHub-only manual release, upload and verify the ZIP/checksum first, then run `scripts/generate-manual-appcast.sh PATH_TO_RELEASE.zip AppStore/releases/VERSION.md`. It checks the bundle signature, embedded public key, feed URL and increasing build number, preserves existing items, and signs a notice without an enclosure. Publish that feed through GitHub Pages and verify that an older updater-enabled app finds the notice. No new app binary is needed to enable this notice for existing users.

The notarized feed generator checks the packaged app's signature, notarization, public key, feed URL and increasing build number. It embeds release notes in the signed feed and produces no binary deltas. The original archive must remain byte-for-byte unchanged after signing.

## Publish in order

1. Upload the verified `MyStat-vVERSION.zip` and its checksum to GitHub release `vVERSION`.
2. Verify that the archive is publicly downloadable and has the expected checksum.
3. Update the website's manual-download link and version copy. Publish the generated `docs/appcast.xml` through the existing GitHub Pages deployment, after the archive is available.
4. Confirm the public feed signature and URLs, then check for the update using a previously installed updater-enabled build. Test the notarized install/relaunch and preserved preferences on a real Mac before treating the release as complete.

Publishing the source or feed alone does not create an update. Preparing a release does not upload an iOS build or resubmit App Review. When recording Apple's physical-device demo, use the exact iOS build being submitted and a matching released companion.

## Development checks

`swift test` covers legacy payloads and capability detection. Build both Mac architectures and the iOS targets. Sparkle's `sign_update --verify` verifies feeds and archives; `generate_appcast` prepares test feeds as well as production feeds. For local updater smoke tests, use a separate copy of the app bundle with a local test feed and re-sign that copy; never commit a localhost feed URL or publish that test build. A local development check does not replace testing a notarized upgrade and relaunch.

Local validation on September 17, 2026: all 30 Swift tests passed, the universal Mac bundle and both Xcode targets built, and signed-feed verification rejected a modified feed. An isolated app with a separate bundle identifier and the production `AppUpdater` code displayed the 1.1.0 release notes, downloaded the signed archive from a loopback server, installed build 2, and relaunched. The installed executable matched the archive, its nested code signatures verified, and a saved preference survived. These were ad-hoc development copies; the production notarized update remains a release check.

Release validation on September 19, 2026: Xcode used the signed-in team's cloud-managed Developer ID certificate to sign 1.3.1 (7), and Apple notarized it. Its stapled ticket, nested signatures, and Gatekeeper acceptance passed. An isolated copy reporting 1.3.0 (6), using the production `AppUpdater` and Sparkle framework, installed the exact notarized release archive from a signed loopback test feed and relaunched. The resulting executable and Info.plist matched the release, Keep Awake preferences were preserved, and the user's separate running app and active Keep Awake session were untouched.

Version 1.4.0 (8), validated September 19, 2026: all 30 core tests passed, along with countdown timing/boundary, Keep Awake lifecycle, native assertion, and dropdown interaction checks. The universal Developer ID release passed nested signature, stapled-ticket, and Gatekeeper validation. A development-signed test copy reporting 1.3.1, using the production `AppUpdater` and the release's Sparkle framework, downloaded the exact notarized 1.4.0 archive from a signed loopback feed, installed it, and relaunched. The resulting executable and Info.plist matched the release, Keep Awake preferences were preserved, and the user's separate installed app remained running. Test hosts that retain Developer ID-signed Sparkle helpers must be signed by the same team so Sparkle's XPC identity checks can succeed.

Version 1.5.0 (9), validated September 19, 2026: all 30 core tests, native-menu regression checks, and Keep Awake lifecycle/progress/assertion checks passed. Apple notarized the universal Developer ID archive; nested signatures, the stapled ticket, and Gatekeeper acceptance passed. The public archive matched its SHA-256 checksum, and Sparkle validated the signed public feed. An isolated 1.4.0 host downloaded the public archive, installed the exact 1.5.0 executable and Info.plist, and relaunched. The local Applications installation was then updated to the same verified release and relaunched, with saved Keep Awake and automatic-update preferences preserved.

Version 1.5.1 (10), validated September 19, 2026: all 30 core tests and native-menu/Keep Awake regression checks passed, including explicit process-icon visibility, submenu actions and checkmarks, duration persistence, deadline preservation, errors, expiry, and countdown updates during menu tracking. Apple notarized the universal Developer ID archive, and nested signatures, the stapled ticket, and Gatekeeper acceptance passed. The public download matched its SHA-256 checksum; the signed public feed and website pointed to build 10. An isolated 1.5.0 host installed the exact public 1.5.1 archive through Sparkle and relaunched with saved preferences preserved. A separate Sparkle probe verified the public feed and confirmed build 10 reports no newer update.

Version 1.6.0 (11), validated September 20, 2026: all 35 core tests and the native-menu checks passed. Network checks covered CSV framing, rate calculations, app grouping, resets, gaps, chart scaling, native rows, stale readings, live unprivileged sampling, low collector CPU use, and cleanup after normal shutdown and force quit. Apple notarized the universal Developer ID archive; nested signatures, its stapled ticket, and Gatekeeper acceptance passed. The public archive matched its SHA-256 checksum, and the signed public feed and website pointed to build 11. The existing 1.5.1 Applications installation discovered the installable update through Sparkle and subsequently relaunched as the exact 1.6.0 release, with saved Keep Awake and update preferences preserved. Its menu exposed the network chart and live app traffic rankings. The matching iPhone source is synced but has not been submitted to App Review.

References: [Sparkle setup](https://sparkle-project.org/documentation/), [programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/), [publishing](https://sparkle-project.org/documentation/publishing/).
