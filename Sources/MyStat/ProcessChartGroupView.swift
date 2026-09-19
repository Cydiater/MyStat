import Cocoa
import MyStatCore

/// Charts stay in the dashboard; their process list lives in a sibling window.
final class ProcessChartGroupView: NSView {
    enum Metric { case cpu, memory }
    private let cpu: StatsChartView
    private let memory: StatsChartView
    private let panel = ProcessPanelView(frame: NSRect(x: 0, y: 0, width: 284, height: 222))
    private lazy var panelWindow: NSPanel = {
        let window = NSPanel(contentRect: panel.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = true
        window.becomesKeyOnlyIfNeeded = true
        window.contentView = DashboardStyle.floatingSurface(around: panel)
        window.collectionBehavior = [.transient, .fullScreenAuxiliary]
        return window
    }()
    private var snapshot: ProcessSnapshot?
    private(set) var displayedMetric: Metric?
    private(set) var pinned = false
    private var candidate: Metric?
    private var candidateSince: TimeInterval = 0
    private var outsideSince: TimeInterval?
    private var suppressedMetric: Metric?
    private var hoverTimer: Timer?
    private var keyboardMonitor: Any?

    init(cpu: StatsChartView, memory: StatsChartView) {
        self.cpu = cpu
        self.memory = memory
        super.init(frame: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: DashboardStyle.chartHeight * 2))
        cpu.frame = NSRect(x: 0, y: DashboardStyle.chartHeight, width: DashboardStyle.width, height: DashboardStyle.chartHeight)
        memory.frame = NSRect(x: 0, y: 0, width: DashboardStyle.width, height: DashboardStyle.chartHeight)
        for view in [memory, cpu] { addSubview(view) }
        for (chart, metric, shortcut) in [(cpu, Metric.cpu, "C"), (memory, .memory, "M")] {
            chart.onProcessPress = { [weak self] in self?.toggle(metric) }
            chart.setAccessibilityElement(true)
            chart.setAccessibilityRole(.button)
            chart.setAccessibilityLabel("\(chart.title) chart, top processes")
            chart.setAccessibilityHelp("Hover to preview. Click to pin. Press \(shortcut) while the menu is open; Escape closes the panel.")
            chart.toolTip = "Top processes · hover to preview, click to pin (\(shortcut))"
        }
        panel.onClose = { [weak self] in self?.dismiss() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        hoverTimer?.invalidate()
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        startTracking()
    }

    func startTracking() {
        stopTracking()
        guard window != nil else { return }
        // Keep hover timing active during control tracking and scrolling.
        // Process sampling remains on its existing background timer.
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in self?.trackPointer() }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        hoverTimer = timer
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isVisible == true,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": self.toggle(.cpu); return nil
            case "m": self.toggle(.memory); return nil
            case "\u{1b}" where self.displayedMetric != nil: self.dismiss(); return nil
            default: return event
            }
        }
    }

    func stopTracking() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        keyboardMonitor = nil
        dismiss()
        suppressedMetric = nil
    }

    func update(_ snapshot: ProcessSnapshot?) {
        self.snapshot = snapshot
        if let displayedMetric { panel.update(snapshot, metric: displayedMetric, pinned: pinned) }
    }

    func toggle(_ metric: Metric) {
        if displayedMetric == metric && pinned { dismiss() }
        else { show(metric, pinned: true) }
    }

    func dismiss() {
        if let window {
            let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            suppressedMetric = cpu.frame.contains(point) ? .cpu : memory.frame.contains(point) ? .memory : nil
        }
        panelWindow.parent?.removeChildWindow(panelWindow)
        panelWindow.orderOut(nil)
        displayedMetric = nil
        pinned = false
        candidate = nil
        candidateSince = ProcessInfo.processInfo.systemUptime
        outsideSince = nil
    }

    private func show(_ metric: Metric, pinned: Bool) {
        guard positionPanel(for: metric), let window else { return }
        displayedMetric = metric
        self.pinned = pinned
        outsideSince = nil
        panel.update(snapshot, metric: metric, pinned: pinned)
        if panelWindow.parent !== window {
            panelWindow.parent?.removeChildWindow(panelWindow)
            window.addChildWindow(panelWindow, ordered: .above)
        }
        panelWindow.orderFront(nil)
    }

    private func positionPanel(for metric: Metric) -> Bool {
        guard let window, let screen = window.screen else { return false }
        let chart = metric == .cpu ? cpu : memory
        guard !chart.visibleRect.isEmpty else { return false }
        let chartRect = window.convertToScreen(chart.convert(chart.bounds, to: nil))
        guard let frame = ProcessPanelPlacement.frame(parent: window.frame, chart: chartRect,
            screen: screen.visibleFrame, size: NSSize(width: 284, height: 222)) else { return false }
        panelWindow.appearance = window.effectiveAppearance
        if panelWindow.frame != frame { panelWindow.setFrame(frame, display: true) }
        return true
    }

    private func trackPointer() {
        guard let window, window.isVisible else { return }
        if let displayedMetric, !positionPanel(for: displayedMetric) { dismiss() }
        guard !pinned else { return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let now = ProcessInfo.processInfo.systemUptime
        if displayedMetric != nil {
            let floating = panelWindow.frame
            let pointer = NSEvent.mouseLocation
            let gapX = floating.minX >= window.frame.maxX ? window.frame.maxX : floating.maxX
            let bridge = NSRect(x: gapX, y: floating.minY, width: 8, height: floating.height)
            // Crossing the small gap or reading the list keeps a preview open.
            if floating.contains(pointer) || bridge.contains(pointer) { outsideSince = nil; return }
        }
        let hovered: Metric? = !visibleRect.contains(point) ? nil : cpu.frame.contains(point) ? .cpu : memory.frame.contains(point) ? .memory : nil
        if let suppressedMetric, hovered == suppressedMetric { return }
        suppressedMetric = nil
        if hovered != candidate { candidate = hovered; candidateSince = now }
        if let hovered {
            outsideSince = nil
            if now - candidateSince >= 0.25 && displayedMetric != hovered { show(hovered, pinned: false) }
        } else if displayedMetric != nil {
            if outsideSince == nil { outsideSince = now }
            if now - (outsideSince ?? now) >= 0.18 { dismiss() }
        }
    }
}

