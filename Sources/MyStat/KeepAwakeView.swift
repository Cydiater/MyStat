import Cocoa

final class KeepAwakeView: NSView {
    private let controller: KeepAwakeController
    private let toggle = NSSwitch()
    private let status = NSTextField(labelWithString: "")
    private let display = NSButton(checkboxWithTitle: "Keep display on", target: nil, action: nil)
    private var presets: [NSButton] = []

    init(controller: KeepAwakeController) {
        self.controller = controller
        super.init(frame: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: 146))
        let title = NSTextField(labelWithString: "Keep Awake")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.frame = NSRect(x: 20, y: 116, width: 220, height: 18)
        addSubview(title)
        toggle.frame = NSRect(x: bounds.width - 60, y: 109, width: 40, height: 28)
        toggle.target = self
        toggle.action = #selector(toggleSession)
        toggle.setAccessibilityLabel("Keep Awake")
        addSubview(toggle)
        status.font = .systemFont(ofSize: 10)
        status.lineBreakMode = .byTruncatingTail
        status.frame = NSRect(x: 20, y: 94, width: bounds.width - 40, height: 16)
        addSubview(status)
        let duration = NSTextField(labelWithString: "Duration")
        duration.font = .systemFont(ofSize: 10, weight: .medium)
        duration.textColor = .secondaryLabelColor
        duration.frame = NSRect(x: 20, y: 73, width: 90, height: 15)
        addSubview(duration)
        for (index, label) in KeepAwakeController.labels.enumerated() {
            let button = DurationButton(title: label, target: self, action: #selector(selectDuration(_:)))
            button.setButtonType(.toggle)
            button.isBordered = false
            button.font = .systemFont(ofSize: 11, weight: .medium)
            button.frame = NSRect(x: 20 + CGFloat(index) * 46, y: 40, width: 40, height: 28)
            button.tag = KeepAwakeController.durations[index]
            button.toolTip = index == 0 ? "Until turned off or MyStat quits" : "\(button.tag) minutes; restarts the timer if active"
            button.setAccessibilityLabel(index == 0 ? "Indefinitely" : "\(button.tag) minutes")
            presets.append(button)
            addSubview(button)
        }
        display.frame = NSRect(x: 20, y: 12, width: bounds.width - 40, height: 20)
        display.font = .systemFont(ofSize: 11)
        display.target = self
        display.action = #selector(changeDisplay)
        display.toolTip = "Prevents automatic display sleep. Manual sleep and closing the lid still work."
        addSubview(display)
        controller.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) { DashboardStyle.card(bounds.insetBy(dx: 8, dy: 3)) }

    private func refresh() {
        toggle.state = controller.isActive ? .on : .off
        display.state = controller.keepsDisplayOn ? .on : .off
        for button in presets {
            button.state = button.tag == controller.durationMinutes ? .on : .off
            button.needsDisplay = true
        }
        let text: String
        if let error = controller.errorMessage { text = error }
        else if !controller.isActive { text = "Off · Normal sleep settings apply" }
        else if let end = controller.endsAt { text = "Active until \(end.formatted(date: .omitted, time: .shortened))" }
        else { text = "Active indefinitely · Until turned off or app quits" }
        status.stringValue = text
        status.toolTip = text
        status.textColor = controller.errorMessage == nil ? .secondaryLabelColor : .systemRed
        toggle.setAccessibilityValue(controller.isActive ? "On. \(text)" : "Off. \(text)")
    }

    @objc private func toggleSession() { controller.setActive(toggle.state == .on) }
    @objc private func selectDuration(_ sender: NSButton) { controller.selectDuration(sender.tag) }
    @objc private func changeDisplay() { controller.setDisplayOn(display.state == .on) }
}

private final class DurationButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        (selected ? DashboardStyle.blue : DashboardStyle.border).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
        DashboardStyle.label(title, in: NSRect(x: 0, y: (bounds.height - 16) / 2, width: bounds.width, height: 16),
                             size: 11, color: selected ? .white : DashboardStyle.text, weight: .semibold, alignment: .center)
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
    }
}
