import Cocoa
import ServiceManagement
import MyStatCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var timer: Timer?
    private weak var launchAtLoginItem: NSMenuItem?
    private weak var sharingItem: NSMenuItem?
    private weak var sharingSection: NSMenuItem?
    private let sharingMenu = NSMenu(title: "iPhone")
    private let keepAwakeController = KeepAwakeController()
    private lazy var keepAwakeMenu = KeepAwakeMenu(controller: keepAwakeController)
    private let deviceMenuTag = 100
    private var lastKnownDevices: [String]?

    private let monitor = StatsMonitor()
    private let extendedMonitor = ExtendedMonitor()
    private let tokenMonitor = TokenMonitor()
    private let processMonitor = ProcessMonitor()
    private let networkProcessMonitor = NetworkProcessMonitor()
    private let networkProcesses = NetworkProcessMenu()
    private let networkChartView = NetworkChartView(frame: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: 140))
    private let cpuProcesses = ProcessMenu(metric: .cpu)
    private let memoryProcesses = ProcessMenu(metric: .memory)
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
        sc.controlSize = .small
        sc.segmentStyle = .rounded
        if #available(macOS 26.0, *) { sc.borderShape = .capsule }
        for index in labels.indices { sc.setWidth(40, forSegment: index) }
        sc.sizeToFit()
        sc.frame.origin = NSPoint(x: DashboardStyle.width - 20 - sc.frame.width, y: (46 - sc.frame.height) / 2)
        sc.selectedSegment = availableRanges.firstIndex { $0.minutes == dropdownMinutes } ?? 0
        return sc
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = DashboardStyle.width
        statusMenu = menu

        let rangeContainer = NSView(frame: NSRect(x: 0, y: 0, width: DashboardStyle.width, height: 46))
        let heading = NSTextField(labelWithString: "Overview")
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        heading.frame = NSRect(x: 20, y: 13, width: 150, height: 20)
        rangeContainer.addSubview(heading)
        rangeContainer.addSubview(rangeControl)
        let rangeItem = NSMenuItem()
        rangeItem.view = rangeContainer
        menu.addItem(rangeItem)

        for (chart, processes) in [(cpuChartView, cpuProcesses), (memChartView, memoryProcesses)] {
            let item = NSMenuItem(title: chart.title, action: nil, keyEquivalent: "")
            item.view = chart
            menu.addItem(item)
            menu.addItem(processes.item)
        }

        let networkItem = NSMenuItem(title: "Network", action: nil, keyEquivalent: "")
        networkItem.view = networkChartView
        menu.addItem(networkItem)
        menu.addItem(networkProcesses.item)

        menu.addItem(.separator())
        menu.addItem(keepAwakeMenu.item)
        keepAwakeController.onChange = { [weak self] in
            guard let self else { return }
            self.keepAwakeMenu.refresh()
            self.renderStatusBar()
        }

        let detailsMenu = NSMenu(title: "Details")
        detailsMenu.autoenablesItems = false
        let detailsItem = NSMenuItem()
        detailsItem.view = detailsView
        detailsMenu.addItem(detailsItem)
        menu.addItem(Self.section("Details", subtitle: "Network, power, storage & Codex", symbol: "slider.horizontal.3", menu: detailsMenu))

        let sharing = NSMenuItem(title: "Starting iPhone sharing…", action: nil, keyEquivalent: "")
        sharing.isEnabled = false
        sharingMenu.addItem(sharing)
        sharingItem = sharing
        let phone = Self.section("iPhone", subtitle: "Starting sharing…", symbol: "iphone", menu: sharingMenu)
        menu.addItem(phone)
        sharingSection = phone
        statsServer.onStatusChange = { [weak self] text in
            self?.sharingItem?.title = text
            self?.updateSharingSummary()
        }
        let settings = NSMenu(title: "Settings")

        if #available(macOS 13.0, *) {
            let enabled = SMAppService.mainApp.status == .enabled
            let launchItem = NSMenuItem(
                title: "Launch at Login",
                action: #selector(toggleLaunchAtLogin(_:)),
                keyEquivalent: ""
            )
            launchItem.target = self
            launchItem.state = enabled ? .on : .off
            settings.addItem(launchItem)
            launchAtLoginItem = launchItem
        }
        settings.addItem(appUpdater.checkItem)
        settings.addItem(appUpdater.automaticItem)
        settings.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About MyStat", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        settings.addItem(aboutItem)
        let quitItem = NSMenuItem(
            title: "Quit MyStat",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        settings.addItem(quitItem)
        menu.addItem(Self.section("Settings", subtitle: "Login, updates & app controls", symbol: "gearshape", menu: settings))
        menu.delegate = self
        // AppKit owns menu tracking, cascading submenus, keyboard navigation,
        // dismissal, and the system's current menu material.
        statusItem.menu = menu
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
        RunLoop.main.add(t, forMode: .eventTracking)
        self.timer = t
    }

    private var lastMemorySnapshot = MemorySnapshot(usedBytes: 0, totalBytes: 0)

    @objc private func showAbout(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "MyStat",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development",
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—",
            .credits: NSAttributedString(string: "Live system readings and process rankings for your desk.\nUpdates: github.com/Cydiater/MyStat")
        ])
    }

    private static func section(_ title: String, subtitle: String, symbol: String, menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        item.toolTip = subtitle
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
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
        networkChartView.windowMinutes = dropdownMinutes
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
        networkProcessMonitor.refresh()
        history.record(cpu: cpu, memory: mem.percent, network: network, power: power)
        lastMemorySnapshot = mem
        statsServer.update(
            samples: history.samples, usedBytes: mem.usedBytes, totalBytes: mem.totalBytes,
            interval: pollInterval, system: system, tokens: tokenMonitor.latest, processes: processMonitor.latest,
            networkApps: networkProcessMonitor.latest?.sharedSnapshot
        )
        detailsView.update(network: network, power: power, system: system, tokens: tokenMonitor.latest)
        cpuProcesses.update(processMonitor.latest)
        memoryProcesses.update(processMonitor.latest)
        networkProcesses.update(networkProcessMonitor.latest)
        updateDeviceMenu()
        renderViews()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        statsServer.stop()
        networkProcessMonitor.stop()
        keepAwakeController.stop()
    }

    private func updateDeviceMenu() {
        let devices = statsServer.activeDevices
        updateSharingSummary()
        guard devices != lastKnownDevices else { return }
        lastKnownDevices = devices

        let menu = sharingMenu

        menu.items.filter { $0.tag >= deviceMenuTag }.forEach { menu.removeItem($0) }

        if devices.isEmpty {
            let empty = NSMenuItem(title: "No devices connected", action: nil, keyEquivalent: "")
            empty.tag = deviceMenuTag
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        let insertAt = menu.items.count
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

    private func updateSharingSummary() {
        let count = statsServer.activeDevices.count
        let status = sharingItem?.title ?? "Starting sharing…"
        if status == "iPhone sharing available" {
            sharingSection?.toolTip = count == 0 ? "Ready to connect" : "\(count) \(count == 1 ? "device" : "devices") connected"
        } else {
            sharingSection?.toolTip = status
        }
    }

    private func renderStatusBar() {
        let barSamples = max(2, Int((statusBarMinutes * 60.0 / pollInterval).rounded()))
        let barCpu = Array(history.cpu.suffix(barSamples))
        let barMem = Array(history.memory.suffix(barSamples))
        let barNetwork = networkHistory(capacity: barSamples)
        let awake = keepAwakeController.status
        if let button = statusItem.button {
            button.image = StatusBarRenderer.render(
                cpu: barCpu, memory: barMem, capacity: barSamples, keepAwake: awake, network: barNetwork
            )
            let rates = "Download \(MetricFormat.rate(barNetwork.download.last ?? nil)), upload \(MetricFormat.rate(barNetwork.upload.last ?? nil))"
            button.toolTip = "MyStat — \(rates) — \(awake.accessibilityDescription)"
            button.setAccessibilityLabel("MyStat")
            button.setAccessibilityValue("CPU, memory and network. \(rates). \(awake.accessibilityDescription)")
        }
    }

    private func renderViews() {
        renderStatusBar()
        let mem = lastMemorySnapshot
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
        networkChartView.update(networkHistory(capacity: dropSamples))
    }

    private func networkHistory(capacity: Int) -> NetworkChartData {
        let samples = history.samples.suffix(capacity)
        return NetworkChartData(download: samples.map { $0.network?.downloadBytesPerSecond },
                                upload: samples.map { $0.network?.uploadBytesPerSecond }, capacity: capacity)
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
