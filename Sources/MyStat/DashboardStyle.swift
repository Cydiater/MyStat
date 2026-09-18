import Cocoa

/// Shared geometry and an opaque dashboard palette, with light/dark variants.
enum DashboardStyle {
    static let width: CGFloat = 360
    static let chartHeight: CGFloat = 124
    static let detailsHeight: CGFloat = 272
    static let background = color(dark: 0x111217, light: 0xF4F5F7)
    static let panel = color(dark: 0x181B1F, light: 0xFFFFFF)
    static let border = color(dark: 0x30343B, light: 0xDDE1E6)
    static let grid = color(dark: 0x343941, light: 0xE2E5E9)
    static let text = color(dark: 0xE8EBEF, light: 0x20252B)
    static let muted = color(dark: 0xA0A8B4, light: 0x626D7A)
    static let orange = color(dark: 0xFF9930, light: 0xA35100)
    static let blue = color(dark: 0x5794F2, light: 0x2867C7)
    static let green = color(dark: 0x73BF69, light: 0x36782B)

    private static func color(dark: UInt32, light: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }

    static func card(_ rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        panel.setFill(); path.fill()
        border.setStroke(); path.lineWidth = 1; path.stroke()
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
    override func draw(_ dirtyRect: NSRect) {
        DashboardStyle.background.setFill()
        bounds.fill()
    }
}
