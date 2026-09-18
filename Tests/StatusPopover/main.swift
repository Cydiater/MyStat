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
