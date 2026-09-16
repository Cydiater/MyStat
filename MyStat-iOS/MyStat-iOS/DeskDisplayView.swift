import SwiftUI

struct DeskDisplayView: View {
    let client: StatsClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var keepAlive = KeepAlive()
    @State private var dimmed = false
    @State private var showsProcesses = false

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let sideBySide = landscape || geometry.size.height < 700
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let live = client.isLive(at: context.date)
                VStack(spacing: landscape ? 10 : 16) {
                    header(live: live)
                    if showsProcesses {
                        ScrollView {
                            TopProcessesView(snapshot: client.latest?.processes, sideBySide: landscape, compact: landscape)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        let layout = sideBySide ? AnyLayout(HStackLayout(spacing: 18)) : AnyLayout(VStackLayout(spacing: 18))
                        layout {
                            metric(title: "CPU", value: client.latest?.cpu, color: .orange,
                                   detail: "Total processor use", path: \.cpu, now: context.date, compact: sideBySide)
                            metric(title: "MEMORY", value: client.latest?.mem, color: .teal,
                                   detail: memoryDetail, path: \.mem, now: context.date, compact: sideBySide)
                        }
                        DeskExtrasView(stats: client.latest, compact: landscape)
                    }
                    footer(live: live)
                }
                .padding(landscape ? 16 : 24)
                .opacity(dimmed ? 0.45 : 1)
            }
        }
        .background(.black)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { if scenePhase == .active { keepAlive.start() } }
        .onDisappear { keepAlive.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { keepAlive.start() } else { keepAlive.stop() }
        }
        .accessibilityIdentifier("deskDisplay")
    }

    private func header(live: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "desktopcomputer").foregroundStyle(.secondary)
            Text(client.hostName).font(.headline).lineLimit(1)
            Circle().fill(live ? .green : .orange).frame(width: 6, height: 6)
            Text(client.isDemo ? "DEMO" : live ? "LIVE" : "OFFLINE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(live ? .green : .orange)
            Spacer(minLength: 0)
            Button { showsProcesses.toggle() } label: {
                Image(systemName: showsProcesses ? "gauge.with.dots.needle.50percent" : "list.number")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(showsProcesses ? "Show overview" : "Show top processes")
            .accessibilityIdentifier("toggleDeskProcesses")
            Button { dimmed.toggle() } label: {
                Image(systemName: dimmed ? "sun.max" : "moon")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(dimmed ? "Brighten display" : "Dim display")
            Button { dismiss() } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close Desk Display")
            .accessibilityIdentifier("closeDeskDisplay")
        }
        .foregroundStyle(.white)
    }

    private func metric(title: String, value: Double?, color: Color, detail: String, path: KeyPath<StatsSample, Double>, now: Date, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            Text(title).font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(color)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map { String(format: "%.0f", $0) } ?? "—")
                    .font(.system(size: compact ? 52 : 88, weight: .medium, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.45).lineLimit(1)
                if value != nil { Text("%").font(.system(size: 32, weight: .regular, design: .rounded)).foregroundStyle(color.opacity(0.65)) }
            }
            .foregroundStyle(color)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            HistorySparkline(samples: Array(client.store.samples.suffix(100)), valuePath: path, color: color, now: now)
                .frame(height: compact ? 18 : 30)
            HStack {
                Text("3 MIN AGO")
                Spacer()
                Text("NOW")
            }
            .font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(.gray)
        }
        .padding(compact ? 16 : 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(color.opacity(0.045), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(color.opacity(0.15), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var memoryDetail: String {
        guard let used = client.latest?.usedBytes, let total = client.latest?.totalBytes else { return "Active, wired & compressed" }
        return String(format: "%.1f / %.0f GB used", Double(used) / 1_073_741_824, Double(total) / 1_073_741_824)
    }

    private func footer(live: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if client.isDemo {
                    Text("Sample data · no Mac connected").foregroundStyle(.secondary)
                } else if let date = client.lastSample {
                    Text("\(live ? "Updated" : "Last reading") \(date, style: .relative) ago")
                        .foregroundStyle(live ? Color.secondary : .orange)
                } else {
                    Text("Waiting for your Mac").foregroundStyle(.orange)
                }
                if !live && !client.isDemo { Text(client.connectionMessage).foregroundStyle(.secondary).lineLimit(2) }
            }
            .font(.caption)
            Spacer(minLength: 0)
            if client.isDemo {
                Button("Connect Mac") { client.endDemo() }
                    .buttonStyle(.bordered).tint(.orange)
            } else if live {
                Label("Display stays awake", systemImage: "sun.max")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Button("Retry", systemImage: "arrow.clockwise") { client.retry() }
                    .buttonStyle(.bordered).tint(.orange)
            }
        }
    }
}

private struct HistorySparkline: View {
    let samples: [StatsSample]
    let valuePath: KeyPath<StatsSample, Double>
    let color: Color
    let now: Date

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                var previous: Date?
                for sample in samples where sample.timestamp >= now.addingTimeInterval(-180) && sample.timestamp <= now {
                    let point = CGPoint(x: geometry.size.width * (1 - now.timeIntervalSince(sample.timestamp) / 180),
                                        y: geometry.size.height * (1 - sample[keyPath: valuePath] / 100))
                    if previous == nil || sample.timestamp.timeIntervalSince(previous!) > 6 { path.move(to: point) }
                    else { path.addLine(to: point) }
                    previous = sample.timestamp
                }
            }
            .stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}
