import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    fatalError("usage: render_icon_fallback.swift <output-directory>")
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let size = 1024
let rgb = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: rgb,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("could not create icon context")
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: rgb, components: [red, green, blue, alpha])!
}

func rounded(_ rect: CGRect, radius: CGFloat) {
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
}

let background = CGGradient(
    colorsSpace: rgb,
    colors: [color(0.02, 0.04, 0.13), color(0.03, 0.18, 0.60), color(0.12, 0.03, 0.32)] as CFArray,
    locations: [0, 0.56, 1]
)!
context.drawLinearGradient(
    background,
    start: CGPoint(x: 120, y: 930),
    end: CGPoint(x: 900, y: 80),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

context.saveGState()
rounded(CGRect(x: 76, y: 76, width: 872, height: 872), radius: 226)
context.clip()
let capsule = CGGradient(
    colorsSpace: rgb,
    colors: [color(0.03, 0.32, 0.88, 0.94), color(0.04, 0.16, 0.55, 0.92), color(0.20, 0.08, 0.50, 0.94)] as CFArray,
    locations: [0, 0.52, 1]
)!
context.drawLinearGradient(
    capsule,
    start: CGPoint(x: 110, y: 930),
    end: CGPoint(x: 920, y: 90),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)
context.restoreGState()

context.saveGState()
rounded(CGRect(x: 92, y: 92, width: 840, height: 840), radius: 210)
context.setStrokeColor(color(0.33, 0.91, 1.0, 0.82))
context.setLineWidth(22)
context.strokePath()
context.restoreGState()

context.setStrokeColor(color(0.86, 0.99, 1.0, 0.58))
context.setLineWidth(18)
context.setLineCap(.round)
context.move(to: CGPoint(x: 182, y: 778))
context.addLine(to: CGPoint(x: 402, y: 900))
context.strokePath()

rounded(CGRect(x: 232, y: 326, width: 560, height: 372), radius: 102)
context.setFillColor(color(0.96, 0.98, 1.0))
context.fillPath()

context.setFillColor(color(0.28, 0.50, 0.95))
context.fill(CGRect(x: 232, y: 444, width: 560, height: 78))

rounded(CGRect(x: 632, y: 602, width: 108, height: 44), radius: 22)
context.setFillColor(color(0.28, 0.50, 0.95))
context.fillPath()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        output.appendingPathComponent("icon_512x512@2x.png") as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      ) else {
    fatalError("could not create icon PNG")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("could not finalize icon PNG")
}
