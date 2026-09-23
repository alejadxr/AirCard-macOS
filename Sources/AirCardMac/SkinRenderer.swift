import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Metal
import UniformTypeIdentifiers

enum SkinRenderer {
    private static let context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()
    private static let outputSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    static func render(_ document: SkinDocument, size: CGSize, tilt: Double? = nil) throws -> CGImage {
        let image = try composite(document, size: size, tilt: tilt ?? document.tilt)
        guard let cgImage = context.createCGImage(
            image,
            from: CGRect(origin: .zero, size: size),
            format: .RGBA8,
            colorSpace: outputSpace
        ) else {
            throw AirCardError.processFailed(AirCardL10n.text("No pude renderizar el diseño."))
        }
        return cgImage
    }

    static func prepare(_ document: SkinDocument) throws -> PreparedArtwork {
        let full = try render(document, size: SkinDocument.canvasSize)
        let half = try render(document, size: SkinDocument.canvas2xSize)
        return PreparedArtwork(
            png: try encodePNG(full),
            png2x: try encodePNG(half),
            pdf: try encodePDF(full),
            sourceWidth: full.width,
            sourceHeight: full.height
        )
    }

    static func thumbnailPNG(_ document: SkinDocument, width: CGFloat = 480) throws -> Data {
        let size = CGSize(width: width, height: (width * SkinDocument.canvasSize.height / SkinDocument.canvasSize.width).rounded())
        return try encodePNG(render(document, size: size))
    }

