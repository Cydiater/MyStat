import Cocoa
import MyStatCore

final class ProcessMenus {
    let cpuItem = NSMenuItem(title: "Top CPU processes", action: nil, keyEquivalent: "")
    let memoryItem = NSMenuItem(title: "Top memory processes", action: nil, keyEquivalent: "")

    init() {
        for (item, caption) in [(cpuItem, "CPU: 100% = one core"), (memoryItem, "Memory: resident bytes") ] {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for _ in 0..<5 {
                let row = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                row.isEnabled = false
                menu.addItem(row)
            }
            menu.addItem(.separator())
            let note = NSMenuItem(title: caption + " · readable processes", action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
            item.submenu = menu
        }
        update(nil)
    }

    func update(_ snapshot: ProcessSnapshot?) {
        for (item, rows, cpu) in [(cpuItem, snapshot?.topCPU ?? [], true), (memoryItem, snapshot?.topMemory ?? [], false)] {
            guard let menu = item.submenu else { continue }
            for index in 0..<5 {
                let entry = menu.items[index]
                entry.isHidden = index >= rows.count && index != 0
                guard index < rows.count else {
                    entry.title = snapshot == nil ? "Process readings unavailable" : cpu ? "Measuring CPU…" : "No readable processes"
                    continue
                }
                let row = rows[index]
                let value = cpu ? String(format: "%.1f%%", row.cpuPercent ?? 0) : MetricFormat.bytes(row.residentBytes)
                entry.title = "\(row.name) (\(row.pid)) — \(value)"
            }
        }
    }
}
