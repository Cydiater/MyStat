import Cocoa

/// Semantic colors let AppKit adapt the dashboard to its material and appearance.
enum DashboardStyle {
    static let width: CGFloat = 360
    static let chartHeight: CGFloat = 124
    static let detailsHeight: CGFloat = 272
    static let background = NSColor.windowBackgroundColor
    static let panel = NSColor.controlBackgroundColor
    static let grid = NSColor.separatorColor.withAlphaComponent(0.35)
    static let text = NSColor.labelColor
    static let muted = NSColor.secondaryLabelColor
    static let orange = NSColor.systemOrange
    static let blue = NSColor.systemBlue
    static let green = NSColor.systemGreen

    /// Charts paint colored data without vibrancy blending. Resolve semantic
    /// colors in Aqua so vibrant appearances don't supply blend-only grays.
    static func drawContent(appearance: NSAppearance, _ drawing: () -> Void) {
        let name = appearance.bestMatch(from: [.darkAqua, .aqua]) ?? .aqua
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance(drawing)
    }

    static func card(_ rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        panel.withAlphaComponent(opaque ? 1 : 0.3).setFill()
        path.fill()
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    static func label(_ value: String, in rect: NSRect, size: CGFloat = 11,
                      color: NSColor = text, weight: NSFont.Weight = .regular,
                      alignment: NSTextAlignment = .left, mono: Bool = false) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        (value as NSString).draw(in: rect, withAttributes: [
            .font: mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color, .paragraphStyle: paragraph
        ])
    }
}
