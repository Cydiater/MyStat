import XCTest
@testable import MyStatCore

final class ProcessStatsTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_789_200_000)

    private func reading(_ pid: Int32, cpu: UInt64, memory: UInt64 = 100, time: Double,
                         start: UInt64 = 1, micros: UInt64 = 0) -> ProcessRateTracker.Reading {
        .init(pid: pid, name: "Process \(pid)", startedSeconds: start, startedMicroseconds: micros,
              cpuNanoseconds: cpu, residentBytes: memory, time: time)
    }

    func testRankingsUseIntervalCPUAndResidentMemoryIndependently() {
        var tracker = ProcessRateTracker()
        let first = tracker.sample((1...8).map { reading(Int32($0), cpu: 1_000_000_000, memory: UInt64($0), time: 10) }, at: date)
        XCTAssertTrue(first.topCPU.isEmpty) // Never present lifetime averages as live CPU.
        XCTAssertEqual(first.topMemory.map(\.pid), [8, 7, 6, 5, 4])
        let next = tracker.sample((1...8).map {
            reading(Int32($0), cpu: 1_000_000_000 + UInt64(9 - $0) * 1_000_000_000,
                    memory: UInt64($0), time: 12)
        }, at: date)
        XCTAssertEqual(next.topCPU.map(\.pid), [1, 2, 3, 4, 5])
        XCTAssertEqual(next.topCPU.first?.cpuPercent, 400) // Four busy cores, not clamped to 100.
        XCTAssertEqual(next.topMemory.map(\.pid), [8, 7, 6, 5, 4])
        XCTAssertTrue(next.isValid)
    }

    func testPIDReuseCounterResetAndSamplingGapsRestartBaseline() {
        var tracker = ProcessRateTracker()
        _ = tracker.sample([reading(1, cpu: 9_000_000_000, time: 10)], at: date)
        XCTAssertTrue(tracker.sample([reading(1, cpu: 10_000_000_000, time: 12, micros: 1)], at: date).topCPU.isEmpty)
        XCTAssertTrue(tracker.sample([reading(1, cpu: 2, time: 14, micros: 1)], at: date).topCPU.isEmpty)
        XCTAssertTrue(tracker.sample([reading(1, cpu: 20_000_000_000, time: 100, micros: 1)], at: date).topCPU.isEmpty)
        let recovered = tracker.sample([reading(1, cpu: 21_000_000_000, time: 102, micros: 1)], at: date)
        XCTAssertEqual(recovered.topCPU.first?.cpuPercent, 50)
        XCTAssertTrue(tracker.sample([reading(1, cpu: 22_000_000_000, time: 102, micros: 1)], at: date).topCPU.isEmpty)
    }

    func testExitedAndUnreadableProcessesDisappearAndTiesAreStable() {
        var tracker = ProcessRateTracker()
        let a = reading(2, cpu: 100, time: 10)
        let b = reading(1, cpu: 100, time: 10)
        XCTAssertEqual(tracker.sample([a, b, a], at: date).topMemory.map(\.pid), [1, 2])
        let empty = tracker.sample([], at: date)
        XCTAssertTrue(empty.topMemory.isEmpty)
        XCTAssertTrue(tracker.sample([reading(1, cpu: 1_000_000, time: 12)], at: date).topCPU.isEmpty)
    }

    func testWireCompatibilityAndValidation() throws {
        let row = ProcessUsage(pid: 42, name: "Browser Helper", cpuPercent: 125, residentBytes: 1024)
        let snapshot = ProcessSnapshot(sampledAt: date, topCPU: [row], topMemory: [row])
        let live = LiveStats(sample: StatsSample(timestamp: date, cpu: 20, mem: 30), host: "Test", processes: snapshot)
        XCTAssertEqual(try LiveStats.decode(JSONEncoder().encode(live)).processes, snapshot)
        XCTAssertNil(try LiveStats.decode(Data(#"{"cpu":20,"mem":40,"ts":100}"#.utf8)).processes)
        XCTAssertFalse(ProcessSnapshot(sampledAt: date, topCPU: [row, row], topMemory: []).isValid)
        XCTAssertFalse(ProcessUsage(pid: 1, name: "Test", cpuPercent: -.infinity, residentBytes: 0).isValid)
        let invalid = ProcessSnapshot(sampledAt: date, topCPU: [], topMemory: [ProcessUsage(pid: -1, name: "Invalid", cpuPercent: nil, residentBytes: 0)])
        let badLive = LiveStats(sample: live.sample, host: nil, processes: invalid)
        XCTAssertThrowsError(try LiveStats.decode(JSONEncoder().encode(badLive)))
        let missingCPU = ProcessUsage(pid: 2, name: "New", cpuPercent: nil, residentBytes: 10)
        XCTAssertFalse(ProcessSnapshot(sampledAt: date, topCPU: [missingCPU], topMemory: []).isValid)
        let many = (1...6).map { ProcessUsage(pid: Int32($0), name: "Test", cpuPercent: 1, residentBytes: 10) }
        XCTAssertFalse(ProcessSnapshot(sampledAt: date, topCPU: many, topMemory: []).isValid)
    }

    func testStaleProcessSnapshotHasItsOwnClock() {
        let snapshot = ProcessSnapshot(sampledAt: date, topCPU: [], topMemory: [])
        XCTAssertFalse(snapshot.isStale(at: date.addingTimeInterval(4)))
        XCTAssertTrue(snapshot.isStale(at: date.addingTimeInterval(11)))
        XCTAssertTrue(snapshot.isStale(at: date.addingTimeInterval(-11)))
    }
}
