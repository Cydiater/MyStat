import Foundation

final class StatsHistory {
    let capacity: Int
    private(set) var cpu: [Double] = []
    private(set) var memory: [Double] = []

    init(capacity: Int) {
        self.capacity = capacity
        cpu.reserveCapacity(capacity)
        memory.reserveCapacity(capacity)
    }

    func record(cpu cpuValue: Double, memory memValue: Double) {
        cpu.append(cpuValue)
        memory.append(memValue)
        if cpu.count > capacity { cpu.removeFirst(cpu.count - capacity) }
        if memory.count > capacity { memory.removeFirst(memory.count - capacity) }
    }
}
