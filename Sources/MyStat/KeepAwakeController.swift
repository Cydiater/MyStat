import AppKit
import IOKit.pwr_mgt

enum KeepAwakeStatus: Equatable {
    case off
    case indefinite
    case timed(seconds: Int, totalSeconds: Int)

    var remainingFraction: Double? {
        guard case .timed(let seconds, let totalSeconds) = self else { return nil }
        return min(1, max(0, Double(seconds) / Double(max(1, totalSeconds))))
    }

    var countdown: String? {
        switch self {
        case .off: return nil
        case .indefinite: return "∞"
        case .timed(let seconds, _):
            if seconds >= 3600 {
                return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            }
            return String(format: "%02d:%02d", seconds / 60, seconds % 60)
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .off: return "Keep Awake off"
        case .indefinite: return "Keep Awake on indefinitely"
        case .timed(let seconds, _):
            let parts = [(seconds / 3600, "hour"), (seconds / 60 % 60, "minute"), (seconds % 60, "second")]
                .filter { $0.0 > 0 }
                .map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
            return "Keep Awake: \(parts.isEmpty ? "0 seconds" : parts.joined(separator: ", ")) remaining"
        }
    }
}

protocol SleepAssertionProviding {
    func create(display: Bool, timeout: TimeInterval) throws -> IOPMAssertionID
    func release(_ id: IOPMAssertionID)
}

struct SystemSleepAssertions: SleepAssertionProviding {
    func create(display: Bool, timeout: TimeInterval) throws -> IOPMAssertionID {
        var id: IOPMAssertionID = 0
        let properties: [String: Any] = [
            kIOPMAssertionTypeKey: display ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep,
            kIOPMAssertionLevelKey: kIOPMAssertionLevelOn,
            kIOPMAssertionNameKey: display ? "MyStat keeping display on" : "MyStat keeping Mac awake",
            kIOPMAssertionTimeoutKey: timeout,
            kIOPMAssertionTimeoutActionKey: kIOPMAssertionTimeoutActionRelease
        ]
        let result = IOPMAssertionCreateWithProperties(properties as CFDictionary, &id)
        guard result == kIOReturnSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result),
                          userInfo: [NSLocalizedDescriptionKey: "macOS couldn't enable Keep Awake (\(result))."])
        }
        return id
    }

    func release(_ id: IOPMAssertionID) { IOPMAssertionRelease(id) }
}

/// An explicit session: remember preferences, but never resume a session on launch.
final class KeepAwakeController {
    // Access on the main thread, like the menu. Intent perform methods use
    // MainActor so both entry points control the same in-process session.
    static let shared = KeepAwakeController()

    enum Action { case start, stop, toggle }

    private struct ActionError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let durations = [0, 15, 30, 45, 60, 240, 480]
    static let labels = ["∞", "15m", "30m", "45m", "1h", "4h", "8h"]
    private let assertions: SleepAssertionProviding
    private let defaults: UserDefaults
    private let now: () -> Date
    private var ids: [IOPMAssertionID] = []
    private var timer: Timer?
    private var sessionDurationSeconds = 0
    private(set) var durationMinutes: Int
    private(set) var keepsDisplayOn: Bool
    private(set) var endsAt: Date?
    private(set) var errorMessage: String?
    var onChange: (() -> Void)?
    var isActive: Bool { !ids.isEmpty }
    var status: KeepAwakeStatus {
        guard isActive else { return .off }
        guard let endsAt else { return .indefinite }
        return .timed(seconds: max(0, Int(ceil(endsAt.timeIntervalSince(now())))), totalSeconds: sessionDurationSeconds)
    }

    init(assertions: SleepAssertionProviding = SystemSleepAssertions(), defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init) {
        self.assertions = assertions
        self.defaults = defaults
        self.now = now
        let saved = defaults.object(forKey: "keepAwake.durationMinutes") as? Int ?? 60
        durationMinutes = Self.durations.contains(saved) ? saved : 60
        keepsDisplayOn = defaults.object(forKey: "keepAwake.displayOn") as? Bool ?? true
    }

    deinit {
        timer?.invalidate()
        ids.forEach { assertions.release($0) }
    }

    func setActive(_ active: Bool) {
        if active { _ = start(minutes: durationMinutes, display: keepsDisplayOn) }
        else { stop() }
    }

    /// Run an external action using the menu's saved preferences and report
    /// assertion failures to the caller instead of claiming success.
    func perform(_ action: Action) throws {
        refresh()
        switch action {
        case .start: setActive(true)
        case .stop: stop()
        case .toggle: setActive(!isActive)
        }
        if let errorMessage { throw ActionError(message: errorMessage) }
    }

    func selectDuration(_ minutes: Int) {
        guard Self.durations.contains(minutes) else { return }
        refresh()
        // Changing the duration of a running session starts that duration now.
        if isActive && !start(minutes: minutes, display: keepsDisplayOn) { return }
        durationMinutes = minutes
        defaults.set(minutes, forKey: "keepAwake.durationMinutes")
        onChange?()
    }

    func setDisplayOn(_ enabled: Bool) {
        refresh()
        // Changing display behavior preserves the existing session's deadline.
        if isActive && !start(minutes: durationMinutes, display: enabled, preserving: endsAt) { return }
        keepsDisplayOn = enabled
        defaults.set(enabled, forKey: "keepAwake.displayOn")
        onChange?()
    }

    @discardableResult
    private func start(minutes: Int, display: Bool, preserving deadline: Date? = nil) -> Bool {
        let end = deadline ?? (minutes == 0 ? nil : now().addingTimeInterval(Double(minutes) * 60))
        let timeout = end.map { max(1, $0.timeIntervalSince(now())) } ?? 0
        var acquired: [IOPMAssertionID] = []
        do {
            acquired.append(try assertions.create(display: false, timeout: timeout))
            if display { acquired.append(try assertions.create(display: true, timeout: timeout)) }
        } catch {
            acquired.forEach { assertions.release($0) }
            errorMessage = error.localizedDescription
            onChange?()
            return false
        }
        // Acquire the replacement before releasing the old session. A failure
        // leaves the old session and its preferences intact, with an inline error.
        ids.forEach { assertions.release($0) }
        ids = acquired
        endsAt = end
        sessionDurationSeconds = minutes * 60
        errorMessage = nil
        timer?.invalidate()
        timer = nil
        if end != nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
            RunLoop.main.add(timer, forMode: .common)
            RunLoop.main.add(timer, forMode: .eventTracking)
            self.timer = timer
        }
        onChange?()
        return true
    }

    func refresh() {
        guard isActive, let endsAt else { return }
        if now() >= endsAt { stop() }
        else { onChange?() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        ids.forEach { assertions.release($0) }
        ids.removeAll()
        endsAt = nil
        sessionDurationSeconds = 0
        errorMessage = nil
        onChange?()
    }
}
