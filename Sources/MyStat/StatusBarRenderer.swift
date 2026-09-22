import Cocoa
import MyStatCore

enum StatusBarRenderer {
    private static let chartWidth: CGFloat = 26
    private static let chartHeight: CGFloat = 14
    private static let groupGap: CGFloat = 5
    private static let keepAwakeWidth: CGFloat = 18

    static func render(cpu: [Double], memory: [Double], capacity: Int, keepAwake: KeepAwakeStatus = .off,
                       network: NetworkChartData? = nil, metric: StatusBarMetric = .cpu,
                       preferUpload: Bool? = nil, unavailable: Bool = false) -> NSImage {
        let barHeight = NSStatusBar.system.thickness
        let caption = caption(cpu: cpu.last, memory: memory.last, network: network, metric: metric,
                              preferUpload: preferUpload, unavailable: unavailable)
        let label = NSAttributedString(string: caption.label, attributes: [
            .font: NSFont.systemFont(ofSize: 7, weight: .semibold), .foregroundColor: NSColor.black
        ])
        let value = NSAttributedString(string: caption.value, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.black
        ])
        // Fit the visible caption; a shared maximum width leaves a blank tail
        // beside short percentages that looks like an inactive Keep Awake slot.
        let textWidth = ceil(max(label.size().width, value.size().width))
        let chartsWidth = chartWidth + groupGap + textWidth
        let size = NSSize(width: chartsWidth + (keepAwake == .off ? 0 : groupGap + keepAwakeWidth), height: barHeight)
        // AppKit tints the template to the system menu-bar text and selection color.
        let image = NSImage(size: size, flipped: false) { _ in
            let tint = NSColor.black
            let rect = NSRect(x: 0, y: (barHeight - chartHeight) / 2, width: chartWidth, height: chartHeight)
            if metric == .network {
                drawNetwork(network ?? .init(), rect: rect, color: tint)
            } else {
                drawChart(rect: rect, values: metric == .cpu ? cpu : memory, capacity: capacity, color: tint)
            }
            let blockHeight = label.size().height + value.size().height - 1
            let bottom = (barHeight - blockHeight) / 2
            let x = chartWidth + groupGap
            label.draw(at: NSPoint(x: x, y: bottom + value.size().height - 1))
            value.draw(at: NSPoint(x: x, y: bottom))
            if keepAwake != .off {
                drawKeepAwake(keepAwake, color: tint,
                    rect: NSRect(x: chartsWidth + groupGap, y: (barHeight - 18) / 2, width: keepAwakeWidth, height: 18))
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func caption(cpu: Double?, memory: Double?, network: NetworkChartData?, metric: StatusBarMetric,
                        preferUpload: Bool? = nil, unavailable: Bool = false) -> (label: String, value: String) {
        switch metric {
        case .cpu, .memory:
            let reading = metric == .cpu ? cpu : memory
            let value = !unavailable ? reading.flatMap { $0.isFinite && (0...100).contains($0) ? String(format: "%.0f%%", $0) : nil } : nil
            return (metric == .cpu ? "CPU" : "MEM", value ?? "—")
        case .network:
            let down = network?.download.last ?? nil, up = network?.upload.last ?? nil
            let upload = preferUpload ?? ((up ?? 0) > (down ?? 0))
            return (upload ? "NET ↑" : "NET ↓", unavailable ? "—" : compactRate(upload ? up : down))
        }
    }

    static func compactRate(_ rate: Double?) -> String {
        guard let rate, rate.isFinite, rate >= 0 else { return "—" }
        let units = ["B/s", "K/s", "M/s", "G/s", "T/s", "P/s", "E/s"]
        var value = rate, unit = 0
        while value >= 999.5 && unit < units.count - 1 { value /= 1_000; unit += 1 }
        guard value < 999.5 else { return "999E+" }
        return String(format: value < 9.95 && unit > 0 ? "%.1f%@" : "%.0f%@", value, units[unit])
    }

    static func explanation(_ highlight: StatusBarHighlight) -> String {
        switch highlight.reason {
        case .percentageChange(let delta):
            return String(format: "%@ %.1f points vs recent baseline", delta >= 0 ? "Up" : "Down", abs(delta))
        case .trafficChange(let delta, let upload):
            return "\(upload ? "Upload" : "Download") \(delta >= 0 ? "up" : "down") \(MetricFormat.rate(abs(delta))) vs recent baseline"
        case .highActivity: return highlight.metric == .memory ? "High memory use" : "Sustained \(highlight.metric.rawValue.lowercased()) activity"
        case .steady: return "No major recent change"
        case .warmingUp: return "Collecting recent activity…"
        case .unavailable: return "\(highlight.metric.rawValue) readings unavailable"
        }
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

    private static func drawChart(rect: NSRect, values: [Double], capacity: Int, color: NSColor) {
        let bg = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        color.withAlphaComponent(0.08).setFill()
        bg.fill()

        let values = Array(values.suffix(max(2, capacity)))
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
