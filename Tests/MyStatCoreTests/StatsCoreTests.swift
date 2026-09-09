import XCTest
@testable import MyStatCore

final class StatsCoreTests: XCTestCase {
    func testResponseSplitAtEveryByte() throws {
        let body = Data("{\"cpu\":12.5,\"mem\":60,\"ts\":100}".utf8)
        let response = Data("HTTP/1.1 200 OK\r\nContent-Length: \(body.count)\r\n\r\n".utf8) + body
        var decoder = HTTPResponseDecoder()
        for (index, byte) in response.enumerated() {
            let result = try decoder.receive(Data([byte]), isComplete: index == response.count - 1)
            if index < response.count - 1 { XCTAssertNil(result) }
            else { XCTAssertEqual(result, body) }
        }
    }

    func testTruncatedAndInvalidResponsesAreRejected() {
        for response in [
            "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\n{}",
            "HTTP/1.1 200 OK\r\nContent-Length: -1\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n{}",
            "HTTP/1.1 200 OK\r\nContent-Length: 99999999\r\n\r\n",
            "HTTP/1.1 500 Error\r\nContent-Length: 2\r\n\r\n{}"
        ] {
            var decoder = HTTPResponseDecoder()
            XCTAssertThrowsError(try decoder.receive(Data(response.utf8), isComplete: true), response)
        }
    }

    func testBackfillKeepsActualTimestampsAcrossSleepAndIsIdempotent() throws {
        let now = Date()
        let samples = [StatsSample(timestamp: now.addingTimeInterval(-300), cpu: 10, mem: 20),
                       StatsSample(timestamp: now, cpu: 40, mem: 50)]
        let payload = HistoryPayload(samples: samples, interval: 2)
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(HistoryPayload.self, from: data).samples()
        XCTAssertEqual(decoded, samples)
        let merged = SampleHistory.merge([samples[1]], decoded, now: now)
        XCTAssertEqual(merged, samples)
        XCTAssertEqual(SampleHistory.merge(merged, decoded, now: now), merged)
    }

    func testLegacyHistoryAndInvalidStats() throws {
        let payload = Data("{\"cpu\":[1,2],\"mem\":[3,4],\"interval\":2,\"endTs\":100}".utf8)
        let samples = try JSONDecoder().decode(HistoryPayload.self, from: payload).samples()
        XCTAssertEqual(samples.map { $0.timestamp.timeIntervalSince1970 }, [98, 100])
        XCTAssertThrowsError(try LiveStats.decode(Data("{\"cpu\":200,\"mem\":3,\"ts\":100}".utf8)))
        XCTAssertThrowsError(try LiveStats.decode(Data("{\"cpu\":20,\"ts\":100}".utf8)))
    }

    func testHistoryRetentionAndSameCountReplacement() {
        let now = Date()
        let expired = StatsSample(timestamp: now.addingTimeInterval(-90_000), cpu: 1, mem: 2)
        let fresh = StatsSample(timestamp: now, cpu: 3, mem: 4)
        XCTAssertEqual(SampleHistory.merge([expired], [fresh], now: now), [fresh])
        let future = StatsSample(timestamp: now.addingTimeInterval(100), cpu: 5, mem: 6)
        XCTAssertEqual(SampleHistory.merge([fresh], [future], now: now), [fresh])
    }

    func testHistoryCapacityIsBounded() {
        let now = Date()
        let incoming = (0...SampleHistory.capacity).map {
            StatsSample(timestamp: now.addingTimeInterval(-Double($0)), cpu: 5, mem: 10)
        }
        let merged = SampleHistory.merge([], incoming, now: now)
        XCTAssertEqual(merged.count, SampleHistory.capacity)
        XCTAssertEqual(merged.last, incoming.first)
    }

    func testMisalignedHistoryIsRejected() throws {
        let data = Data("{\"cpu\":[1,2],\"mem\":[3],\"interval\":2,\"endTs\":100,\"timestamps\":[98,100]}".utf8)
        let payload = try JSONDecoder().decode(HistoryPayload.self, from: data)
        XCTAssertThrowsError(try payload.samples())
    }
}
