import Cocoa
import MyStatCore

final class StatusBarModeMenu: NSObject {
    let item = NSMenuItem(title: "Menu Bar", action: nil, keyEquivalent: "")
    let menu = NSMenu(title: "Menu Bar")
    private(set) var selected: StatusBarMetric?
    var onChange: ((StatusBarMetric?) -> Void)?

    init(selected: StatusBarMetric?) {
        self.selected = selected
        super.init()
        menu.autoenablesItems = false
        item.submenu = menu
        item.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: nil)
        item.setAccessibilityHelp("Automatically feature recent activity, or pin a menu-bar metric.")
        for (index, title) in (["Automatic"] + StatusBarMetric.allCases.map(\.rawValue)).enumerated() {
            let choice = NSMenuItem(title: title, action: #selector(selectMode(_:)), keyEquivalent: "")
            choice.tag = index
            choice.target = self
            menu.addItem(choice)
        }
        updateCheckmarks()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard menu.items.contains(sender) else { return }
        selected = sender.tag == 0 ? nil : StatusBarMetric.allCases[sender.tag - 1]
        updateCheckmarks()
        onChange?(selected)
    }

    private func updateCheckmarks() {
        let selectedTag = selected.flatMap { StatusBarMetric.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        for choice in menu.items { choice.state = choice.tag == selectedTag ? .on : .off }
    }
}
