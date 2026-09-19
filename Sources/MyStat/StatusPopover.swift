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
    private weak var positioningButton: NSView?
    var isShown: Bool { popover.isShown }
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
        // An explicit toggle must also close any attached process panel.
        // performClose can refuse to close a popover with a child window.
        if popover.isShown { popover.close(); return }
        positioningButton = button
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        let screenHeight = button.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800
        popover.contentSize = NSSize(width: DashboardStyle.width, height: min(contentHeight, screenHeight - 60))
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
        let content = DashboardCanvas(frame: .zero)
        var y: CGFloat = 8
        // AppKit coordinates increase upward, so assemble from the bottom.
        for item in menu.items.reversed() {
            if let custom = customViews[ObjectIdentifier(item)] {
                custom.removeFromSuperview()
                custom.frame.origin = NSPoint(x: 0, y: y)
                content.addSubview(custom)
                y += custom.frame.height
            } else if item.isSeparatorItem {
                let line = NSBox(frame: NSRect(x: 12, y: y + 5, width: DashboardStyle.width - 24, height: 1))
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
                button.frame = NSRect(x: 8, y: y, width: DashboardStyle.width - 16, height: 23)
                button.tag = buttons.count
                buttons.append((button, item))
                content.addSubview(button)
                y += 23
            }
        }
        content.frame.size = NSSize(width: DashboardStyle.width, height: y + 8)
        contentHeight = content.frame.height
        let scroll = NSScrollView(frame: content.frame)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = content
        controller.view = scroll
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        popover.contentSize = NSSize(width: DashboardStyle.width, height: min(contentHeight, screenHeight - 60))
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

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        shouldClose(for: NSApp.currentEvent?.type, at: NSEvent.mouseLocation)
    }

    func shouldClose(for eventType: NSEvent.EventType?, at location: NSPoint) -> Bool {
        // Let the status button's action own the entire click. Otherwise the
        // transient popover can close on mouse-down and reopen on mouse-up.
        if eventType == .leftMouseDown || eventType == .leftMouseUp,
           let button = positioningButton, let window = button.window,
           window.convertToScreen(button.convert(button.bounds, to: nil)).contains(location) {
            return false
        }
        // A click on our nonactivating child process panel belongs to this
        // dropdown, even though its window lies outside the popover's bounds.
        if eventType == .leftMouseDown || eventType == .rightMouseDown {
            let children = controller.view.window?.childWindows ?? []
            if children.contains(where: { $0.isVisible && $0.frame.contains(location) }) { return false }
        }
        return true
    }

    func popoverDidClose(_ notification: Notification) {
        positioningButton = nil
        onClose?()
    }
}
