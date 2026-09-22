import AppKit

// A normal application search result for Macs where Spotlight doesn't surface
// App Intents. Shortcuts routes the action to MyStat's existing live session.
let runner = Process()
runner.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
runner.arguments = ["run", "Keep Awake"]
let errors = Pipe()
runner.standardError = errors

do {
    try runner.run()
    let details = errors.fileHandleForReading.readDataToEndOfFile()
    runner.waitUntilExit()
    if runner.terminationStatus != 0 {
        throw NSError(domain: "MyStat.KeepAwakeLauncher", code: Int(runner.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: String(data: details, encoding: .utf8) ?? "The shortcut could not run."])
    }
} catch {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "Couldn't run Keep Awake"
    alert.informativeText = "Install MyStat and import the Keep Awake shortcut first.\n\n\(error.localizedDescription)"
    alert.runModal()
    exit(1)
}
