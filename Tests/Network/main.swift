import Cocoa
import MyStatCore

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

// Headers are the frame boundary; data can arrive one byte at a time.
let csv = ",bytes_out,bytes_in,\r\n\"App.with.\"\"quotes\"\", comma.42\",100,300,\r\ninvalid,1,2,\r\n,bytes_out,bytes_in,\r\n"
var parser = NetworkTrafficParser()
var frames: [NetworkTrafficParser.Frame] = []
for byte in csv.utf8 { frames += parser.append(Data([byte]), time: 100) }
precondition(frames.count == 1 && frames[0].counters.count == 1)
let counter = frames[0].counters[0]
precondition(counter.pid == 42 && counter.name == "App.with.\"quotes\", comma" && counter.received == 300 && counter.sent == 100)
precondition(parser.append(Data("Bad.3,nope,0,\n,bytes_out,bytes_in,\n".utf8), time: 102).first?.counters.isEmpty == true)
precondition(parser.append(Data(repeating: 65, count: 1_048_577), time: 104).isEmpty)
precondition(parser.append(Data(",bytes_in,bytes_out,\nOK.1,1,2,\n,bytes_in,bytes_out,\n".utf8), time: 106).first?.counters.count == 1)
print("PASS: CSV framing, chunk boundaries, column order, names, malformed counters and bounded buffering")

func reading(_ pid: Int32, _ received: UInt64, _ sent: UInt64 = 0, birth: Int = 1, app: String? = nil) -> NetworkAppRateTracker.Reading {
    let identity = "\(pid):\(birth)"
    return .init(counter: .init(pid: pid, name: "Process \(pid)", received: received, sent: sent),
                 identity: identity, appID: app ?? identity, name: app ?? "Process \(pid)", applicationURL: nil)
}
var tracker = NetworkAppRateTracker()
let date = Date()
precondition(tracker.sample([reading(1, 100), reading(2, 200)], time: 100, at: date) == nil)
let grouped = tracker.sample([reading(1, 300, 100, app: "Browser"), reading(2, 800, 300, app: "Browser")], time: 102, at: date)!
precondition(grouped.apps.count == 1 && grouped.apps[0].download == 400 && grouped.apps[0].upload == 200)
let shared = grouped.sharedSnapshot
precondition(shared.isValid && shared.apps[0].name == "Browser" && shared.apps[0].downloadBytesPerSecond == 400)
let sharedJSON = String(decoding: try JSONEncoder().encode(shared), as: UTF8.self)
precondition(!sharedJSON.contains("applicationURL"))
precondition(tracker.sample([reading(1, 10_000, birth: 2), reading(2, 20)], time: 104, at: date)!.apps.isEmpty,
             "PID reuse and counter reset must not create traffic spikes")
precondition(tracker.sample([reading(1, 10_000, birth: 2)], time: 106, at: date)!.apps.isEmpty, "Zero traffic is a valid empty ranking")
precondition(tracker.sample([reading(1, 100_000, birth: 2)], time: 120, at: date) == nil, "Long gaps establish a new baseline")
precondition(tracker.sample([reading(1, 200_000, birth: 2)], time: 119, at: date) == nil)
tracker = .init()
_ = tracker.sample((1...8).map { reading(Int32($0), 0) }, time: 1, at: date)
let ranked = tracker.sample((1...8).map { reading(Int32($0), UInt64($0 * 100)) }, time: 3, at: date)!
precondition(ranked.apps.map(\.pid) == [8, 7, 6, 5, 4])
precondition(!ranked.isStale(at: date + 9) && ranked.isStale(at: date + 11))
print("PASS: byte deltas, elapsed time, helper grouping, PID reuse, reset, zero traffic, gaps and top-five ranking")

let clean = NetworkChartData(download: [1, 2, nil, .nan, -.infinity, -1, 1200], upload: [nil, 400], capacity: 6)
precondition(clean.download.count == 6 && clean.download[0] == 2 && clean.download[1...4].allSatisfy { $0 == nil })
precondition(clean.ceiling == 2000 && NetworkChartData().ceiling == 1000)
precondition(NetworkChartData(download: [.greatestFiniteMagnitude]).ceiling.isFinite)
let base = StatusBarRenderer.render(cpu: [0, 20], memory: [40, 50], capacity: 2)
let net = StatusBarRenderer.render(cpu: [0, 20], memory: [40, 50], capacity: 2, network: clean, metric: .network)
let unavailable = StatusBarRenderer.render(cpu: [], memory: [], capacity: 2, network: .init(), metric: .network)
let mem = StatusBarRenderer.render(cpu: [0, 20], memory: [40, 50], capacity: 2, metric: .memory)
precondition(base.size.width < 75 && mem.size == base.size && net.size.width < 75 && unavailable.size.width < net.size.width,
             "Each caption must fit its text instead of reserving space for longer readings")
precondition([base, net, unavailable, mem].allSatisfy { $0.isTemplate && $0.size.height == base.size.height })
for (rate, expected) in [(0.0, "0B/s"), (999, "999B/s"), (999.5, "1.0K/s"), (9_999, "10K/s"),
                         (999_500, "1.0M/s"), (1_200_000, "1.2M/s"), (120_000_000, "120M/s")] {
    precondition(StatusBarRenderer.compactRate(rate) == expected)
    let width = NSAttributedString(string: expected, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)]).size().width
    precondition(width <= 44, "A formatted rate must fit without clipping or resizing the item")
}
precondition(StatusBarRenderer.compactRate(.nan) == "—" && StatusBarRenderer.compactRate(-1) == "—")
let uploadCaption = StatusBarRenderer.caption(cpu: nil, memory: nil, network: clean, metric: .network, preferUpload: true)
precondition(uploadCaption.label == "NET ↑" && uploadCaption.value == "400B/s")
precondition(StatusBarRenderer.caption(cpu: 30, memory: 60, network: clean, metric: .cpu, unavailable: true).value == "—")
print("PASS: chart range, invalid data gaps, capacity, scale and compact menu-bar captions")

