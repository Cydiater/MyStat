# Keep Awake from Spotlight

Install and launch a development- or Developer ID-signed MyStat build, then open
`Keep Awake.shortcut` and add it to Shortcuts. It contains one action:
**MyStat → Toggle Keep Awake**. **Show in Spotlight** is enabled.

Search for **Keep Awake** in Spotlight and run the shortcut. Each run switches
the current session on or off using MyStat's selected duration and display setting.

If Spotlight doesn't show the shortcut, run `./scripts/install-spotlight-launcher.sh`.
This installs **Keep Awake.app** in `~/Applications`, giving Spotlight an ordinary
application result. The launcher runs the saved shortcut and immediately exits;
MyStat continues holding the sleep assertion. Keep the shortcut named **Keep Awake**.

The exported shortcut contains no shell script, personal files, or account data.
Its only action targets the installed MyStat app. The optional launcher invokes
Apple's `/usr/bin/shortcuts run "Keep Awake"` command.
