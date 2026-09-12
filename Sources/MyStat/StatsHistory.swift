import Foundation
import MyStatCore

final class StatsHistory {
    let capacity: Int
    private(set) var samples: [StatsSample] = []
    var cpu: [Double] { samples.map(\.cpu) }
    var memory: [Double] { samples.map(\.mem) }

    init(capacity: Int) {
        self.capacity = capacity
        samples.reserveCapacity(capacity)
    }

    func record(cpu: Double, memory: Double, timestamp: Date = .now, network: NetworkStats? = nil, power: PowerStats? = nil) {
        samples.append(StatsSample(timestamp: timestamp, cpu: min(100, max(0, cpu)), mem: min(100, max(0, memory)), network: network, power: power))
        let cutoff = timestamp.addingTimeInterval(-3600)
        if let first = samples.firstIndex(where: { $0.timestamp >= cutoff }), first > 0 { samples.removeFirst(first) }
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }
}
