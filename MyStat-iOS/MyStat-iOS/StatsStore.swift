import Foundation
import Observation

private struct HistoryArchive: Codable {
    let serverID: String?
    let samples: [StatsSample]
}

private actor HistoryWriter {
    private var savedRevision = -1
    func save(_ archive: HistoryArchive, to url: URL, revision: Int) throws {
        guard revision > savedRevision else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(archive)
        try data.write(to: url, options: .atomic)
        savedRevision = revision
    }
}

@MainActor @Observable
final class StatsStore {
    private(set) var samples: [StatsSample] = []
    private(set) var saveError: String?
    private var serverID: String?
    private var revision = 0
    private var savedRevision = 0
    private var lastSave: Date = .distantPast
    private let writer = HistoryWriter()
    private let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("stats_history.json")

    init() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let archive = try? decoder.decode(HistoryArchive.self, from: data) {
            serverID = archive.serverID
            samples = SampleHistory.merge([], archive.samples)
        } else if let legacy = try? decoder.decode([StatsSample].self, from: data) {
            samples = SampleHistory.merge([], legacy)
        }
    }

    func select(_ server: ServerAddress) {
        guard serverID != server.id else { return }
        if serverID != nil { samples = [] }
        serverID = server.id
        revision += 1
    }

    func append(_ sample: StatsSample) {
        guard sample.isValid else { return }
        if let last = samples.last, sample.timestamp == last.timestamp { return }
        if samples.last.map({ $0.timestamp < sample.timestamp }) ?? true {
            samples.append(sample)
            let cutoff = Date().addingTimeInterval(-SampleHistory.retention)
            if let first = samples.firstIndex(where: { $0.timestamp >= cutoff }), first > 0 { samples.removeFirst(first) }
            if samples.count > SampleHistory.capacity { samples.removeFirst(samples.count - SampleHistory.capacity) }
            revision += 1
        } else {
            mergeHistory([sample])
        }
    }

    func mergeHistory(_ incoming: [StatsSample]) {
        let merged = SampleHistory.merge(samples, incoming)
        guard merged != samples else { return }
        samples = merged
        revision += 1
    }

    func saveIfNeeded() async {
        guard Date().timeIntervalSince(lastSave) >= 30 else { return }
        await saveNow()
    }

    func saveNow() async {
        guard revision != savedRevision else { return }
        let snapshotRevision = revision
        let archive = HistoryArchive(serverID: serverID, samples: samples)
        do {
            try await writer.save(archive, to: fileURL, revision: snapshotRevision)
            savedRevision = max(savedRevision, snapshotRevision)
            lastSave = .now
            saveError = nil
        } catch {
            saveError = "History could not be saved: \(error.localizedDescription)"
        }
    }
}
