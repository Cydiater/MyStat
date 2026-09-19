import Cocoa

// Run with scripts/test-status-popover.sh. This exercises the real assembled
// dropdown after AppKit has laid it out, including a device-list rebuild.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let menu = NSMenu()
let range = NSView(frame: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: 30))
let charts = NSView(frame: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: DashboardStyle.detailsHeight + DashboardStyle.chartHeight * 2))
for view in [range, charts] {
    let item = NSMenuItem()
    item.view = view
    menu.addItem(item)
}
menu.addItem(.separator())
let sharing = NSMenuItem(title: "iPhone sharing available", action: nil, keyEquivalent: "")
menu.addItem(sharing)
let awake = KeepAwakeView(controller: KeepAwakeController())
let awakeItem = NSMenuItem()
awakeItem.view = awake
menu.addItem(awakeItem)
for title in ["Launch at Login", "About MyStat", "Check for Updates…", "Automatically Check for Updates", "Quit MyStat"] {
    menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
}
let popover = NSPopover()
let dropdown = StatusPopover(menu: menu, popover: popover)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: 750), styleMask: [.borderless], backing: .buffered, defer: false)

func verifyLayout(_ name: String) {
    dropdown.refresh()
    window.contentView = popover.contentViewController!.view
    window.contentView!.layoutSubtreeIfNeeded()
    menu.update()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    let scroll = window.contentView as! NSScrollView
    let document = scroll.documentView!
    let frames = document.subviews.map(\.frame).sorted { $0.minY < $1.minY }
    precondition(charts.superview === document && range.superview === document && awake.superview === document, "Lost custom views on rebuild")
    precondition(charts.frame.height == DashboardStyle.detailsHeight + DashboardStyle.chartHeight * 2 && range.frame.height == 30, "Custom view resized")
    for (lower, upper) in zip(frames, frames.dropFirst()) {
        precondition(lower.maxY <= upper.minY + 0.5, "\(name): rows overlap: \(lower) / \(upper)")
    }
    precondition(abs(range.frame.maxY - (document.bounds.maxY - 8)) < 0.5, "Range control is not at the top")
    precondition(abs(charts.frame.maxY - range.frame.minY) < 0.5, "Blank space above charts")
    print("PASS: \(name), charts=\(charts.frame), range=\(range.frame)")
}
verifyLayout("initial dropdown")
let originalCharts = charts.frame
menu.insertItem(withTitle: "iPhone Air", action: nil, keyEquivalent: "", at: 3)
verifyLayout("device connected")
precondition(charts.frame.minY == originalCharts.minY + 23, "Device row did not reserve its own space")
menu.removeItem(at: 3)
verifyLayout("device disconnected")
precondition(charts.frame == originalCharts, "Layout did not restore after disconnect")
for _ in 0..<3 { dropdown.refresh() }
verifyLayout("repeated refresh")
print("All popover layout checks passed")

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
