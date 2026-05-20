import Foundation
import Darwin

struct MemorySnapshot {
    let usedBytes: UInt64
    let totalBytes: UInt64
    var percent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100.0
    }
}

final class StatsMonitor {
    private var prevTotalTicks: UInt32 = 0
    private var prevIdleTicks: UInt32 = 0
    private let totalMemory: UInt64 = {
        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &size, nil, 0)
        return total
    }()

    func cpuUsage() -> Double {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &cpuLoad) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let user = cpuLoad.cpu_ticks.0
        let system = cpuLoad.cpu_ticks.1
        let idle = cpuLoad.cpu_ticks.2
        let nice = cpuLoad.cpu_ticks.3
        let total = user &+ system &+ idle &+ nice

        let totalDelta = total &- prevTotalTicks
        let idleDelta = idle &- prevIdleTicks
        prevTotalTicks = total
        prevIdleTicks = idle

        guard totalDelta > 0 else { return 0 }
        let used = totalDelta &- idleDelta
        return min(100.0, max(0.0, Double(used) / Double(totalDelta) * 100.0))
    }

    func memory() -> MemorySnapshot {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return MemorySnapshot(usedBytes: 0, totalBytes: totalMemory)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active &+ wired &+ compressed
        return MemorySnapshot(usedBytes: used, totalBytes: totalMemory)
    }
}

enum ByteFormat {
    static func gb(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        return String(format: "%.1f", gb)
    }
}
