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
        let sourceRatio = CGFloat(sourceWidth) / CGFloat(sourceHeight)
        let targetRatio = CGFloat(targetWidth) / CGFloat(targetHeight)

        let crop: CGRect
        if sourceRatio > targetRatio {
            let cropWidth = CGFloat(sourceHeight) * targetRatio
            crop = CGRect(
                x: (CGFloat(sourceWidth) - cropWidth) / 2,
                y: 0,
                width: cropWidth,
                height: CGFloat(sourceHeight)
            )
        } else {
            let cropHeight = CGFloat(sourceWidth) / targetRatio
            crop = CGRect(
                x: 0,
                y: (CGFloat(sourceHeight) - cropHeight) / 2,
                width: CGFloat(sourceWidth),
                height: cropHeight
            )
        }

        guard let cropped = image.cropping(to: crop.integral),
              let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: targetWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw AirCardError.processFailed("No pude preparar el recorte de la imagen.")
        }

        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
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
