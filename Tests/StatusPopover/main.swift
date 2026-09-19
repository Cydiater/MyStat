import Cocoa

// Run with scripts/test-status-popover.sh. This exercises the real assembled
// dropdown after AppKit has laid it out, including a device-list rebuild.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let menu = NSMenu()
let range = NSView(frame: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: 46))
let charts = NSView(frame: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: DashboardStyle.chartHeight * 2))
let domain = "com.cydiater.MyStat.popover-tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: domain)!
defer { defaults.removePersistentDomain(forName: domain) }
let awakeController = KeepAwakeController(defaults: defaults)
let awake = KeepAwakeView(controller: awakeController)
for view in [range, charts, awake] {
    let item = NSMenuItem()
    item.view = view
    menu.addItem(item)
}
menu.addItem(.separator())
let details = NSView(frame: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: DashboardStyle.detailsHeight))
let detailsMenu = NSMenu(title: "Details")
let detailsItem = NSMenuItem()
detailsItem.view = details
detailsMenu.addItem(detailsItem)
let sharingMenu = NSMenu(title: "iPhone")
let sharing = NSMenuItem(title: "iPhone sharing available", action: nil, keyEquivalent: "")
sharing.isEnabled = false
sharingMenu.addItem(sharing)
let settingsMenu = NSMenu(title: "Settings")
final class Actions: NSObject, NSMenuItemValidation {
    var count = 0
    var enabled = true
    @objc func toggle(_ item: NSMenuItem) { item.state = item.state == .on ? .off : .on; count += 1 }
    func validateMenuItem(_ item: NSMenuItem) -> Bool { enabled }
}
let actions = Actions()
let setting = NSMenuItem(title: "Launch at Login", action: #selector(Actions.toggle(_:)), keyEquivalent: "q")
setting.target = actions
settingsMenu.addItem(setting)
for page in [detailsMenu, sharingMenu, settingsMenu] {
    let item = NSMenuItem(title: page.title, action: nil, keyEquivalent: "")
    item.submenu = page
    menu.addItem(item)
}
let popover = NSPopover()
let dropdown = StatusPopover(menu: menu, popover: popover)
awake.onHeightChange = { dropdown.refresh() }
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: 750), styleMask: [.borderless], backing: .buffered, defer: false)
var pageChanges: [Bool] = []
dropdown.onPageChange = { pageChanges.append($0) }

func mountPage() -> NSView {
    dropdown.refresh()
    window.contentView = popover.contentViewController!.view
    window.contentView!.layoutSubtreeIfNeeded()
    menu.update()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    let document = (window.contentView as! NSScrollView).documentView!
    let frames = document.subviews.map(\.frame).sorted { $0.minY < $1.minY }
    for (lower, upper) in zip(frames, frames.dropFirst()) {
        precondition(lower.maxY <= upper.minY + 0.5, "Rows overlap: \(lower) / \(upper)")
    }
    return document
}
func descendants(_ view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants($0) }
}
func button(_ title: String, in root: NSView? = nil) -> NSButton {
    descendants(root ?? popover.contentViewController!.view).compactMap { $0 as? NSButton }.first {
        $0.title.trimmingCharacters(in: .whitespaces) == title
    }!
}
func verifyLayout(_ name: String) {
    let document = mountPage()
    precondition(dropdown.isShowingOverview && details.superview == nil, "Details leaked into overview")
    precondition(charts.superview === document && range.superview === document && awake.superview === document, "Lost custom views on rebuild")
    precondition(charts.frame.height == DashboardStyle.chartHeight * 2 && range.frame.height == 46, "Custom view resized")
    precondition(abs(range.frame.maxY - (document.bounds.maxY - 8)) < 0.5, "Range control is not at the top")
    precondition(abs(charts.frame.maxY - range.frame.minY) < 0.5, "Blank space above charts")
    print("PASS: \(name), overview height=\(document.frame.height)")
}
verifyLayout("compact overview")
let compactHeight = popover.contentSize.height
precondition(compactHeight <= 540, "Overview should fit without the old full dashboard")
let originalCharts = charts.frame
sharingMenu.addItem(withTitle: "iPhone Air", action: nil, keyEquivalent: "")
verifyLayout("device connected while hidden")
precondition(charts.frame == originalCharts, "Connected devices must not change the overview layout")
button("iPhone").performClick(nil)
let connectedPage = mountPage()
precondition(!dropdown.isShowingOverview && charts.superview == nil, "Overview must leave the window on a detail page")
precondition(descendants(connectedPage).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "iPhone Air" }, "Device names should be readable labels")
sharingMenu.removeItem(at: 1)
let phonePage = mountPage()
precondition(!descendants(phonePage).compactMap({ $0 as? NSTextField }).contains { $0.stringValue == "iPhone Air" }, "Disconnected device remained visible")
sharing.title = "iPhone sharing: waiting for network"
dropdown.refresh()
precondition(descendants(phonePage).compactMap { $0 as? NSTextField }.contains { $0.stringValue == sharing.title }, "Sharing status must refresh on its page")
button("Back").performClick(nil)
verifyLayout("back from iPhone")
button("Details").performClick(nil)
let detailsPage = mountPage()
precondition(details.superview === detailsPage && range.superview == nil, "Details must own its page")
for _ in 0..<3 { dropdown.refresh() }
precondition(details.superview === detailsPage, "Routine refresh should preserve the current page")
button("Back").performClick(nil)
verifyLayout("back from details")
button("Keep Awake", in: awake).performClick(nil)
verifyLayout("Keep Awake options expanded")
precondition(awake.isExpanded && popover.contentSize.height == compactHeight + 88, "Expanded options must resize the popover")
let durations = descendants(awake).compactMap { $0 as? NSSegmentedControl }.first!
durations.selectedSegment = KeepAwakeController.durations.firstIndex(of: 30)!
durations.sendAction(durations.action, to: durations.target)
button("Keep Awake", in: awake).performClick(nil)
verifyLayout("Keep Awake options collapsed")
precondition(!awake.isExpanded && popover.contentSize.height == compactHeight && awakeController.durationMinutes == 30, "Collapsing must preserve preferences")
button("Settings").performClick(nil)
_ = mountPage()
button("Launch at Login").performClick(nil)
precondition(setting.state == .on && actions.count == 1, "Nested actions must be dispatched")
actions.enabled = false
dropdown.refresh()
precondition(!button("✓  Launch at Login").isEnabled, "Nested action validation must update")
actions.enabled = true
button("Back").performClick(nil)
verifyLayout("back from settings")
precondition(pageChanges == [false, true, false, true, false, true], "Page lifecycle callbacks must track navigation")
print("All popover hierarchy and layout checks passed")

