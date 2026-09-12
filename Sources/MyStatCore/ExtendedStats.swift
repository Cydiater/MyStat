import Foundation

public struct NetworkStats: Codable, Equatable, Sendable {
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double

    public init(downloadBytesPerSecond: Double, uploadBytesPerSecond: Double) {
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }

    public var isValid: Bool {
        [downloadBytesPerSecond, uploadBytesPerSecond].allSatisfy { $0.isFinite && $0 >= 0 }
    }
}

public struct PowerStats: Codable, Equatable, Sendable {
    public let onACPower: Bool
    public let batteryPercent: Double?
    public let isCharging: Bool
    /// Net power at the battery: positive charges, negative discharges.
    /// This is not whole-system consumption or wall-socket input.
    public let batteryWatts: Double?
    public let adapterWatts: Double?
    public let cycleCount: Int?

    public init(onACPower: Bool, batteryPercent: Double? = nil, isCharging: Bool = false,
                batteryWatts: Double? = nil, adapterWatts: Double? = nil, cycleCount: Int? = nil) {
        self.onACPower = onACPower
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.batteryWatts = batteryWatts
        self.adapterWatts = adapterWatts
        self.cycleCount = cycleCount
    }

    public var isValid: Bool {
        (batteryPercent.map { $0.isFinite && (0...100).contains($0) } ?? true)
            && (batteryWatts.map { $0.isFinite && abs($0) <= 2000 } ?? true)
            && (adapterWatts.map { $0.isFinite && $0 > 0 && $0 <= 2000 } ?? true)
            && (cycleCount.map { $0 >= 0 } ?? true)
    }

    public var status: String {
        guard batteryPercent != nil else { return onACPower ? "AC power" : "Power source unavailable" }
        if isCharging { return "Charging" }
        return onACPower ? "Plugged in · not charging" : "On battery"
    }
}

public struct SystemStats: Codable, Equatable, Sendable {
    public enum ThermalState: String, Codable, Sendable {
        case nominal, fair, serious, critical, unknown
        public var label: String {
            switch self {
            case .nominal: return "Normal"
            case .fair: return "Warm"
            case .serious: return "Hot"
            case .critical: return "Critical"
            case .unknown: return "Unavailable"
            }
        }
    }
    public let uptimeSeconds: Double
    public let thermalState: ThermalState
    public let diskFreeBytes: UInt64?
    public let diskTotalBytes: UInt64?
    public let swapUsedBytes: UInt64?

    public init(uptimeSeconds: Double, thermalState: ThermalState, diskFreeBytes: UInt64? = nil,
                diskTotalBytes: UInt64? = nil, swapUsedBytes: UInt64? = nil) {
        self.uptimeSeconds = uptimeSeconds
        self.thermalState = thermalState
        self.diskFreeBytes = diskFreeBytes
        self.diskTotalBytes = diskTotalBytes
        self.swapUsedBytes = swapUsedBytes
    }

    public var isValid: Bool {
        uptimeSeconds.isFinite && uptimeSeconds >= 0
            && (diskFreeBytes == nil || diskTotalBytes == nil || diskFreeBytes! <= diskTotalBytes!)
    }
}

public struct TokenUsage: Codable, Equatable, Sendable {
    public let inputTokens: Int64
    public let cachedInputTokens: Int64
    public let outputTokens: Int64
    public let updatedAt: Date
    public let dayStart: Date
    public let timeZone: String
    public var totalTokens: Int64 { inputTokens + outputTokens }

    public init(inputTokens: Int64, cachedInputTokens: Int64, outputTokens: Int64,
                updatedAt: Date, dayStart: Date, timeZone: String) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.updatedAt = updatedAt
        self.dayStart = dayStart
        self.timeZone = timeZone
    }

    public var isValid: Bool {
        inputTokens >= 0 && outputTokens >= 0 && cachedInputTokens >= 0 && cachedInputTokens <= inputTokens
            && !inputTokens.addingReportingOverflow(outputTokens).overflow
            && updatedAt.timeIntervalSince1970.isFinite && dayStart.timeIntervalSince1970.isFinite
            && updatedAt >= dayStart
    }
}

public enum MetricFormat {
    public static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        return scaled(Double(value), units: ["B", "KB", "MB", "GB", "TB"], base: 1000)
    }

    public static func rate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        return scaled(value, units: ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"], base: 1000)
    }

    public static func tokens(_ value: Int64?) -> String {
        guard let value, value >= 0 else { return "—" }
        return scaled(Double(value), units: ["", "K", "M", "B", "T"], base: 1000, separator: "")
    }

    public static func watts(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f W", abs(value))
    }

    public static func uptime(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "—" }
        let minutes = Int(seconds / 60)
        if minutes >= 1440 { return "\(minutes / 1440)d \(minutes % 1440 / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    private static func scaled(_ value: Double, units: [String], base: Double, separator: String = " ") -> String {
        var value = value
        var index = 0
        while value >= base && index < units.count - 1 { value /= base; index += 1 }
        return String(format: index == 0 || value >= 100 ? "%.0f" : "%.1f", value) + separator + units[index]
    }
}

/// Per-interface baselines avoid spikes when adapters appear, reset, or sleep.
public struct NetworkRateTracker {
    public struct Counters {
        public let received: UInt64
        public let sent: UInt64
        public init(received: UInt64, sent: UInt64) { self.received = received; self.sent = sent }
    }
    private var previous: [String: Counters] = [:]
    private var previousTime: Double?
    public init() {}

    public mutating func sample(_ counters: [String: Counters], time: Double) -> NetworkStats? {
        defer { previous = counters; previousTime = time }
        guard let previousTime, time > previousTime, time - previousTime <= 10 else { return nil }
        var received = 0.0
        var sent = 0.0
        var matched = false
        for (name, current) in counters {
            guard let old = previous[name], current.received >= old.received, current.sent >= old.sent else { continue }
            matched = true
            received += Double(current.received - old.received)
            sent += Double(current.sent - old.sent)
        }
        guard matched else { return nil }
        return NetworkStats(downloadBytesPerSecond: received / (time - previousTime),
                            uploadBytesPerSecond: sent / (time - previousTime))
    }
}
