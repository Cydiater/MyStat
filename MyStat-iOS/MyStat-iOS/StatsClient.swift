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
    let store = StatsStore()

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
        startBrowser()
        beginPolling()
    }

    private func startBrowser() {
        browser?.cancel()
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
        guard isConnected, let lastSuccess, let lastSample else { return false }
        return date.timeIntervalSince(lastSuccess) < 10 && date.timeIntervalSince(lastSample) < 10
    }
}
