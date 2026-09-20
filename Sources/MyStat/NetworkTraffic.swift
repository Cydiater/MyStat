import Foundation
import MyStatCore

struct NetworkProcessCounter {
    let pid: Int32
    let name: String
    let received: UInt64
    let sent: UInt64
}

/// nettop repeats its CSV header before every snapshot. Keep framing independent
/// of read boundaries, and only publish complete snapshots.
struct NetworkTrafficParser {
    struct Frame {
        let time: TimeInterval
        let counters: [NetworkProcessCounter]
    }
    private var buffer = Data()
    private var columns: [String] = []
    private var counters: [NetworkProcessCounter] = []
    private var frameTime: TimeInterval?

    mutating func append(_ data: Data, time: TimeInterval) -> [Frame] {
        buffer.append(data)
        // A damaged stream must not grow indefinitely.
        guard buffer.count <= 1_048_576 else { self = .init(); return [] }
        var frames: [Frame] = []
        while let end = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<end], as: UTF8.self).trimmingCharacters(in: .newlines)
            buffer.removeSubrange(...end)
            let fields = Self.csvFields(line)
            if fields.first == "", fields.contains("bytes_in"), fields.contains("bytes_out") {
                if let frameTime { frames.append(Frame(time: frameTime, counters: counters)) }
                columns = fields
                counters = []
                frameTime = time
            } else if frameTime != nil,
                      let input = columns.firstIndex(of: "bytes_in"),
                      let output = columns.firstIndex(of: "bytes_out"),
                      fields.count > max(input, output), let process = fields.first,
                      let dot = process.lastIndex(of: "."),
                      let pid = Int32(process[process.index(after: dot)...]), pid > 0,
                      let received = UInt64(fields[input]), let sent = UInt64(fields[output]),
                      counters.count < 32_768 {
                let name = String(process[..<dot].unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
                counters.append(.init(pid: pid, name: name, received: received, sent: sent))
            }
        }
        return frames
    }

    private static func csvFields(_ line: String) -> [String] {
        var fields: [String] = [], field = "", quoted = false
        var characters = line.makeIterator()
        var current = characters.next()
        while let character = current {
            let next = characters.next()
            if character == "\"" {
                if quoted && next == "\"" { field.append("\""); current = characters.next(); continue }
                quoted.toggle()
            } else if character == "," && !quoted { fields.append(field); field = "" }
            else { field.append(character) }
            current = next
        }
        fields.append(field)
        return quoted ? [] : fields
    }
}

struct NetworkAppUsage {
    let id: String
    let name: String
    let pid: Int32
    let applicationURL: URL?
    var download: Double
    var upload: Double
}

struct NetworkAppSnapshot {
    let sampledAt: Date
    let apps: [NetworkAppUsage]
    func isStale(at date: Date = .now) -> Bool { date.timeIntervalSince(sampledAt) > 10 }

    var sharedSnapshot: NetworkTrafficSnapshot {
        NetworkTrafficSnapshot(sampledAt: sampledAt, apps: apps.map {
            NetworkAppTraffic(pid: $0.pid, name: $0.name, downloadBytesPerSecond: $0.download, uploadBytesPerSecond: $0.upload)
        }.filter(\.isValid))
    }
}

struct NetworkAppRateTracker {
    struct Reading {
        let counter: NetworkProcessCounter
        let identity: String // PID plus kernel process birth time
        let appID: String
        let name: String
        let applicationURL: URL?
    }
    private var previous: [String: NetworkProcessCounter] = [:]
    private var previousTime: TimeInterval?

    mutating func sample(_ readings: [Reading], time: TimeInterval, at date: Date) -> NetworkAppSnapshot? {
        defer {
            previous = Dictionary(readings.map { ($0.identity, $0.counter) }, uniquingKeysWith: { _, last in last })
            previousTime = time
        }
        guard let previousTime, time > previousTime, time - previousTime <= 10 else { return nil }
        var apps: [String: NetworkAppUsage] = [:]
        for reading in readings {
            let counter = reading.counter
            guard let old = previous[reading.identity], counter.received >= old.received, counter.sent >= old.sent else { continue }
            let download = Double(counter.received - old.received) / (time - previousTime)
            let upload = Double(counter.sent - old.sent) / (time - previousTime)
            guard download + upload > 0 else { continue }
            var app = apps[reading.appID] ?? NetworkAppUsage(id: reading.appID, name: reading.name,
                pid: counter.pid, applicationURL: reading.applicationURL, download: 0, upload: 0)
            app.download += download
            app.upload += upload
            apps[reading.appID] = app
        }
        let ranked = apps.values.sorted {
            let left = $0.download + $0.upload, right = $1.download + $1.upload
            return left == right ? $0.id < $1.id : left > right
        }
        return NetworkAppSnapshot(sampledAt: date, apps: Array(ranked.prefix(5)))
    }
}
