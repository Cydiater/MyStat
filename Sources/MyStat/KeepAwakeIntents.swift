import AppIntents

// Foreground execution launches the long-lived menu-bar app when needed, so
// its sleep assertions survive after Spotlight or Shortcuts finishes the action.
@available(macOS 13.0, *)
struct StartKeepAwakeIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Keep Awake"
    static var description = IntentDescription("Keep your Mac awake using MyStat's selected duration and display setting. Starts a new timer if already active.")
    static var openAppWhenRun: Bool = true
    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult {
        try KeepAwakeController.shared.perform(.start)
        return .result()
    }
}

@available(macOS 13.0, *)
struct StopKeepAwakeIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Keep Awake"
    static var description = IntentDescription("End MyStat's Keep Awake session and allow normal idle sleep.")
    static var openAppWhenRun: Bool = true
    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult {
        try KeepAwakeController.shared.perform(.stop)
        return .result()
    }
}

@available(macOS 13.0, *)
struct ToggleKeepAwakeIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Keep Awake"
    static var description = IntentDescription("Turn MyStat's Keep Awake on or off using the selected duration and display setting.")
    static var openAppWhenRun: Bool = true
    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult {
        try KeepAwakeController.shared.perform(.toggle)
        return .result()
    }
}

@available(macOS 13.0, *)
struct KeepAwakeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartKeepAwakeIntent(),
            phrases: ["Start Keep Awake in \(.applicationName)", "Keep my Mac awake with \(.applicationName)"],
            shortTitle: "Start Keep Awake",
            systemImageName: "cup.and.saucer.fill"
        )
        AppShortcut(
            intent: StopKeepAwakeIntent(),
            phrases: ["Stop Keep Awake in \(.applicationName)"],
            shortTitle: "Stop Keep Awake",
            systemImageName: "moon.zzz"
        )
        AppShortcut(
            intent: ToggleKeepAwakeIntent(),
            phrases: ["Toggle Keep Awake in \(.applicationName)"],
            shortTitle: "Toggle Keep Awake",
            systemImageName: "power"
        )
    }
}
