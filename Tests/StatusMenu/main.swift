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
    func create(display: Bool, timeout: TimeInterval) throws -> IOPMAssertionID { defer { next += 1 }; return next }
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
let awakeController = KeepAwakeController(assertions: FakeAssertions(), defaults: defaults, now: { now })
let awake = KeepAwakeView(controller: awakeController)
var awakeUpdates = 0
awakeController.onChange = { [weak awake] in awake?.refresh(); awakeUpdates += 1 }
awakeController.selectDuration(15)
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
let awakeItem = NSMenuItem()
awakeItem.view = awake
menu.addItem(awakeItem)
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
var expanded = false
var collapsed = false
let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
    guard chart.window != nil else { return }
    precondition(chart.enclosingMenuItem === chartItem && awake.enclosingMenuItem === awakeItem,
                 "AppKit must own the custom-view layout")
    precondition(chart.frame.height == DashboardStyle.chartHeight)
    if !mounted {
        mounted = true
        let heading = awake.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Keep Awake" }!
        heading.performClick(nil)
        expanded = awake.isExpanded && awake.frame.height == 146
        heading.performClick(nil)
        collapsed = !awake.isExpanded && awake.frame.height == 58
        now += 10
    }
    // Wait for the actual one-second Keep Awake timer in menu-tracking mode.
    if awakeUpdates > updatesBeforeTracking {
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
precondition(mounted && expanded && collapsed, "Keep Awake options must work in the native menu")
precondition(awakeUpdates > updatesBeforeTracking + 1, "Countdown must keep ticking while the menu tracks")
precondition(lifecycle.opened == 1 && lifecycle.closed == 1)
precondition(chartItem.view === chart && awakeItem.view === awake, "Closing must preserve custom views")
print("PASS: native menu lifecycle, custom chart layout, Keep Awake expansion, and countdown during menu tracking")