let menu = NetworkProcessMenu()
precondition(menu.item.view == nil && menu.item.submenu === menu.menu && menu.menu.items.allSatisfy { $0.view == nil })
menu.update(grouped)
let firstRow = menu.menu.items[0]
precondition(!firstRow.isHidden && firstRow.image != nil)
if #available(macOS 14.0, *) { precondition(firstRow.badge?.stringValue == "↓ 400 B/s  ↑ 200 B/s") }
if #available(macOS 27.0, *) { precondition(firstRow.preferredImageVisibility == .visible) }
menu.update(.init(sampledAt: date - 30, apps: grouped.apps))
precondition(menu.menu.items[0] === firstRow && firstRow.toolTip!.contains("Stale"))
menu.update(.init(sampledAt: date, apps: []))
precondition(firstRow.isHidden && menu.menu.items.contains { !$0.isHidden && $0.title == "No active app traffic" })
menu.update(nil)
precondition(menu.menu.items.contains { !$0.isHidden && $0.title.contains("unavailable") })
print("PASS: native submenu, icons, rate badges, stable rows, empty, missing and stale readings")

// Render code-owned views, not a screen capture, for light/dark visual inspection.
let chart = NetworkChartView(frame: NSRect(x: 0, y: 0, width: 360, height: 140))
let samples: [Double?] = (0..<90).map { index in index == 52 ? nil : (sin(Double(index) / 5) + 1.2) * 150_000 }
chart.update(.init(download: samples, upload: samples.map { $0.map { $0 / 3 } }, capacity: 90))
for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
    chart.appearance = NSAppearance(named: appearance)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 720, pixelsHigh: 280, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = chart.bounds.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    chart.appearance!.performAsCurrentDrawingAppearance {
        NSColor.windowBackgroundColor.setFill(); chart.bounds.fill()
        chart.draw(chart.bounds)
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/network-tests/chart-\(name).png"))
}

if CommandLine.arguments.contains("--crash-child") {
    // A separate harness is killed by the --live test to exercise pipe EOF.
    let monitor = NetworkProcessMonitor()
    monitor.refresh()
    RunLoop.main.run(until: Date() + 15)
    monitor.stop()
    exit(0)
}

if CommandLine.arguments.contains("--live") {
    let monitor = NetworkProcessMonitor()
    monitor.refresh()
    let deadline = Date() + 9
    while Date() < deadline && monitor.latest == nil { RunLoop.main.run(until: Date() + 0.1) }
    precondition(monitor.latest != nil && !monitor.latest!.isStale(), "The real collector must return a fresh snapshot")
    print("PASS: live unprivileged nettop stream (\(monitor.latest!.apps.count) active apps)")
    func children(of pid: Int32) -> [Int32] {
        let command = Process(), pipe = Pipe()
        command.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        command.arguments = ["-P", "\(pid)"]
        command.standardOutput = pipe
        try! command.run(); command.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").compactMap { Int32($0) }.filter { $0 != command.processIdentifier }
    }
    let supervisor = children(of: getpid()).first!
    let childPID = children(of: supervisor).first!
    func cpuSeconds() -> Double {
        var info = proc_taskinfo(), timebase = mach_timebase_info_data_t()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        precondition(proc_pidinfo(childPID, PROC_PIDTASKINFO, 0, &info, size) == size)
        mach_timebase_info(&timebase)
        return Double(info.pti_total_user + info.pti_total_system) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }
    let before = cpuSeconds()
    RunLoop.main.run(until: Date() + 2)
    let usedCPU = cpuSeconds() - before
    precondition(usedCPU < 0.4, "An idle collector must not spin on stdin EOF")
    print(String(format: "PASS: collector uses %.3f CPU seconds over a two-second sample", usedCPU))
    monitor.stop()
    let stopDeadline = Date() + 3
    while Date() < stopDeadline && (kill(supervisor, 0) == 0 || kill(childPID, 0) == 0) { RunLoop.main.run(until: Date() + 0.1) }
    precondition(kill(supervisor, 0) != 0 && kill(childPID, 0) != 0, "Stopping MyStat must terminate its collector and supervisor")
    print("PASS: collector shutdown leaves no subprocess")

    let crash = Process()
    crash.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    crash.arguments = ["--crash-child"]
    crash.standardOutput = FileHandle.nullDevice
    try crash.run()
    var crashSupervisor: Int32?, crashCollector: Int32?
    let launchDeadline = Date() + 5
    while Date() < launchDeadline && crashCollector == nil {
        crashSupervisor = children(of: crash.processIdentifier).first
        crashCollector = crashSupervisor.flatMap { children(of: $0).first }
        RunLoop.main.run(until: Date() + 0.1)
    }
    precondition(crashCollector != nil)
    kill(crash.processIdentifier, SIGKILL); crash.waitUntilExit()
    let cleanupDeadline = Date() + 3
    while Date() < cleanupDeadline && (kill(crashCollector!, 0) == 0 || kill(crashSupervisor!, 0) == 0) {
        RunLoop.main.run(until: Date() + 0.1)
    }
    precondition(kill(crashCollector!, 0) != 0 && kill(crashSupervisor!, 0) != 0, "Crashing MyStat must close its lifeline and clean up nettop")
    print("PASS: force-quit cleanup leaves no orphan collector or supervisor")
}
