import Foundation
import Network

public struct StatsSample: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let cpu: Double
    public let mem: Double

    public init(timestamp: Date, cpu: Double, mem: Double) {
        // Canonical millisecond precision survives Date's reference-date and
        // Unix-time conversions, so JSON round trips never create duplicates.
        self.timestamp = Date(timeIntervalSince1970: (timestamp.timeIntervalSince1970 * 1000).rounded() / 1000)
        self.cpu = cpu
        self.mem = mem
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(timestamp: try values.decode(Date.self, forKey: .timestamp),
                  cpu: try values.decode(Double.self, forKey: .cpu),
                  mem: try values.decode(Double.self, forKey: .mem))
    }

    public var isValid: Bool {
        timestamp.timeIntervalSince1970.isFinite && timestamp.timeIntervalSince1970 > 0
            && cpu.isFinite && mem.isFinite && (0...100).contains(cpu) && (0...100).contains(mem)
    }
}

public struct ServerAddress: Codable, Hashable, Identifiable, Sendable {
    public let name: String
    public let type: String
    public let domain: String
    public var id: String { "\(name)|\(type)|\(domain)" }
    public var endpoint: NWEndpoint { .service(name: name, type: type, domain: domain, interface: nil) }

    public init(name: String, type: String = "_mystat._tcp", domain: String = "local.") {
        self.name = name
        self.type = type
        self.domain = domain
    }

    public init?(endpoint: NWEndpoint) {
        guard case .service(let name, let type, let domain, _) = endpoint else { return nil }
        self.init(name: name, type: type, domain: domain)
    }
}

public struct LiveStats: Codable, Sendable {
    public let cpu: Double
    public let mem: Double
    public let ts: Double
    public let host: String?
    public let usedBytes: UInt64?
    public let totalBytes: UInt64?

    public init(sample: StatsSample, host: String?, usedBytes: UInt64? = nil, totalBytes: UInt64? = nil) {
        cpu = sample.cpu
        mem = sample.mem
        ts = sample.timestamp.timeIntervalSince1970
        self.host = host
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }

    public var sample: StatsSample { StatsSample(timestamp: Date(timeIntervalSince1970: ts), cpu: cpu, mem: mem) }

    public static func decode(_ data: Data) throws -> LiveStats {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.sample.isValid else { throw StatsError.invalidData }
        return value
    }
}

public struct HistoryPayload: Codable, Sendable {
    public let interval: Double
    public let cpu: [Double]
    public let mem: [Double]
    public let endTs: Double
    public let timestamps: [Double]?

    public init(samples: [StatsSample], interval: Double) {
        self.interval = interval
        cpu = samples.map(\.cpu)
        mem = samples.map(\.mem)
        timestamps = samples.map { $0.timestamp.timeIntervalSince1970 }
        endTs = samples.last?.timestamp.timeIntervalSince1970 ?? 0
    }

    public func samples() throws -> [StatsSample] {
        guard cpu.count == mem.count, cpu.count <= 10_000, interval.isFinite, interval > 0,
              timestamps == nil || timestamps?.count == cpu.count else { throw StatsError.invalidData }
        let result = cpu.indices.map { i in
            StatsSample(
                timestamp: Date(timeIntervalSince1970: timestamps?[i] ?? (endTs - Double(cpu.count - 1 - i) * interval)),
                cpu: cpu[i], mem: mem[i]
            )
        }
        guard result.allSatisfy(\.isValid) else { throw StatsError.invalidData }
        return result
    }
}

public enum StatsError: Error, LocalizedError {
    case invalidData, invalidResponse, responseTooLarge, timedOut, httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidData: return "The Mac sent invalid stats. Try updating MyStat on your Mac."
        case .invalidResponse: return "The connection ended before a complete response arrived."
        case .responseTooLarge: return "The Mac's response was too large."
        case .timedOut: return "The Mac did not respond. Check that it is awake and on the same network."
        case .httpStatus(let code): return "The Mac returned an error (\(code))."
        }
    }
}

public enum SampleHistory {
    /// Retain one day, capped at the normal two-second sample count. Server
    /// timestamps let backfills and live requests identify the same measurement.
    public static let retention: TimeInterval = 24 * 60 * 60
    public static let capacity = 43_200

    public static func merge(_ existing: [StatsSample], _ incoming: [StatsSample], now: Date = .now) -> [StatsSample] {
        let cutoff = now.addingTimeInterval(-retention)
        var byTime: [Date: StatsSample] = [:]
        for sample in incoming + existing where sample.isValid && sample.timestamp >= cutoff && sample.timestamp <= now.addingTimeInterval(60) {
            byTime[sample.timestamp] = sample
        }
        return Array(byTime.values.sorted { $0.timestamp < $1.timestamp }.suffix(capacity))
    }
}
