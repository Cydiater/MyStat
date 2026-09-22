import XCTest
@testable import MyStatCore

final class StatusBarFocusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_200_000)

    private func samples(at end: Date? = nil, cpu: Double = 20, memory: Double = 60,
                         download: Double = 100_000, upload: Double = 1_000,
                         baseCPU: Double = 20, baseMemory: Double = 60,
                         baseDownload: Double = 100_000) -> [StatsSample] {
        stride(from: -60, through: 0, by: 2).map { offset in
            let recent = offset >= -10
            return StatsSample(timestamp: (end ?? now) + Double(offset), cpu: recent ? cpu : baseCPU,
                mem: recent ? memory : baseMemory, network: NetworkStats(
                    downloadBytesPerSecond: recent ? download : baseDownload,
                    uploadBytesPerSecond: recent ? upload : 1_000))
        }
    }

    func testQuietActivityAndOneNoisySampleDoNotCreateAHighlight() {
        var focus = StatusBarFocus()
        let quiet = focus.update(samples: samples(), at: now)
        XCTAssertEqual(quiet.metric, .cpu)
        XCTAssertEqual(quiet.reason, .steady)
        var noisy = samples()
        noisy[noisy.count - 1] = .init(timestamp: now, cpu: 100, mem: 60,
                                     network: .init(downloadBytesPerSecond: 100_000, uploadBytesPerSecond: 1_000))
        XCTAssertEqual(focus.update(samples: noisy, at: now).reason, .steady)
        XCTAssertEqual(focus.update(samples: samples(download: 1000, baseDownload: 1), at: now).metric, .cpu,
                       "A large percentage of negligible traffic must not take over the stack")
    }

    func testPercentageChangesAreComparedInMetricSpecificUnits() {
        var focus = StatusBarFocus()
        let result = focus.update(samples: samples(cpu: 40, memory: 72), at: now)
        XCTAssertEqual(result.metric, .memory)
        guard case .percentageChange(let delta) = result.reason else { return XCTFail("Missing change explanation") }
        XCTAssertEqual(delta, 12, accuracy: 0.001)
        var cpuFocus = StatusBarFocus()
        XCTAssertEqual(cpuFocus.update(samples: samples(cpu: 80, memory: 63), at: now).metric, .cpu)
    }

    func testNetworkBurstAndRealDropAreInterestingButMissingDataIsNotADrop() {
        for (rate, baseline, expectedDelta) in [(2_000_000.0, 100_000.0, 1_900_000.0), (0, 2_000_000, -2_000_000)] {
            var focus = StatusBarFocus()
            let result = focus.update(samples: samples(download: rate, baseDownload: baseline), at: now)
            XCTAssertEqual(result.metric, .network)
            guard case .trafficChange(let delta, let upload) = result.reason else { return XCTFail("Missing traffic explanation") }
            XCTAssertFalse(upload)
            XCTAssertEqual(delta, expectedDelta, accuracy: 0.001)
        }
        var focus = StatusBarFocus()
        var missing = samples(download: 0, baseDownload: 2_000_000)
        missing[missing.count - 1] = .init(timestamp: now, cpu: 20, mem: 60)
        XCTAssertEqual(focus.update(samples: missing, at: now).metric, .cpu)
        XCTAssertEqual(focus.update(samples: missing, at: now, pinned: .network).reason, .unavailable)
    }

    func testUploadAndSustainedHighActivityCanLead() {
        var focus = StatusBarFocus()
        let upload = focus.update(samples: samples(upload: 3_000_000), at: now)
        XCTAssertEqual(upload.metric, .network)
        guard case .trafficChange(_, let isUpload) = upload.reason else { return XCTFail("Missing upload explanation") }
        XCTAssertTrue(isUpload)
        focus = .init()
        let memory = focus.update(samples: samples(cpu: 85, memory: 95, baseCPU: 85, baseMemory: 95), at: now)
        XCTAssertEqual(memory.metric, .memory)
        XCTAssertEqual(memory.reason, .highActivity)
        focus = .init()
        let transfer = focus.update(samples: samples(download: 10_000_000, baseDownload: 10_000_000), at: now)
        XCTAssertEqual(transfer.metric, .network)
        XCTAssertEqual(transfer.reason, .highActivity)
    }

    func testCooldownAndOpenMenuHoldPreventAutomaticSwitching() {
        var focus = StatusBarFocus()
        XCTAssertEqual(focus.update(samples: samples(cpu: 80), at: now).metric, .cpu)
        XCTAssertEqual(focus.update(samples: samples(at: now + 8, memory: 80), at: now + 8).metric, .cpu)
        XCTAssertEqual(focus.update(samples: samples(at: now + 24, memory: 80), at: now + 24, holdSelection: true).metric, .cpu)
        XCTAssertEqual(focus.update(samples: samples(at: now + 24, memory: 80), at: now + 24).metric, .memory)
        XCTAssertEqual(focus.update(samples: samples(at: now + 26, cpu: 100), at: now + 26, pinned: .network, holdSelection: true).metric, .network)
        XCTAssertEqual(focus.selected, .memory, "Pinning must not change the automatic selection")
    }

    func testNearTiesDoNotOscillateAndMissingFocusCanRecoverImmediately() {
        var focus = StatusBarFocus()
        XCTAssertEqual(focus.update(samples: samples(memory: 72), at: now).metric, .memory)
        XCTAssertEqual(focus.update(samples: samples(at: now + 30, cpu: 83, memory: 72), at: now + 30).metric, .memory,
                       "A small score advantage must not swap charts")
        focus = .init()
        XCTAssertEqual(focus.update(samples: samples(download: 2_000_000), at: now).metric, .network)
        let missing = samples(at: now + 2).map { StatsSample(timestamp: $0.timestamp, cpu: $0.cpu, mem: $0.mem) }
        XCTAssertEqual(focus.update(samples: missing, at: now + 2).metric, .cpu)
    }

    func testWarmupGapsAndStaleSamplesCannotManufactureChanges() {
        var focus = StatusBarFocus()
        XCTAssertEqual(focus.update(samples: [], at: now).reason, .unavailable)
        XCTAssertEqual(focus.update(samples: Array(samples().suffix(2)), at: now).reason, .warmingUp)
        let gapped = samples(cpu: 30, download: 0, baseDownload: 2_000_000).filter { $0.timestamp < now - 30 || $0.timestamp >= now - 8 }
        XCTAssertEqual(focus.update(samples: gapped, at: now).reason, .warmingUp)
        XCTAssertEqual(focus.update(samples: gapped, at: now, pinned: .network).reason, .warmingUp)
        XCTAssertEqual(focus.update(samples: samples(cpu: 100), at: now + 20).reason, .unavailable)
        let invalid = [StatsSample(timestamp: now, cpu: .nan, mem: -.infinity,
                                   network: .init(downloadBytesPerSecond: .nan, uploadBytesPerSecond: 0))]
        XCTAssertEqual(focus.update(samples: invalid, at: now).reason, .unavailable)
    }
}
