import Cocoa

/// A real view hierarchy lets charts receive mouse and keyboard input. NSMenu
/// remains the action model so updater validation and toggle state stay shared.
final class StatusPopover: NSObject, NSPopoverDelegate {
    private let popover: NSPopover
    private let controller = NSViewController()
    private let menu: NSMenu
    private var buttons: [(NSButton, NSMenuItem)] = []
    private var itemIDs: [ObjectIdentifier] = []
    private var customViews: [ObjectIdentifier: NSView] = [:]
    private var contentHeight: CGFloat = 0
    var onClose: (() -> Void)?

    init(menu: NSMenu, popover: NSPopover = NSPopover()) {
        self.menu = menu
        self.popover = popover
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = controller
        rebuild()
    }

    func toggle(relativeTo button: NSView) {
        if popover.isShown { popover.performClose(nil); return }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        let screenHeight = button.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800
        popover.contentSize = NSSize(width: 300, height: min(contentHeight, screenHeight - 60))
        if let scroll = controller.view as? NSScrollView {
            scroll.documentView?.scroll(NSPoint(x: 0, y: max(0, contentHeight - popover.contentSize.height)))
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func refresh() {
        if itemIDs != menu.items.map({ ObjectIdentifier($0) }) { rebuild() }
        for (button, item) in buttons {
            if let validator = item.target as? NSMenuItemValidation {
                item.isEnabled = validator.validateMenuItem(item)
            }
            button.title = (item.state == .on ? "✓  " : "    ") + item.title
            button.isEnabled = item.isEnabled && item.action != nil
        }
    }

    private func rebuild() {
        buttons.removeAll()
        itemIDs = menu.items.map { ObjectIdentifier($0) }
        customViews = customViews.filter { itemIDs.contains($0.key) }
        for item in menu.items {
            if let custom = item.view {
                // NSMenu keeps resetting its custom views' origins, even when
                // the menu is only used as an action model. Give the popover
                // sole ownership of their layout before placing them here.
                customViews[ObjectIdentifier(item)] = custom
                item.view = nil
            }
        }
        let content = NSView(frame: .zero)
        var y: CGFloat = 8
        // AppKit coordinates increase upward, so assemble from the bottom.
        for item in menu.items.reversed() {
            if let custom = customViews[ObjectIdentifier(item)] {
                custom.removeFromSuperview()
                custom.frame.origin = NSPoint(x: 0, y: y)
                content.addSubview(custom)
                y += custom.frame.height
            } else if item.isSeparatorItem {
                let line = NSBox(frame: NSRect(x: 12, y: y + 5, width: 276, height: 1))
                line.boxType = .separator
                content.addSubview(line)
                y += 12
            } else {
                let button = NSButton(title: item.title, target: self, action: #selector(performItem(_:)))
                button.isBordered = false
                button.alignment = .left
                button.font = .menuFont(ofSize: 12)
                button.keyEquivalent = item.keyEquivalent
                button.keyEquivalentModifierMask = item.keyEquivalentModifierMask
                button.frame = NSRect(x: 8, y: y, width: 284, height: 23)
                button.tag = buttons.count
                buttons.append((button, item))
                content.addSubview(button)
                y += 23
            }
        }
        content.frame.size = NSSize(width: 300, height: y + 8)
        contentHeight = content.frame.height
        let scroll = NSScrollView(frame: content.frame)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = content
        controller.view = scroll
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        popover.contentSize = NSSize(width: 300, height: min(contentHeight, screenHeight - 60))
        content.scroll(NSPoint(x: 0, y: max(0, contentHeight - popover.contentSize.height)))
    }

    @objc private func performItem(_ sender: NSButton) {
        let item = buttons[sender.tag].1
        guard item.isEnabled, let action = item.action else { return }
        // Actions that open another window should dismiss the dropdown first.
        if item.title == "About MyStat" || item.title == "Check for Updates…" || item.title == "Quit MyStat" {
            popover.performClose(nil)
        }
        NSApp.sendAction(action, to: item.target, from: item)
        refresh()
    }

    func popoverDidClose(_ notification: Notification) { onClose?() }
}
