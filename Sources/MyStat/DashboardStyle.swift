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

    /// Floating process panels use the system's glass and its accessibility
    /// adaptations. The main dropdown already has an NSPopover material.
    static func floatingSurface(around content: NSView) -> NSView {
        let frame = NSRect(origin: .zero, size: content.frame.size)
        content.frame = frame
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.style = .regular
            glass.cornerRadius = 18
            glass.contentView = content
            return glass
        }
        let material = NSVisualEffectView(frame: frame)
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 14
        material.layer?.masksToBounds = true
        content.autoresizingMask = [.width, .height]
        material.addSubview(content)
        return material
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

final class DashboardCanvas: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        // Preserve the native popover backdrop instead of covering it with an
        // opaque rectangle. The system controls glass, blur, and contrast.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            DashboardStyle.background.setFill()
            bounds.fill()
        }
    }
}
