import XCTest
@testable import MyStatCore

final class NetworkAppStatsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_200_000)
    private func row(_ pid: Int32 = 1, name: String = "Browser", download: Double = 1500, upload: Double = 200) -> NetworkAppTraffic {
        .init(pid: pid, name: name, downloadBytesPerSecond: download, uploadBytesPerSecond: upload)
    }

    func testLiveAndCacheRoundTripWithNetworkRankings() throws {
        let ranks = NetworkTrafficSnapshot(sampledAt: now, apps: [row()])
        let live = LiveStats(sample: StatsSample(timestamp: now, cpu: 20, mem: 40), host: "Mac",
                             companion: CompanionInfo(version: "Next", build: "Next", capabilities: [CompanionInfo.networkAppRankings]),
                             networkApps: ranks)
        let data = try JSONEncoder().encode(live)
        let decoded = try LiveStats.decode(data)
        XCTAssertEqual(decoded.networkApps, ranks)
        XCTAssertFalse(decoded.needsNetworkCompanionUpdate)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let network = try XCTUnwrap(json["networkApps"] as? [String: Any])
        let apps = try XCTUnwrap(network["apps"] as? [[String: Any]])
        XCTAssertEqual(Set(apps[0].keys), ["pid", "name", "downloadBytesPerSecond", "uploadBytesPerSecond"],
                       "Only names, representative PIDs and byte rates belong on the wire")
        let history = try JSONEncoder().encode(HistoryPayload(samples: [live.sample], interval: 2))
        XCTAssertFalse(String(decoding: history, as: UTF8.self).contains("networkApps"))
    }

    func testLegacyAndUnavailableAreDifferentFromIdleTraffic() throws {
        let legacy = try LiveStats.decode(Data(#"{"cpu":20,"mem":40,"ts":100}"#.utf8))
        XCTAssertNil(legacy.networkApps)
        XCTAssertTrue(legacy.needsNetworkCompanionUpdate)
        let capable = LiveStats(sample: legacy.sample, host: nil,
            companion: CompanionInfo(version: "Next", build: "Next", capabilities: [CompanionInfo.networkAppRankings]))
        let unavailable = try LiveStats.decode(JSONEncoder().encode(capable))
        XCTAssertNil(unavailable.networkApps)
        XCTAssertFalse(unavailable.needsNetworkCompanionUpdate, "Collector warmup/failure must not request an app update")
        let idle = LiveStats(sample: legacy.sample, host: nil, networkApps: .init(sampledAt: now, apps: []))
        let decodedIdle = try LiveStats.decode(JSONEncoder().encode(idle))
        XCTAssertEqual(decodedIdle.networkApps?.apps, [])
        XCTAssertFalse(decodedIdle.needsNetworkCompanionUpdate)
    }

    func testValidationRejectsBadRatesNamesDuplicatesAndOversizedRankings() throws {
        for bad in [row(download: -1), row(download: .nan), row(upload: .infinity), row(0), row(name: ""),
                    row(name: "Bad\nName"), row(name: String(repeating: "x", count: 257))] {
            XCTAssertFalse(bad.isValid)
        }
        for apps in [[row(), row()], (1...6).map { row(Int32($0)) }, [row(download: -1)]] {
            let invalid = LiveStats(sample: .init(timestamp: now, cpu: 1, mem: 2), host: nil,
                networkApps: .init(sampledAt: now, apps: apps))
            XCTAssertThrowsError(try LiveStats.decode(JSONEncoder().encode(invalid)))
        }
        let ranks = NetworkTrafficSnapshot(sampledAt: now, apps: [])
        XCTAssertFalse(ranks.isStale(at: now + 9))
        XCTAssertTrue(ranks.isStale(at: now + 11))
        XCTAssertTrue(ranks.isStale(at: now - 11))
        XCTAssertFalse(NetworkTrafficSnapshot(sampledAt: Date(timeIntervalSince1970: -1), apps: []).isValid)
    }

    func testNetworkChartKeepsZeroButBreaksMissingReadingsAndTimeGaps() {
        func sample(_ offset: Double, _ rate: Double?) -> StatsSample {
            .init(timestamp: now + offset, cpu: 10, mem: 20,
                  network: rate.map { NetworkStats(downloadBytesPerSecond: $0, uploadBytesPerSecond: $0 / 2) })
        }
        let history = NetworkHistorySeries(samples: [sample(-30, 500), sample(-20, 0), sample(-18, nil),
                                                    sample(-16, 1600), sample(-14, 800), sample(-2, 20), sample(2, 9999)],
                                           start: now - 20, end: now)
        XCTAssertEqual(history.points.map(\.download), [0, 1600, 800, 20])
        XCTAssertEqual(history.points.map(\.segment), [0, 1, 1, 2])
        XCTAssertEqual(history.ceiling, 2000)
        XCTAssertEqual(NetworkHistorySeries(samples: [], start: now - 180, end: now).ceiling, 1000)
    }

    func testLongChartsStayBoundedAndPreservePeaksAndGaps() {
        let samples: [StatsSample] = (0..<1800).map { index in
            let network: NetworkStats? = index == 901 ? nil : NetworkStats(
                downloadBytesPerSecond: index == 301 ? 999_999 : 100,
                uploadBytesPerSecond: index == 1215 ? 499_999 : 10)
            let timestamp = now.addingTimeInterval(-Double(1799 - index) * 2)
            return StatsSample(timestamp: timestamp, cpu: 10, mem: 20, network: network)
        }
        let history = NetworkHistorySeries(samples: samples, start: now - 3600, end: now)
        XCTAssertLessThanOrEqual(history.points.count, 300)
        XCTAssertEqual(history.points.first?.timestamp, samples.first?.timestamp)
        XCTAssertEqual(history.points.last?.timestamp, samples.last?.timestamp)
        XCTAssertEqual(history.points.map(\.download).max(), 999_999)
        XCTAssertEqual(history.points.map(\.upload).max(), 499_999)
        XCTAssertEqual(Set(history.points.map(\.segment)), [0, 1])
        XCTAssertEqual(history.ceiling, 1_000_000)
    }
}
