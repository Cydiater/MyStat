import Cocoa
import IOKit.pwr_mgt

final class FakeAssertions: SleepAssertionProviding {
    struct Request { let display: Bool; let timeout: TimeInterval }
    var held: [IOPMAssertionID: Request] = [:]
    var next: IOPMAssertionID = 1
    var failDisplay = false
    func create(display: Bool, timeout: TimeInterval) throws -> IOPMAssertionID {
        if display && failDisplay { throw NSError(domain: "test", code: 1) }
        defer { next += 1 }
        held[next] = Request(display: display, timeout: timeout)
        return next
    }
    func release(_ id: IOPMAssertionID) { held.removeValue(forKey: id) }
}

let domain = "com.cydiater.MyStat.keep-awake-tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: domain)!
defer { defaults.removePersistentDomain(forName: domain) }
let assertions = FakeAssertions()
var now = Date(timeIntervalSince1970: 1000)
let controller = KeepAwakeController(assertions: assertions, defaults: defaults, now: { now })
precondition(!controller.isActive && controller.keepsDisplayOn && controller.durationMinutes == 60)
controller.selectDuration(15)
precondition(!controller.isActive && assertions.held.isEmpty, "Selecting duration must not start a session")
controller.setActive(true)
precondition(controller.isActive && assertions.held.count == 2, "Must hold both system and display assertions")
precondition(assertions.held.values.contains { $0.display && $0.timeout == 900 })
let initialEnd = controller.endsAt!
now += 60
controller.setDisplayOn(false)
precondition(assertions.held.count == 1 && !assertions.held.values.first!.display)
precondition(controller.endsAt == initialEnd && assertions.held.values.first!.timeout == 840, "Display option must preserve time remaining")
precondition(controller.status.remainingFraction == 840.0 / 900)
assertions.failDisplay = true
let oldIDs = Set(assertions.held.keys)
controller.setDisplayOn(true)
precondition(controller.errorMessage != nil && !controller.keepsDisplayOn)
precondition(Set(assertions.held.keys) == oldIDs && controller.endsAt == initialEnd, "Failure must roll back partial assertions and preserve session")
precondition(controller.status.remainingFraction == 840.0 / 900, "Failed assertion changes must preserve progress")
assertions.failDisplay = false
controller.setDisplayOn(true)
precondition(controller.errorMessage == nil && assertions.held.count == 2)
controller.selectDuration(30)
precondition(controller.endsAt == now + 1800, "Changing active duration must restart the timer")
now += 1801
controller.refresh()
precondition(!controller.isActive && controller.endsAt == nil && assertions.held.isEmpty, "Expired sessions must release everything")
controller.selectDuration(0)
controller.setActive(true)
now += 100_000
controller.refresh()
precondition(controller.isActive && controller.endsAt == nil && assertions.held.values.allSatisfy { $0.timeout == 0 })
controller.stop()
precondition(assertions.held.isEmpty)
controller.stop()
assertions.failDisplay = true
controller.setActive(true)
precondition(!controller.isActive && assertions.held.isEmpty && controller.errorMessage != nil, "Failed start must leave the switch off")
let restored = KeepAwakeController(assertions: assertions, defaults: defaults)
precondition(!restored.isActive && restored.durationMinutes == 0 && restored.keepsDisplayOn, "Restore preferences only, never active sessions")
assertions.failDisplay = false
var disposable: KeepAwakeController? = KeepAwakeController(assertions: assertions, defaults: defaults)
disposable!.setActive(true)
disposable = nil
precondition(assertions.held.isEmpty, "Deinit must release assertions")
print("PASS: defaults, timed/indefinite sessions, restart, expiry, display mode, failure rollback, preference restore, cleanup")

