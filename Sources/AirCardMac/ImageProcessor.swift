import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ImageProcessor {
    static let targetWidth = 1_536
    static let targetHeight = 969

    static func prepare(url: URL) throws -> PreparedArtwork {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AirCardError.processFailed("No pude leer la imagen seleccionada.")
        }

        let sourceWidth = image.width
        let sourceHeight = image.height
        let scale = min(
            CGFloat(targetWidth) / CGFloat(sourceWidth),
            CGFloat(targetHeight) / CGFloat(sourceHeight)
        )
        let fittedSize = CGSize(
            width: CGFloat(sourceWidth) * scale,
            height: CGFloat(sourceHeight) * scale
        )
        let fittedRect = CGRect(
            x: (CGFloat(targetWidth) - fittedSize.width) / 2,
            y: (CGFloat(targetHeight) - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )

        guard let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: targetWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw AirCardError.processFailed("No pude preparar el lienzo de la imagen.")
        }

        context.interpolationQuality = .high
        // First cover the canvas so there are no empty bands. The full-canvas
        // layer is only a backdrop; the fitted layer below keeps every source
        // pixel, including borders, at its original proportions.
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        context.draw(image, in: fittedRect)
        guard let resized = context.makeImage() else {
            throw AirCardError.processFailed("No pude redimensionar la imagen.")
        }

        let png = try encodePNG(resized)
        let pdf = try encodePDF(resized)
        return PreparedArtwork(
            png: png,
            pdf: pdf,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight
        )
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
