import Cocoa
import MyStatCore
import IOKit.pwr_mgt

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let cpu = ProcessMenu(metric: .cpu)
let memory = ProcessMenu(metric: .memory)
let process = ProcessUsage(pid: getpid(), name: "Menu Test", cpuPercent: 24.5, residentBytes: 1_000_000_000)
let snapshot = ProcessSnapshot(sampledAt: .now, topCPU: [process], topMemory: [process])
cpu.update(snapshot)
memory.update(snapshot)
for list in [cpu, memory] {
    precondition(list.item.view == nil && list.item.submenu === list.menu, "Process navigation must use a native submenu item")
    let row = list.menu.items.first!
    precondition(!row.isHidden && row.image != nil && row.toolTip!.contains("PID \(getpid())"))
    if #available(macOS 27.0, *) {
        precondition(list.menu.items.prefix(5).allSatisfy { $0.preferredImageVisibility == .visible },
                     "Process icons must stay visible instead of following AppKit's automatic hiding policy")
    }
    precondition(list.menu.items.dropFirst().prefix(4).allSatisfy(\.isHidden), "Hide empty process slots")
    if #available(macOS 14.0, *) {
        precondition(row.title == "Menu Test" && row.badge?.stringValue == (list === cpu ? "24.5%" : MetricFormat.bytes(process.residentBytes)))
    }
}
let firstCPU = cpu.menu.items.first!
cpu.update(ProcessSnapshot(sampledAt: Date(timeIntervalSinceNow: -30), topCPU: [process], topMemory: []))
precondition(cpu.menu.items.first === firstCPU, "Live updates must keep menu rows stable")
precondition(cpu.menu.items.last!.title.contains("stale") && firstCPU.toolTip!.contains("Stale"))
cpu.update(nil)
precondition(firstCPU.isHidden && cpu.menu.items.contains { !$0.isHidden && $0.title == "Readings unavailable" })
cpu.update(snapshot)
print("PASS: native process menus, value badges, icons, empty/stale readings, stable updates")

final class FakeAssertions: SleepAssertionProviding {
    var next: IOPMAssertionID = 1
    var fails = false
    func create(display: Bool, timeout: TimeInterval) throws -> IOPMAssertionID {
        if fails { throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Assertion unavailable"]) }
        defer { next += 1 }
        return next
    }
    func release(_ id: IOPMAssertionID) {}
}
final class Actions: NSObject, NSMenuItemValidation {
    var count = 0
    var enabled = true
    @objc func toggle(_ item: NSMenuItem) { item.state = item.state == .on ? .off : .on; count += 1 }
    func validateMenuItem(_ item: NSMenuItem) -> Bool { enabled }
}
final class MenuLifecycle: NSObject, NSMenuDelegate {
    var opened = 0
    var closed = 0
    func menuWillOpen(_ menu: NSMenu) { opened += 1 }
    func menuDidClose(_ menu: NSMenu) { closed += 1 }
}
let domain = "com.cydiater.MyStat.native-menu-tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: domain)!
defer { defaults.removePersistentDomain(forName: domain) }
var now = Date()
let assertions = FakeAssertions()
let awakeController = KeepAwakeController(assertions: assertions, defaults: defaults, now: { now })
let awake = KeepAwakeMenu(controller: awakeController)
var awakeUpdates = 0
awakeController.onChange = { [weak awake] in awake?.refresh(); awakeUpdates += 1 }
precondition(awake.item.view == nil && awake.item.submenu === awake.menu)
precondition(awake.menu.items.allSatisfy { $0.view == nil && $0.submenu == nil }, "Keep Awake must use native rows in one submenu")
func chooseAwake(_ title: String) {
    let index = awake.menu.items.firstIndex { $0.title == title }!
    awake.menu.performActionForItem(at: index)
}
func awakeChoice(_ title: String) -> NSMenuItem { awake.menu.items.first { $0.title == title }! }
func expectAwakeSummary(_ summary: String) {
    if #available(macOS 14.0, *) { precondition(awake.item.badge?.stringValue == summary) }
    else { precondition(awake.item.title == "Keep Awake — \(summary)") }
}
expectAwakeSummary("Off")
chooseAwake("30 Minutes")
precondition(!awakeController.isActive && defaults.integer(forKey: "keepAwake.durationMinutes") == 30,
             "Choosing a duration while off must save it without starting a session")
precondition(awakeChoice("30 Minutes").state == .on && awakeChoice("1 Hour").state == .off)
chooseAwake("Keep Awake")
precondition(awakeController.isActive && awake.item.state == .on && awakeChoice("Keep Awake").state == .on)
let deadline = awakeController.endsAt
now += 10
awakeController.refresh()
expectAwakeSummary("29:50")
chooseAwake("Keep Display On")
precondition(!awakeController.keepsDisplayOn && awakeChoice("Keep Display On").state == .off && awakeController.endsAt == deadline,
             "Changing the display option must preserve the deadline")
assertions.fails = true
// Exercise error presentation without opening a modal alert in this test.
awakeController.selectDuration(60)
expectAwakeSummary("Error")
precondition(awake.item.toolTip == "Assertion unavailable" && awake.item.state == .on)
precondition(awakeChoice("30 Minutes").state == .on && awakeChoice("1 Hour").state == .off,
             "A failed duration change must preserve the selected preset")
assertions.fails = false
chooseAwake("15 Minutes")
precondition(awakeController.endsAt == now.addingTimeInterval(900), "Changing duration must restart the active session")
expectAwakeSummary("15:00")
chooseAwake("Keep Awake")
precondition(!awakeController.isActive && awake.item.state == .off)
expectAwakeSummary("Off")
chooseAwake("Until Turned Off")
chooseAwake("Keep Awake")
precondition(awakeController.isActive && awakeController.endsAt == nil && awakeChoice("Until Turned Off").state == .on)
expectAwakeSummary("∞")
chooseAwake("15 Minutes")
now += 900
awake.menuWillOpen(awake.menu)
precondition(!awakeController.isActive && awakeChoice("Keep Awake").state == .off,
             "Opening the submenu must clear an expired session")
expectAwakeSummary("Off")
print("PASS: native Keep Awake cascade, toggle, duration checkmarks, saved preferences, display deadline, errors, and expiry")
let menu = NSMenu(title: "MyStat")
menu.autoenablesItems = false
menu.minimumWidth = DashboardStyle.width
let lifecycle = MenuLifecycle()
menu.delegate = lifecycle
let chart = StatsChartView(frame: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: DashboardStyle.chartHeight))
chart.title = "CPU"
chart.update(values: [10, 20, 15], capacity: 3, subtitle: "System utilization")
let chartItem = NSMenuItem(title: "CPU", action: nil, keyEquivalent: "")
chartItem.view = chart
menu.addItem(chartItem)
menu.addItem(cpu.item)
menu.addItem(memory.item)
menu.addItem(awake.item)
menu.addItem(.separator())
let actions = Actions()
let settings = NSMenu(title: "Settings")
let toggle = NSMenuItem(title: "Example Setting", action: #selector(Actions.toggle(_:)), keyEquivalent: "q")
toggle.target = actions
settings.addItem(toggle)
let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
settingsItem.submenu = settings
menu.addItem(settingsItem)
settings.update()
precondition(toggle.isEnabled)
actions.enabled = false
settings.update()
precondition(!toggle.isEnabled, "AppKit must validate native actions")
actions.enabled = true
settings.update()
let commandQ = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
    windowNumber: 0, context: nil, characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12)!
