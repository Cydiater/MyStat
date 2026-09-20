import Cocoa
import MyStatCore

final class NetworkChartView: NSView {
    var windowMinutes = 3
    private(set) var data = NetworkChartData()

    func update(_ data: NetworkChartData) {
        self.data = data
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Network chart")
        setAccessibilityValue("Download \(MetricFormat.rate(data.download.last ?? nil)), upload \(MetricFormat.rate(data.upload.last ?? nil)). Last \(windowMinutes) minutes, automatic scale.")
        toolTip = "Physical Wi-Fi and Ethernet · automatic scale · solid download, dashed upload"
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        DashboardStyle.drawContent(appearance: effectiveAppearance) {
            DashboardStyle.card(bounds.insetBy(dx: 8, dy: 3))
            DashboardStyle.label("Network", in: NSRect(x: 20, y: bounds.height - 26, width: 120, height: 17), size: 12, weight: .semibold)
            DashboardStyle.label("Auto scale", in: NSRect(x: 230, y: bounds.height - 26, width: 110, height: 17),
                                 size: 10, color: DashboardStyle.muted, alignment: .right)
            for (index, entry) in [("↓", data.download, NSColor.systemBlue), ("↑", data.upload, NSColor.systemPurple)].enumerated() {
                DashboardStyle.label("\(entry.0) \(MetricFormat.rate(entry.1.last ?? nil))",
                    in: NSRect(x: 20 + CGFloat(index) * 168, y: bounds.height - 54, width: 160, height: 26),
                    size: 19, color: entry.2, weight: .medium, mono: true)
            }
            let plot = NSRect(x: 72, y: 24, width: max(1, bounds.width - 92), height: max(1, bounds.height - 88))
            for fraction in [0.0, 0.5, 1.0] {
                let y = plot.minY + plot.height * fraction
                let line = NSBezierPath()
                line.move(to: NSPoint(x: plot.minX, y: y)); line.line(to: NSPoint(x: plot.maxX, y: y))
                DashboardStyle.grid.setStroke(); line.lineWidth = 0.5; line.stroke()
                DashboardStyle.label(MetricFormat.rate(data.ceiling * fraction),
                    in: NSRect(x: 10, y: y - 5, width: 56, height: 12), size: 8,
                    color: DashboardStyle.muted, alignment: .right, mono: true)
            }
            for index in 0...3 {
                let x = plot.minX + plot.width * CGFloat(index) / 3
                let minutes = windowMinutes * (3 - index) / 3
                let label = index == 3 ? "now" : minutes == 60 ? "1h" : "\(minutes)m"
                DashboardStyle.label(label, in: NSRect(x: x - (index == 3 ? 28 : 0), y: 8, width: 30, height: 12),
                    size: 8, color: DashboardStyle.muted, alignment: index == 3 ? .right : .left)
            }
            Self.drawSeries(data.download, data: data, rect: plot, color: .systemBlue)
            Self.drawSeries(data.upload, data: data, rect: plot, color: .systemPurple, dashed: true)
        }
    }

    static func drawSeries(_ values: [Double?], data: NetworkChartData, rect: NSRect, color: NSColor,
                           dashed: Bool = false, lineWidth: CGFloat = 1.5) {
        let line = NSBezierPath()
        line.lineWidth = lineWidth; line.lineJoinStyle = .round; line.lineCapStyle = .round
        if dashed { line.setLineDash([3, 2], count: 2, phase: 0) }
        let leading = data.capacity - values.count
        var connected = false
        for (index, value) in values.enumerated() {
            guard let value else { connected = false; continue }
            let point = NSPoint(x: rect.minX + CGFloat(leading + index) / CGFloat(data.capacity - 1) * rect.width,
                                y: rect.minY + CGFloat(value / data.ceiling) * rect.height)
            if connected { line.line(to: point) } else { line.move(to: point) }
            connected = true
        }
        color.setStroke(); line.stroke()
    }
}
