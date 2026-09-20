import Cocoa
import MyStatCore

final class NetworkProcessMenu: NSObject, NSMenuDelegate {
    let item = NSMenuItem(title: "Network Apps", action: nil, keyEquivalent: "")
    let menu = NSMenu(title: "Network Apps")
    private let icons = ProcessIconProvider()
    private let rows = (0..<5).map { _ in NSMenuItem(title: "", action: nil, keyEquivalent: "") }
    private let placeholder = NSMenuItem(title: "Measuring traffic…", action: nil, keyEquivalent: "")
    private let footer = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var snapshot: NetworkAppSnapshot?

    override init() {
        super.init()
        menu.autoenablesItems = false
        menu.minimumWidth = 320
        menu.delegate = self
        item.submenu = menu
        item.toolTip = "Top five apps and system processes by combined download and upload"
        for row in rows {
            row.isEnabled = false
            if #available(macOS 27.0, *) { row.preferredImageVisibility = .visible }
            menu.addItem(row)
        }
        placeholder.isEnabled = false; menu.addItem(placeholder)
        menu.addItem(.separator())
        footer.isEnabled = false; menu.addItem(footer)
        let note = NSMenuItem(title: "VPNs and proxies can affect attribution", action: nil, keyEquivalent: "")
        note.isEnabled = false
        note.toolTip = "TCP/UDP app traffic can include virtual interfaces. App rates may differ from physical Wi-Fi and Ethernet totals."
        menu.addItem(note)
        refresh()
    }

    func update(_ snapshot: NetworkAppSnapshot?) { self.snapshot = snapshot; refresh() }
    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func refresh() {
        let stale = snapshot?.isStale() == true
        let apps = snapshot?.apps ?? []
        for (index, row) in rows.enumerated() {
            row.isHidden = index >= apps.count
            guard index < apps.count else { continue }
            let app = apps[index]
            let amount = "↓ \(MetricFormat.rate(app.download))  ↑ \(MetricFormat.rate(app.upload))"
            row.title = app.name
            if #available(macOS 14.0, *) { row.badge = NSMenuItemBadge(string: amount) }
            else { row.title += " — \(amount)" }
            let image = (app.applicationURL.map { icons.icon(forApplication: $0) } ?? icons.icon(for: app.pid)).copy() as! NSImage
            image.size = NSSize(width: 16, height: 16); row.image = image
            row.toolTip = "\(app.name) · \(amount)\(stale ? " · Stale reading" : "")"
            row.setAccessibilityLabel("\(app.name), download \(MetricFormat.rate(app.download)), upload \(MetricFormat.rate(app.upload))\(stale ? ", stale reading" : "")")
        }
        placeholder.isHidden = !apps.isEmpty
        placeholder.title = snapshot == nil ? "Readings unavailable · waiting for samples" : stale ? "Readings are stale" : "No active app traffic"
        footer.title = stale ? "Readings are stale · waiting for a new sample" : "Live TCP/UDP · app helpers combined"
    }
}
