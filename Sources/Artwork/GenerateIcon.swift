import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main
struct GenerateIcon {
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    static func main() {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let suffix = scale == 2 ? "@2x" : ""
                let url = directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
                let image = makeIcon(pixels: points * scale)
                guard let png = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                    fatalError("Couldn’t create \(url.lastPathComponent)")
                }
                CGImageDestinationAddImage(png, image, nil)
                guard CGImageDestinationFinalize(png) else { fatalError("Couldn’t write \(url.lastPathComponent)") }
            }
        }
    }

    private static func makeIcon(pixels: Int) -> CGImage {
        let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let scale = CGFloat(pixels) / 1024
        context.scaleBy(x: scale, y: scale)

        let tile = CGRect(x: 100, y: 106, width: 824, height: 824)
        let shape = CGPath(roundedRect: tile, cornerWidth: 196, cornerHeight: 196, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -26 * scale), blur: 42 * scale, color: color(0x122A56, alpha: 0.40))
        context.setFillColor(color(0x15294D))
        context.addPath(shape)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        let base = CGGradient(colorsSpace: space, colors: [color(0x27467D), color(0x12243F)] as CFArray, locations: nil)!
        context.drawLinearGradient(base, start: CGPoint(x: 140, y: 880), end: CGPoint(x: 835, y: 170),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        let light = CGGradient(colorsSpace: space, colors: [color(0x557DBF), color(0x476CA9, alpha: 0)] as CFArray, locations: nil)!
        let origin = CGPoint(x: 281, y: 950)
        context.drawRadialGradient(light, startCenter: origin, startRadius: 0, endCenter: origin, endRadius: 610, options: [])
        context.addPath(shape)
        context.setStrokeColor(color(0xA1B5DE, alpha: 0.50))
        context.setLineWidth(12)
        context.strokePath()
        context.restoreGState()

        let switchRect = CGRect(x: tile.midX - 243, y: tile.midY - 243, width: 486, height: 486)
        CircuitSwitch.draw(in: context, rect: switchRect, isOpen: true, color: color(0xFFFFFF))
        return context.makeImage()!
    }

    private static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        func component(_ shift: UInt32) -> CGFloat {
            CGFloat((hex >> shift) & 0xFF) / 255
        }
        return CGColor(colorSpace: space, components: [component(16), component(8), component(0), alpha])!
    }
}
