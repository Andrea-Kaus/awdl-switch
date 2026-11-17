import CoreGraphics

enum CircuitSwitch {
    static func draw(in context: CGContext, rect: CGRect, isOpen: Bool, color: CGColor) {
        let scale = min(rect.width, rect.height) / 24
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.midX - 12 * scale, y: rect.midY + 12 * scale)
        context.scaleBy(x: scale, y: -scale)
        context.setStrokeColor(color)
        context.setLineWidth(1.85)
        context.setLineCap(.round)

        let contactY: CGFloat = isOpen ? 14.5 : 13
        let radius: CGFloat = 2.05
        for x: CGFloat in [4.5, 19.5] {
            context.addEllipse(in: CGRect(x: x - radius, y: contactY - radius, width: 2 * radius, height: 2 * radius))
        }
        if isOpen {
            context.move(to: CGPoint(x: 6.3, y: 13.55))
            context.addLine(to: CGPoint(x: 15.6, y: 7.45))
        } else {
            context.move(to: CGPoint(x: 6.55, y: 13))
            context.addLine(to: CGPoint(x: 17.45, y: 13))
        }
        context.strokePath()
    }
}
