import Foundation
import Network
import Observation
import WidgetKit
import UIKit

@MainActor @Observable
final class StatsClient {
    private(set) var latest: LiveStats?
    private(set) var lastSuccess: Date?
    private(set) var servers: [ServerAddress] = []
    private(set) var selectedServer: ServerAddress? = SharedDefaults.server
    private(set) var connectionMessage = "Looking for your Mac…"
    private(set) var isConnected = false
    private(set) var historyMessage: String?
    private(set) var store = StatsStore()
    private(set) var isDemo = false
    private var liveStore: StatsStore?

    var hostName: String { latest?.host ?? selectedServer?.name ?? "Your Mac" }
    var cpu: Double { latest?.cpu ?? 0 }
    var mem: Double { latest?.mem ?? 0 }
    var lastSample: Date? { latest?.sample.timestamp }

    private var browser: NWBrowser?
    private var pollTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var browserRetry: Task<Void, Never>?
    private var running = false
    private var generation = UUID()
    private var lastHistoryFetch: Date = .distantPast
    private var lastWidgetReload: Date = .distantPast
    private let deviceName = UIDevice.current.name

    init() {
        if let server = selectedServer { store.select(server) }
        if let cached = SharedDefaults.load() { latest = cached.stats }
    }

    func start() {
        guard !running else { return }
        running = true
        if isDemo { beginDemoPolling(); return }
        startBrowser()
        beginPolling()
    }