// Countdown presentation follows the deadline, not the number of timer ticks.
do {
    let fake = FakeAssertions()
    var clock = Date(timeIntervalSince1970: 2000)
    let countdown = KeepAwakeController(assertions: fake, defaults: defaults, now: { clock })
    var updates: [KeepAwakeStatus] = []
    countdown.onChange = { [weak countdown] in
        if let status = countdown?.status { updates.append(status) }
    }
    precondition(countdown.status == .off && countdown.status.countdown == nil && countdown.status.remainingFraction == nil)
    countdown.selectDuration(60)
    countdown.setActive(true)
    precondition(updates.last?.countdown == "1:00:00", "Starting must immediately show the full duration")
    precondition(updates.last?.remainingFraction == 1, "A new session starts with a full progress bar")
    clock -= 20
    precondition(countdown.status.remainingFraction == 1, "Moving the clock back must not overflow the progress bar")
    clock += 20
    clock += 0.1
    countdown.refresh()
    precondition(updates.last?.countdown == "1:00:00", "Fractional seconds must round up")
    clock += 0.9
    updates.removeAll()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.2))
    precondition(updates.last?.countdown == "59:59", "The active timer must publish countdown changes")
    clock += 59
    countdown.refresh()
    precondition(updates.last?.countdown == "59:00")
    countdown.setDisplayOn(false)
    precondition(updates.last?.countdown == "59:00", "Display changes must not reset the countdown")
    countdown.selectDuration(15)
    precondition(updates.last?.countdown == "15:00", "Duration changes must immediately restart the countdown")
    precondition(updates.last?.remainingFraction == 1, "Changing duration must reset progress to full")
    clock += 450
    countdown.refresh()
    precondition(updates.last?.remainingFraction == 0.5, "Half the session remaining must produce half a bar")
    countdown.setDisplayOn(true)
    precondition(updates.last?.remainingFraction == 0.5, "Display changes must preserve progress")
    clock += 449.25
    countdown.refresh()
    precondition(updates.last?.countdown == "00:01", "Keep the final second visible until expiry")
    precondition(countdown.status.accessibilityDescription == "Keep Awake: 1 second remaining")
    clock += 0.75
    countdown.refresh()
    precondition(updates.last == .off && countdown.status.countdown == nil && fake.held.isEmpty,
                 "At the deadline, remove the countdown and release assertions together")
    let expiredUpdateCount = updates.count
    countdown.refresh()
    precondition(updates.count == expiredUpdateCount, "Inactive sessions must not publish timer updates")
    countdown.selectDuration(480)
    countdown.setActive(true)
    precondition(updates.last?.countdown == "8:00:00")
    countdown.selectDuration(0)
    precondition(updates.last == .indefinite && countdown.status.countdown == "∞")
    precondition(countdown.status.remainingFraction == nil, "Untimed sessions must not show timed progress")
    clock += 100_000
    countdown.refresh()
    precondition(countdown.status == .indefinite, "Untimed sessions must keep their infinity indicator")
    countdown.stop()
    precondition(updates.last == .off && countdown.status.countdown == nil)
}
print("PASS: immediate countdown updates, timer ticks, hour/minute boundaries, rounding, expiry, restart, infinity, stop")

// Keep the active indicator small and stable across timed and untimed sessions.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let inactive = StatusBarRenderer.render(cpu: [], memory: [], capacity: 2)
for status in [KeepAwakeStatus.timed(seconds: 28800, totalSeconds: 28800),
               .timed(seconds: 450, totalSeconds: 900), .timed(seconds: 1, totalSeconds: 900), .indefinite] {
    let image = StatusBarRenderer.render(cpu: [], memory: [], capacity: 2, keepAwake: status)
    precondition(image.size.width - inactive.size.width == 23, "Keep Awake must occupy only 23 extra points")
    precondition(image.isTemplate && image.size.height == inactive.size.height, "Preserve native menu-bar tint and sizing")
}
print("PASS: remaining progress, preserved deadlines, compact and stable menu-bar width")

// Exercise IOKit itself briefly, without changing any persistent power settings.
let system = SystemSleepAssertions()
let systemID = try system.create(display: false, timeout: 5)
let displayID = try system.create(display: true, timeout: 2)
defer { system.release(systemID); system.release(displayID) }
func properties(_ id: IOPMAssertionID) -> NSDictionary? {
    IOPMAssertionCopyProperties(id)?.takeRetainedValue() as NSDictionary?
}
precondition(properties(systemID)?[kIOPMAssertionTypeKey] as? String == kIOPMAssertionTypePreventUserIdleSystemSleep)
precondition(properties(displayID)?[kIOPMAssertionTypeKey] as? String == kIOPMAssertionTypePreventUserIdleDisplaySleep)
precondition(properties(displayID)?[kIOPMAssertionLevelKey] as? Int == kIOPMAssertionLevelOn)
RunLoop.main.run(until: Date(timeIntervalSinceNow: 3))
precondition(properties(displayID) == nil, "macOS must release the assertion at its deadline without an app timer")
system.release(systemID)
precondition(properties(systemID) == nil)
print("PASS: real macOS system/display assertions, native timeout, explicit release")