let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
let panelSize = NSSize(width: 284, height: 222)
for x: CGFloat in [0, 500, 1080] {
    let parent = NSRect(x: x, y: 50, width: 360, height: 750)
    let chart = NSRect(x: x + 8, y: 650, width: 344, height: 124)
    let side = ProcessPanelPlacement.frame(parent: parent, chart: chart, screen: screen, size: panelSize)!
    precondition(!side.intersects(parent), "Side panel covers dashboard")
    precondition(screen.contains(side), "Side panel extends beyond screen")
    if x == 0 { precondition(side.minX >= parent.maxX) }
    if x == 1080 { precondition(side.maxX <= parent.minX) }
}
let leftScreen = NSRect(x: -1280, y: -100, width: 1280, height: 800)
let parent = NSRect(x: -370, y: 0, width: 360, height: 600)
let lowChart = NSRect(x: -360, y: -90, width: 340, height: 124)
let side = ProcessPanelPlacement.frame(parent: parent, chart: lowChart, screen: leftScreen, size: panelSize)!
precondition(leftScreen.contains(side) && !side.intersects(parent), "Secondary screen placement failed")
let narrow = ProcessPanelPlacement.frame(parent: NSRect(x: 230, y: 0, width: 360, height: 700), chart: lowChart,
    screen: NSRect(x: 0, y: 0, width: 820, height: 700), size: panelSize)!
precondition(narrow.width == 222, "Panel should fit available side space")
precondition(ProcessPanelPlacement.frame(parent: NSRect(x: 100, y: 0, width: 360, height: 600), chart: lowChart,
    screen: NSRect(x: 0, y: 0, width: 560, height: 600), size: panelSize) == nil, "Never overlap when neither side fits")
print("All side-panel placement checks passed")

