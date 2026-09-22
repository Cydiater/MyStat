import Foundation

public enum StatusBarMetric: String, CaseIterable, Sendable {
    case cpu = "CPU", memory = "Memory", network = "Network"
}

public struct StatusBarHighlight: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case percentageChange(Double)
        case trafficChange(Double, upload: Bool)
        case highActivity
        case steady
        case warmingUp
        case unavailable
    }
    public let metric: StatusBarMetric
    public let reason: Reason
    public let score: Double
}

/// Compares the last ten seconds with the preceding fifty seconds. Thresholds
/// use percentage points and a network rate floor, so tiny idle changes cannot
/// outrank useful activity. Selection is independent of the chart's time range.
public struct StatusBarFocus {
    public private(set) var selected: StatusBarMetric = .cpu
    private var selectedAt: Date?

    public init() {}

    public mutating func update(samples: [StatsSample], at now: Date,
                                pinned: StatusBarMetric? = nil, holdSelection: Bool = false) -> StatusBarHighlight {
        let highlights = StatusBarMetric.allCases.map { Self.assess($0, samples: samples, now: now) }
        func result(_ metric: StatusBarMetric) -> StatusBarHighlight { highlights.first { $0.metric == metric }! }
        if let pinned { return result(pinned) }
        let current = result(selected)
        let available = highlights.filter { $0.reason != .unavailable }
        let best = available.reduce(available.first) { best, value in
            guard let best else { return value }
            return value.score > best.score ? value : best
        }
        if !holdSelection, let best {
            let expired = selectedAt.map { now.timeIntervalSince($0) >= 20 || now < $0 } ?? true
            let meaningful = best.score >= (selectedAt == nil ? 1 : max(1, current.score * 1.35))
            if current.reason == .unavailable || (expired && meaningful) {
                if selected != best.metric || selectedAt == nil { selectedAt = now }
                selected = best.metric
            }
        }
        return result(selected)
    }

    private struct Reading {
        let recent: Double
        let baseline: Double?
        let count: Int
    }

    private static func reading(_ samples: [StatsSample], now: Date,
                                value: (StatsSample) -> Double?) -> Reading? {
        var points: [(Date, Double)] = []
        for sample in samples where sample.timestamp <= now && sample.timestamp >= now - 60 {
            guard let value = value(sample), value.isFinite, value >= 0 else {
                points.removeAll(keepingCapacity: true)
                continue
            }
            if let previous = points.last?.0,
               sample.timestamp <= previous || sample.timestamp.timeIntervalSince(previous) > 6 {
                points.removeAll(keepingCapacity: true)
            }
            points.append((sample.timestamp, value))
        }
        guard let last = points.last, now.timeIntervalSince(last.0) <= 6 else { return nil }
        let recent = points.filter { $0.0 >= now - 10 }.map(\.1)
        let baseline = points.filter { $0.0 < now - 10 }.map(\.1).sorted()
        guard !recent.isEmpty else { return nil }
        // A median baseline resists isolated earlier spikes; a short average
        // requires more than a single noisy sample to change the menu-bar metric.
        return Reading(recent: recent.reduce(0) { $0 + $1 / Double(recent.count) },
                       baseline: baseline.count >= 10 ? baseline[baseline.count / 2] : nil,
                       count: recent.count)
    }

    private static func assess(_ metric: StatusBarMetric, samples: [StatsSample], now: Date) -> StatusBarHighlight {
        func highlight(_ reason: StatusBarHighlight.Reason, _ score: Double = 0) -> StatusBarHighlight {
            .init(metric: metric, reason: reason, score: min(6, score))
        }
        if metric == .network {
            let down = reading(samples, now: now) { $0.network?.isValid == true ? $0.network?.downloadBytesPerSecond : nil }
            let up = reading(samples, now: now) { $0.network?.isValid == true ? $0.network?.uploadBytesPerSecond : nil }
            guard let down, let up else { return highlight(.unavailable) }
            guard down.count >= 3, up.count >= 3 else { return highlight(.warmingUp) }
            let rate = max(down.recent, up.recent)
            let levelScore = rate >= 5_000_000 ? min(3, 1 + log2(rate / 5_000_000)) : 0
            var change: (delta: Double, score: Double, upload: Bool)?
            for (reading, upload) in [(down, false), (up, true)] {
                guard let baseline = reading.baseline else { continue }
                let delta = reading.recent - baseline
                let score = abs(delta) / max(256_000, baseline * 0.5)
                if score > (change?.score ?? 0) { change = (delta, score, upload) }
            }
            if let change, change.score >= 1, change.score >= levelScore {
                return highlight(.trafficChange(change.delta, upload: change.upload), change.score)
            }
            if levelScore >= 1 { return highlight(.highActivity, levelScore) }
            return highlight(down.baseline == nil || up.baseline == nil ? .warmingUp : .steady)
        }
        guard let reading = reading(samples, now: now, value: {
            let value = metric == .cpu ? $0.cpu : $0.mem
            return (0...100).contains(value) ? value : nil
        }) else { return highlight(.unavailable) }
        guard reading.count >= 3 else { return highlight(.warmingUp) }
        let threshold = metric == .cpu ? 80.0 : 90.0
        let levelScore = reading.recent >= threshold ? 1 + (reading.recent - threshold) / (metric == .cpu ? 20 : 5) : 0
        if let baseline = reading.baseline {
            let delta = reading.recent - baseline
            let score = abs(delta) / (metric == .cpu ? 15 : 3)
            if score >= 1, score >= levelScore { return highlight(.percentageChange(delta), score) }
        }
        if levelScore >= 1 { return highlight(.highActivity, levelScore) }
        return highlight(reading.baseline == nil ? .warmingUp : .steady)
    }
}
