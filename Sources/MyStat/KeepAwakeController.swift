import Foundation
import IOKit.pwr_mgt

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
    static let durations = [0, 15, 30, 45, 60, 240, 480]
    static let labels = ["∞", "15m", "30m", "45m", "1h", "4h", "8h"]
    private let assertions: SleepAssertionProviding
    private let defaults: UserDefaults
    private let now: () -> Date
    private var ids: [IOPMAssertionID] = []
    private var timer: Timer?
    private(set) var durationMinutes: Int
    private(set) var keepsDisplayOn: Bool
    private(set) var endsAt: Date?
    private(set) var errorMessage: String?
    var onChange: (() -> Void)?
    var isActive: Bool { !ids.isEmpty }

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
        errorMessage = nil
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        onChange?()
        return true
    }

    func refresh() {
        if isActive, let endsAt, now() >= endsAt { stop() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        ids.forEach { assertions.release($0) }
        ids.removeAll()
        endsAt = nil
        errorMessage = nil
        onChange?()
    }
}
