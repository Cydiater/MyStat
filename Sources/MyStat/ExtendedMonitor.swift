import Foundation
import Darwin
import IOKit
import IOKit.ps
import MyStatCore

final class ExtendedMonitor {
    private var networkTracker = NetworkRateTracker()
    private var cachedDisk: (free: UInt64?, total: UInt64?) = (nil, nil)
    private var lastDiskRead: Double = -.infinity

    func network() -> NetworkStats? {
        // NET_RT_IFLIST2 supplies 64-bit counters, unlike getifaddrs' if_data.
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            networkTracker = NetworkRateTracker(); return nil
        }
        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { sysctl(&mib, UInt32(mib.count), $0.baseAddress, &size, nil, 0) }
        guard result == 0 else { networkTracker = NetworkRateTracker(); return nil }
        var counters: [String: NetworkRateTracker.Counters] = [:]
        data.withUnsafeBytes { bytes in
            var offset = 0
            // Route address messages have a shorter header than interface
            // messages. Inspect only the common four-byte prefix first.
            while offset + 4 <= size {
                let length = Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                let type = bytes[offset + 3]
                guard length >= 4, offset + length <= size else { break }
                defer { offset += length }
                guard type == RTM_IFINFO2, length >= MemoryLayout<if_msghdr2>.size else { continue }
                let info = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                guard info.ifm_flags & IFF_UP != 0, info.ifm_flags & IFF_LOOPBACK == 0 else { continue }
                var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                guard if_indextoname(UInt32(info.ifm_index), &name) != nil else { continue }
                let interface = String(cString: name)
                // Count physical Wi-Fi/Ethernet adapters once, excluding VPN,
                // loopback, peer-to-peer and bridge copies of the same traffic.
                guard interface.hasPrefix("en"), info.ifm_data.ifi_type == IFT_ETHER else { continue }
                counters[interface] = .init(received: info.ifm_data.ifi_ibytes, sent: info.ifm_data.ifi_obytes)
            }
        }
        return networkTracker.sample(counters, time: ProcessInfo.processInfo.systemUptime)
    }

    func power() -> PowerStats? {
        guard let unmanaged = IOPSCopyPowerSourcesInfo() else { return nil }
        let blob = unmanaged.takeRetainedValue()
        let sourceType = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        let onAC = sourceType == kIOPSACPowerValue
        var battery: [String: Any]?
        if let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                if let details = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                   details[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                    battery = details; break
                }
            }
        }
        var percent: Double?
        if let current = (battery?[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue,
           let maximum = (battery?[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue, maximum > 0 {
            percent = min(100, max(0, current / maximum * 100))
        }
        var watts: Double?
        var cycles: Int?
        // AppleSmartBattery is optional. Desktop placeholder nodes may report
        // zero voltage/capacity; those are not zero-watt measurements.
        if percent != nil {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if service != 0 {
                defer { IOObjectRelease(service) }
                func number(_ key: String) -> NSNumber? {
                    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
                }
                if let voltage = number("Voltage")?.doubleValue, voltage > 0,
                   let amperage = number("Amperage") {
                    // IOKit can expose negative mA as an unsigned integer.
                    let current = Double(Int32(truncatingIfNeeded: amperage.int64Value))
                    let value = voltage * current / 1_000_000
                    if abs(value) <= 2000 { watts = value }
                }
                if let count = number("CycleCount")?.intValue, count >= 0 { cycles = count }
            }
        }
        let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
        let rating = (adapter?[kIOPSPowerAdapterWattsKey] as? NSNumber)?.doubleValue
        return PowerStats(onACPower: onAC, batteryPercent: percent,
                          isCharging: battery?[kIOPSIsChargingKey] as? Bool ?? false, batteryWatts: watts,
                          adapterWatts: onAC ? rating.flatMap { $0 > 0 && $0 <= 2000 ? $0 : nil } : nil, cycleCount: cycles)
    }

    func system() -> SystemStats {
        let uptime = ProcessInfo.processInfo.systemUptime
        if uptime - lastDiskRead >= 30 {
            let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            cachedDisk = ((attributes?[.systemFreeSize] as? NSNumber)?.uint64Value,
                          (attributes?[.systemSize] as? NSNumber)?.uint64Value)
            lastDiskRead = uptime
        }
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let swapResult = sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        let thermal: SystemStats.ThermalState
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .unknown
        }
        return SystemStats(uptimeSeconds: uptime, thermalState: thermal, diskFreeBytes: cachedDisk.free,
                           diskTotalBytes: cachedDisk.total, swapUsedBytes: swapResult == 0 ? swap.xsu_used : nil)
    }
}
