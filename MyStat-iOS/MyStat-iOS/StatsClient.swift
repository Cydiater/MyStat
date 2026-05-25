import Foundation
import Network
import WidgetKit
import UIKit

@Observable
final class StatsClient {
    var cpu: Double = 0
    var mem: Double = 0
    var isConnected = false
    var hostName: String?
    let store = StatsStore()

    private var browser: NWBrowser?
    private var endpoint: NWEndpoint?
    private var timer: Timer?
    private var lastWidgetReload: Date = .distantPast
    private var didFetchHistory = false
    private let deviceName = UIDevice.current.name

    func start() {
        let params = NWParameters()
        params.includePeerToPeer = true
        browser = NWBrowser(for: .bonjour(type: "_mystat._tcp", domain: nil), using: params)

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                if let result = results.first {
                    self.endpoint = result.endpoint
                    if case .service(let name, _, _, _) = result.endpoint {
                        self.hostName = name
                    }
                    if !self.isConnected {
                        self.isConnected = true
                        self.didFetchHistory = false
                        self.startPolling()
                    }
                } else {
                    self.endpoint = nil
                    self.hostName = nil
                    self.isConnected = false
                    self.didFetchHistory = false
                    self.stopPolling()
                }
            }
        }

        browser?.start(queue: .main)
    }

    private func startPolling() {
        timer?.invalidate()
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.fetch()
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func fetch() {
        guard let endpoint else { return }
        let conn = NWConnection(to: endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.sendRequest(conn)
            case .failed:
                conn.cancel()
            default:
                break
            }
        }
        conn.start(queue: .main)
    }

    private func sendRequest(_ conn: NWConnection) {
        let request = "GET / HTTP/1.1\r\nHost: mystat\r\nX-Device-Name: \(deviceName)\r\nConnection: close\r\n\r\n"
        conn.send(content: request.data(using: .utf8), completion: .contentProcessed { error in
            if error != nil {
                conn.cancel()
                return
            }
            conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
                defer { conn.cancel() }
                guard let data, let text = String(data: data, encoding: .utf8) else { return }
                guard let bodyStart = text.range(of: "\r\n\r\n") else { return }
                let body = Data(text[bodyStart.upperBound...].utf8)
                guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return }

                if let self, !self.didFetchHistory,
                   let path = conn.currentPath,
                   let remote = path.remoteEndpoint {
                    self.fetchHistoryHTTP(remote: remote)
                }

                DispatchQueue.main.async {
                    let cpuVal = json["cpu"] as? Double ?? 0
                    let memVal = json["mem"] as? Double ?? 0
                    self?.cpu = cpuVal
                    self?.mem = memVal
                    self?.store.append(cpu: cpuVal, mem: memVal)
                    SharedDefaults.save(cpu: cpuVal, mem: memVal, host: self?.hostName)

                    if let self, Date().timeIntervalSince(self.lastWidgetReload) > 30 {
                        WidgetCenter.shared.reloadAllTimelines()
                        self.lastWidgetReload = Date()
                    }
                }
            }
        })
    }

    private func fetchHistoryHTTP(remote: NWEndpoint) {
        didFetchHistory = true

        guard case .hostPort(let host, let port) = remote else { return }
        let hostStr: String
        switch host {
        case .ipv6:
            hostStr = "[\(host)]"
        default:
            hostStr = "\(host)"
        }

        guard let url = URL(string: "http://\(hostStr):\(port.rawValue)/history") else { return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(deviceName, forHTTPHeaderField: "X-Device-Name")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data else { return }
            self?.parseHistory(data)
        }.resume()
    }

    private func parseHistory(_ body: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let cpuArr = json["cpu"] as? [Double],
              let memArr = json["mem"] as? [Double],
              let interval = json["interval"] as? Double,
              let endTs = json["endTs"] as? Double else { return }

        let count = min(cpuArr.count, memArr.count)
        guard count > 0 else { return }

        var samples: [StatsSample] = []
        samples.reserveCapacity(count)
        let endDate = Date(timeIntervalSince1970: endTs)
        for i in 0..<count {
            let offset = Double(count - 1 - i) * interval
            let ts = endDate.addingTimeInterval(-offset)
            samples.append(StatsSample(timestamp: ts, cpu: cpuArr[i], mem: memArr[i]))
        }

        DispatchQueue.main.async { [weak self] in
            self?.store.mergeHistory(samples)
        }
    }

    func stop() {
        browser?.cancel()
        browser = nil
        stopPolling()
    }
}
