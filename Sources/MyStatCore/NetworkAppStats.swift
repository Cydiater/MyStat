import Foundation

/// Share only ranked names, representative PIDs and byte rates. Executable
/// paths, app bundle locations and network endpoints remain on the Mac.
public struct NetworkAppTraffic: Codable, Equatable, Sendable, Identifiable {
    public let pid: Int32
    public let name: String
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double
    public var id: Int32 { pid }

    public init(pid: Int32, name: String, downloadBytesPerSecond: Double, uploadBytesPerSecond: Double) {
        self.pid = pid; self.name = name
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }

    public var isValid: Bool {
        pid > 0 && !name.isEmpty && name.utf8.count <= 256
            && name.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
            && downloadBytesPerSecond.isFinite && downloadBytesPerSecond >= 0
            && uploadBytesPerSecond.isFinite && uploadBytesPerSecond >= 0
    }
}

public struct NetworkTrafficSnapshot: Codable, Equatable, Sendable {
    public let sampledAt: Date
    public let apps: [NetworkAppTraffic]

    public init(sampledAt: Date, apps: [NetworkAppTraffic]) {
        self.sampledAt = sampledAt; self.apps = apps
    }

    public var isValid: Bool {
        sampledAt.timeIntervalSince1970.isFinite && sampledAt.timeIntervalSince1970 > 0
            && apps.count <= 5 && apps.allSatisfy(\.isValid) && Set(apps.map(\.pid)).count == apps.count
    }

    public func isStale(at date: Date) -> Bool {
        abs(date.timeIntervalSince(sampledAt)) > 10
    }
}

/// A bounded pair of history series with shared segments and a byte-rate scale.
/// Missing sensors and collection gaps must never become zero-rate samples.
public struct NetworkHistorySeries {
    public struct Point: Identifiable {
        public let timestamp: Date
        public let download: Double
        public let upload: Double
        public let segment: Int
        public var id: Date { timestamp }
    }
    public let points: [Point]
    public let ceiling: Double

    public init(samples: [StatsSample], start: Date, end: Date) {
        var points: [Point] = []
        var previous: Date?
        var segment = 0
        var peak = 1_000.0
        for sample in samples where sample.timestamp >= start && sample.timestamp <= end {
            guard let network = sample.network, network.isValid else { previous = nil; segment += 1; continue }
            if let previous, sample.timestamp.timeIntervalSince(previous) > 6 { segment += 1 }
            previous = sample.timestamp
            peak = max(peak, network.downloadBytesPerSecond, network.uploadBytesPerSecond)
            points.append(Point(timestamp: sample.timestamp, download: network.downloadBytesPerSecond,
                                upload: network.uploadBytesPerSecond, segment: segment))
        }
        // Keep interval endpoints and peaks in both directions. Segment IDs are
        // assigned before reducing the data, so downsampling cannot bridge gaps.
        if points.count > 300 {
            let bucketSize = Int(ceil(Double(points.count) / 75))
            var reduced: [Point] = []
            for start in stride(from: 0, to: points.count, by: bucketSize) {
                let end = min(start + bucketSize, points.count)
                let indices = start..<end
                let download = indices.max { points[$0].download < points[$1].download }!
                let upload = indices.max { points[$0].upload < points[$1].upload }!
                for index in Set([start, end - 1, download, upload]).sorted() { reduced.append(points[index]) }
            }
            self.points = reduced
        } else { self.points = points }
        let power = pow(10, floor(log10(peak)))
        let rounded = ([1.0, 2, 5, 10].first { $0 >= peak / power } ?? 10) * power
        ceiling = rounded.isFinite ? rounded : peak
    }
}
