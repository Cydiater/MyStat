import WidgetKit
import SwiftUI
import AppIntents

struct StatsEntry: TimelineEntry {
    let date: Date
    let cached: CachedStats?
    var fetchFailed = false
    var isStale: Bool { fetchFailed || cached?.isStale(at: date) != false }
}

private enum WidgetRefresh {
    static func fetch() async -> Bool {
        guard let server = SharedDefaults.server else { return false }
        // Opening the widget just after a foreground poll needs no extra request.
        if let cached = SharedDefaults.load(), !cached.isStale(), Date().timeIntervalSince(cached.receivedAt) < 5 { return true }
        do {
            let stats = try await StatsTransport.fetch(server, deviceName: "MyStat widget")
            guard server == SharedDefaults.server else { return false }
            SharedDefaults.save(stats, server: server)
            return true
        } catch { return false }
    }
}

struct RefreshStatsIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Mac Stats"
    static var description = IntentDescription("Fetch the latest CPU and memory readings from your Mac.")

    func perform() async throws -> some IntentResult {
        _ = await WidgetRefresh.fetch()
        WidgetCenter.shared.reloadTimelines(ofKind: SharedDefaults.widgetKind)
        return .result()
    }
}

struct StatsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatsEntry {
        let server = ServerAddress(name: "Mac")
        let stats = LiveStats(sample: StatsSample(timestamp: .now, cpu: 42, mem: 65), host: "Mac")
        return StatsEntry(date: .now, cached: CachedStats(stats: stats, server: server, receivedAt: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : StatsEntry(date: .now, cached: SharedDefaults.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        Task {
            let fetched = await WidgetRefresh.fetch()
            let now = Date()
            let cached = SharedDefaults.load()
            var entries = [StatsEntry(date: now, cached: cached, fetchFailed: !fetched)]
            // Expire the snapshot in the existing timeline, without relying on a
            // network reload to warn that its readings are no longer current.
            if fetched, let cached, !cached.isStale(at: now) {
                let expiration = cached.timestamp.addingTimeInterval(61)
                if expiration > now { entries.append(StatsEntry(date: expiration, cached: cached)) }
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
        }
    }
}

private struct FreshnessLabel: View {
    let entry: StatsEntry
    var body: some View {
        VStack(spacing: 2) {
            if let cached = entry.cached {
                Text(cached.hostName).lineLimit(1)
                HStack(spacing: 3) {
                    if entry.isStale { Image(systemName: "clock.badge.exclamationmark") }
                    Text(cached.timestamp, style: .relative)
                    Text("ago")
                }
                .lineLimit(1)
                .foregroundStyle(entry.isStale ? Color.orange : .secondary)
            } else {
                Text("Open MyStat to connect").multilineTextAlignment(.center)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }
}

private struct WidgetGauge: View {
    let title: String
    let value: Double?
    let color: Color
    var large = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().trim(from: 0, to: 0.75)
                    .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: large ? 8 : 6, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle().trim(from: 0, to: CGFloat(min(100, max(0, value ?? 0))) / 100 * 0.75)
                    .stroke(color, style: StrokeStyle(lineWidth: large ? 8 : 6, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Text(value.map { "\(Int($0))%" } ?? "—")
                    .font(.system(size: large ? 24 : 16, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .frame(width: large ? 80 : 52, height: large ? 80 : 52)
            Text(title).font(.system(size: large ? 11 : 9, weight: .semibold)).foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DashboardWidgetView: View {
    let entry: StatsEntry
    let large: Bool

    var body: some View {
        VStack(spacing: large ? 12 : 7) {
            HStack(spacing: large ? 32 : 18) {
                WidgetGauge(title: "CPU", value: entry.cached?.stats.cpu, color: .orange, large: large)
                WidgetGauge(title: "MEM", value: entry.cached?.stats.mem, color: .teal, large: large)
            }
            .opacity(entry.isStale ? 0.55 : 1)
            HStack(spacing: 8) {
                FreshnessLabel(entry: entry)
                if SharedDefaults.server != nil {
                    Button(intent: RefreshStatsIntent()) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh stats from Mac")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.black, for: .widget)
    }
}

private struct AccessoryStatsView: View {
    let entry: StatsEntry
    let circular: Bool

    var body: some View {
        VStack(spacing: 2) {
            if entry.cached == nil {
                Image(systemName: "desktopcomputer")
                Text("Open MyStat").font(.caption2)
            } else if circular {
                Text(entry.isStale ? "OLD" : "CPU / MEM").font(.system(size: 7, weight: .bold))
                Text("\(Int(entry.cached!.stats.cpu)) / \(Int(entry.cached!.stats.mem))")
                    .font(.system(size: 12, weight: .bold, design: .rounded)).minimumScaleFactor(0.7)
            } else if let cached = entry.cached {
                HStack {
                    Text("CPU \(Int(cached.stats.cpu))%")
                    Spacer()
                    Text("MEM \(Int(cached.stats.mem))%")
                }.font(.system(.headline, design: .rounded))
                HStack(spacing: 3) {
                    if entry.isStale { Text("Last reading ·") }
                    Text(cached.timestamp, style: .relative)
                    Text("ago")
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct MyStatWidgetEntryView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium: DashboardWidgetView(entry: entry, large: true)
            case .accessoryRectangular: AccessoryStatsView(entry: entry, circular: false)
            case .accessoryCircular: AccessoryStatsView(entry: entry, circular: true)
            default: DashboardWidgetView(entry: entry, large: false)
            }
        }
        .widgetURL(URL(string: "mystat://desk"))
    }
}

@main
struct MyStatWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedDefaults.widgetKind, provider: StatsTimelineProvider()) { entry in
            MyStatWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("MyStat")
        .description("Mac stats with the time of the last reading. Tap to open the live Desk Display.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}
