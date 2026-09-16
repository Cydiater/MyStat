import SwiftUI

struct ContentView: View {
    @State private var client = StatsClient()
    @State private var showsDeskDisplay = false
    @State private var showsHelp = false
    @State private var historyMetric: HistoryMetric = .cpu
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    connectionHeader
                    if client.latest != nil {
                        HStack {
                            Spacer()
                            GaugeView(title: "CPU", value: client.cpu, color: .orange)
                            Spacer()
                            GaugeView(title: "MEM", value: client.mem, color: .teal)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }

                    Button { showsDeskDisplay = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.inset.filled.and.person.filled")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Open Desk Display").font(.headline)
                                Text("Live stats · screen stays awake").font(.caption)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                        .padding(18)
                        .foregroundStyle(.black)
                        .background(.orange.gradient, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("openDeskDisplay")

                    if let stats = client.latest {
                        TopProcessesView(snapshot: stats.processes)
                        ExtendedStatsView(stats: stats)
                    }

                    if !client.store.samples.isEmpty {
                        VStack(spacing: 24) {
                            Picker("History metric", selection: $historyMetric) {
                                ForEach(HistoryMetric.allCases) { metric in Text(metric.rawValue).tag(metric) }
                            }
                            .pickerStyle(.segmented)
                            InteractiveChartView(samples: client.store.samples, metric: historyMetric)
                                .id(historyMetric)
                        }
                        .padding(16)
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
                        Text("Pinch to zoom · drag to explore · up to 24 hours saved")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let message = client.historyMessage ?? client.store.saveError {
                        Text(message).font(.caption).foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Using your iPhone as a monitor", systemImage: "info.circle").font(.subheadline.bold())
                        Text("For continuous updates, leave Desk Display open. It works in portrait or landscape. On your Mac, turn on MyStat’s Keep Awake if you want monitoring to continue while its display sleeps.")
                        Text("Apple StandBy widgets show snapshots. iOS chooses when they refresh; tap the refresh button for a new reading, or tap the widget to open Desk Display.")
                    }
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(16)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
                }
                .padding(20)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(.black)
            .navigationTitle("MyStat")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Help", systemImage: "questionmark.circle") { showsHelp = true }
                        .accessibilityIdentifier("setupHelp")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let selected = client.selectedServer, !client.servers.contains(selected) {
                            Text("\(selected.name) — unavailable")
                        }
                        ForEach(client.servers) { server in
                            Button { client.select(server) } label: {
                                if server == client.selectedServer { Label(server.name, systemImage: "checkmark") }
                                else { Text(server.name) }
                            }
                        }
                        Button("Retry Connection", systemImage: "arrow.clockwise") { client.retry() }
                        Button("Open Settings", systemImage: "gear") { openSettings() }
                        Divider()
                        Button(client.isDemo ? "Connect My Mac" : "Explore Demo", systemImage: "play.rectangle") {
                            if client.isDemo { client.endDemo() } else { client.showDemo() }
                        }
                    } label: {
                        Image(systemName: "desktopcomputer")
                    }
                    .accessibilityLabel("Choose Mac and connection settings")
                }
            }
        }
        .fullScreenCover(isPresented: $showsDeskDisplay) { DeskDisplayView(client: client) }
        .sheet(isPresented: $showsHelp) { SetupHelpView() }
        .onAppear { if scenePhase == .active { client.start() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { client.start() }
            if phase == .background { client.suspend() }
        }
        .onOpenURL { url in if url.scheme == "mystat" { showsDeskDisplay = true } }
    }

    private var connectionHeader: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let live = client.isLive(at: context.date)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle().fill(live ? .green : .orange).frame(width: 7, height: 7)
                    Text(client.hostName).font(.headline)
                    Spacer()
                    Text(client.isDemo ? "DEMO" : live ? "LIVE" : client.latest == nil ? "CONNECTING" : "LAST READING")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(live ? .green : .orange)
                }
                if client.isDemo {
                    Text("Sample data · connect your Mac for real readings")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Connect My Mac") { client.endDemo() }
                        .buttonStyle(.bordered).tint(.orange)
                } else if let date = client.lastSample {
                    Text("Updated \(date, style: .relative) ago")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !live && !client.isDemo {
                    Text(client.connectionMessage).font(.subheadline).foregroundStyle(.secondary)
                    Text("Keep MyStat running on your Mac, use the same Wi-Fi, and allow Local Network access on your iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        Button("Retry", systemImage: "arrow.clockwise") { client.retry() }
                        Button("Settings", systemImage: "gear") { openSettings() }
                    }
                    .buttonStyle(.bordered).tint(.orange)
                    if client.latest == nil {
                        HStack {
                            Button("Get the Free Mac App") { showsHelp = true }
                            Spacer()
                            Button("Explore Demo") { client.showDemo() }
                                .accessibilityIdentifier("exploreDemo")
                        }
                        .font(.subheadline)
                        .tint(.teal)
                    }
                }
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}
