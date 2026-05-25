import Foundation
import Network

final class StatsServer {
    private var listener: NWListener?
    private(set) var cpu: Double = 0
    private(set) var mem: Double = 0
    private var cpuHistory: [Double] = []
    private var memHistory: [Double] = []
    private var interval: Double = 2.0
    private var devices: [String: Date] = [:]
    private let deviceTimeout: TimeInterval = 10

    var activeDevices: [String] {
        let cutoff = Date().addingTimeInterval(-deviceTimeout)
        return devices.filter { $0.value > cutoff }.keys.sorted()
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            listener = try NWListener(using: params, on: 18735)
        } catch {
            return
        }

        listener?.service = NWListener.Service(name: "MyStat", type: "_mystat._tcp")

        listener?.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }

        listener?.stateUpdateHandler = { state in
            if case .failed(let err) = state {
                NSLog("StatsServer listener failed: \(err)")
            }
        }

        listener?.start(queue: .main)
    }

    func update(cpu: Double, mem: Double, cpuHistory: [Double], memHistory: [Double], interval: Double) {
        self.cpu = cpu
        self.mem = mem
        self.cpuHistory = cpuHistory
        self.memHistory = memHistory
        self.interval = interval
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .main)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                conn.cancel()
                return
            }

            let lines = request.components(separatedBy: "\r\n")
            let parts = (lines.first ?? "").split(separator: " ")
            let path = parts.count >= 2 ? String(parts[1]) : "/"

            for line in lines {
                if line.lowercased().hasPrefix("x-device-name:") {
                    let name = String(line.dropFirst("X-Device-Name:".count)).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { self.devices[name] = Date() }
                }
            }

            let body: String
            switch path {
            case "/history":
                body = self.historyJSON()
            default:
                body = self.statsJSON()
            }

            let http = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            conn.send(content: http.data(using: .utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                conn.cancel()
            })
        }
    }

    private func statsJSON() -> String {
        "{\"cpu\":\(String(format: "%.1f", cpu)),\"mem\":\(String(format: "%.1f", mem)),\"ts\":\(Int(Date().timeIntervalSince1970))}"
    }

    private func historyJSON() -> String {
        let cpuStr = cpuHistory.map { String(format: "%.1f", $0) }.joined(separator: ",")
        let memStr = memHistory.map { String(format: "%.1f", $0) }.joined(separator: ",")
        return "{\"interval\":\(interval),\"cpu\":[\(cpuStr)],\"mem\":[\(memStr)],\"endTs\":\(Int(Date().timeIntervalSince1970))}"
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}
