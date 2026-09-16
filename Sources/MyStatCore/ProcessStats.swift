import Foundation

public struct ProcessUsage: Codable, Equatable, Sendable, Identifiable {
    public let pid: Int32
    public let name: String
    /// 100% is one fully occupied CPU core; multithreaded processes can exceed it.
    public let cpuPercent: Double?
    public let residentBytes: UInt64
    public var id: Int32 { pid }

    public init(pid: Int32, name: String, cpuPercent: Double?, residentBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
    }

    public var isValid: Bool {
        pid > 0 && !name.isEmpty && name.utf8.count <= 256
            && (cpuPercent.map { $0.isFinite && $0 >= 0 } ?? true)
    }
}

public struct ProcessSnapshot: Codable, Equatable, Sendable {
    public let sampledAt: Date
    public let topCPU: [ProcessUsage]
    public let topMemory: [ProcessUsage]

    public init(sampledAt: Date, topCPU: [ProcessUsage], topMemory: [ProcessUsage]) {
        self.sampledAt = sampledAt
        self.topCPU = topCPU
        self.topMemory = topMemory
    }

    public var isValid: Bool {
        sampledAt.timeIntervalSince1970.isFinite && sampledAt.timeIntervalSince1970 > 0
            && [topCPU, topMemory].allSatisfy { rows in
                rows.count <= 5 && rows.allSatisfy(\.isValid) && Set(rows.map(\.pid)).count == rows.count
            } && topCPU.allSatisfy { $0.cpuPercent != nil }
    }

    public func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(sampledAt) > 10 || sampledAt.timeIntervalSince(date) > 10
    }
}

/// Independent of libproc so PID reuse, sampling gaps and counter resets can be tested.
public struct ProcessRateTracker {
    public struct Reading {
        public let pid: Int32
        public let name: String
        public let startedSeconds: UInt64
        public let startedMicroseconds: UInt64
        public let cpuNanoseconds: UInt64
        public let residentBytes: UInt64
        public let time: Double

        public init(pid: Int32, name: String, startedSeconds: UInt64, startedMicroseconds: UInt64,
                    cpuNanoseconds: UInt64, residentBytes: UInt64, time: Double) {
            self.pid = pid; self.name = name
            self.startedSeconds = startedSeconds; self.startedMicroseconds = startedMicroseconds
            self.cpuNanoseconds = cpuNanoseconds; self.residentBytes = residentBytes; self.time = time
        }
    }

    private var previous: [Int32: Reading] = [:]
    public init() {}

    public mutating func sample(_ readings: [Reading], at date: Date) -> ProcessSnapshot {
        var next: [Int32: Reading] = [:]
        var rows: [ProcessUsage] = []
        for reading in readings where reading.pid > 0 && reading.time.isFinite {
            guard next[reading.pid] == nil else { continue }
            next[reading.pid] = reading
            var cpu: Double?
            if let old = previous[reading.pid],
               old.startedSeconds == reading.startedSeconds, old.startedMicroseconds == reading.startedMicroseconds,
               reading.time > old.time, reading.time - old.time <= 10,
               reading.cpuNanoseconds >= old.cpuNanoseconds {
                let value = Double(reading.cpuNanoseconds - old.cpuNanoseconds) / 1_000_000_000
                    / (reading.time - old.time) * 100
                if value.isFinite { cpu = value }
            }
            let row = ProcessUsage(pid: reading.pid, name: reading.name, cpuPercent: cpu, residentBytes: reading.residentBytes)
            if row.isValid { rows.append(row) }
        }
        previous = next // Exited or inaccessible processes lose their baseline.
        let cpu = rows.filter { $0.cpuPercent != nil }.sorted {
            $0.cpuPercent == $1.cpuPercent ? $0.pid < $1.pid : $0.cpuPercent! > $1.cpuPercent!
        }
        let memory = rows.sorted {
            $0.residentBytes == $1.residentBytes ? $0.pid < $1.pid : $0.residentBytes > $1.residentBytes
        }
        return ProcessSnapshot(sampledAt: date, topCPU: Array(cpu.prefix(5)), topMemory: Array(memory.prefix(5)))
    }
}
