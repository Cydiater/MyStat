import Foundation

struct StatsSample: Codable {
    let timestamp: Date
    let cpu: Double
    let mem: Double
}

@Observable
final class StatsStore {
    private(set) var samples: [StatsSample] = []
    private var isDirty = false
    private var saveTimer: Timer?

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("stats_history.json")
    }

    init() {
        load()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.saveIfNeeded()
        }
    }

    func append(cpu: Double, mem: Double) {
        samples.append(StatsSample(timestamp: .now, cpu: cpu, mem: mem))
        isDirty = true
    }

    func mergeHistory(_ incoming: [StatsSample]) {
        guard !incoming.isEmpty else { return }
        let earliest = samples.first?.timestamp ?? .distantFuture
        let newSamples = incoming.filter { $0.timestamp < earliest }
        guard !newSamples.isEmpty else { return }
        samples.insert(contentsOf: newSamples, at: 0)
        isDirty = true
    }

    func saveNow() {
        isDirty = true
        saveIfNeeded()
    }

    private func saveIfNeeded() {
        guard isDirty else { return }
        isDirty = false
        let snapshot = samples
        DispatchQueue.global(qos: .utility).async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        samples = (try? decoder.decode([StatsSample].self, from: data)) ?? []
    }
}
