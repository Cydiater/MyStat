import Cocoa

/// Position outside the dashboard, never over its charts or actions. Coordinates
/// are in screen space, including screens left of the primary display.
enum ProcessPanelPlacement {
    static func frame(parent: NSRect, chart: NSRect, screen: NSRect, size: NSSize) -> NSRect? {
        let gap: CGFloat = 8
        let right = screen.maxX - parent.maxX - gap
        let left = parent.minX - screen.minX - gap
        let useRight = right >= size.width || right >= left
        let available = useRight ? right : left
        guard available >= 220, screen.height >= size.height else { return nil }
        let width = min(size.width, available)
        let x = useRight ? parent.maxX + gap : parent.minX - gap - width
        let y = max(screen.minY, min(chart.maxY - size.height, screen.maxY - size.height))
        return NSRect(x: x, y: y, width: width, height: size.height)
    }
}
