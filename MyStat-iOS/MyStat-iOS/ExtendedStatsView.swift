import SwiftUI

struct ExtendedStatsView: View {
    let stats: LiveStats

    var body: some View {
        VStack(spacing: 16) {
            card("Network", icon: "network", color: .blue) {
                HStack(spacing: 20) {
                    reading("DOWNLOAD", value: MetricFormat.rate(stats.network?.downloadBytesPerSecond), color: .blue)
                    reading("UPLOAD", value: MetricFormat.rate(stats.network?.uploadBytesPerSecond), color: .purple)
                }
                Text("Wi-Fi + Ethernet · includes local traffic").font(.caption).foregroundStyle(.secondary)
            }
            card("Power", icon: "bolt.fill", color: .green) {
                HStack(spacing: 20) {
                    reading("BATTERY", value: stats.power?.batteryPercent.map { String(format: "%.0f%%", $0) } ?? "—", color: .green)
                    reading(flowTitle, value: MetricFormat.watts(stats.power?.batteryWatts), color: .green)
                }
                Text(stats.power?.status ?? "Power readings unavailable").font(.subheadline).foregroundStyle(.secondary)
                if let rating = stats.power?.adapterWatts { detail("Adapter rating", MetricFormat.watts(rating)) }
                if let cycles = stats.power?.cycleCount { detail("Battery cycles", String(cycles)) }
                Text("Watts show net flow at the battery. Adapter rating is its reported capacity; wall power and USB output are unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            card("System", icon: "desktopcomputer", color: .teal) {
                HStack(spacing: 20) {
                    reading("STORAGE FREE", value: MetricFormat.bytes(stats.system?.diskFreeBytes), color: .teal)
                    reading("SWAP USED", value: MetricFormat.bytes(stats.system?.swapUsedBytes), color: .teal)
                }
                if let free = stats.system?.diskFreeBytes, let total = stats.system?.diskTotalBytes, total > 0 {
                    ProgressView(value: Double(total - min(free, total)), total: Double(total)).tint(.teal)
                    detail("Home volume capacity", MetricFormat.bytes(total))
                }
                detail("Thermal state", stats.system?.thermalState.label ?? "—")
                detail("Uptime", MetricFormat.uptime(stats.system?.uptimeSeconds))
            }
            card("Codex tokens", icon: "sparkles", color: .purple) {
                if let tokens = stats.tokens {
                    reading("TODAY ON THIS MAC", value: MetricFormat.tokens(tokens.totalTokens), color: .purple)
                    detail("Input", tokens.inputTokens.formatted())
                    detail("Cached input · included above", tokens.cachedInputTokens.formatted())
                    detail("Output", tokens.outputTokens.formatted())
                    Text("Checked \(tokens.updatedAt, style: .relative) ago · \(tokens.timeZone)")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No local usage available").font(.headline)
                    Text("Usage appears when readable Codex session logs contain token counts. The Mac checks every 30 seconds.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Recorded local sessions only. Cached input is part of input; reasoning is part of output. Account limits, billing and other AI apps are not included.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var flowTitle: String {
        guard let watts = stats.power?.batteryWatts else { return "BATTERY FLOW" }
        return watts > 0 ? "BATTERY IN" : watts < 0 ? "BATTERY OUT" : "BATTERY IDLE"
    }

    private func card<Content: View>(_ title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.subheadline.bold()).foregroundStyle(color)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.13)))
    }

    private func reading(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(color).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }.font(.caption)
    }
}

/// Always-visible secondary readings sized to leave room for the big gauges.
struct DeskExtrasView: View {
    let stats: LiveStats?
    let compact: Bool

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: compact ? 3 : 2), spacing: 10) {
            tile("NETWORK", color: .blue) {
                Text("↓ \(MetricFormat.rate(stats?.network?.downloadBytesPerSecond))")
                Text("↑ \(MetricFormat.rate(stats?.network?.uploadBytesPerSecond))")
            }
            tile("POWER", color: .green) {
                if let watts = stats?.power?.batteryWatts {
                    Text("\(MetricFormat.watts(watts)) \(watts > 0 ? "in" : watts < 0 ? "out" : "idle")")
                } else { Text(stats?.power?.status ?? "—") }
                if let percent = stats?.power?.batteryPercent { Text("Battery \(Int(percent))%") }
                else { Text("Battery watts unavailable").font(.system(size: 10)) }
            }
            tile("CODEX TODAY", color: .purple) {
                Text(stats?.tokens.map { MetricFormat.tokens($0.totalTokens) + " tokens" } ?? "—")
                Text("Local sessions").font(.system(size: 10))
            }
            if !compact {
                tile("SYSTEM", color: .teal) {
                    Text("\(MetricFormat.bytes(stats?.system?.diskFreeBytes)) free")
                    Text(stats?.system?.thermalState.label ?? "—")
                }
            }
        }
    }

    private func tile<Content: View>(_ title: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(color)
            content().font(.system(size: compact ? 14 : 17, weight: .medium, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 48 : 56, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.065), in: RoundedRectangle(cornerRadius: 13))
        .accessibilityElement(children: .combine)
    }
}
