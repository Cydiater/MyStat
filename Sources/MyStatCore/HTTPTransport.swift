import Foundation
import Network

/// HTTP/1.x framing for the small, Content-Length-delimited MyStat protocol.
/// TCP reads may split anywhere, including in the header terminator or JSON.
public struct HTTPResponseDecoder {
    private var buffer = Data()
    private var bodyStart: Int?
    private var bodyLength: Int?
    public static let maximumSize = 2 * 1024 * 1024
    public init() {}

    public mutating func receive(_ data: Data, isComplete: Bool) throws -> Data? {
        buffer.append(data)
        guard buffer.count <= Self.maximumSize else { throw StatsError.responseTooLarge }
        if bodyStart == nil {
            if let boundary = buffer.range(of: Data("\r\n\r\n".utf8)) {
                guard boundary.lowerBound <= 16_384,
                      let header = String(data: buffer[..<boundary.lowerBound], encoding: .utf8) else { throw StatsError.invalidResponse }
                let lines = header.components(separatedBy: "\r\n")
                let status = (lines.first ?? "").split(separator: " ")
                guard status.count >= 2, status[0].hasPrefix("HTTP/1."), let code = Int(status[1]) else { throw StatsError.invalidResponse }
                guard code == 200 else { throw StatsError.httpStatus(code) }
                var lengths: [Int] = []
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { throw StatsError.invalidResponse }
                    let key = line[..<colon].lowercased()
                    let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if key == "transfer-encoding" { throw StatsError.invalidResponse }
                    if key == "content-length" {
                        guard let length = Int(value), length >= 0 else { throw StatsError.invalidResponse }
                        lengths.append(length)
                    }
                }
                guard lengths.count == 1, let length = lengths.first else { throw StatsError.invalidResponse }
                guard length <= Self.maximumSize - boundary.upperBound else { throw StatsError.responseTooLarge }
                bodyStart = boundary.upperBound
                bodyLength = length
            } else if buffer.count > 16_384 {
                throw StatsError.responseTooLarge
            }
        }
        if let start = bodyStart, let length = bodyLength {
            guard buffer.count <= start + length else { throw StatsError.invalidResponse }
            if buffer.count == start + length { return Data(buffer[start...]) }
        }
        if isComplete { throw StatsError.invalidResponse }
        return nil
    }
}

public enum StatsTransport {
    public static func get(endpoint: NWEndpoint, path: String = "/", deviceName: String = "MyStat", timeout: TimeInterval = 6) async throws -> Data {
        let operation = HTTPRequest(endpoint: endpoint, path: path, deviceName: deviceName, timeout: timeout)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in operation.start(continuation) }
        } onCancel: {
            operation.cancel()
        }
    }

    public static func fetch(_ server: ServerAddress, deviceName: String = "MyStat") async throws -> LiveStats {
        try LiveStats.decode(await get(endpoint: server.endpoint, deviceName: deviceName))
    }
}

/// All mutable request state, including cancellation, stays on this serial queue.
private final class HTTPRequest: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MyStat.HTTPRequest")
    private let connection: NWConnection
    private let request: Data
    private let timeout: TimeInterval
    private var continuation: CheckedContinuation<Data, Error>?
    private var deadline: DispatchWorkItem?
    private var decoder = HTTPResponseDecoder()
    private var cancelled = false
    private var finished = false

    init(endpoint: NWEndpoint, path: String, deviceName: String, timeout: TimeInterval) {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        connection = NWConnection(to: endpoint, using: params)
        let name = String(deviceName.filter { !$0.isNewline && $0 != "\r" }.prefix(128))
        request = Data("GET \(path) HTTP/1.1\r\nHost: mystat\r\nX-Device-Name: \(name)\r\nConnection: close\r\n\r\n".utf8)
        self.timeout = timeout
    }

    func start(_ continuation: CheckedContinuation<Data, Error>) {
        queue.async {
            self.continuation = continuation
            if self.cancelled { self.finish(.failure(CancellationError())); return }
            let deadline = DispatchWorkItem { [weak self] in self?.finish(.failure(StatsError.timedOut)) }
            self.deadline = deadline
            self.queue.asyncAfter(deadline: .now() + self.timeout, execute: deadline)
            self.connection.stateUpdateHandler = { [weak self] state in
                guard let self, !self.finished else { return }
                switch state {
                case .ready:
                    self.connection.send(content: self.request, completion: .contentProcessed { [weak self] error in
                        guard let self, !self.finished else { return }
                        if let error { self.finish(.failure(error)) } else { self.receive() }
                    })
                case .failed(let error): self.finish(.failure(error))
                default: break // Waiting for Wi-Fi/permission is bounded by the deadline.
                }
            }
            self.connection.start(queue: self.queue)
        }
    }

    func cancel() {
        queue.async {
            self.cancelled = true
            if self.continuation != nil { self.finish(.failure(CancellationError())) }
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self, !self.finished else { return }
            do {
                if let body = try self.decoder.receive(data ?? Data(), isComplete: isComplete) {
                    self.finish(.success(body))
                } else if let error {
                    self.finish(.failure(error))
                } else {
                    self.receive()
                }
            } catch { self.finish(.failure(error)) }
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard !finished else { return }
        finished = true
        deadline?.cancel()
        deadline = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation?.resume(with: result)
        continuation = nil
    }
}
