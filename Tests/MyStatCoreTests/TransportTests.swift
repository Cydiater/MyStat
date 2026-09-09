import XCTest
import Network
@testable import MyStatCore

private final class FixtureServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "MyStat.TransportTests")
    private var connections: [NWConnection] = []
    var endpoint: NWEndpoint { .hostPort(host: "127.0.0.1", port: listener.port!) }

    init() throws { listener = try NWListener(using: .tcp, on: .any) }

    func start(reply: @escaping (NWConnection) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready: resumed = true; continuation.resume()
                case .failed(let error): resumed = true; continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.connections.append(connection)
                connection.start(queue: self.queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in reply(connection) }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        queue.sync {
            listener.cancel()
            for connection in connections { connection.cancel() }
            connections = []
        }
    }
}

final class TransportTests: XCTestCase {
    func testFetchWaitsForFragmentedResponse() async throws {
        let server = try FixtureServer()
        let body = Data("{\"cpu\":42,\"mem\":60,\"ts\":100}".utf8)
        try await server.start { connection in
            connection.send(content: Data("HTTP/1.1 200 OK\r\nContent-Length: \(body.count)\r\n\r\n".utf8), completion: .contentProcessed { _ in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                    connection.send(content: body.prefix(5), completion: .contentProcessed { _ in
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                            connection.send(content: body.dropFirst(5), completion: .contentProcessed { _ in })
                        }
                    })
                }
            })
        }
        defer { server.stop() }
        let data = try await StatsTransport.get(endpoint: server.endpoint, timeout: 2)
        XCTAssertEqual(data, body)
        XCTAssertEqual(try LiveStats.decode(data).cpu, 42)
    }

    func testTimeoutClosesSilentConnection() async throws {
        let server = try FixtureServer()
        try await server.start { _ in }
        defer { server.stop() }
        let started = Date()
        do {
            _ = try await StatsTransport.get(endpoint: server.endpoint, timeout: 0.15)
            XCTFail("A silent server must time out")
        } catch StatsError.timedOut { }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func testCancellationDoesNotWaitForTimeout() async throws {
        let server = try FixtureServer()
        try await server.start { _ in }
        defer { server.stop() }
        let task = Task { try await StatsTransport.get(endpoint: server.endpoint, timeout: 10) }
        try await Task.sleep(nanoseconds: 50_000_000)
        let started = Date()
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request succeeded") }
        catch is CancellationError { }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func testCancelledBeforeStartAndSubsequentRequestWorks() async throws {
        let server = try FixtureServer()
        try await server.start { connection in
            connection.send(content: Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}".utf8), completion: .contentProcessed { _ in })
        }
        defer { server.stop() }
        let task = Task { try await StatsTransport.get(endpoint: server.endpoint, timeout: 2) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request succeeded") }
        catch is CancellationError { }
        let data = try await StatsTransport.get(endpoint: server.endpoint, timeout: 2)
        XCTAssertEqual(data, Data("{}".utf8))
    }
}