    private static func composite(_ document: SkinDocument, size: CGSize, tilt: Double) throws -> CIImage {
        let extent = CGRect(origin: .zero, size: size)
        var result = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
        for layer in document.layers where layer.isVisible && layer.opacity > 0 {
            guard var image = try layerImage(layer, document: document, size: size, tilt: tilt) else { continue }
            image = image.cropped(to: extent)
            if layer.opacity < 1 {
                image = image.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: CGFloat(layer.opacity), y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: CGFloat(layer.opacity), z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(layer.opacity), w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(layer.opacity))
                ])
            }
            result = blend(image, over: result, mode: layer.blend).cropped(to: extent)
        }
        return applyAdjustments(document.adjustments, to: result, extent: extent)
    }

    private static func blend(_ top: CIImage, over bottom: CIImage, mode: SkinBlendMode) -> CIImage {
        guard let filter = CIFilter(name: mode.filterName) else { return top.composited(over: bottom) }
        filter.setValue(top, forKey: kCIInputImageKey)
        filter.setValue(bottom, forKey: kCIInputBackgroundImageKey)
        return filter.outputImage ?? top.composited(over: bottom)
    }

    private static func layerImage(
        _ layer: SkinLayer,
        document: SkinDocument,
        size: CGSize,
        tilt: Double
    ) throws -> CIImage? {
        let scale = Float(size.width / SkinDocument.canvasSize.width)
        let tiltValue = Float(tilt)
        switch layer.content {
        case .solid(let color):
            return CIImage(color: ciColor(color)).cropped(to: CGRect(origin: .zero, size: size))
        case .image(let style):
            guard let data = document.assets[style.assetID] else { return nil }
            return imageLayer(data: data, style: style, size: size)
        case .linearGradient(let style):
            return try SkinGeneratorKernel.image(
                kind: .linear, canvas: size,
                params: pad([Float(style.angle), Float(style.stops.count)]),
                colors: stopFloats(style.stops)
            )
        case .radialGradient(let style):
            return try SkinGeneratorKernel.image(
                kind: .radial, canvas: size,
                params: pad([Float(style.centerX), Float(style.centerY), Float(style.radius), Float(style.stops.count)]),
                colors: stopFloats(style.stops)
            )
        case .conicGradient(let style):
            return try SkinGeneratorKernel.image(
                kind: .conic, canvas: size,
                params: pad([Float(style.centerX), Float(style.centerY), Float(style.angle), Float(style.stops.count)]),
                colors: stopFloats(style.stops)
            )
        case .meshGradient(let style):
            let colors = (style.colors + Array(repeating: SkinColor.black, count: max(0, 9 - style.colors.count)))
                .prefix(9).flatMap(\.floats)
            return try SkinGeneratorKernel.image(
                kind: .mesh, canvas: size,
                params: pad([Float(style.warp), Float(style.seed)]),
                colors: Array(colors)
            )
        case .holographic(let style):
            return try SkinGeneratorKernel.image(
                kind: .holographic, canvas: size,
                params: pad([
                    Float(style.scale), Float(style.angle), Float(style.turbulence),
                    Float(style.sparkle), Float(style.seed)
                ], tilt: tiltValue),
                colors: []
            )
        case .brushedMetal(let style):
            return try SkinGeneratorKernel.image(
                kind: .brushedMetal, canvas: size,
                params: pad([Float(style.angle), Float(style.grain), Float(style.sheen)], tilt: tiltValue),
                colors: style.tint.floats
            )
        case .sheen(let style):
            return try SkinGeneratorKernel.image(
                kind: .sheen, canvas: size,
                params: pad([Float(style.angle), Float(style.position), Float(style.width)], tilt: tiltValue),
                colors: style.color.floats
            )
        case .grain(let style):
            return try SkinGeneratorKernel.image(
                kind: .grain, canvas: size,
                params: pad([Float(style.size) * scale.squareRoot(), style.monochrome ? 1 : 0, Float(style.seed)]),
                colors: []
            )
        case .pattern(let style):
            return try SkinGeneratorKernel.image(
                kind: .pattern, canvas: size,
                params: pad([
                    Float(style.style.rawValue), Float(style.spacing), Float(style.thickness), Float(style.angle)
                ]),
                colors: style.color.floats
            )
        case .text(let style):
            return textLayer(style, size: size)
        }
    }

    private static func imageLayer(data: Data, style: ImageLayerStyle, size: CGSize) -> CIImage? {
        guard let source = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        let image = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY))
        let extent = CGRect(origin: .zero, size: size)
        let width = image.extent.width
        let height = image.extent.height
        guard width > 0, height > 0 else { return nil }

        func placed(_ mode: ImageFit, userScale: Double, offsetX: Double, offsetY: Double) -> CIImage {
            let sx = size.width / width
            let sy = size.height / height
            var transform: CGAffineTransform
            switch mode {
            case .stretch:
                transform = CGAffineTransform(scaleX: sx, y: sy)
            case .fill:
                let s = max(sx, sy) * userScale
                transform = CGAffineTransform(scaleX: s, y: s)
            case .fit, .fitBlurred:
                let s = min(sx, sy) * userScale
                transform = CGAffineTransform(scaleX: s, y: s)
            }
            let scaled = image.transformed(by: transform)
            let dx = (size.width - scaled.extent.width) / 2 + offsetX * size.width
            let dy = (size.height - scaled.extent.height) / 2 - offsetY * size.height
            return scaled.transformed(by: CGAffineTransform(translationX: dx - scaled.extent.minX, y: dy - scaled.extent.minY))
        }

        var output = placed(style.fit, userScale: style.scale, offsetX: style.offsetX, offsetY: style.offsetY)
        if style.fit == .fitBlurred {
            let backdrop = placed(.fill, userScale: 1.1, offsetX: 0, offsetY: 0)
                .clampedToExtent()
                .applyingGaussianBlur(sigma: 40 * size.width / SkinDocument.canvasSize.width)
                .cropped(to: extent)
            output = output.composited(over: backdrop)
        }
        if style.blur > 0 {
            output = output.clampedToExtent()
                .applyingGaussianBlur(sigma: style.blur * size.width / SkinDocument.canvasSize.width)
                .cropped(to: extent)
        }
        return output
    }

    private static func textLayer(_ style: TextLayerStyle, size: CGSize) -> CIImage? {
        guard !style.text.isEmpty else { return nil }
        let scale = size.width / SkinDocument.canvasSize.width
        let font = NSFont(name: style.fontName, size: style.size * scale)
            ?? NSFont.systemFont(ofSize: style.size * scale, weight: .semibold)
        let attributed = NSAttributedString(string: style.text, attributes: [
            .font: font,
            .foregroundColor: NSColor(
                srgbRed: style.color.red, green: style.color.green, blue: style.color.blue, alpha: style.color.alpha
            ),
            .kern: style.tracking * scale
        ])
        guard let generator = CIFilter(name: "CIAttributedTextImageGenerator") else { return nil }
        generator.setValue(attributed, forKey: "inputText")
        generator.setValue(1.0, forKey: "inputScaleFactor")
        guard let text = generator.outputImage else { return nil }
        let x = style.x * size.width
        let y = (1 - style.y) * size.height - text.extent.height
        return text.transformed(by: CGAffineTransform(translationX: x - text.extent.minX, y: y - text.extent.minY))
    }

    private static func applyAdjustments(_ adjustments: SkinAdjustments, to input: CIImage, extent: CGRect) -> CIImage {
        guard !adjustments.isIdentity else { return input }
        var image = input
        let scale = extent.width / SkinDocument.canvasSize.width
        if adjustments.brightness != 0 || adjustments.contrast != 1 || adjustments.saturation != 1 {
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: adjustments.brightness,
                kCIInputContrastKey: adjustments.contrast,
                kCIInputSaturationKey: adjustments.saturation
            ])
        }
        if adjustments.hue != 0 {
            image = image.applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: adjustments.hue * .pi / 180])
        }
        if adjustments.blur > 0 {
            image = image.clampedToExtent().applyingGaussianBlur(sigma: adjustments.blur * scale).cropped(to: extent)
        }
        if adjustments.bloom > 0 {
            image = image.clampedToExtent().applyingFilter("CIBloom", parameters: [
                kCIInputRadiusKey: 18 * scale,
                kCIInputIntensityKey: adjustments.bloom
            ]).cropped(to: extent)
        }
        if adjustments.sharpen > 0 {
            image = image.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: adjustments.sharpen])
        }
        if adjustments.vignette > 0 {
            image = image.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: adjustments.vignette * 2,
                kCIInputRadiusKey: 1.6
            ])
        }
        return image.cropped(to: extent)
    }

    private static func pad(_ values: [Float], tilt: Float = 0.5) -> [Float] {
        var params = values + Array(repeating: 0, count: max(0, 13 - values.count))
        params = Array(params.prefix(13))
        params.append(tilt)
        return params
    }

    private static func stopFloats(_ stops: [GradientStop]) -> [Float] {
        stops.sorted { $0.location < $1.location }.prefix(12).flatMap { stop in
            stop.color.floats + [Float(stop.location)]
        }
    }

    private static func ciColor(_ color: SkinColor) -> CIColor {
        CIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha, colorSpace: outputSpace)
            ?? CIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    static func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw AirCardError.processFailed(AirCardL10n.text("No pude crear el PNG de la tarjeta."))
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AirCardError.processFailed(AirCardL10n.text("No pude finalizar el PNG de la tarjeta."))
        }
        return data as Data
    }

    private static func encodePDF(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw AirCardError.processFailed(AirCardL10n.text("No pude crear el PDF de la tarjeta."))
        }
        context.beginPDFPage(nil)
        context.draw(image, in: mediaBox)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