precondition(menu.performKeyEquivalent(with: commandQ) && actions.count == 1 && toggle.state == .on,
             "Native shortcuts and checkmarks must work inside unopened submenus")
print("PASS: native action validation, nested keyboard shortcuts, and checkmark state")

let window = NSWindow(contentRect: NSRect(x: 300, y: 100, width: 400, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
let anchor = NSButton(frame: NSRect(x: 0, y: 460, width: 160, height: 30))
window.contentView!.addSubview(anchor)
window.orderFrontRegardless()
defer { window.orderOut(nil) }
awakeController.setActive(true)
let updatesBeforeTracking = awakeUpdates
var mounted = false
var countdownUpdated = false
let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
    guard chart.window != nil else { return }
    precondition(chart.enclosingMenuItem === chartItem, "AppKit must own the custom-view layout")
    precondition(chart.frame.height == DashboardStyle.chartHeight)
    if !mounted {
        mounted = true
        now += 10
    }
    // Wait for the actual one-second Keep Awake timer in menu-tracking mode.
    if awakeUpdates > updatesBeforeTracking {
        expectAwakeSummary("14:50")
        countdownUpdated = true
        menu.cancelTrackingWithoutAnimation()
    }
}
RunLoop.main.add(timer, forMode: .eventTracking)
let timeout = Timer(timeInterval: 3, repeats: false) { _ in menu.cancelTrackingWithoutAnimation() }
RunLoop.main.add(timeout, forMode: .eventTracking)
menu.popUp(positioning: nil, at: .zero, in: anchor)
timer.invalidate()
timeout.invalidate()
awakeController.stop()
precondition(mounted && countdownUpdated, "Keep Awake's parent status must update during menu tracking")
precondition(awakeUpdates > updatesBeforeTracking + 1, "Countdown must keep ticking while the menu tracks")
precondition(lifecycle.opened == 1 && lifecycle.closed == 1)
precondition(chartItem.view === chart && awake.item.submenu === awake.menu, "Closing must preserve charts and submenus")
print("PASS: native menu lifecycle, custom chart layout, and Keep Awake status during menu tracking")
