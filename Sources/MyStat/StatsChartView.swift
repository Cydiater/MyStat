import Cocoa

final class StatsChartView: NSView {
    var title = ""
    var subtitle = ""
    var color: NSColor = DashboardStyle.orange
    var capacity = 90
    var windowMinutes = 3
    var onProcessPress: (() -> Void)?
    private(set) var values: [Double] = []

    override func mouseDown(with event: NSEvent) { onProcessPress?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        guard let onProcessPress else { return false }
        onProcessPress(); return true
    }

    func update(values: [Double], capacity: Int, subtitle: String) {
        self.values = values
        self.capacity = capacity
        self.subtitle = subtitle
        setAccessibilityValue(String(format: "%.1f%%, %@", values.last ?? 0, subtitle))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        DashboardStyle.drawContent(appearance: effectiveAppearance) { drawChart() }
    }

    private func drawChart() {
        DashboardStyle.card(bounds.insetBy(dx: 8, dy: 3))
        DashboardStyle.label(title, in: NSRect(x: 20, y: bounds.height - 26, width: 120, height: 17),
                             size: 12, weight: .semibold)
        if onProcessPress != nil {
            DashboardStyle.label("Processes ›", in: NSRect(x: bounds.width - 120, y: bounds.height - 26, width: 100, height: 16),
                                 size: 11, color: DashboardStyle.muted, alignment: .right)
        }
        DashboardStyle.label(values.last.map { String(format: "%.1f%%", $0) } ?? "—",
                             in: NSRect(x: 20, y: bounds.height - 56, width: 116, height: 30),
                             size: 25, weight: .medium, mono: true)
        DashboardStyle.label(subtitle, in: NSRect(x: 140, y: bounds.height - 51, width: bounds.width - 160, height: 16),
                             size: 10, color: DashboardStyle.muted, alignment: .right, mono: true)

        let plot = NSRect(x: 42, y: 24, width: max(1, bounds.width - 62), height: max(1, bounds.height - 88))
        for value in [0, 50, 100] {
            let y = plot.minY + plot.height * CGFloat(value) / 100
            let line = NSBezierPath()
            line.move(to: NSPoint(x: plot.minX, y: y)); line.line(to: NSPoint(x: plot.maxX, y: y))
            DashboardStyle.grid.setStroke(); line.lineWidth = 0.5; line.stroke()
            DashboardStyle.label("\(value)", in: NSRect(x: 12, y: y - 5, width: 25, height: 12),
                                 size: 8, color: DashboardStyle.muted, alignment: .right, mono: true)
        }
        let tickCount = 3
        for index in 0...tickCount {
            let x = plot.minX + plot.width * CGFloat(index) / CGFloat(tickCount)
            let minutes = windowMinutes * (tickCount - index) / tickCount
            let label = index == tickCount ? "now" : minutes == 60 ? "1h" : "\(minutes)m"
            DashboardStyle.label(label, in: NSRect(x: x - (index == tickCount ? 28 : 0), y: 8, width: 30, height: 12),
                                 size: 8, color: DashboardStyle.muted, alignment: index == tickCount ? .right : .left)
        }
        guard capacity >= 2, !values.isEmpty else { return }
        let samples = Array(values.suffix(capacity))
        let step = plot.width / CGFloat(capacity - 1)
        let leading = capacity - samples.count
        let line = NSBezierPath()
        line.lineJoinStyle = .round; line.lineCapStyle = .round; line.lineWidth = 1.75
        var last = NSPoint.zero
        for (index, value) in samples.enumerated() {
            let point = NSPoint(x: plot.minX + CGFloat(leading + index) * step,
                                y: plot.minY + CGFloat(min(100, max(0, value))) / 100 * plot.height)
            if index == 0 { line.move(to: point) } else { line.line(to: point) }
            last = point
        }
        let area = line.copy() as! NSBezierPath
        area.line(to: NSPoint(x: last.x, y: plot.minY))
        area.line(to: NSPoint(x: plot.minX + CGFloat(leading) * step, y: plot.minY)); area.close()
        color.withAlphaComponent(0.1).setFill(); area.fill()
        color.setStroke(); line.stroke()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: last.x - 2, y: last.y - 2, width: 4, height: 4)).fill()
    }
}
