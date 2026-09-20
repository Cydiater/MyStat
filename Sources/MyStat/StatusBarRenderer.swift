import Cocoa

enum StatusBarRenderer {
    private static let labelWidth: CGFloat = 9
    private static let labelChartGap: CGFloat = 2
    private static let chartWidth: CGFloat = 26
    private static let chartHeight: CGFloat = 14
    private static let groupGap: CGFloat = 5
    private static let keepAwakeWidth: CGFloat = 18

    static func render(cpu: [Double], memory: [Double], capacity: Int, keepAwake: KeepAwakeStatus = .off,
                       network: NetworkChartData? = nil) -> NSImage {
        let barHeight = NSStatusBar.system.thickness
        let chartsWidth = labelWidth + labelChartGap + chartWidth + groupGap
            + labelWidth + labelChartGap + chartWidth
            + (network == nil ? 0 : groupGap + labelWidth + labelChartGap + chartWidth)
        let totalWidth = chartsWidth + (keepAwake == .off ? 0 : groupGap + keepAwakeWidth)
        let size = NSSize(width: totalWidth, height: barHeight)

        // Snapshot values so the drawing closure isn't racing the recorder.
        let cpuSnapshot = cpu
        let memSnapshot = memory

        // Drawn as a template image: only the alpha channel is used; AppKit
        // re-tints it to the menu-bar text color (white in dark mode, black in
        // light) and handles the active/click highlight, matching system icons.
        let image = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            let chartY = (barHeight - chartHeight) / 2
            let tint = NSColor.black // RGB is discarded for template images.

            drawVerticalLabel(
                "CPU",
                color: tint,
                rect: NSRect(x: x, y: 0, width: labelWidth, height: barHeight)
            )
            x += labelWidth + labelChartGap
            drawChart(
                rect: NSRect(x: x, y: chartY, width: chartWidth, height: chartHeight),
                values: cpuSnapshot, capacity: capacity, color: tint
            )
            x += chartWidth + groupGap

            drawVerticalLabel(
                "MEM",
                color: tint,
                rect: NSRect(x: x, y: 0, width: labelWidth, height: barHeight)
            )
            x += labelWidth + labelChartGap
            drawChart(
                rect: NSRect(x: x, y: chartY, width: chartWidth, height: chartHeight),
                values: memSnapshot, capacity: capacity, color: tint
            )
            if let network {
                x += chartWidth + groupGap
                drawVerticalLabel("NET", color: tint,
                    rect: NSRect(x: x, y: 0, width: labelWidth, height: barHeight))
                x += labelWidth + labelChartGap
                drawNetwork(network, rect: NSRect(x: x, y: chartY, width: chartWidth, height: chartHeight), color: tint)
            }
            if keepAwake != .off {
                drawKeepAwake(keepAwake, color: tint,
                    rect: NSRect(x: chartsWidth + groupGap, y: (barHeight - 18) / 2, width: keepAwakeWidth, height: 18))
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Download above the center line, upload below; both use the same rate scale.
    private static func drawNetwork(_ data: NetworkChartData, rect: NSRect, color: NSColor) {
        color.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        let center = NSBezierPath()
        center.move(to: NSPoint(x: rect.minX, y: rect.midY))
        center.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        color.withAlphaComponent(0.25).setStroke(); center.lineWidth = 0.5; center.stroke()
        for (values, direction) in [(data.download, 1.0), (data.upload, -1.0)] {
            let line = NSBezierPath()
            line.lineWidth = 1.1; line.lineJoinStyle = .round; line.lineCapStyle = .round
            var connected = false
            for (index, value) in values.enumerated() {
                guard let value else { connected = false; continue }
                let point = NSPoint(x: rect.minX + CGFloat(data.capacity - values.count + index) / CGFloat(data.capacity - 1) * rect.width,
                    y: rect.midY + CGFloat(value / data.ceiling * direction) * (rect.height / 2 - 0.5))
                if connected { line.line(to: point) } else { line.move(to: point) }
                connected = true
            }
            color.setStroke(); line.stroke()
        }
    }

    private static func drawKeepAwake(_ status: KeepAwakeStatus, color: NSColor, rect: NSRect) {
        guard let remaining = status.remainingFraction else {
            let label = NSAttributedString(string: "∞", attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: color
            ])
            let size = label.size()
            label.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            return
        }

        let symbol = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        symbol?.draw(in: NSRect(x: rect.midX - 6, y: rect.minY + 5, width: 12, height: 12))

        let track = NSRect(x: rect.minX, y: rect.minY + 1, width: rect.width, height: 2)
        color.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1, yRadius: 1).fill()
        if remaining > 0 {
            let fill = NSRect(x: track.minX, y: track.minY, width: track.width * remaining, height: track.height)
            color.setFill()
            NSBezierPath(roundedRect: fill, xRadius: min(1, fill.width / 2), yRadius: 1).fill()
        }
    }

    private static func drawVerticalLabel(_ text: String, color: NSColor, rect: NSRect) {
        let font = NSFont.systemFont(ofSize: 8, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: -0.3 as NSNumber,
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attr.size()

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        // Rotate -90° around the rect's center so the string reads top-to-bottom.
        ctx.translateBy(x: rect.midX, y: rect.midY)
        ctx.rotate(by: -.pi / 2)
        attr.draw(at: NSPoint(x: -textSize.width / 2, y: -textSize.height / 2))
    }

    private static func drawChart(rect: NSRect, values: [Double], capacity: Int, color: NSColor) {
        let bg = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        bg.fill()

        guard values.count >= 2, capacity >= 2 else { return }

        let step = rect.width / CGFloat(capacity - 1)
        let leading = capacity - values.count
        let firstX = rect.minX + CGFloat(leading) * step
        let lastX = rect.minX + CGFloat(leading + values.count - 1) * step

        let line = NSBezierPath()
        line.lineJoinStyle = .round
        line.lineCapStyle = .round
        line.lineWidth = 1.2

        for (i, v) in values.enumerated() {
            let clamped = min(100.0, max(0.0, v))
            let xi = rect.minX + CGFloat(leading + i) * step
            let yi = rect.minY + CGFloat(clamped / 100.0) * rect.height
            let pt = NSPoint(x: xi, y: yi)
            if i == 0 { line.move(to: pt) } else { line.line(to: pt) }
        }

        // Close down to the baseline for a translucent fill under the line.
        let fill = line.copy() as! NSBezierPath
        fill.line(to: NSPoint(x: lastX, y: rect.minY))
        fill.line(to: NSPoint(x: firstX, y: rect.minY))
        fill.close()
        color.withAlphaComponent(0.28).setFill()
        fill.fill()

        color.setStroke()
        line.stroke()
    }
}
