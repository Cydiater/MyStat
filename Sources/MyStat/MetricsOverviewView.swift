import Cocoa
import MyStatCore

final class MetricsOverviewView: NSView {
    private var rows: [(String, String, NSColor)] = []
    override var isFlipped: Bool { true }

    func update(network: NetworkStats?, power: PowerStats?, system: SystemStats, tokens: TokenUsage?) {
        let flow: String
        if let watts = power?.batteryWatts {
            flow = "\(MetricFormat.watts(watts)) \(watts > 0 ? "in" : watts < 0 ? "out" : "idle")"
        } else { flow = "Unavailable" }
        let battery = power?.batteryPercent.map { String(format: "%.0f%% · %@", $0, power?.isCharging == true ? "charging" : power?.onACPower == true ? "plugged in" : "discharging") }
        rows = [
            ("↓ Download", MetricFormat.rate(network?.downloadBytesPerSecond), .systemBlue),
            ("↑ Upload", MetricFormat.rate(network?.uploadBytesPerSecond), .systemPurple),
            ("Battery", battery ?? power?.status ?? "Unavailable", .systemGreen),
            ("Battery flow", flow, .systemGreen),
            ("Adapter rating", MetricFormat.watts(power?.adapterWatts), .secondaryLabelColor),
            ("Storage free", MetricFormat.bytes(system.diskFreeBytes), .labelColor),
            ("Swap used", MetricFormat.bytes(system.swapUsedBytes), .labelColor),
            ("Thermal / uptime", "\(system.thermalState.label) · \(MetricFormat.uptime(system.uptimeSeconds))", .labelColor),
            ("Codex today", tokens.map { MetricFormat.tokens($0.totalTokens) + " tokens" } ?? "No local usage", .systemPurple),
            ("Input / output", "\(MetricFormat.tokens(tokens?.inputTokens)) / \(MetricFormat.tokens(tokens?.outputTokens))", .secondaryLabelColor),
            ("Cached input", MetricFormat.tokens(tokens?.cachedInputTokens), .secondaryLabelColor)
        ]
        toolTip = "Network: physical Wi-Fi and Ethernet, including local traffic. Battery flow is net battery power; adapter rating is not wall consumption. Codex: today's recorded local usage, including cached input. No account quota or billing data."
        setAccessibilityElement(true)
        setAccessibilityLabel(rows.map { "\($0.0): \($0.1)" }.joined(separator: ", "))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for (index, row) in rows.enumerated() {
            let y = CGFloat(index) * 20 + 8
            let label = NSAttributedString(string: row.0, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: row.2])
            label.draw(at: NSPoint(x: 12, y: y))
            let value = NSAttributedString(string: row.1, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.labelColor])
            value.draw(at: NSPoint(x: bounds.maxX - 12 - value.size().width, y: y))
        }
    }
}
