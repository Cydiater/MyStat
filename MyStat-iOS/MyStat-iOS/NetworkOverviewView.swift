import SwiftUI
import Charts

struct NetworkOverviewView: View {
    let stats: LiveStats
    let samples: [StatsSample]
    @State private var minutes = 3
    @State private var showsApps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Network", systemImage: "network").font(.subheadline.bold()).foregroundStyle(.blue)
            HStack(spacing: 16) {
                rate("Download", symbol: "arrow.down", value: stats.network?.downloadBytesPerSecond, color: .blue)
                rate("Upload", symbol: "arrow.up", value: stats.network?.uploadBytesPerSecond, color: .purple)
            }
            Picker("Network history range", selection: $minutes) {
                Text("3m").tag(3)
                Text("15m").tag(15)
                Text("1h").tag(60)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("networkHistoryRange")
            TimelineView(.periodic(from: .now, by: 2)) { context in
                NetworkHistoryChart(samples: samples, duration: Double(minutes * 60), now: context.date)
                    .frame(height: 140)
            }
            Text("Wi-Fi + Ethernet · automatic scale\nSolid download · dashed upload")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            DisclosureGroup(isExpanded: $showsApps) {
                NetworkAppsView(snapshot: stats.networkApps, needsCompanionUpdate: stats.needsNetworkCompanionUpdate)
                    .padding(.top, 10)
            } label: {
                Label("Top network apps", systemImage: "list.number").font(.subheadline.bold())
            }
            .tint(.blue)
            .accessibilityIdentifier("networkAppsDisclosure")
        }
        .padding(18)
        .background(.blue.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.blue.opacity(0.13)))
    }

    private func rate(_ title: String, symbol: String, value: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(MetricFormat.rate(value)).font(.system(size: 25, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct NetworkHistoryChart: View {
    let samples: [StatsSample]
    var duration: TimeInterval = 180
    let now: Date
    var compact = false

    var body: some View {
        let start = now.addingTimeInterval(-duration)
        let series = NetworkHistorySeries(samples: samples, start: start, end: now)
        Chart(series.points) { point in
            LineMark(x: .value("Time", point.timestamp), y: .value("Download", point.download),
                     series: .value("Series", "Download \(point.segment)"))
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            LineMark(x: .value("Time", point.timestamp), y: .value("Upload", point.upload),
                     series: .value("Series", "Upload \(point.segment)"))
                .foregroundStyle(.purple)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        .chartXScale(domain: start...now)
        .chartYScale(domain: 0...series.ceiling)
        .chartXAxis {
            if !compact {
                AxisMarks(values: [start, now.addingTimeInterval(-duration / 2), now]) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(date: .omitted, time: .shortened)).font(.system(size: 9))
                        }
                    }
                }
            }
        }
        .chartYAxis {
            if !compact {
                AxisMarks(values: [0, series.ceiling / 2, series.ceiling]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    AxisValueLabel {
                        Text(MetricFormat.rate(value.as(Double.self))).font(.system(size: 9))
                    }
                }
            }
        }
        .overlay {
            if series.points.isEmpty && !compact {
                Text("No network readings in this range").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Download and upload history")
        .accessibilityValue("Last \(Int(duration / 60)) minutes. Automatic scale up to \(MetricFormat.rate(series.ceiling)).")
        .accessibilityHidden(compact)
    }
}
