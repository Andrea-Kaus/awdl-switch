import AppKit

@MainActor
enum StatusIcon {
    static let itemWidth: CGFloat = 28
    static let indicatorDiameter: CGFloat = 5
    static let indicatorOffset: CGFloat = 9
    static let on = makeSwitch(isOpen: false)
    static let suppressed = makeSwitch(isOpen: true)
    static let unknown = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)

    private static func makeSwitch(isOpen: Bool) -> NSImage {
        let size = NSSize(width: isOpen ? 24 : 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let glyph = CGRect(x: rect.minX, y: rect.minY, width: rect.height, height: rect.height)
            CircuitSwitch.draw(in: context, rect: glyph, isOpen: isOpen, color: NSColor.black.cgColor)
            return true
        }
        image.isTemplate = true
        return image
    }
}

final class SuppressionIndicator: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let green = dark
            ? NSColor(srgbRed: 0.35, green: 0.91, blue: 0.55, alpha: 1)
            : NSColor(srgbRed: 0.07, green: 0.51, blue: 0.25, alpha: 1)
        green.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
