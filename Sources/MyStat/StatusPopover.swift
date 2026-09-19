import Cocoa

/// A real view hierarchy lets charts receive mouse and keyboard input. NSMenu
/// remains the action model so updater validation and toggle state stay shared.
final class StatusPopover: NSObject, NSPopoverDelegate {
    private let popover: NSPopover
    private let controller = NSViewController()
    private let menu: NSMenu
    private var buttons: [(NSButton, NSMenuItem)] = []
    private var labels: [(NSTextField, NSMenuItem)] = []
    private var itemIDs: [ObjectIdentifier] = []
    private var customViews: [ObjectIdentifier: NSView] = [:]
    private var customHeights: [ObjectIdentifier: CGFloat] = [:]
    private var navigationPath: [NSMenuItem] = []
    private var keyboardMonitor: Any?
    private var contentHeight: CGFloat = 0
    private weak var positioningButton: NSView?
    private var visibleMenu: NSMenu { navigationPath.last?.submenu ?? menu }
    var isShown: Bool { popover.isShown }
    var isShowingOverview: Bool { navigationPath.isEmpty }
    var onClose: (() -> Void)?
    var onPageChange: ((Bool) -> Void)?

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

    deinit {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }

    func toggle(relativeTo button: NSView) {
        // An explicit toggle must also close any attached process panel.
        // performClose can refuse to close a popover with a child window.
        if popover.isShown { popover.close(); return }
        positioningButton = button
        if !navigationPath.isEmpty {
            navigationPath.removeAll()
            rebuild()
        }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        resizeToContent()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        guard popover.isShown else { return }
        popover.contentViewController?.view.window?.makeKey()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event) == true ? nil : event
        }
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard isShown else { return false }
        if event.modifierFlags.contains(.command) {
            return menu.performKeyEquivalent(with: event)
        }
        guard !isShowingOverview, event.charactersIgnoringModifiers == "\u{1b}" else { return false }
        goBack()
        return true
    }

    func refresh() {
        let items = allItems(in: menu)
        // The menu is an action model; refresh() validates its controls.
        // Native validation would disable pages containing only read-only views.
        menu.autoenablesItems = false
        items.forEach { $0.submenu?.autoenablesItems = false }
        for item in items {
            if let validator = item.target as? NSMenuItemValidation {
                item.isEnabled = validator.validateMenuItem(item)
            }
        }
        if navigationPath.contains(where: { page in !items.contains(where: { $0 === page }) || page.submenu == nil }) {
            navigationPath.removeAll()
            rebuild()
            onPageChange?(true)
        } else if itemIDs != items.map({ ObjectIdentifier($0) }) || customHeights != customViews.mapValues({ $0.frame.height }) {
            rebuild()
        }
        for (button, item) in buttons {
            if let navigation = button as? PopoverNavigationButton {
                navigation.title = item.title
                navigation.detail = item.toolTip ?? ""
                navigation.image = item.image
                navigation.setAccessibilityLabel(item.title)
                navigation.setAccessibilityHelp(item.toolTip)
                navigation.needsDisplay = true
            } else {
                button.title = (item.state == .on ? "✓  " : "    ") + item.title
            }
            button.isEnabled = item.isEnabled && (item.action != nil || item.submenu != nil)
        }
        for (label, item) in labels {
            label.stringValue = item.title
            label.toolTip = item.title
        }
    }

    private func allItems(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in [item] + (item.submenu.map { allItems(in: $0) } ?? []) }
    }

    private func rebuild() {
        buttons.removeAll()
        labels.removeAll()
        let items = allItems(in: menu)
        itemIDs = items.map { ObjectIdentifier($0) }
        customViews = customViews.filter { itemIDs.contains($0.key) }
        for item in items {
            if let custom = item.view {
                // NSMenu keeps resetting its custom views' origins, even when
                // the menu is only used as an action model. Give the popover
                // sole ownership of their layout before placing them here.
                customViews[ObjectIdentifier(item)] = custom
                item.view = nil
            }
        }
        customHeights = customViews.mapValues { $0.frame.height }
        // Hidden pages retain their controls and state, but not a window or
        // chart tracking. NSMenu never owns their view layout again.
        customViews.values.forEach { $0.removeFromSuperview() }
        let content = DashboardCanvas(frame: .zero)
        var y: CGFloat = 8
        // AppKit coordinates increase upward, so assemble from the bottom.
        for item in visibleMenu.items.reversed() {
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
            } else if item.action == nil && item.submenu == nil {
                let label = NSTextField(labelWithString: item.title)
                label.font = .systemFont(ofSize: 12)
                label.textColor = DashboardStyle.muted
                label.lineBreakMode = .byTruncatingTail
                label.frame = NSRect(x: 20, y: y + 6, width: DashboardStyle.width - 40, height: 17)
                labels.append((label, item))
                content.addSubview(label)
                y += 28
            } else {
                let button: NSButton = item.submenu == nil
                    ? NSButton(title: item.title, target: self, action: #selector(performItem(_:)))
                    : PopoverNavigationButton(title: item.title, target: self, action: #selector(performItem(_:)))
                button.isBordered = false
                button.alignment = .left
                button.font = .menuFont(ofSize: 12)
                button.keyEquivalent = item.keyEquivalent
                button.keyEquivalentModifierMask = item.keyEquivalentModifierMask
                let rowHeight: CGFloat = item.submenu == nil ? 28 : 52
                button.frame = NSRect(x: 8, y: y, width: DashboardStyle.width - 16, height: rowHeight)
                button.tag = buttons.count
                buttons.append((button, item))
                content.addSubview(button)
                y += rowHeight
            }
        }
        if let page = navigationPath.last {
            let header = NSView(frame: NSRect(x: 0, y: y, width: DashboardStyle.width, height: 42))
            let back = NSButton(title: "Back", target: self, action: #selector(goBack))
            back.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
            back.imagePosition = .imageLeading
            back.controlSize = .small
            if #available(macOS 26.0, *) {
                back.bezelStyle = .glass
                back.borderShape = .capsule
            } else {
                back.bezelStyle = .rounded
            }
            back.font = .systemFont(ofSize: 12)
            back.sizeToFit()
            back.frame.origin = NSPoint(x: 12, y: (42 - back.frame.height) / 2)
            back.setAccessibilityLabel("Back to \(navigationPath.dropLast().last?.title ?? "Overview")")
            header.addSubview(back)
            let title = NSTextField(labelWithString: page.title)
            title.font = .systemFont(ofSize: 14, weight: .semibold)
            title.alignment = .center
            title.frame = NSRect(x: 88, y: 11, width: DashboardStyle.width - 176, height: 20)
            header.addSubview(title)
            content.addSubview(header)
            y += 42
        }
        content.frame.size = NSSize(width: DashboardStyle.width, height: y + 8)
        contentHeight = content.frame.height
        let scroll = NSScrollView(frame: content.frame)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = content
        controller.view = scroll
        resizeToContent()
    }

    private func resizeToContent() {
        let screenHeight = positioningButton?.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800
        popover.contentSize = NSSize(width: DashboardStyle.width, height: min(contentHeight, screenHeight - 60))
        (controller.view as? NSScrollView)?.documentView?.scroll(NSPoint(x: 0, y: max(0, contentHeight - popover.contentSize.height)))
    }

    @objc private func goBack() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
        rebuild()
        refresh()
        onPageChange?(isShowingOverview)
    }

    @objc private func performItem(_ sender: NSButton) {
        let item = buttons[sender.tag].1
        if item.isEnabled, item.submenu != nil {
            navigationPath.append(item)
            rebuild()
            refresh()
            onPageChange?(false)
            return
        }
        guard item.isEnabled, let action = item.action else { return }
        // Actions that open another window should dismiss the dropdown first.
        if item.title == "About MyStat" || item.title == "Check for Updates…" || item.title == "Quit MyStat" {
            popover.close()
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
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        keyboardMonitor = nil
        positioningButton = nil
        onClose?()
    }
}

/// A compact entry point to a secondary page, with a useful summary.
private final class PopoverNavigationButton: NSButton {
    var detail = ""
    private var hoverArea: NSTrackingArea?
    private var hovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted || hovered {
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 2), xRadius: 10, yRadius: 10).fill()
        }
        let tint = NSImage.SymbolConfiguration(paletteColors: [DashboardStyle.muted])
        image?.withSymbolConfiguration(tint)?.draw(in: NSRect(x: 12, y: 17, width: 18, height: 18))
        DashboardStyle.label(title, in: NSRect(x: 42, y: 8, width: bounds.width - 74, height: 18), size: 13, weight: .medium)
        DashboardStyle.label(detail, in: NSRect(x: 42, y: 28, width: bounds.width - 74, height: 15), size: 11, color: DashboardStyle.muted)
        NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(tint)?.draw(in: NSRect(x: bounds.width - 22, y: 20, width: 7, height: 12))
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 2), xRadius: 10, yRadius: 10).fill()
    }
}
