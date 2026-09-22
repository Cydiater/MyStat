import AppIntents
import Foundation

@main
struct KeepAwakeIntentTests {
    @MainActor
    static func main() async throws {
        guard #available(macOS 13.0, *) else { return }
        let controller = KeepAwakeController.shared
        let duration = controller.durationMinutes
        let display = controller.keepsDisplayOn
        defer { controller.stop() }

        _ = try await StartKeepAwakeIntent().perform()
        precondition(controller.isActive, "The Start intent must activate the shared controller")
        _ = try await ToggleKeepAwakeIntent().perform()
        precondition(!controller.isActive, "The Toggle intent must stop the same shared session")
        _ = try await ToggleKeepAwakeIntent().perform()
        precondition(controller.isActive, "The Toggle intent must also start a session")
        _ = try await StopKeepAwakeIntent().perform()
        _ = try await StopKeepAwakeIntent().perform()
        precondition(!controller.isActive, "The Stop intent must be safe when already stopped")
        controller.setActive(true)
        _ = try await StopKeepAwakeIntent().perform()
        precondition(!controller.isActive, "The Stop intent must stop menu-started sessions")
        precondition(controller.durationMinutes == duration && controller.keepsDisplayOn == display,
                     "Running intents must preserve the user's settings")
        print("PASS: real intent handlers share the menu controller and preserve preferences")

        if CommandLine.arguments.count > 1 {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let metadata = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let actions = metadata["actions"] as! [String: [String: Any]]
            let expected = Set(["StartKeepAwakeIntent", "StopKeepAwakeIntent", "ToggleKeepAwakeIntent"])
            precondition(Set(actions.keys) == expected, "The bundle must expose all three actions")
            for action in actions.values {
                precondition(action["isDiscoverable"] as? Bool == true)
                precondition(action["openAppWhenRun"] as? Bool == true,
                             "Intent execution must launch the persistent menu-bar app")
                precondition((action["parameters"] as? [Any])?.isEmpty == true,
                             "Keep Awake actions must run without a parameter prompt")
            }
            let shortcuts = metadata["autoShortcuts"] as! [[String: Any]]
            precondition(Set(shortcuts.compactMap { $0["actionIdentifier"] as? String }) == expected)
            print("PASS: packaged metadata exposes three discoverable, ready-to-run App Shortcuts")
        }
    }
}
