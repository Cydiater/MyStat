import Foundation
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
assertions.failDisplay = true
let oldIDs = Set(assertions.held.keys)
controller.setDisplayOn(true)
precondition(controller.errorMessage != nil && !controller.keepsDisplayOn)
precondition(Set(assertions.held.keys) == oldIDs && controller.endsAt == initialEnd, "Failure must roll back partial assertions and preserve session")
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