// Exercise the mouse-down / mouse-up ordering of a transient popover. AppKit
// asks to close it before the status button delivers its mouse-up action.
let toggleMenu = NSMenu()
toggleMenu.addItem(withTitle: "Toggle regression check", action: nil, keyEquivalent: "")
let togglePopover = NSPopover()
let toggleDropdown = StatusPopover(menu: toggleMenu, popover: togglePopover)
let visibleFrame = NSScreen.main!.visibleFrame
let anchorWindow = NSWindow(
    contentRect: NSRect(x: visibleFrame.midX, y: visibleFrame.maxY - 80, width: 140, height: 40),
    styleMask: [.borderless], backing: .buffered, defer: false
)
let anchor = NSButton(frame: NSRect(x: 20, y: 5, width: 100, height: 30))
anchorWindow.contentView!.addSubview(anchor)
anchorWindow.orderFrontRegardless()
defer { anchorWindow.orderOut(nil) }
let anchorFrame = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
let anchorPoint = NSPoint(x: anchorFrame.midX, y: anchorFrame.midY)
let outsidePoint = NSPoint(x: anchorWindow.frame.minX + 2, y: anchorWindow.frame.midY)
var closeCount = 0
toggleDropdown.onClose = { closeCount += 1 }

for click in 1...6 {
    toggleDropdown.toggle(relativeTo: anchor)
    precondition(togglePopover.isShown, "Click \(click): popover did not open")
    for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        // Simulate AppKit's automatic close attempt before the button action.
        if toggleDropdown.shouldClose(for: eventType, at: anchorPoint) {
            togglePopover.performClose(nil)
        }
    }
    toggleDropdown.toggle(relativeTo: anchor)
    precondition(!togglePopover.isShown, "Click \(click): popover reopened instead of closing")
    precondition(closeCount == click, "Click \(click): close callback did not run exactly once")
}
print("PASS: repeated status-button clicks close without reopening")

toggleDropdown.toggle(relativeTo: anchor)
precondition(toggleDropdown.shouldClose(for: .leftMouseDown, at: outsidePoint), "Outside clicks must still dismiss")
precondition(toggleDropdown.shouldClose(for: .rightMouseDown, at: anchorPoint), "Right-click must not wait for a left-click action")
precondition(toggleDropdown.shouldClose(for: .keyDown, at: anchorPoint), "Escape must still dismiss with the pointer over the button")
precondition(toggleDropdown.shouldClose(for: nil, at: anchorPoint), "Non-mouse dismissal must still work")
togglePopover.performClose(nil)
precondition(!togglePopover.isShown && closeCount == 7, "Normal dismissal failed")

toggleDropdown.toggle(relativeTo: anchor)
let popoverWindow = togglePopover.contentViewController!.view.window!
let child = NSPanel(
    contentRect: NSRect(x: visibleFrame.minX + 10, y: visibleFrame.minY + 10, width: 180, height: 100),
    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
)
popoverWindow.addChildWindow(child, ordered: .above)
child.orderFrontRegardless()
let childPoint = NSPoint(x: child.frame.midX, y: child.frame.midY)
for eventType in [NSEvent.EventType.leftMouseDown, .rightMouseDown] {
    precondition(!toggleDropdown.shouldClose(for: eventType, at: childPoint), "Process-panel clicks must keep the dropdown open")
}
toggleDropdown.onClose = {
    closeCount += 1
    child.parent?.removeChildWindow(child)
    child.orderOut(nil)
}
toggleDropdown.toggle(relativeTo: anchor)
precondition(!togglePopover.isShown && !child.isVisible, "Explicit toggle must close the dropdown and its process panel")
precondition(closeCount == 8, "Process-panel close callback must run exactly once")
toggleDropdown.toggle(relativeTo: anchor)
precondition(togglePopover.isShown, "Popover must reopen after closing a process panel")
toggleDropdown.toggle(relativeTo: anchor)
precondition(!togglePopover.isShown && closeCount == 9, "Popover must remain toggleable after reopening")
print("All popover interaction checks passed")

// Keyboard navigation and shortcuts also work when their controls are hidden.
window.contentView = nil
dropdown.toggle(relativeTo: anchor)
button("Details").performClick(nil)
precondition(popover.isShown && !dropdown.isShowingOverview)
let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
    windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
precondition(dropdown.handleKeyDown(escape) && dropdown.isShowingOverview && popover.isShown, "Escape should return from a secondary page")
precondition(!dropdown.handleKeyDown(escape), "Overview Escape must remain available to the popover and process panel")
let commandQ = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
    windowNumber: 0, context: nil, characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12)!
precondition(dropdown.handleKeyDown(commandQ) && actions.count == 2, "Shortcuts must reach actions inside hidden pages")
button("iPhone").performClick(nil)
dropdown.toggle(relativeTo: anchor)
precondition(!popover.isShown, "Menu button must close a secondary page")
dropdown.toggle(relativeTo: anchor)
precondition(popover.isShown && dropdown.isShowingOverview, "Reopening must start on the overview")
dropdown.toggle(relativeTo: anchor)
print("PASS: Escape, hidden command shortcuts, dismissal from a detail page, and reopening at overview")
