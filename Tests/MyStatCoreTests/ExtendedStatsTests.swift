import XCTest
@testable import MyStatCore

final class ExtendedStatsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_200_000)

    func testExtendedLiveHistoryAndDiskRoundTrips() throws {
        let network = NetworkStats(downloadBytesPerSecond: 1_500_000, uploadBytesPerSecond: 350_000)
        let power = PowerStats(onACPower: false, batteryPercent: 72, batteryWatts: -12.5, cycleCount: 100)
        let sample = StatsSample(timestamp: now, cpu: 25, mem: 50, network: network, power: power)
        let system = SystemStats(uptimeSeconds: 3600, thermalState: .nominal, diskFreeBytes: 10, diskTotalBytes: 100, swapUsedBytes: 5)
        let tokens = TokenUsage(inputTokens: 100, cachedInputTokens: 40, outputTokens: 20, updatedAt: now,
                                dayStart: now.addingTimeInterval(-3600), timeZone: "UTC")
        let live = LiveStats(sample: sample, host: "Mac", system: system, tokens: tokens)
        let decoded = try LiveStats.decode(JSONEncoder().encode(live))
        XCTAssertEqual(decoded.sample, sample)
        XCTAssertEqual(decoded.tokens, tokens)
        XCTAssertEqual(decoded.system, system)
        // Gaps in optional sensors must survive backfill without becoming zero.
        let samples = [StatsSample(timestamp: now.addingTimeInterval(-2), cpu: 10, mem: 20), sample]
        let history = try JSONDecoder().decode(HistoryPayload.self, from: JSONEncoder().encode(HistoryPayload(samples: samples, interval: 2)))
        XCTAssertEqual(try history.samples(), samples)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        XCTAssertEqual(try decoder.decode([StatsSample].self, from: encoder.encode(samples)), samples)
    }

    func testLegacyLiveAndPersistedSamplesStillDecode() throws {
        let live = try LiveStats.decode(Data(#"{"cpu":20,"mem":40,"ts":100}"#.utf8))
        XCTAssertNil(live.network)
        XCTAssertNil(live.power)
        XCTAssertNil(live.system)
        XCTAssertNil(live.tokens)
        let sample = try JSONDecoder().decode(StatsSample.self, from: Data(#"{"cpu":20,"mem":40,"timestamp":100}"#.utf8))
        XCTAssertTrue(sample.isValid)
        XCTAssertNil(sample.network)
    }

    func testInvalidOptionalMeasurementsAreRejected() throws {
        for extra in [
            #""network":{"downloadBytesPerSecond":-1,"uploadBytesPerSecond":2}"#,
            #""power":{"onACPower":true,"isCharging":false,"batteryPercent":200}"#,
            #""power":{"onACPower":true,"isCharging":false,"batteryWatts":3000}"#,
            #""system":{"uptimeSeconds":-1,"thermalState":"nominal"}"#,
            #""system":{"uptimeSeconds":10,"thermalState":"nominal","diskFreeBytes":200,"diskTotalBytes":100}"#,
            #""tokens":{"inputTokens":9223372036854775807,"outputTokens":1,"cachedInputTokens":0,"updatedAt":100,"dayStart":0,"timeZone":"UTC"}"#
        ] {
            XCTAssertThrowsError(try LiveStats.decode(Data("{\"cpu\":20,\"mem\":40,\"ts\":100,\(extra)}".utf8)))
        }
        let misaligned = Data(#"{"cpu":[1,2],"mem":[3,4],"interval":2,"endTs":100,"network":[null]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(HistoryPayload.self, from: misaligned).samples())
    }

    func testNormalHourFitsTransportBudget() throws {
        let samples = (0..<1800).map { index in
            StatsSample(timestamp: now.addingTimeInterval(Double(index) * -2), cpu: 99.12345, mem: 80.12345,
                        network: NetworkStats(downloadBytesPerSecond: 123_456_789.123, uploadBytesPerSecond: 123_456.789),
                        power: PowerStats(onACPower: true, batteryPercent: 99.1234, isCharging: true,
                                          batteryWatts: 80.1234, adapterWatts: 140, cycleCount: 400))
        }
        let data = try JSONEncoder().encode(HistoryPayload(samples: samples, interval: 2))
        XCTAssertLessThan(data.count + 1024, HTTPResponseDecoder.maximumSize)
    }

    func testRatesIgnoreNewAdaptersResetsAndSleep() {
        var tracker = NetworkRateTracker()
        func counters(_ received: UInt64, _ sent: UInt64) -> NetworkRateTracker.Counters { .init(received: received, sent: sent) }
        XCTAssertNil(tracker.sample(["en0": counters(100, 100)], time: 10))
        let rate = tracker.sample(["en0": counters(500, 300), "en1": counters(10000, 10000)], time: 12)
        XCTAssertEqual(rate?.downloadBytesPerSecond, 200)
        XCTAssertEqual(rate?.uploadBytesPerSecond, 100)
        XCTAssertNil(tracker.sample(["en0": counters(5, 5)], time: 14))
        XCTAssertNil(tracker.sample(["en0": counters(50000, 50000)], time: 100))
        XCTAssertEqual(tracker.sample(["en0": counters(50200, 50100)], time: 102)?.downloadBytesPerSecond, 100)
        XCTAssertNil(tracker.sample([:], time: 104))
    }

    func testUnavailableFormattingAndPowerDirection() {
        XCTAssertEqual(MetricFormat.rate(nil), "—")
        XCTAssertEqual(MetricFormat.rate(0), "0 B/s")
        XCTAssertEqual(MetricFormat.rate(1_500_000), "1.5 MB/s")
        XCTAssertEqual(MetricFormat.watts(-12.5), "12.5 W")
        XCTAssertEqual(MetricFormat.tokens(1_500_000), "1.5M")
        XCTAssertEqual(PowerStats(onACPower: true).status, "AC power")
        XCTAssertEqual(PowerStats(onACPower: true, batteryPercent: 80).status, "Plugged in · not charging")
    }
}

final class CodexUsageTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return calendar
    }
    private var now: Date { ISO8601DateFormatter().date(from: "2026-09-12T08:00:00Z")! }

    private func event(_ timestamp: String, input: Int64, cached: Int64, output: Int64,
                       lastInput: Int64? = nil, lastOutput: Int64? = nil) -> Data {
        Data("""
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output)},"last_token_usage":{"input_tokens":\(lastInput ?? input),"cached_input_tokens":0,"output_tokens":\(lastOutput ?? output),"reasoning_output_tokens":50}}}}
        """.utf8)
    }

    func testDailyDeltasCrossMidnightAndRepeatedNotifications() {
        var usage = CodexUsageAccumulator(now: now, calendar: calendar)
        usage.consume(event("2026-09-11T15:59:00Z", input: 1000, cached: 500, output: 100), source: "one")
        let fresh = event("2026-09-11T16:01:00.123Z", input: 1200, cached: 600, output: 150)
        usage.consume(fresh, source: "one")
        usage.consume(fresh, source: "one")
        usage.consume(event("2026-09-11T16:02:00Z", input: 1200, cached: 600, output: 150), source: "one")
        let result = usage.snapshot(at: now)
        XCTAssertEqual(result.inputTokens, 200)
        XCTAssertEqual(result.cachedInputTokens, 100)
        XCTAssertEqual(result.outputTokens, 50)
        XCTAssertEqual(result.totalTokens, 250) // reasoning and cached counts are subsets
    }

    func testForkedCopiesFirstEventAndCounterReset() {
        var usage = CodexUsageAccumulator(now: now, calendar: calendar)
        let first = event("2026-09-12T01:00:00Z", input: 5000, cached: 1000, output: 500, lastInput: 100, lastOutput: 10)
        usage.consume(first, source: "one")
        usage.consume(first, source: "copied")
        usage.consume(event("2026-09-12T01:01:00Z", input: 5050, cached: 1000, output: 520), source: "copied")
        usage.consume(event("2026-09-12T01:02:00Z", input: 20, cached: 0, output: 5), source: "one")
        XCTAssertEqual(usage.snapshot(at: now).totalTokens, 205)
    }

    func testMalformedUnrelatedAndFutureEventsAreIgnored() {
        var usage = CodexUsageAccumulator(now: now, calendar: calendar)
        for line in ["garbage", #"{"type":"event_msg","payload":{"type":"token_count","info":null}}"#,
                     #"{"type":"response_item","payload":{"type":"message","content":"token_count"}}"#] {
            usage.consume(Data(line.utf8), source: "one")
        }
        XCTAssertFalse(usage.hasUsage)
        usage.consume(event("2026-09-13T01:00:00Z", input: 50, cached: 0, output: 5), source: "future")
        usage.consume(event("2026-09-12T01:00:00Z", input: -1, cached: 0, output: 5), source: "invalid")
        XCTAssertEqual(usage.snapshot(at: now).totalTokens, 0)
    }

    func testReplacedLogStartsWithItsLastRequest() {
        var usage = CodexUsageAccumulator(now: now, calendar: calendar)
        usage.consume(event("2026-09-12T01:00:00Z", input: 100, cached: 0, output: 10), source: "one")
        usage.resetSource("one")
        usage.consume(event("2026-09-12T02:00:00Z", input: 5000, cached: 0, output: 500, lastInput: 50, lastOutput: 5), source: "one")
        XCTAssertEqual(usage.snapshot(at: now).totalTokens, 165)
    }

    func testPartialAppendsAndOversizedLines() {
        var buffer = UsageLineBuffer()
        var lines: [Data] = []
        buffer.append(Data("first\npar".utf8)) { lines.append($0) }
        XCTAssertEqual(lines, [Data("first".utf8)])
        buffer.append(Data("tial\n".utf8)) { lines.append($0) }
        buffer.append(Data(repeating: 65, count: UsageLineBuffer.maximumLineSize + 1)) { lines.append($0) }
        buffer.append(Data("\nlast\n".utf8)) { lines.append($0) }
        XCTAssertEqual(lines.map { String(decoding: $0, as: UTF8.self) }, ["first", "partial", "last"])
    }
}
