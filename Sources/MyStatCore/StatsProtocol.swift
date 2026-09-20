import Foundation
import Network

public struct StatsSample: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let cpu: Double
    public let mem: Double
    public let network: NetworkStats?
    public let power: PowerStats?

    public init(timestamp: Date, cpu: Double, mem: Double, network: NetworkStats? = nil, power: PowerStats? = nil) {
        // Canonical millisecond precision survives Date's reference-date and
        // Unix-time conversions, so JSON round trips never create duplicates.
        self.timestamp = Date(timeIntervalSince1970: (timestamp.timeIntervalSince1970 * 1000).rounded() / 1000)
        self.cpu = cpu
        self.mem = mem
        self.network = network
        self.power = power
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(timestamp: try values.decode(Date.self, forKey: .timestamp),
                  cpu: try values.decode(Double.self, forKey: .cpu),
                  mem: try values.decode(Double.self, forKey: .mem),
                  network: try values.decodeIfPresent(NetworkStats.self, forKey: .network),
                  power: try values.decodeIfPresent(PowerStats.self, forKey: .power))
    }

    public var isValid: Bool {
        timestamp.timeIntervalSince1970.isFinite && timestamp.timeIntervalSince1970 > 0
            && cpu.isFinite && mem.isFinite && (0...100).contains(cpu) && (0...100).contains(mem)
            && (network?.isValid ?? true) && (power?.isValid ?? true)
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

public struct CompanionInfo: Codable, Equatable, Sendable {
    public static let processRankings = "process-rankings"
    public static let networkAppRankings = "network-app-rankings"
    public let version: String
    public let build: String
    public let capabilities: [String]

    public init(version: String, build: String, capabilities: [String]) {
        self.version = version; self.build = build; self.capabilities = capabilities
    }
}

public struct LiveStats: Codable, Sendable {
    public let cpu: Double
    public let mem: Double
    public let ts: Double
    public let host: String?
    public let usedBytes: UInt64?
    public let totalBytes: UInt64?
    public let network: NetworkStats?
    public let power: PowerStats?
    public let system: SystemStats?
    public let tokens: TokenUsage?
    public let processes: ProcessSnapshot?
    public let networkApps: NetworkTrafficSnapshot?
    public let companion: CompanionInfo?

    public init(sample: StatsSample, host: String?, usedBytes: UInt64? = nil, totalBytes: UInt64? = nil,
                system: SystemStats? = nil, tokens: TokenUsage? = nil, processes: ProcessSnapshot? = nil,
                companion: CompanionInfo? = nil, networkApps: NetworkTrafficSnapshot? = nil) {
        cpu = sample.cpu
        mem = sample.mem
        ts = sample.timestamp.timeIntervalSince1970
        self.host = host
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        network = sample.network
        power = sample.power
        self.system = system
        self.tokens = tokens
        self.processes = processes
        self.networkApps = networkApps
        self.companion = companion
    }

    public var needsProcessCompanionUpdate: Bool {
        if let companion { return !companion.capabilities.contains(CompanionInfo.processRankings) }
        // Companions before capability reporting can still provide process rankings.
        return processes == nil
    }

    public var needsNetworkCompanionUpdate: Bool {
        if let companion { return !companion.capabilities.contains(CompanionInfo.networkAppRankings) }
        return networkApps == nil
    }

    public var sample: StatsSample { StatsSample(timestamp: Date(timeIntervalSince1970: ts), cpu: cpu, mem: mem, network: network, power: power) }

    public static func decode(_ data: Data) throws -> LiveStats {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.isValid else { throw StatsError.invalidData }
        return value
    }

    public var isValid: Bool {
        sample.isValid && (system?.isValid ?? true) && (tokens?.isValid ?? true) && (processes?.isValid ?? true)
            && (networkApps?.isValid ?? true)
    }
}

public struct HistoryPayload: Codable, Sendable {
    public let interval: Double
    public let cpu: [Double]
    public let mem: [Double]
    public let endTs: Double
    public let timestamps: [Double]?
    public let network: [NetworkStats?]?
    public let power: [PowerStats?]?

    public init(samples: [StatsSample], interval: Double) {
        self.interval = interval
        cpu = samples.map(\.cpu)
        mem = samples.map(\.mem)
        timestamps = samples.map { $0.timestamp.timeIntervalSince1970 }
        endTs = samples.last?.timestamp.timeIntervalSince1970 ?? 0
        network = samples.contains { $0.network != nil } ? samples.map(\.network) : nil
        power = samples.contains { $0.power != nil } ? samples.map(\.power) : nil
    }

    public func samples() throws -> [StatsSample] {
        guard cpu.count == mem.count, cpu.count <= 10_000, interval.isFinite, interval > 0,
              timestamps == nil || timestamps?.count == cpu.count,
              network == nil || network?.count == cpu.count,
              power == nil || power?.count == cpu.count else { throw StatsError.invalidData }
        let result = cpu.indices.map { i in
            StatsSample(
                timestamp: Date(timeIntervalSince1970: timestamps?[i] ?? (endTs - Double(cpu.count - 1 - i) * interval)),
                cpu: cpu[i], mem: mem[i], network: network?[i], power: power?[i]
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