private final class ProcessPanelView: NSView {
    var onClose: (() -> Void)?
    private let heading = NSTextField(labelWithString: "")
    private let note = NSTextField(labelWithString: "")
    private let footer = NSTextField(labelWithString: "")
    private let iconProvider = ProcessIconProvider()
    private var icons: [NSImageView] = []
    private var names: [NSTextField] = []
    private var amounts: [NSTextField] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        heading.frame = NSRect(x: 12, y: 194, width: 225, height: 18)
        heading.autoresizingMask = [.width]
        addSubview(heading)
        let close = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close process panel")!, target: self, action: #selector(closePanel))
        close.isBordered = false
        close.frame = NSRect(x: 252, y: 192, width: 22, height: 22)
        close.autoresizingMask = [.minXMargin]
        addSubview(close)
        note.font = .systemFont(ofSize: 9)
        note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: 12, y: 176, width: 260, height: 14)
        note.autoresizingMask = [.width]
        addSubview(note)
        for index in 0..<5 {
            let icon = NSImageView(frame: NSRect(x: 12, y: 146 - index * 26, width: 16, height: 16))
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.contentTintColor = .secondaryLabelColor
            icon.setAccessibilityElement(false)
            let name = NSTextField(labelWithString: "")
            name.font = .systemFont(ofSize: 11)
            name.lineBreakMode = .byTruncatingTail
            name.frame = NSRect(x: 34, y: 145 - index * 26, width: 152, height: 19)
            let amount = NSTextField(labelWithString: "")
            amount.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            amount.alignment = .right
            amount.frame = NSRect(x: 188, y: 145 - index * 26, width: 84, height: 19)
            name.autoresizingMask = [.width]
            amount.autoresizingMask = [.minXMargin]
            addSubview(icon); addSubview(name); addSubview(amount)
            icons.append(icon)
            names.append(name); amounts.append(amount)
        }
        footer.font = .systemFont(ofSize: 9)
        footer.textColor = .secondaryLabelColor
        footer.frame = NSRect(x: 12, y: 10, width: 260, height: 15)
        footer.autoresizingMask = [.width]
        addSubview(footer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func closePanel() { onClose?() }

    func update(_ snapshot: ProcessSnapshot?, metric: ProcessChartGroupView.Metric, pinned: Bool) {
        let cpu = metric == .cpu
        heading.stringValue = cpu ? "Top CPU processes" : "Top memory processes"
        heading.textColor = cpu ? DashboardStyle.orange : DashboardStyle.blue
        note.stringValue = cpu ? "100% = one core · readable processes" : "Resident memory · readable processes"
        let stale = snapshot?.isStale(at: .now) == true
        footer.stringValue = stale ? "Readings are stale · waiting for a new sample" : pinned ? "Pinned · Esc or × to close · C / M to switch" : "Click the chart to pin · C / M to switch"
        let rows = (cpu ? snapshot?.topCPU : snapshot?.topMemory) ?? []
        for index in 0..<5 {
            names[index].textColor = stale ? .secondaryLabelColor : .labelColor
            amounts[index].textColor = stale ? .secondaryLabelColor : .labelColor
            guard index < rows.count else {
                icons[index].image = nil
                icons[index].isHidden = true
                names[index].frame.origin.x = 12
                names[index].frame.size.width = bounds.width - 110
                names[index].stringValue = index == 0 ? (snapshot == nil ? "Readings unavailable" : cpu ? "Measuring CPU…" : "No readable processes") : ""
                names[index].toolTip = nil
                names[index].setAccessibilityLabel(nil)
                amounts[index].stringValue = ""
                continue
            }
            let row = rows[index]
            icons[index].image = iconProvider.icon(for: row.pid)
            icons[index].isHidden = false
            icons[index].alphaValue = stale ? 0.5 : 1
            names[index].frame.origin.x = 34
            names[index].frame.size.width = bounds.width - 132
            names[index].stringValue = row.name
            names[index].toolTip = "\(row.name) · PID \(row.pid)"
            names[index].setAccessibilityLabel("\(row.name), process \(row.pid)")
            amounts[index].stringValue = cpu ? String(format: "%.1f%%", row.cpuPercent ?? 0) : MetricFormat.bytes(row.residentBytes)
        }
    }
}
