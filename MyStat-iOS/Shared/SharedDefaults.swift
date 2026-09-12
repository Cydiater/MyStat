import Foundation

struct CachedStats: Codable {
    let stats: LiveStats
    let server: ServerAddress
    let receivedAt: Date
    var timestamp: Date { stats.sample.timestamp }
    var hostName: String { stats.host ?? server.name }

    func isStale(at date: Date = .now) -> Bool {
        date.timeIntervalSince(timestamp) > 60 || timestamp.timeIntervalSince(date) > 60
    }
}

/// A single atomic record shared by the app and extension. File coordination
/// serializes cross-process read/modify/write operations, including host changes.
/// Reading the file directly also avoids process-local preferences caches.
enum SharedDefaults {
    static let widgetKind = "MyStatWidget"
    private static let suiteName = "group.com.cydiater.MyStat"
    private struct State: Codable {
        var server: ServerAddress?
        var snapshot: CachedStats?
    }
    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)?
            .appendingPathComponent("widget_state.json")
    }

    static var server: ServerAddress? {
        get { read().server }
        set {
            update { state in
                guard state.server != newValue else { return }
                state.server = newValue
                state.snapshot = nil
            }
        }
    }

    static func save(_ stats: LiveStats, server: ServerAddress) {
        guard stats.isValid else { return }
        update { state in
            guard state.server == server else { return }
            // Late widget requests must not overwrite a newer foreground poll.
            if let previous = state.snapshot, previous.stats.ts > stats.ts { return }
            state.snapshot = CachedStats(stats: stats, server: server, receivedAt: .now)
        }
    }

    static func load() -> CachedStats? {
        let state = read()
        guard let value = state.snapshot, value.server == state.server, value.stats.isValid else { return nil }
        return value
    }

    private static func read(at url: URL? = nil) -> State {
        guard let url = url ?? fileURL else { return State() }
        if let data = try? Data(contentsOf: url), let state = try? JSONDecoder().decode(State.self, from: data) { return state }
        // Migrate a selection saved by an earlier version. The original widgets
        // only stored numeric values; those are intentionally not labeled fresh.
        let defaults = UserDefaults(suiteName: suiteName)
        let server = defaults?.data(forKey: "selectedServer").flatMap { try? JSONDecoder().decode(ServerAddress.self, from: $0) }
        return State(server: server)
    }

    private static func update(_ change: (inout State) -> Void) {
        guard let url = fileURL else { return }
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { url in
            var state = read(at: url)
            change(&state)
            do {
                let data = try JSONEncoder().encode(state)
                // Widgets can read while locked after the phone's first unlock.
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch { NSLog("MyStat widget cache: %@", error.localizedDescription) }
        }
        if let coordinationError { NSLog("MyStat widget cache: %@", coordinationError.localizedDescription) }
    }
}
