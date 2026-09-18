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

`docs/appcast.xml` contains signed notices for published releases, including a manual-download notice for 1.2.0. Do not edit a signed feed manually; changes invalidate its signature. The release script preserves prior entries and signs the completed feed. Back up the key before shipping because requiring verification before extraction restricts recovery if the key is lost; consult Sparkle's key-rotation documentation.

Developer ID signing/notarization and Sparkle signatures are separate. Automatically installable production updates require both. Ad-hoc builds may appear only as signed informational notices with a GitHub release link and no enclosure. Existing Sparkle clients show “Learn More…” for these notices; they never automatically download or install them. The notarization checks for installable feed entries remain in place.

## Build and prepare a release

1. Increment `CFBundleShortVersionString` and the integer `CFBundleVersion` in `Sources/MyStat/Info.plist`. Build numbers must increase across every update, even if the display version changes.
2. Add `AppStore/releases/VERSION.md` with release notes. Test the Mac app and matching phone features.
3. Run `./build.sh` for a local universal app. It embeds Sparkle and signs nested code inside-out. `swift run` is useful for monitoring development, but a bare executable cannot use in-app updates.
4. For a notarized, automatically installable release, run `scripts/release-macos.sh` with the existing `MYSTAT_SIGNING_IDENTITY` and `MYSTAT_NOTARY_PROFILE` settings. It verifies the update key, builds, notarizes, staples, verifies the app, packages it, then generates and signs `docs/appcast.xml`.
5. If using Xcode's Developer ID archive/export route instead, run `scripts/generate-appcast.sh PATH_TO_NOTARIZED_ZIP AppStore/releases/VERSION.md` after exporting and packaging `MyStat.app`. The XcodeGen Mac project embeds and signs the same pinned Sparkle framework.

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

References: [Sparkle setup](https://sparkle-project.org/documentation/), [programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/), [publishing](https://sparkle-project.org/documentation/publishing/).
