import Cocoa
import MyStatCore

/// Process readings use standard menu rows, including native value badges.
final class ProcessMenu: NSObject, NSMenuDelegate {
    enum Metric { case cpu, memory }
    let item: NSMenuItem
    let menu: NSMenu
    private let metric: Metric
    private let icons = ProcessIconProvider()
    private let rows = (0..<5).map { _ in NSMenuItem(title: "", action: nil, keyEquivalent: "") }
    private let placeholder = NSMenuItem(title: "Readings unavailable", action: nil, keyEquivalent: "")
    private let footer = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var snapshot: ProcessSnapshot?

    init(metric: Metric) {
        self.metric = metric
        let title = metric == .cpu ? "CPU Processes" : "Memory Processes"
        menu = NSMenu(title: title)
        item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        super.init()
        menu.autoenablesItems = false
        menu.minimumWidth = 260
        menu.delegate = self
        item.submenu = menu
        item.toolTip = "Top five readable processes"
        for row in rows {
            row.isEnabled = false
            menu.addItem(row)
        }
        placeholder.isEnabled = false
        menu.addItem(placeholder)
        menu.addItem(.separator())
        footer.isEnabled = false
        menu.addItem(footer)
        refresh()
    }

    func update(_ snapshot: ProcessSnapshot?) {
        self.snapshot = snapshot
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func refresh() {
        let processes = (metric == .cpu ? snapshot?.topCPU : snapshot?.topMemory) ?? []
        let stale = snapshot?.isStale(at: .now) == true
        for (index, item) in rows.enumerated() {
            item.isHidden = index >= processes.count
            guard index < processes.count else { continue }
            let process = processes[index]
            let amount = metric == .cpu ? String(format: "%.1f%%", process.cpuPercent ?? 0) : MetricFormat.bytes(process.residentBytes)
            item.title = process.name
            if #available(macOS 14.0, *) {
                item.badge = NSMenuItemBadge(string: amount)
            } else {
                item.title += " — \(amount)"
            }
            let image = icons.icon(for: process.pid).copy() as! NSImage
            image.size = NSSize(width: 16, height: 16)
            item.image = image
            item.toolTip = "\(process.name) · PID \(process.pid) · \(amount)\(stale ? " · Stale reading" : "")"
            item.setAccessibilityLabel("\(process.name), \(amount)\(stale ? ", stale reading" : "")")
        }
        placeholder.isHidden = !processes.isEmpty
        placeholder.title = snapshot == nil ? "Readings unavailable" : metric == .cpu ? "Measuring CPU…" : "No readable processes"
        footer.title = stale ? "Readings are stale · waiting for a new sample" : metric == .cpu ? "100% = one core · readable processes" : "Resident memory · readable processes"
    }
}
