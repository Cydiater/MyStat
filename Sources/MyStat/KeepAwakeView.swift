import Cocoa

final class KeepAwakeView: NSView {
    private let controller: KeepAwakeController
    private let toggle = MenuSwitch()
    private let heading = NSButton(title: "Keep Awake", target: nil, action: nil)
    private let duration = NSTextField(labelWithString: "Duration")
    private let status = NSTextField(labelWithString: "")
    private let display = NSButton(checkboxWithTitle: "Keep display on", target: nil, action: nil)
    private let presets = NSSegmentedControl()
    private(set) var isExpanded = false

    init(controller: KeepAwakeController) {
        self.controller = controller
        super.init(frame: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: 58))
        heading.font = .systemFont(ofSize: 13, weight: .medium)
        heading.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        heading.isBordered = false
        heading.alignment = .left
        heading.imagePosition = .imageLeading
        heading.target = self
        heading.action = #selector(toggleOptions)
        heading.toolTip = "Duration and display options"
        addSubview(heading)
        toggle.controlSize = .small
        toggle.sizeToFit()
        toggle.target = self
        toggle.action = #selector(toggleSession)
        toggle.setAccessibilityLabel("Keep Awake")
        addSubview(toggle)
        status.font = .systemFont(ofSize: 11)
        status.lineBreakMode = .byTruncatingTail
        status.frame = NSRect(x: 20, y: 94, width: bounds.width - 40, height: 16)
        addSubview(status)
        duration.font = .systemFont(ofSize: 10, weight: .medium)
        duration.textColor = .secondaryLabelColor
        duration.frame = NSRect(x: 20, y: 73, width: 90, height: 15)
        addSubview(duration)
        presets.segmentCount = KeepAwakeController.labels.count
        presets.trackingMode = .selectOne
        presets.segmentStyle = .rounded
        presets.controlSize = .small
        presets.font = .systemFont(ofSize: 11)
        presets.target = self
        presets.action = #selector(selectDuration(_:))
        presets.setAccessibilityLabel("Keep Awake duration")
        for (index, label) in KeepAwakeController.labels.enumerated() {
            presets.setLabel(label, forSegment: index)
            presets.setWidth(40, forSegment: index)
            let minutes = KeepAwakeController.durations[index]
            presets.setToolTip(index == 0 ? "Until turned off or MyStat quits" : "\(minutes) minutes; restarts the timer if active", forSegment: index)
        }
        presets.sizeToFit()
        presets.frame.origin = NSPoint(x: (bounds.width - presets.frame.width) / 2, y: 40)
        addSubview(presets)
        display.frame = NSRect(x: 20, y: 12, width: bounds.width - 40, height: 20)
        display.font = .systemFont(ofSize: 11)
        display.target = self
        display.action = #selector(changeDisplay)
        display.toolTip = "Prevents automatic display sleep. Manual sleep and closing the lid still work."
        addSubview(display)
        layoutOptions()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) { DashboardStyle.card(bounds.insetBy(dx: 8, dy: 3)) }

    func refresh() {
        toggle.state = controller.isActive ? .on : .off
        display.state = controller.keepsDisplayOn ? .on : .off
        presets.selectedSegment = KeepAwakeController.durations.firstIndex(of: controller.durationMinutes) ?? 0
        let text: String
        if let error = controller.errorMessage { text = error }
        else if !controller.isActive {
            let duration = controller.durationMinutes == 0 ? "Indefinite" : KeepAwakeController.labels[KeepAwakeController.durations.firstIndex(of: controller.durationMinutes)!]
            text = "Off · \(duration) · \(controller.keepsDisplayOn ? "Display on" : "Display may sleep")"
        }
        else if let end = controller.endsAt { text = "Active until \(end.formatted(date: .omitted, time: .shortened))" }
        else { text = "Active indefinitely · Until turned off or app quits" }
        status.stringValue = text
        status.toolTip = text
        status.textColor = controller.errorMessage == nil ? .secondaryLabelColor : .systemRed
        toggle.setAccessibilityValue(controller.isActive ? "On. \(text)" : "Off. \(text)")
    }

    private func layoutOptions() {
        frame.size.height = isExpanded ? 146 : 58
        heading.frame = NSRect(x: 20, y: bounds.height - 33, width: 240, height: 24)
        heading.image = NSImage(systemSymbolName: isExpanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        heading.setAccessibilityLabel(isExpanded ? "Hide Keep Awake options" : "Show Keep Awake options")
        toggle.frame.origin = NSPoint(x: bounds.width - 20 - toggle.frame.width, y: bounds.height - 22 - toggle.frame.height / 2)
        status.frame.origin.y = bounds.height - 52
        duration.isHidden = !isExpanded
        display.isHidden = !isExpanded
        presets.isHidden = !isExpanded
        needsDisplay = true
    }

    @objc private func toggleOptions() {
        isExpanded.toggle()
        layoutOptions()
    }

    @objc private func toggleSession() { controller.setActive(toggle.state == .on) }
    @objc private func selectDuration(_ sender: NSSegmentedControl) {
        guard KeepAwakeController.durations.indices.contains(sender.selectedSegment) else { return }
        controller.selectDuration(KeepAwakeController.durations[sender.selectedSegment])
    }
    @objc private func changeDisplay() { controller.setDisplayOn(display.state == .on) }
}

/// Menu windows do not become key; the switch must accept the first click.
private final class MenuSwitch: NSSwitch {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
