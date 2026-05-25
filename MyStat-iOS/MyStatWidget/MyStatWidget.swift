import WidgetKit
import SwiftUI

struct StatsEntry: TimelineEntry {
    let date: Date
    let cpu: Double
    let mem: Double
    let hostName: String?
    let isStale: Bool
}

struct StatsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatsEntry {
        StatsEntry(date: .now, cpu: 42, mem: 65, hostName: "Mac", isStale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        let nextUpdate = Calendar.current.date(byAdding: .second, value: 30, to: .now)!
        completion(Timeline(entries: [entry()], policy: .after(nextUpdate)))
    }

    private func entry() -> StatsEntry {
        let (cpu, mem, host, ts) = SharedDefaults.load()
        let stale = ts == 0 || Date().timeIntervalSince1970 - ts > 60
        return StatsEntry(date: .now, cpu: cpu, mem: mem, hostName: host, isStale: stale)
    }
}

struct SmallWidgetView: View {
    let entry: StatsEntry

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                widgetGauge(title: "CPU", value: entry.cpu, color: .orange)
                widgetGauge(title: "MEM", value: entry.mem, color: .teal)
            }

            if let host = entry.hostName {
                HStack(spacing: 4) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 8))
                    Text(host)
                        .font(.system(size: 9))
                }
                .foregroundStyle(entry.isStale ? .tertiary : .secondary)
            }
        }
        .containerBackground(.black, for: .widget)
    }

    private func widgetGauge(title: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(color.opacity(0.2), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(135))

                Circle()
                    .trim(from: 0, to: min(value / 100, 1.0) * 0.75)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(135))

                Text("\(Int(value))%")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 54, height: 54)

            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

struct MediumWidgetView: View {
    let entry: StatsEntry

    var body: some View {
        HStack(spacing: 32) {
            mediumGauge(title: "CPU", value: entry.cpu, color: .orange)
            mediumGauge(title: "MEM", value: entry.mem, color: .teal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let host = entry.hostName {
                HStack(spacing: 4) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 9))
                    Text(host)
                        .font(.system(size: 10))
                }
                .foregroundStyle(entry.isStale ? .tertiary : .secondary)
                .padding(.bottom, 8)
            }
        }
        .containerBackground(.black, for: .widget)
    }

    private func mediumGauge(title: String, value: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(color.opacity(0.2), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(135))

                Circle()
                    .trim(from: 0, to: min(value / 100, 1.0) * 0.75)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(135))

                Text("\(Int(value))%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 80, height: 80)

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

struct RectangularWidgetView: View {
    let entry: StatsEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Label("CPU", systemImage: "cpu")
                    .font(.caption2)
                Text("\(Int(entry.cpu))%")
                    .font(.system(.title3, design: .rounded, weight: .bold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Label("MEM", systemImage: "memorychip")
                    .font(.caption2)
                Text("\(Int(entry.mem))%")
                    .font(.system(.title3, design: .rounded, weight: .bold))
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct CircularWidgetView: View {
    let entry: StatsEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Text("\(Int(entry.cpu))")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Rectangle()
                    .frame(width: 16, height: 0.5)
                    .opacity(0.4)
                Text("\(Int(entry.mem))")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct MyStatWidgetEntryView: View {
    var entry: StatsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .accessoryRectangular:
            RectangularWidgetView(entry: entry)
        case .accessoryCircular:
            CircularWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

@main
struct MyStatWidget: Widget {
    let kind = "MyStatWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatsTimelineProvider()) { entry in
            MyStatWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("MyStat")
        .description("CPU and memory usage from your Mac")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}