    private func startBrowser() {
        browser?.cancel()
        if !isConnected { connectionMessage = "Looking for your Mac…" }
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_mystat._tcp", domain: nil), using: params)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            Task { @MainActor in
                guard let self, self.running, self.browser === browser else { return }
                self.servers = Array(Set(results.compactMap { ServerAddress(endpoint: $0.endpoint) }))
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if self.selectedServer == nil, let first = self.servers.first { self.select(first) }
            }
        }
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            Task { @MainActor in
                guard let self, self.running, self.browser === browser else { return }
                switch state {
                case .waiting(let error), .failed(let error):
                    if !self.isConnected {
                        self.connectionMessage = "Discovery unavailable. Check Local Network access in Settings. \(error.localizedDescription)"
                    }
                    if case .failed = state { self.retryBrowser() }
                default: break
                }
            }
        }
        browser.start(queue: .main)
    }

    private func retryBrowser() {
        browserRetry?.cancel()
        browserRetry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard let self, self.running else { return }
            self.startBrowser()
        }
    }

    func select(_ server: ServerAddress) {
        if isDemo { endDemo() }
        guard selectedServer != server else { return }
        cancelRequests()
        selectedServer = server
        SharedDefaults.server = server
        latest = nil
        lastSuccess = nil
        isConnected = false
        lastHistoryFetch = .distantPast
        historyMessage = nil
        store.select(server)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedDefaults.widgetKind)
        beginPolling()
    }

    private func beginPolling() {
        pollTask?.cancel()
        guard running, let server = selectedServer else { return }
        let generation = generation
        connectionMessage = "Connecting to \(server.name)…"
        pollTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let stats = try await StatsTransport.fetch(server, deviceName: self.deviceName)
                    guard !Task.isCancelled, self.generation == generation else { return }
                    let recovered = !self.isConnected
                    self.latest = stats
                    self.lastSuccess = .now
                    self.isConnected = Date().timeIntervalSince(stats.sample.timestamp) < 10
                        && stats.sample.timestamp.timeIntervalSinceNow < 60
                    self.connectionMessage = self.isConnected ? "Connected" : "The Mac is responding, but its readings are old."
                    self.store.append(stats.sample)
                    SharedDefaults.save(stats, server: server)
                    if recovered || Date().timeIntervalSince(self.lastWidgetReload) >= 60 {
                        WidgetCenter.shared.reloadTimelines(ofKind: SharedDefaults.widgetKind)
                        self.lastWidgetReload = .now
                    }
                    if recovered || Date().timeIntervalSince(self.lastHistoryFetch) >= 30 { self.fetchHistory() }
                    await self.store.saveIfNeeded()
                    failures = 0
                } catch {
                    guard !Task.isCancelled, self.generation == generation else { return }
                    self.isConnected = false
                    self.connectionMessage = "Reconnecting to \(server.name). \(error.localizedDescription)"
                    failures += 1
                }
                do { try await Task.sleep(for: .seconds(min(10, failures == 0 ? 2 : Double(failures * 2)))) } catch { return }
            }
        }
    }

    private func fetchHistory() {
        guard historyTask == nil, let server = selectedServer else { return }
        let generation = generation
        historyTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == generation { self.historyTask = nil } }
            do {
                let data = try await StatsTransport.get(endpoint: server.endpoint, path: "/history", deviceName: self.deviceName)
                let payload = try JSONDecoder().decode(HistoryPayload.self, from: data)
                let samples = try payload.samples()
                guard !Task.isCancelled, self.generation == generation else { return }
                self.store.mergeHistory(samples)
                self.lastHistoryFetch = .now
                self.historyMessage = nil
            } catch {
                guard !Task.isCancelled, self.generation == generation else { return }
                self.historyMessage = "History sync will retry automatically."
                // Avoid retrying on every poll when only the history endpoint fails.
                self.lastHistoryFetch = Date().addingTimeInterval(-20)
            }
        }
    }

    func retry() {
        if isDemo { endDemo(); return }
        cancelRequests()
        isConnected = false
        lastHistoryFetch = .distantPast
        guard running else { start(); return }
        startBrowser()
        beginPolling()
    }

    private func cancelRequests() {
        generation = UUID()
        pollTask?.cancel()
        pollTask = nil
        historyTask?.cancel()
        historyTask = nil
    }

    func stop() {
        running = false
        browser?.cancel()
        browser = nil
        browserRetry?.cancel()
        browserRetry = nil
        cancelRequests()
        isConnected = false
        connectionMessage = "Updates paused while MyStat is in the background."
    }

    func suspend() {
        stop()
        WidgetCenter.shared.reloadTimelines(ofKind: SharedDefaults.widgetKind)
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save stats history") {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }
        Task {
            await store.saveNow()
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }
    }

    func isLive(at date: Date) -> Bool {
        guard !isDemo else { return false }
        guard isConnected, let lastSuccess, let lastSample else { return false }
        return date.timeIntervalSince(lastSuccess) < 10 && date.timeIntervalSince(lastSample) < 10
    }

    func showDemo() {
        guard !isDemo else { return }
        stop()
        liveStore = store
        store = StatsStore(persistent: false)
        isDemo = true
        start()
    }

    func endDemo() {
        guard isDemo else { return }
        stop()
        isDemo = false
        store = liveStore ?? StatsStore()
        liveStore = nil
        latest = SharedDefaults.load()?.stats
        lastSuccess = nil
        lastHistoryFetch = .distantPast
        historyMessage = nil
        start()
    }

    private func beginDemoPolling() {
        connectionMessage = "Sample data. Connect your Mac for real readings."
        historyMessage = nil
        updateDemo()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self, self.isDemo, self.running else { return }
                self.updateDemo()
            }
        }
    }

    private func updateDemo() {
        let now = Date()
        let samples = (0..<91).map { offset -> StatsSample in
            let date = now.addingTimeInterval(Double(offset - 90) * 2)
            let phase = date.timeIntervalSince1970 / 12
            return StatsSample(timestamp: date,
                cpu: 32 + 12 * sin(phase) + 5 * sin(phase * 2.3),
                mem: 61 + 2 * sin(phase / 4),
                network: NetworkStats(downloadBytesPerSecond: 8_400_000 + 2_000_000 * sin(phase / 2),
                                      uploadBytesPerSecond: 720_000 + 180_000 * sin(phase)),
                power: PowerStats(onACPower: true, batteryPercent: 76, isCharging: true,
                                  batteryWatts: 18.4, adapterWatts: 67, cycleCount: 42))
        }
        // A separate memory-only store keeps sample data out of real history and widgets.
        let sample = samples.last!
        if store.samples.isEmpty { store.mergeHistory(samples) }
        else { store.append(sample) }
        latest = LiveStats(sample: sample, host: "MacBook Pro", usedBytes: UInt64(sample.mem / 100 * 34_359_738_368),
            totalBytes: 34_359_738_368,
            system: SystemStats(uptimeSeconds: 183_600, thermalState: .nominal,
                                diskFreeBytes: 428_000_000_000, diskTotalBytes: 1_000_000_000_000, swapUsedBytes: 268_435_456),
            tokens: TokenUsage(inputTokens: 126_400, cachedInputTokens: 84_200, outputTokens: 18_600,
                               updatedAt: now, dayStart: Calendar.current.startOfDay(for: now),
                               timeZone: TimeZone.current.identifier),
            processes: demoProcesses(at: now),
            networkApps: NetworkTrafficSnapshot(sampledAt: now, apps: [
                NetworkAppTraffic(pid: 102, name: "Web Browser", downloadBytesPerSecond: sample.network!.downloadBytesPerSecond * 0.75,
                                  uploadBytesPerSecond: sample.network!.uploadBytesPerSecond * 0.6),
                NetworkAppTraffic(pid: 104, name: "Music Player", downloadBytesPerSecond: sample.network!.downloadBytesPerSecond * 0.15,
                                  uploadBytesPerSecond: sample.network!.uploadBytesPerSecond * 0.05),
                NetworkAppTraffic(pid: 106, name: "Cloud Sync", downloadBytesPerSecond: sample.network!.downloadBytesPerSecond * 0.1,
                                  uploadBytesPerSecond: sample.network!.uploadBytesPerSecond * 0.35)
            ]))
    }

    private func demoProcesses(at date: Date) -> ProcessSnapshot {
        let rows = [
            ProcessUsage(pid: 101, name: "Video Editor", cpuPercent: 142 + 10 * sin(date.timeIntervalSince1970 / 8), residentBytes: 2_800_000_000),
            ProcessUsage(pid: 102, name: "Web Browser", cpuPercent: 36, residentBytes: 1_600_000_000),
            ProcessUsage(pid: 103, name: "Photo Editor", cpuPercent: 18, residentBytes: 3_200_000_000),
            ProcessUsage(pid: 104, name: "Music Player", cpuPercent: 5, residentBytes: 420_000_000),
            ProcessUsage(pid: 105, name: "MyStat", cpuPercent: 0.8, residentBytes: 48_000_000)
        ]
        return ProcessSnapshot(sampledAt: date, topCPU: rows,
                               topMemory: rows.sorted { $0.residentBytes > $1.residentBytes })
    }
}
