import Cocoa
import ServiceManagement
import MyStatCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var statusPopover: StatusPopover!
    private var timer: Timer?
    private weak var launchAtLoginItem: NSMenuItem?
    private weak var sharingItem: NSMenuItem?
    private let keepAwakeController = KeepAwakeController()
    private lazy var keepAwakeView = KeepAwakeView(controller: keepAwakeController)
    private let deviceMenuTag = 100
    private var lastKnownDevices: [String] = []

    private let monitor = StatsMonitor()
    private let extendedMonitor = ExtendedMonitor()
    private let tokenMonitor = TokenMonitor()
    private let processMonitor = ProcessMonitor()
    private lazy var processCharts = ProcessChartGroupView(cpu: cpuChartView, memory: memChartView, details: detailsView)
    private let appUpdater = AppUpdater()
    private let detailsView = MetricsOverviewView(frame: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: DashboardStyle.detailsHeight))
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
        let v = StatsChartView(frame: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: DashboardStyle.chartHeight))
        v.title = "CPU"
        v.color = DashboardStyle.orange
        v.windowMinutes = dropdownMinutes
        return v
    }()

    private lazy var memChartView: StatsChartView = {
        let v = StatsChartView(frame: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: DashboardStyle.chartHeight))
        v.title = "Memory"
        v.color = DashboardStyle.blue
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
        sc.frame = NSRect(x: 8, y: 4, width: DashboardStyle.width - 16, height: 22)
        sc.selectedSegment = availableRanges.firstIndex { $0.minutes == dropdownMinutes } ?? 0
        return sc
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        statusMenu = menu

        let rangeContainer = NSView(frame: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: 30))
        rangeContainer.addSubview(rangeControl)
        let rangeItem = NSMenuItem()
        rangeItem.view = rangeContainer
        menu.addItem(rangeItem)

        let chartsItem = NSMenuItem()
        chartsItem.view = processCharts
        menu.addItem(chartsItem)

        menu.addItem(Self.insetSeparator())
        let sharing = NSMenuItem(title: "Starting iPhone sharing…", action: nil, keyEquivalent: "")
        sharing.isEnabled = false
        menu.addItem(sharing)
        sharingItem = sharing
        statsServer.onStatusChange = { [weak self] text in self?.sharingItem?.title = text }
        let keepAwakeMenuItem = NSMenuItem()
        keepAwakeMenuItem.view = keepAwakeView
        menu.addItem(keepAwakeMenuItem)

        if #available(macOS 13.0, *) {
            let enabled = SMAppService.mainApp.status == .enabled
            let launchItem = NSMenuItem(
                title: "Launch at Login",
                action: #selector(toggleLaunchAtLogin(_:)),
                keyEquivalent: ""
            )
            launchItem.target = self
            launchItem.state = enabled ? .on : .off
            menu.addItem(launchItem)
            launchAtLoginItem = launchItem
        }
        menu.addItem(Self.insetSeparator())
        let aboutItem = NSMenuItem(title: "About MyStat", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(appUpdater.checkItem)
        menu.addItem(appUpdater.automaticItem)
        menu.addItem(Self.insetSeparator())
        let quitItem = NSMenuItem(
            title: "Quit MyStat",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        menu.delegate = self
        statusPopover = StatusPopover(menu: menu)
        statusPopover.onClose = { [weak self] in self?.processCharts.stopTracking() }
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleStatusPopover(_:))
        appUpdater.start()

        statsServer.start()

        // Prime the CPU sampler so the first visible tick is meaningful.
        _ = monitor.cpuUsage()
        _ = extendedMonitor.network()

        refresh()
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    private var lastMemorySnapshot = MemorySnapshot(usedBytes: 0, totalBytes: 0)

    @objc private func toggleStatusPopover(_ sender: NSStatusBarButton) {
        if !statusPopover.isShown { menuWillOpen(statusMenu) }
        statusPopover.toggle(relativeTo: sender)
        if statusPopover.isShown { processCharts.startTracking() }
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "MyStat",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development",
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—",
            .credits: NSAttributedString(string: "Live system readings and process rankings for your desk.\nUpdates: github.com/Cydiater/MyStat")
        ])
    }

    /// A separator whose line is inset on the left so it clears the checkmark
    /// gutter used by the toggle items, instead of spanning the full width.
    private static func insetSeparator() -> NSMenuItem {
        let item = NSMenuItem()
        item.view = InsetSeparatorView(frame: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: 11))
        return item
    }

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
        sender.state = service.status == .enabled ? .on : .off
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
        let network = extendedMonitor.network()
        let power = extendedMonitor.power()
        let system = extendedMonitor.system()
        tokenMonitor.refresh()
        processMonitor.refresh()
        history.record(cpu: cpu, memory: mem.percent, network: network, power: power)
        lastMemorySnapshot = mem
        statsServer.update(
            samples: history.samples, usedBytes: mem.usedBytes, totalBytes: mem.totalBytes,
            interval: pollInterval, system: system, tokens: tokenMonitor.latest, processes: processMonitor.latest
        )
        detailsView.update(network: network, power: power, system: system, tokens: tokenMonitor.latest)
        processCharts.update(processMonitor.latest)
        updateDeviceMenu()
        statusPopover.refresh()
        renderViews()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        statsServer.stop()
        keepAwakeController.stop()
    }

    private func updateDeviceMenu() {
        let devices = statsServer.activeDevices
        guard devices != lastKnownDevices else { return }
        lastKnownDevices = devices

        guard let menu = statusMenu else { return }

        menu.items.filter { $0.tag >= deviceMenuTag }.forEach { menu.removeItem($0) }

        guard !devices.isEmpty else { return }

        let insertAt = menu.items.firstIndex(where: { $0 === sharingItem }) ?? 5
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
            subtitle: "System utilization"
        )
        memChartView.update(
            values: dropMem,
            capacity: dropSamples,
            subtitle: String(
                format: "%@ / %@ GB",
                ByteFormat.gb(mem.usedBytes),
                ByteFormat.gb(mem.totalBytes)
            )
        )
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        keepAwakeController.refresh()
        if #available(macOS 13.0, *), let item = launchAtLoginItem {
            item.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }
}

/// Draws a thin separator line that is inset from the left edge so it does not
/// run across the menu's checkmark gutter.
private final class InsetSeparatorView: NSView {
    private let leftInset: CGFloat = 21
    private let rightInset: CGFloat = 8

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        let line = NSRect(
            x: leftInset,
            y: (bounds.height - 1).rounded() / 2,
            width: bounds.width - leftInset - rightInset,
            height: 1
        )
        line.fill()
    }
}
