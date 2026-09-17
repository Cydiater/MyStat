import Cocoa
import Sparkle

/// The standard Sparkle UI handles release notes, downloads, validation and relaunch.
final class AppUpdater: NSObject, NSMenuItemValidation {
    private var controller: SPUStandardUpdaterController?
    private var startupError: String?
    let checkItem = NSMenuItem(title: "Check for Updates…", action: nil, keyEquivalent: "")
    let automaticItem = NSMenuItem(title: "Automatically Check for Updates", action: nil, keyEquivalent: "")

    override init() {
        super.init()
        checkItem.target = self
        checkItem.action = #selector(checkForUpdates(_:))
        automaticItem.target = self
        automaticItem.action = #selector(toggleAutomaticChecks(_:))
    }

    func start() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            startupError = "Open the MyStat app bundle to use updates. Command-line development builds cannot update themselves."
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        do {
            try controller.updater.start()
            self.controller = controller
            automaticItem.state = controller.updater.automaticallyChecksForUpdates ? .on : .off
        } catch {
            startupError = error.localizedDescription
            NSLog("MyStat updater could not start: %@", error.localizedDescription)
        }
    }

    @objc private func checkForUpdates(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        if let controller {
            controller.checkForUpdates(sender)
        } else {
            let alert = NSAlert()
            alert.messageText = "Updates are unavailable"
            alert.informativeText = startupError ?? "The updater is still starting. Please try again."
            alert.runModal()
        }
    }

    @objc private func toggleAutomaticChecks(_ sender: NSMenuItem) {
        guard let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates.toggle()
        sender.state = updater.automaticallyChecksForUpdates ? .on : .off
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem === automaticItem {
            menuItem.state = controller?.updater.automaticallyChecksForUpdates == true ? .on : .off
            return controller != nil
        }
        return controller?.updater.canCheckForUpdates ?? (startupError != nil)
    }
}
