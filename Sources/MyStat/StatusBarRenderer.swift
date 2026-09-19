import Cocoa

enum StatusBarRenderer {
    private static let labelWidth: CGFloat = 9
    private static let labelChartGap: CGFloat = 2
    private static let chartWidth: CGFloat = 26
    private static let chartHeight: CGFloat = 14
    private static let groupGap: CGFloat = 5
    private static let countdownFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    // Reserve room for hours throughout the session, including the 1:00:00 → 59:59 transition.
    private static let countdownTextWidth = ceil(("8:00:00" as NSString).size(withAttributes: [.font: countdownFont]).width)
    private static let countdownWidth = 6 + 12 + 4 + countdownTextWidth + 6

    static func render(cpu: [Double], memory: [Double], capacity: Int, keepAwake: KeepAwakeStatus = .off) -> NSImage {
        let barHeight = NSStatusBar.system.thickness
        let chartsWidth = labelWidth + labelChartGap + chartWidth + groupGap
            + labelWidth + labelChartGap + chartWidth
        let totalWidth = chartsWidth + (keepAwake.countdown == nil ? 0 : groupGap + countdownWidth)
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
            if let countdown = keepAwake.countdown {
                drawCountdown(countdown, color: tint,
                    rect: NSRect(x: chartsWidth + groupGap, y: (barHeight - 18) / 2, width: countdownWidth, height: 18))
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawCountdown(_ text: String, color: NSColor, rect: NSRect) {
        color.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()

        let symbol = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        symbol?.draw(in: NSRect(x: rect.minX + 6, y: rect.midY - 6, width: 12, height: 12))
        let label = NSAttributedString(string: text, attributes: [.font: countdownFont, .foregroundColor: color])
        let size = label.size()
        let textX = rect.minX + 22 + (countdownTextWidth - size.width) / 2
        label.draw(at: NSPoint(x: textX, y: rect.midY - size.height / 2))
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
