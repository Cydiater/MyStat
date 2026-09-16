import Foundation
import MyStatCore

final class ProcessMonitor {
    private let queue = DispatchQueue(label: "MyStat.Processes", qos: .utility)
    private let sampler = MacProcessSampler() // queue only
    private var scanning = false // main queue only
    private(set) var latest: ProcessSnapshot? // main queue only

    func refresh() {
        if latest?.isStale(at: .now) == true { latest = nil }
        guard !scanning else { return }
        scanning = true
        queue.async { [self] in
            let result = sampler.sample()
            DispatchQueue.main.async { [self] in
                latest = result
                scanning = false
            }
        }
    }
}
