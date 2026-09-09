import UIKit

/// Keeps the display awake only during an active, visible desk display session.
/// Restores the previous auto-lock setting when dismissed or backgrounded.
@MainActor
final class KeepAlive {
    private var previousIdleSetting: Bool?

    func start() {
        guard previousIdleSetting == nil else { return }
        previousIdleSetting = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stop() {
        guard let previousIdleSetting else { return }
        UIApplication.shared.isIdleTimerDisabled = previousIdleSetting
        self.previousIdleSetting = nil
    }
}
