import Foundation
import Network
import MyStatCore

final class StatsServer {
    private var listener: NWListener?
    private var retry: DispatchWorkItem?
    private var running = false
    private var snapshot: LiveStats?
    private var history = HistoryPayload(samples: [], interval: 2)
    private var devices: [String: Date] = [:]
    private var connections: [UUID: NWConnection] = [:]
    private var deadlines: [UUID: DispatchWorkItem] = [:]
    var onStatusChange: ((String) -> Void)?

    var activeDevices: [String] {
        devices = devices.filter { Date().timeIntervalSince($0.value) < 15 }
        return devices.keys.sorted()
    }

    func start() {
        guard !running else { return }
        running = true
        listen()
    }

    private func listen() {
        guard running else { return }
        retry?.cancel()
        listener?.cancel()
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            let newListener = try NWListener(using: params, on: 18735)
            listener = newListener
            newListener.service = NWListener.Service(name: Host.current().localizedName ?? "MyStat", type: "_mystat._tcp")
            newListener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            newListener.stateUpdateHandler = { [weak self, weak newListener] state in
                guard let self, let newListener, self.listener === newListener else { return }
                switch state {
                case .ready: self.onStatusChange?("iPhone sharing available")
                case .failed(let error): self.scheduleRetry(error)
                case .waiting: self.onStatusChange?("iPhone sharing: waiting for network")
                default: break
                }
            }
            newListener.start(queue: .main)
        } catch { scheduleRetry(error) }
    }

    private func scheduleRetry(_ error: Error) {
        guard running else { return }
        NSLog("StatsServer: %@", error.localizedDescription)
        onStatusChange?("iPhone sharing unavailable — retrying")
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        retry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.listen() }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    func update(samples: [StatsSample], usedBytes: UInt64, totalBytes: UInt64, interval: Double) {
        guard let latest = samples.last else { return }
        snapshot = LiveStats(sample: latest, host: Host.current().localizedName, usedBytes: usedBytes, totalBytes: totalBytes)
        history = HistoryPayload(samples: samples, interval: interval)
    }

    private func handle(_ conn: NWConnection) {
        guard connections.count < 32 else { conn.cancel(); return }
        let id = UUID()
        connections[id] = conn
        let deadline = DispatchWorkItem { [weak self] in self?.close(id) }
        deadlines[id] = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: deadline)
        conn.start(queue: .main)
        receiveHeader(id, buffer: Data())
    }

    private func receiveHeader(_ id: UUID, buffer: Data) {
        guard let conn = connections[id] else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self, self.connections[id] != nil else { return }
            var buffer = buffer
            buffer.append(data ?? Data())
            guard buffer.count <= 16_384 else { self.respond(id, status: "431 Request Header Fields Too Large"); return }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)),
               let header = String(data: buffer[..<end.lowerBound], encoding: .utf8) {
                self.route(id, header: header)
            } else if complete || error != nil {
                self.close(id)
            } else {
                self.receiveHeader(id, buffer: buffer)
            }
        }
    }

    private func route(_ id: UUID, header: String) {
        let lines = header.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count == 3 else { respond(id, status: "400 Bad Request"); return }
        guard parts[0] == "GET" else { respond(id, status: "405 Method Not Allowed"); return }
        guard parts[1] == "/" || parts[1] == "/history" else { respond(id, status: "404 Not Found"); return }
        for line in lines.dropFirst() where line.lowercased().hasPrefix("x-device-name:") {
            let name = String(line.dropFirst(14)).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { devices[String(name.prefix(128))] = .now }
        }
        guard let snapshot else { respond(id, status: "503 Service Unavailable"); return }
        do {
            let encoder = JSONEncoder()
            let data = try parts[1] == "/history" ? encoder.encode(history) : encoder.encode(snapshot)
            respond(id, status: "200 OK", body: data)
        } catch { respond(id, status: "500 Internal Server Error") }
    }

    private func respond(_ id: UUID, status: String, body: Data = Data("{}".utf8)) {
        guard let conn = connections[id] else { return }
        var data = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        data.append(body)
        conn.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in self?.close(id) })
    }

    private func close(_ id: UUID) {
        deadlines.removeValue(forKey: id)?.cancel()
        connections.removeValue(forKey: id)?.cancel()
    }

    func stop() {
        running = false
        retry?.cancel()
        retry = nil
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        for id in Array(connections.keys) { close(id) }
    }
}
