# App Review follow-up — version 1.0.0 (2)

Submission: https://appstoreconnect.apple.com/apps/6811325325/distribution/reviewsubmissions/details/c640ad4f-402d-4a7a-a7c1-40f38c6f7b2c

Apple reviewed build 2 on September 15, 2026, using an iPad Air 11-inch (M3).

The working tree now includes process rankings for a future build. That feature has not been uploaded to App Store Connect. If it is included in this resubmission, first upload a replacement iOS build, distribute the matching companion, and update the build references in the recording steps and reply. Record the exact build being submitted.

## Completed

The en-US App Information localization was updated in App Store Connect:

- Name: **MyStat: Desk Monitor** (20 characters).
- Subtitle: **Live CPU, memory & network** (26 characters).

These replace the name and subtitle containing “Mac” and “iPhone” that Apple flagged under guideline 5.2.5. Apple still needs to review the correction.

## Record the required video

Use a second phone or camera to film the computer and the physical phone/tablet together. Apple explicitly asks for physical-device footage, initial pairing, and the whole app workflow. A simulator recording or screen recording alone does not meet that request.

Before filming:

- Install the submitted iOS version **1.0.0 (2)** on a physical device, for example through TestFlight. Show its version/build in TestFlight as part of the footage if available. Avoid filming a newer development build as evidence for build 2.
- Use the free [companion version 1.0.0](https://github.com/Cydiater/MyStat/releases/download/v1.0.0/MyStat-v1.0.0.zip) on the computer.
- Put both devices on the same trusted local network. Close private windows and notifications that could appear in the footage.
- Begin with the companion quit and MyStat on the phone waiting for a connection. If the phone is showing DEMO, use **Connect My Mac** to return to real discovery. Do not delete existing app data just to recreate onboarding.

Suggested continuous recording (roughly 2–3 minutes):

1. **Identify the setup.** Show the physical devices and the installed app version. Say: “This is MyStat version 1.0.0, build 2, running on a physical device with the MyStat companion on this computer.”
2. **Show initial discovery and connection.** Launch the computer companion and open its menu. Open the phone app. Allow Local Network access if prompted; otherwise explain it was previously granted. Show automatic discovery and select the computer from the computer menu if needed. MyStat connects through local-network discovery; it does not have an account or pairing code.
3. **Show real readings.** Keep both screens in frame while showing the computer menu and phone dashboard. Let the readings update for at least 10–15 seconds. Open an ordinary app or webpage on the computer so the phone shows changing CPU/network readings. Verify the phone is connected and is not labeled DEMO.
4. **Show history and Desk Display.** Switch a history metric and demonstrate pinch/pan. Tap **Open Desk Display**, rotate between portrait and landscape, and demonstrate the dim control. Keep live readings visible for another 10–15 seconds.
5. **Show the widget workflow.** Return to the Home Screen and show a MyStat widget after the initial connection. Tap its Refresh control, then tap the widget to open Desk Display. Explain that widgets provide snapshots and the foreground Desk Display provides continuous updates. If showing StandBy, describe its snapshot behavior accurately.
6. **Show recovery if practical.** Quit the computer companion, show the phone eventually marking the connection offline, then reopen the companion and show automatic recovery. Finish with a working connection.

Check the video is legible and actually demonstrates successful discovery and live data. If any step fails, fix that issue before recording the final evidence. The physical-device video is still pending; no video has been generated or submitted by this workflow.

## Finish the submission after recording

1. Upload the footage to a shareable location and obtain a link Apple can open without an access-request flow. Keep it accessible throughout review and verify playback from a signed-out browser.
2. Add the video link at the beginning of the existing **App Review Information → Notes**. Preserve the existing setup instructions and review contact information. No demo account is required because MyStat has no sign-in.
3. Reply in the existing review conversation with the draft below after replacing the placeholder and checking the actual footage supports every statement.
4. Mark the corrected submission item resolved and resubmit only after the video is available and the metadata is verified. Reuse build 2 if only metadata and review information changed; if code must change, upload and demonstrate the replacement build instead.

## Draft review-note addition — do not submit with placeholder

```text
Physical-device demonstration for version 1.0.0 (2): [DEMO_VIDEO_URL]

The video shows MyStat on a physical device alongside the computer running the free companion, including initial local-network discovery/connection and the app workflow with live readings. MyStat has no sign-in and requires no demo credentials.
```

## Draft reply — not sent

```text
Hello App Review,

Thank you for your feedback on version 1.0.0 (2).

For guideline 5.2.5, we have changed the app name to “MyStat: Desk Monitor” and the subtitle to “Live CPU, memory & network,” removing the Apple product terms identified in the review.

For guideline 2.1, we have added a physical-device demonstration video to App Review Information: [DEMO_VIDEO_URL]

The video shows the app on a physical device and the computer running the companion together, including initial discovery/connection and the workflow with live readings. Both devices use the same local network. There is no sign-in or demo account requirement.

Thank you for reviewing the updated information.
```
