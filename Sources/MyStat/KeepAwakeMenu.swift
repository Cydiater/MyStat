import Cocoa

/// Keep session controls in a native cascade, with a compact status in the overview.
final class KeepAwakeMenu: NSObject, NSMenuDelegate {
    let item = NSMenuItem(title: "Keep Awake", action: nil, keyEquivalent: "")
    let menu = NSMenu(title: "Keep Awake")
    private let controller: KeepAwakeController
    private let toggle = NSMenuItem(title: "Keep Awake", action: nil, keyEquivalent: "")
    private let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let display = NSMenuItem(title: "Keep Display On", action: nil, keyEquivalent: "")
    private var durations: [NSMenuItem] = []

    init(controller: KeepAwakeController) {
        self.controller = controller
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        item.submenu = menu
        toggle.target = self
        toggle.action = #selector(toggleSession)
        menu.addItem(toggle)
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let heading = NSMenuItem(title: "Duration", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        for minutes in KeepAwakeController.durations {
            let title: String
            if minutes == 0 { title = "Until Turned Off" }
            else if minutes < 60 { title = "\(minutes) Minutes" }
            else { title = "\(minutes / 60) \(minutes == 60 ? "Hour" : "Hours")" }
            let preset = NSMenuItem(title: title, action: #selector(selectDuration(_:)), keyEquivalent: "")
            preset.target = self
            preset.tag = minutes
            preset.toolTip = "Sets the duration; restarts the timer if Keep Awake is active."
            menu.addItem(preset)
            durations.append(preset)
        }
        menu.addItem(.separator())
        display.target = self
        display.action = #selector(changeDisplay)
        display.toolTip = "Prevents automatic display sleep. Manual sleep and closing the lid still work."
        menu.addItem(display)
        refresh()
    }

    func refresh() {
        let summary = controller.errorMessage == nil ? (controller.status.countdown ?? "Off") : "Error"
        if #available(macOS 14.0, *) {
            item.badge = NSMenuItemBadge(string: summary)
        } else {
            item.title = "Keep Awake — \(summary)"
        }
        item.state = controller.isActive ? .on : .off
        toggle.state = item.state
        display.state = controller.keepsDisplayOn ? .on : .off
        for preset in durations {
            preset.state = preset.tag == controller.durationMinutes ? .on : .off
        }
        if let error = controller.errorMessage { status.title = error }
        else if let end = controller.endsAt {
            status.title = "Active until \(end.formatted(date: .omitted, time: .shortened))"
        } else if controller.isActive { status.title = "Active until turned off or MyStat quits" }
        else { status.title = "Off — enable Keep Awake to start" }
        item.setAccessibilityLabel(controller.errorMessage ?? controller.status.accessibilityDescription)
    }

    func menuWillOpen(_ menu: NSMenu) {
        controller.refresh()
        refresh()
    }

    @objc private func toggleSession() {
        controller.setActive(!controller.isActive)
        didChange()
    }

    @objc private func selectDuration(_ sender: NSMenuItem) {
        controller.selectDuration(sender.tag)
        didChange()
    }

    @objc private func changeDisplay() {
        controller.setDisplayOn(!controller.keepsDisplayOn)
        didChange()
    }

    private func didChange() {
        refresh()
        if let error = controller.errorMessage {
            let alert = NSAlert()
            alert.messageText = "Couldn't update Keep Awake"
            alert.informativeText = error
            alert.runModal()
        }
    }
}
