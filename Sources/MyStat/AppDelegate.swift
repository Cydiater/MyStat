import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private weak var launchAtLoginItem: NSMenuItem?
    private let deviceMenuTag = 100
    private var lastKnownDevices: [String] = []

    private let monitor = StatsMonitor()
    private let statsServer = StatsServer()
    private let pollInterval: TimeInterval = 2.0

    /// Long-lived sample buffer. The status bar always reads the most recent
    /// `statusBarMinutes`; the dropdown reads `dropdownMinutes`, which the user
    /// picks from the segmented control at the top of the menu.
    private let maxHistoryMinutes: Double = 60
    private let statusBarMinutes: Double = 3
    private let availableRanges: [(label: String, minutes: Int)] = [
        ("3m", 3), ("15m", 15), ("1h", 60),
    ]
    private var dropdownMinutes: Int = 3

    private lazy var history = StatsHistory(
        capacity: Int((maxHistoryMinutes * 60.0 / pollInterval).rounded())
    )

    private lazy var cpuChartView: StatsChartView = {
        let v = StatsChartView(frame: NSRect(x: 0, y: 0, width: 260, height: 100))
        v.title = "CPU"
        v.color = .systemOrange
        v.windowMinutes = dropdownMinutes
        return v
    }()

    private lazy var memChartView: StatsChartView = {
        let v = StatsChartView(frame: NSRect(x: 0, y: 0, width: 260, height: 100))
        v.title = "Memory"
        v.color = .systemTeal
        v.windowMinutes = dropdownMinutes
        return v
    }()

    private lazy var rangeControl: NSSegmentedControl = {
        let labels = availableRanges.map(\.label)
        let sc = NSSegmentedControl(
            labels: labels,
            trackingMode: .selectOne,
            target: self,
            action: #selector(rangeChanged(_:))
        )
        sc.frame = NSRect(x: 8, y: 4, width: 244, height: 22)
        sc.selectedSegment = availableRanges.firstIndex { $0.minutes == dropdownMinutes } ?? 0
        return sc
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly

        let menu = NSMenu()

        let rangeContainer = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
        rangeContainer.addSubview(rangeControl)
        let rangeItem = NSMenuItem()
        rangeItem.view = rangeContainer
        menu.addItem(rangeItem)

        let cpuItem = NSMenuItem()
        cpuItem.view = cpuChartView
        let memItem = NSMenuItem()
        memItem.view = memChartView
        menu.addItem(cpuItem)
        menu.addItem(memItem)

        menu.addItem(.separator())
        if #available(macOS 13.0, *) {
            let enabled = SMAppService.mainApp.status == .enabled
            let launchItem = NSMenuItem(
                title: "Launch at Login",
                action: #selector(toggleLaunchAtLogin(_:)),
                keyEquivalent: ""
            )
            launchItem.target = self
            launchItem.image = Self.launchAtLoginIcon(enabled: enabled)
            menu.addItem(launchItem)
            launchAtLoginItem = launchItem
        }
        let quitItem = NSMenuItem(
            title: "Quit MyStat",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)
        menu.delegate = self
        statusItem.menu = menu

        statsServer.start()

        // Prime the CPU sampler so the first visible tick is meaningful.
        _ = monitor.cpuUsage()

        refresh()
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    private var lastMemorySnapshot = MemorySnapshot(usedBytes: 0, totalBytes: 0)

    @available(macOS 13.0, *)
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        sender.image = Self.launchAtLoginIcon(enabled: service.status == .enabled)
    }

    private static func launchAtLoginIcon(enabled: Bool) -> NSImage? {
        let name = enabled ? "checkmark.circle.fill" : "circle"
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    @objc private func rangeChanged(_ sender: NSSegmentedControl) {
        let idx = sender.selectedSegment
        guard idx >= 0, idx < availableRanges.count else { return }
        dropdownMinutes = availableRanges[idx].minutes
        cpuChartView.windowMinutes = dropdownMinutes
        memChartView.windowMinutes = dropdownMinutes
        renderViews()
    }

    private func refresh() {
        let cpu = monitor.cpuUsage()
        let mem = monitor.memory()
        history.record(cpu: cpu, memory: mem.percent)
        lastMemorySnapshot = mem
        statsServer.update(
            cpu: cpu, mem: mem.percent,
            cpuHistory: history.cpu, memHistory: history.memory,
            interval: pollInterval
        )
        updateDeviceMenu()
        renderViews()
    }

    private func updateDeviceMenu() {
        let devices = statsServer.activeDevices
        guard devices != lastKnownDevices else { return }
        lastKnownDevices = devices

        guard let menu = statusItem.menu else { return }

        menu.items.filter { $0.tag >= deviceMenuTag }.forEach { menu.removeItem($0) }

        guard !devices.isEmpty else { return }

        let insertAt = 3
        let sep = NSMenuItem.separator()
        sep.tag = deviceMenuTag
        menu.insertItem(sep, at: insertAt)

        for (i, device) in devices.enumerated() {
            let item = NSMenuItem()
            item.title = device
            item.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: nil)
            item.isEnabled = false
            item.tag = deviceMenuTag + 1 + i
            menu.insertItem(item, at: insertAt + 1 + i)
        }
    }

    private func renderViews() {
        let cpu = history.cpu.last ?? 0
        let mem = lastMemorySnapshot
        let barSamples = max(2, Int((statusBarMinutes * 60.0 / pollInterval).rounded()))
        let barCpu = Array(history.cpu.suffix(barSamples))
        let barMem = Array(history.memory.suffix(barSamples))
        if let button = statusItem.button {
            button.image = StatusBarRenderer.render(
                cpu: barCpu, memory: barMem, capacity: barSamples
            )
        }

        let dropSamples = max(2, Int((Double(dropdownMinutes) * 60.0 / pollInterval).rounded()))
        let dropCpu = Array(history.cpu.suffix(dropSamples))
        let dropMem = Array(history.memory.suffix(dropSamples))

        cpuChartView.update(
            values: dropCpu,
            capacity: dropSamples,
            subtitle: String(format: "%.1f%%", cpu)
        )
        memChartView.update(
            values: dropMem,
            capacity: dropSamples,
            subtitle: String(
                format: "%@ / %@ GB  (%.0f%%)",
                ByteFormat.gb(mem.usedBytes),
                ByteFormat.gb(mem.totalBytes),
                mem.percent
            )
        )
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        if #available(macOS 13.0, *), let item = launchAtLoginItem {
            let enabled = SMAppService.mainApp.status == .enabled
            item.image = AppDelegate.launchAtLoginIcon(enabled: enabled)
        }
    }
}
