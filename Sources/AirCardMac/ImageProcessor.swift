import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ImageProcessor {
    static let targetWidth = 1_536
    static let targetHeight = 969
    static let target2xWidth = 1_024
    static let target2xHeight = 646

    static func prepare(url: URL) throws -> PreparedArtwork {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AirCardError.processFailed("No pude leer la imagen seleccionada.")
        }

        let sourceWidth = image.width
        let sourceHeight = image.height
        let resized = try render(image, width: targetWidth, height: targetHeight)
        let resized2x = try render(image, width: target2xWidth, height: target2xHeight)

        let png = try encodePNG(resized)
        let png2x = try encodePNG(resized2x)
        let pdf = try encodePDF(resized)
        return PreparedArtwork(
            png: png,
            png2x: png2x,
            pdf: pdf,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight
        )
    }

    private static func render(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
        let scale = min(
            CGFloat(width) / CGFloat(image.width),
            CGFloat(height) / CGFloat(image.height)
        )
        let fittedSize = CGSize(
            width: CGFloat(image.width) * scale,
            height: CGFloat(image.height) * scale
        )
        let fittedRect = CGRect(
            x: (CGFloat(width) - fittedSize.width) / 2,
            y: (CGFloat(height) - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )

        guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw AirCardError.processFailed("No pude preparar el lienzo de la imagen.")
        }

        context.interpolationQuality = .high
        // Cover the canvas first so there are no empty bands. The fitted layer
        // below keeps every source pixel, including borders, at its proportions.
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: fittedRect)
        guard let rendered = context.makeImage() else {
            throw AirCardError.processFailed("No pude redimensionar la imagen.")
        }
        return rendered
    }

    private static func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw AirCardError.processFailed("No pude crear el PNG de la tarjeta.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AirCardError.processFailed("No pude finalizar el PNG de la tarjeta.")
        }
        return data as Data
    }

    private static func encodePDF(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw AirCardError.processFailed("No pude crear el PDF de la tarjeta.")
        }
        context.beginPDFPage(nil)
        context.draw(image, in: mediaBox)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
