import Cocoa

// Run with scripts/test-status-popover.sh. This exercises the real assembled
// dropdown after AppKit has laid it out, including a device-list rebuild.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let menu = NSMenu()
let range = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
let charts = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 450))
for view in [range, charts] {
    let item = NSMenuItem()
    item.view = view
    menu.addItem(item)
}
menu.addItem(.separator())
let sharing = NSMenuItem(title: "iPhone sharing available", action: nil, keyEquivalent: "")
menu.addItem(sharing)
for title in ["Keep Awake", "Launch at Login", "About MyStat", "Check for Updates…", "Automatically Check for Updates", "Quit MyStat"] {
    menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
}
let popover = NSPopover()
let dropdown = StatusPopover(menu: menu, popover: popover)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 750), styleMask: [.borderless], backing: .buffered, defer: false)

func verifyLayout(_ name: String) {
    dropdown.refresh()
    window.contentView = popover.contentViewController!.view
    window.contentView!.layoutSubtreeIfNeeded()
    menu.update()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    let scroll = window.contentView as! NSScrollView
    let document = scroll.documentView!
    let frames = document.subviews.map(\.frame).sorted { $0.minY < $1.minY }
    precondition(charts.superview === document && range.superview === document, "Lost custom views on rebuild")
    precondition(charts.frame.height == 450 && range.frame.height == 30, "Custom view resized")
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
