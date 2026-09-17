import XCTest
@testable import MyStatCore

final class CompanionInfoTests: XCTestCase {
    func testLegacyCompanionRequestsUpdateWithoutBreakingStats() throws {
        let legacy = try LiveStats.decode(Data(#"{"cpu":20,"mem":40,"ts":100}"#.utf8))
        XCTAssertTrue(legacy.needsProcessCompanionUpdate)
        XCTAssertEqual(legacy.cpu, 20)
    }

    func testNewCompanionDoesNotRequestUpdateWhenSamplingIsUnavailable() throws {
        let info = CompanionInfo(version: "1.1.0", build: "2", capabilities: [CompanionInfo.processRankings, "sparkle-updates"])
        let live = LiveStats(sample: StatsSample(timestamp: .now, cpu: 20, mem: 40), host: "Test",
                             processes: nil, companion: info)
        let decoded = try LiveStats.decode(JSONEncoder().encode(live))
        XCTAssertEqual(decoded.companion, info)
        XCTAssertNil(decoded.processes)
        XCTAssertFalse(decoded.needsProcessCompanionUpdate)
        let missingCapability = LiveStats(sample: live.sample, host: "Test",
            companion: CompanionInfo(version: "1.0.0", build: "1", capabilities: []))
        XCTAssertTrue(missingCapability.needsProcessCompanionUpdate)
    }

    func testProcessCompanionWithoutVersionReportingStillWorks() {
        let live = LiveStats(sample: StatsSample(timestamp: .now, cpu: 20, mem: 40), host: "Test",
            processes: ProcessSnapshot(sampledAt: .now, topCPU: [], topMemory: []))
        XCTAssertFalse(live.needsProcessCompanionUpdate)
    }
}
