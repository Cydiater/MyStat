import Foundation
import MyStatCore

/// Incremental reads on a utility queue keep file I/O off the menu-bar timer.
final class TokenMonitor {
    private let queue = DispatchQueue(label: "MyStat.TokenUsage", qos: .utility)
    private var accumulator = CodexUsageAccumulator(now: .now)
    private struct Cursor {
        var offset: UInt64 = 0
        var lines = UsageLineBuffer()
    }
    private var cursors: [String: Cursor] = [:]
    private var scanning = false // main queue only
    private var lastScan: Date = .distantPast // main queue only
    private(set) var latest: TokenUsage? // main queue only
    private let root: URL

    init() {
        let path = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory() + "/.codex"
        root = URL(fileURLWithPath: path, isDirectory: true)
    }

    func refresh() {
        let now = Date()
        // Never show yesterday's aggregate as today's while a scan runs.
        if latest.map({ !Calendar.current.isDate($0.dayStart, inSameDayAs: now) }) == true { latest = nil }
        guard !scanning, now.timeIntervalSince(lastScan) >= 30 else { return }
        scanning = true
        lastScan = now
        queue.async { [self] in
            let result = scan(now: now)
            DispatchQueue.main.async { [self] in latest = result; scanning = false }
        }
    }

    private func scan(now: Date) -> TokenUsage? {
        let calendar = Calendar.current
        if accumulator.dayStart != calendar.startOfDay(for: now) || accumulator.snapshot(at: now).timeZone != calendar.timeZone.identifier {
            accumulator = CodexUsageAccumulator(now: now)
            cursors = [:]
        }
        let fm = FileManager.default
        var failed = false
        var foundDirectory = false
        for directory in ["sessions", "archived_sessions"] {
            let url = root.appendingPathComponent(directory)
            guard fm.fileExists(atPath: url.path) else { continue }
            foundDirectory = true
            guard let files = fm.enumerator(at: url, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                                           options: [.skipsHiddenFiles], errorHandler: { _, _ in failed = true; return true }) else {
                failed = true; continue
            }
            for case let file as URL in files where file.pathExtension == "jsonl" {
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]) else {
                    failed = true; continue
                }
                guard values.isRegularFile == true, let modified = values.contentModificationDate,
                      modified >= accumulator.dayStart, let size = values.fileSize else { continue }
                // A rollout's filename stays the same when it is archived.
                let key = file.lastPathComponent
                var cursor = cursors[key] ?? Cursor()
                if UInt64(size) < cursor.offset {
                    cursor = Cursor()
                    accumulator.resetSource(key)
                }
                guard UInt64(size) > cursor.offset else { continue }
                do {
                    let handle = try FileHandle(forReadingFrom: file)
                    defer { try? handle.close() }
                    try handle.seek(toOffset: cursor.offset)
                    // Read a fixed snapshot of the file. Appends wait for the
                    // next scan so an active session cannot monopolize this job.
                    var remaining = UInt64(size) - cursor.offset
                    while remaining > 0 {
                        guard let chunk = try handle.read(upToCount: Int(min(remaining, 64 * 1024))), !chunk.isEmpty else { break }
                        cursor.lines.append(chunk) { accumulator.consume($0, source: key) }
                        cursor.offset += UInt64(chunk.count)
                        remaining -= UInt64(chunk.count)
                    }
                    cursors[key] = cursor
                } catch { failed = true }
            }
        }
        guard foundDirectory, !failed, accumulator.hasUsage else { return nil }
        return accumulator.snapshot(at: now)
    }
}
