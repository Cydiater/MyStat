import Cocoa
import Darwin

/// Apple's nettop supplies per-process TCP/UDP byte counters without elevation.
/// Only process summaries are requested: no endpoints or packet contents.
final class NetworkProcessMonitor {
    private(set) var latest: NetworkAppSnapshot?
    private let queue = DispatchQueue(label: "com.cydiater.MyStat.network-apps", qos: .utility)
    private var process: Process?
    private var output: FileHandle?
    private var lifeline: Pipe?
    private var parser = NetworkTrafficParser()
    private var tracker = NetworkAppRateTracker()
    private var lastOutput: TimeInterval = 0
    private var retryAfter: TimeInterval = 0
    private var stopped = false
    private var generation = 0

    func refresh() {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if let process = self.process {
                if now - self.lastOutput > 12 { self.end(process) }
            } else if now >= self.retryAfter { self.start() }
        }
    }

    func stop() {
        queue.sync {
            stopped = true
            generation += 1
            try? lifeline?.fileHandleForWriting.close()
            lifeline = nil
            if let process { end(process) }
            output?.readabilityHandler = nil
            try? output?.close()
            output = nil
        }
    }

    private func start() {
        generation += 1
        let currentGeneration = generation
        parser = .init(); tracker = .init()
        let child = Process()
        // An idle supervisor holds a pipe from MyStat. EOF (including a crash or
        // force quit) terminates nettop, which otherwise survives its parent.
        // This is a fixed script: no shell interpolation of external input.
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", """
            /usr/bin/nettop -P -L 0 -s 2 -J bytes_in,bytes_out -x -n -t external <&1 &
            collector=$!
            trap 'kill -TERM "$collector" 2>/dev/null; wait "$collector" 2>/dev/null' EXIT
            trap 'exit 0' HUP INT TERM
            read -r lifeline
            """]
        let pipe = Pipe()
        child.standardInput = pipe
        child.standardError = FileHandle.nullDevice

        // nettop block-buffers stdout to pipes, delaying small snapshots for many
        // seconds. A PTY makes its CSV output line-buffered. Give it enough rows
        // to avoid terminal-height truncation, and disable terminal processing.
        var master: Int32 = -1, slave: Int32 = -1
        var size = winsize(ws_row: 32768, ws_col: 1024, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else { retryAfter = ProcessInfo.processInfo.systemUptime + 30; return }
        var attributes = termios()
        if tcgetattr(slave, &attributes) == 0 { cfmakeraw(&attributes); tcsetattr(slave, TCSANOW, &attributes) }
        let reader = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        let writer = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        child.standardOutput = writer
        // The script redirects nettop's stdin to this same idle PTY. /dev/null
        // would be permanently readable at EOF, making its input loop spin.
        child.terminationHandler = { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                self.output?.readabilityHandler = nil
                try? self.output?.close()
                self.output = nil; self.process = nil
                try? self.lifeline?.fileHandleForWriting.close()
                self.lifeline = nil
                self.retryAfter = ProcessInfo.processInfo.systemUptime + 30
            }
        }
        do { try child.run() }
        catch {
            try? reader.close(); try? writer.close()
            retryAfter = ProcessInfo.processInfo.systemUptime + 30
            return
        }
        try? writer.close()
        process = child; output = reader; lifeline = pipe
        lastOutput = ProcessInfo.processInfo.systemUptime
        reader.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            let receivedAt = ProcessInfo.processInfo.systemUptime
            self?.queue.async { [weak self] in
                guard let self, !self.stopped, self.generation == currentGeneration else { return }
                guard !data.isEmpty else { self.output?.readabilityHandler = nil; return }
                self.lastOutput = receivedAt
                for frame in self.parser.append(data, time: receivedAt) {
                    let readings = frame.counters.compactMap(Self.reading)
                    let snapshot = self.tracker.sample(readings, time: frame.time,
                        at: Date().addingTimeInterval(frame.time - ProcessInfo.processInfo.systemUptime))
                    DispatchQueue.main.async { [weak self] in self?.latest = snapshot }
                }
            }
        }
    }

    private func end(_ child: Process) {
        guard child.isRunning else { return }
        child.terminate()
        // A hung collector must not survive shutdown or block a restart.
        queue.asyncAfter(deadline: .now() + 2) {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }

    private static func reading(_ counter: NetworkProcessCounter) -> NetworkAppRateTracker.Reading? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(counter.pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let identity = "\(counter.pid):\(info.pbi_start_tvsec):\(info.pbi_start_tvusec)"
        let location = ProcessIconProvider.executableURL(for: counter.pid)
        let application = location.flatMap(ProcessIconProvider.owningApplication)
        let name = application?.deletingPathExtension().lastPathComponent ?? counter.name
        return .init(counter: counter, identity: identity, appID: application?.path ?? identity,
                     name: name, applicationURL: application)
    }
}
