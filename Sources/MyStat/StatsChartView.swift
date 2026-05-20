import Cocoa

final class StatsChartView: NSView {
    var title: String = ""
    var subtitle: String = ""
    var color: NSColor = .systemOrange
    var capacity: Int = 90
    var windowMinutes: Int = 3

    private(set) var values: [Double] = []

    func update(values: [Double], capacity: Int, subtitle: String) {
        self.values = values
        self.capacity = capacity
        self.subtitle = subtitle
        needsDisplay = true
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let pad: CGFloat = 12
        let headerH: CGFloat = 16
        let axisLabelH: CGFloat = 12
        let axisGap: CGFloat = 4
        let headerGap: CGFloat = 4
        let headerY = bounds.maxY - pad - headerH

        // Header: title (left) + subtitle (right)
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let titleAttr = NSAttributedString(string: title, attributes: [
            .font: titleFont,
            .foregroundColor: color,
        ])
        titleAttr.draw(at: NSPoint(x: pad, y: headerY))

        let subtitleFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let subtitleAttr = NSAttributedString(string: subtitle, attributes: [
            .font: subtitleFont,
            .foregroundColor: NSColor.labelColor,
        ])
        let subtitleSize = subtitleAttr.size()
        subtitleAttr.draw(at: NSPoint(
            x: bounds.maxX - pad - subtitleSize.width,
            y: headerY
        ))

        // Chart area sits between header and axis labels.
        let chartRect = NSRect(
            x: bounds.minX + pad,
            y: bounds.minY + pad + axisLabelH + axisGap,
            width: bounds.width - pad * 2,
            height: bounds.height - pad * 2 - headerH - headerGap - axisLabelH - axisGap
        )

        let bg = NSBezierPath(roundedRect: chartRect, xRadius: 4, yRadius: 4)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        bg.fill()

        // Horizontal gridlines at 50% and 100%.
        NSColor.labelColor.withAlphaComponent(0.10).setStroke()
        for fraction in [0.5, 1.0] {
            let y = chartRect.minY + chartRect.height * CGFloat(fraction)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: chartRect.minX, y: y))
            path.line(to: NSPoint(x: chartRect.maxX, y: y))
            path.lineWidth = 0.5
            path.stroke()
        }

        // Vertical gridlines + x-axis time labels at each minute boundary.
        drawTimeAxis(chartRect: chartRect, axisLabelTop: chartRect.minY - axisGap)

        guard values.count >= 2, capacity >= 2 else { return }

        let step = chartRect.width / CGFloat(capacity - 1)
        let leading = capacity - values.count
        let firstX = chartRect.minX + CGFloat(leading) * step
        let lastX = chartRect.minX + CGFloat(leading + values.count - 1) * step

        let line = NSBezierPath()
        line.lineJoinStyle = .round
        line.lineCapStyle = .round
        line.lineWidth = 1.5

        for (i, v) in values.enumerated() {
            let clamped = min(100.0, max(0.0, v))
            let xi = chartRect.minX + CGFloat(leading + i) * step
            let yi = chartRect.minY + CGFloat(clamped / 100.0) * chartRect.height
            let pt = NSPoint(x: xi, y: yi)
            if i == 0 { line.move(to: pt) } else { line.line(to: pt) }
        }

        let fill = line.copy() as! NSBezierPath
        fill.line(to: NSPoint(x: lastX, y: chartRect.minY))
        fill.line(to: NSPoint(x: firstX, y: chartRect.minY))
        fill.close()
        color.withAlphaComponent(0.25).setFill()
        fill.fill()

        color.setStroke()
        line.stroke()
    }

    private var axisTickMinutes: Int {
        switch windowMinutes {
        case ...3: return 1
        case 4...15: return 5
        case 16...30: return 10
        default: return 15
        }
    }

    private static func formatTimeAgo(_ minutes: Int) -> String {
        if minutes == 0 { return "now" }
        if minutes >= 60, minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    private func drawTimeAxis(chartRect: NSRect, axisLabelTop: CGFloat) {
        guard windowMinutes > 0 else { return }
        let tickMin = axisTickMinutes

        let labelFont = NSFont.systemFont(ofSize: 9, weight: .regular)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let tickColor = NSColor.labelColor.withAlphaComponent(0.10)

        var ticks: [Int] = []
        var m = 0
        while m <= windowMinutes {
            ticks.append(m)
            m += tickMin
        }
        if ticks.last != windowMinutes {
            ticks.append(windowMinutes) // ensure "now" lands at the right edge
        }

        for m in ticks {
            let frac = CGFloat(m) / CGFloat(windowMinutes)
            let x = chartRect.minX + chartRect.width * frac
            let minutesAgo = windowMinutes - m
            let label = Self.formatTimeAgo(minutesAgo)

            if m > 0 && m < windowMinutes {
                tickColor.setStroke()
                let tick = NSBezierPath()
                tick.move(to: NSPoint(x: x, y: chartRect.minY))
                tick.line(to: NSPoint(x: x, y: chartRect.maxY))
                tick.lineWidth = 0.5
                tick.stroke()
            }

            let attr = NSAttributedString(string: label, attributes: labelAttrs)
            let size = attr.size()
            let labelX: CGFloat
            if m == 0 {
                labelX = x
            } else if m == windowMinutes {
                labelX = x - size.width
            } else {
                labelX = x - size.width / 2
            }
            attr.draw(at: NSPoint(x: labelX, y: axisLabelTop - size.height))
        }
    }
}
