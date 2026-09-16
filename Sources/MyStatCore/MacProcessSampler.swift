#if os(macOS)
import Foundation
import Darwin

/// Call from one background queue. No elevated privileges, shell commands or task ports.
public final class MacProcessSampler {
    private var tracker = ProcessRateTracker()
    private let nanosecondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom)
    }()
    public init() {}

    public func sample() -> ProcessSnapshot? {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { tracker = ProcessRateTracker(); return nil }
        // Allow for processes created between sizing and filling the buffer.
        let capacity = Int(count) + 256
        var pids = [Int32](repeating: 0, count: capacity)
        let actual = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard actual > 0 else { tracker = ProcessRateTracker(); return nil }
        var readings: [ProcessRateTracker.Reading] = []
        readings.reserveCapacity(min(Int(actual), capacity))
        for pid in pids.prefix(min(Int(actual), capacity)) where pid > 0 {
            var info = proc_taskallinfo()
            let size = Int32(MemoryLayout<proc_taskallinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, size) == size else { continue }
            let cpu = info.ptinfo.pti_total_user.addingReportingOverflow(info.ptinfo.pti_total_system)
            guard !cpu.overflow else { continue }
            // proc_taskinfo exposes Mach absolute time, not nanoseconds. On
            // Apple silicon the timebase ratio is commonly 125/3; Intel is 1/1.
            let nanoseconds = Double(cpu.partialValue) * nanosecondsPerTick
            guard nanoseconds.isFinite, nanoseconds >= 0, nanoseconds < Double(UInt64.max) else { continue }
            // Kernel process names only. Never read command arguments, executable paths or environments.
            let name = withUnsafeBytes(of: info.pbsd.pbi_name) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            let fallback = withUnsafeBytes(of: info.pbsd.pbi_comm) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            let cleaned = (name.isEmpty ? fallback : name).unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            let label = String(String.UnicodeScalarView(cleaned))
            readings.append(.init(pid: pid, name: label.isEmpty ? "Process \(pid)" : label,
                startedSeconds: info.pbsd.pbi_start_tvsec, startedMicroseconds: info.pbsd.pbi_start_tvusec,
                cpuNanoseconds: UInt64(nanoseconds), residentBytes: info.ptinfo.pti_resident_size,
                time: ProcessInfo.processInfo.systemUptime))
        }
        guard !readings.isEmpty else { tracker = ProcessRateTracker(); return nil }
        return tracker.sample(readings, at: .now)
    }
}
#endif
