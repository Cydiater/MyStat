import Cocoa
import MyStatCore

final class MetricsOverviewView: NSView {
    private var cards: [(String, String, String)] = []
    private var systemRows: [(String, String)] = []
    private var tokensValue = "—"
    private var tokensDetail = "No local usage"
    override var isFlipped: Bool { true }

    func update(network: NetworkStats?, power: PowerStats?, system: SystemStats, tokens: TokenUsage?) {
        let battery = power?.batteryPercent.map { String(format: "%.0f%%", $0) } ?? "—"
        let batteryState = power?.status ?? "Unavailable"
        let flow = power?.batteryWatts.map { $0 > 0 ? "Charging" : $0 < 0 ? "Discharging" : "Idle" } ?? "Unavailable"
        cards = [
            ("Download", MetricFormat.rate(network?.downloadBytesPerSecond), "Physical network adapters"),
            ("Upload", MetricFormat.rate(network?.uploadBytesPerSecond), "Physical network adapters"),
            ("Battery", battery, batteryState),
            ("Battery flow", MetricFormat.watts(power?.batteryWatts), "\(flow) · Adapter \(MetricFormat.watts(power?.adapterWatts))")
        ]
        systemRows = [
            ("Storage free", MetricFormat.bytes(system.diskFreeBytes)),
            ("Swap used", MetricFormat.bytes(system.swapUsedBytes)),
            ("Thermal / uptime", "\(system.thermalState.label) · \(MetricFormat.uptime(system.uptimeSeconds))")
        ]
        tokensValue = tokens.map { MetricFormat.tokens($0.totalTokens) } ?? "—"
        tokensDetail = tokens.map { "In \(MetricFormat.tokens($0.inputTokens))   Out \(MetricFormat.tokens($0.outputTokens))   Cached \(MetricFormat.tokens($0.cachedInputTokens))" } ?? "No local usage"
        toolTip = "Network includes local traffic. Battery flow is net battery power, not wall consumption. Codex counts today's recorded local usage, including cached input, not account quota or billing."
        setAccessibilityElement(true)
        setAccessibilityLabel((cards.map { "\($0.0): \($0.1), \($0.2)" } + systemRows.map { "\($0.0): \($0.1)" } + ["Codex today: \(tokensValue). \(tokensDetail)"]).joined(separator: "; "))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        DashboardStyle.drawContent(appearance: effectiveAppearance) { drawMetrics() }
    }

    private func drawMetrics() {
        let width = (bounds.width - 24) / 2
        for (index, card) in cards.enumerated() {
            let rect = NSRect(x: 8 + CGFloat(index % 2) * (width + 8), y: 4 + CGFloat(index / 2) * 64, width: width, height: 58)
            DashboardStyle.card(rect)
            DashboardStyle.label(card.0, in: NSRect(x: rect.minX + 10, y: rect.minY + 6, width: width - 20, height: 14), size: 10, color: DashboardStyle.muted, weight: .medium)
            DashboardStyle.label(card.1, in: NSRect(x: rect.minX + 10, y: rect.minY + 20, width: width - 20, height: 23), size: 19, weight: .medium, mono: true)
            DashboardStyle.label(card.2, in: NSRect(x: rect.minX + 10, y: rect.minY + 43, width: width - 20, height: 12), size: 8, color: DashboardStyle.muted)
        }
        DashboardStyle.card(NSRect(x: 8, y: 132, width: bounds.width - 16, height: 70))
        for (index, row) in systemRows.enumerated() {
            let y = 140 + CGFloat(index) * 20
            DashboardStyle.label(row.0, in: NSRect(x: 18, y: y, width: 118, height: 16), size: 10, color: DashboardStyle.muted)
            DashboardStyle.label(row.1, in: NSRect(x: 140, y: y, width: bounds.width - 158, height: 16), size: 11, alignment: .right, mono: true)
        }
        DashboardStyle.card(NSRect(x: 8, y: 210, width: bounds.width - 16, height: 58))
        DashboardStyle.label("Codex today", in: NSRect(x: 18, y: 218, width: 110, height: 16), size: 11, color: DashboardStyle.muted, weight: .medium)
        DashboardStyle.label(tokensValue, in: NSRect(x: 142, y: 215, width: bounds.width - 160, height: 26), size: 22, weight: .medium, alignment: .right, mono: true)
        DashboardStyle.label(tokensDetail, in: NSRect(x: 18, y: 247, width: bounds.width - 36, height: 14), size: 9, color: DashboardStyle.muted, mono: true)
    }
}
