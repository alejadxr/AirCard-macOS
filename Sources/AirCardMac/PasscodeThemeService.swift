import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PasscodeThemeService: Sendable {
    private static let telephonyVersions = ["TelephonyUI-10", "TelephonyUI-9", "TelephonyUI-8"]
    private static let imageExtensions = Set(["png", "jpg", "jpeg"])

    func load(url: URL) async throws -> PasscodeTheme {
        let work = try NativeTools.temporaryDirectory(prefix: "aircard-passthm")
        defer { try? FileManager.default.removeItem(at: work) }

        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-q", url.path, "-d", work.path],
            timeout: .seconds(30)
        )
        guard result.status == 0 else {
            throw AirCardError.processFailed("No pude abrir el paquete .passthm: (result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        let files = (FileManager.default.enumerator(
            at: work,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey]
        )?.compactMap { $0 as? URL } ?? []).filter { url in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { return false }
            let lower = url.pathExtension.lowercased()
            let leaf = url.lastPathComponent
            let isMarker = leaf == "_big" || leaf == "_small"
            return !leaf.hasPrefix(".") &&
                !url.pathComponents.contains("__MACOSX") &&
                (Self.imageExtensions.contains(lower) || isMarker)
        }

        guard !files.isEmpty else {
            throw AirCardError.processFailed("El paquete .passthm no contiene imágenes de teclado.")
        }

        var byVersion: [String: [String: PasscodeAsset]] = [:]
        var unversioned: [String: PasscodeAsset] = [:]
        for file in files {
            let name = file.lastPathComponent
            guard let data = try? Data(contentsOf: file) else { continue }
            let asset = PasscodeAsset(
                name: normalizedLeafName(name),
                data: data,
                isImage: Self.imageExtensions.contains(file.pathExtension.lowercased())
            )
            if let version = Self.telephonyVersions.first(where: { file.pathComponents.contains($0) }) {
                byVersion[version, default: [:]][asset.name] = asset
            } else {
                unversioned[asset.name] = asset
            }
        }

        guard !byVersion.isEmpty || !unversioned.isEmpty else {
            throw AirCardError.processFailed("No pude leer los assets del paquete .passthm.")
        }

        let detected = Self.telephonyVersions.first(where: { byVersion[$0]?.isEmpty == false }) ?? "TelephonyUI-10"
        return PasscodeTheme(
            name: url.deletingPathExtension().lastPathComponent,
            detectedVersion: detected,
            assetsByVersion: byVersion.mapValues { $0.values.sorted { $0.name < $1.name } },
            unversionedAssets: unversioned.values.sorted { $0.name < $1.name }
        )
    }

    func preview(theme: PasscodeTheme, color: PasscodeTint, targetVersion: String) throws -> Data {
        guard let asset = theme.assets(for: targetVersion).first(where: { $0.isImage }) else {
            throw AirCardError.processFailed("No hay una tecla de imagen para mostrar.")
        }
        return try Self.recolor(asset.data, tint: color)
    }

    func flash(
        theme: PasscodeTheme,
        device: DeviceInfo,
        color: PasscodeTint,
        targetVersion: String,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> PasscodeFlashResult {
        try Task.checkCancellation()
        let selectedAssets = theme.assets(for: targetVersion)
        guard !selectedAssets.isEmpty else {
            throw AirCardError.processFailed("El tema no tiene assets para (targetVersion).")
        }

        await progress("Recoloreando las teclas a \(Self.hex(color)) y generando variantes --white/--black…")
        let files = try await Task.detached(priority: .userInitiated) {
            try Self.recoloredFiles(selectedAssets, tint: color)
        }.value

        guard !files.isEmpty else {
            throw AirCardError.processFailed("No encontré imágenes válidas para recolorear.")
        }

        let target = "/var/mobile/Library/Caches/\(targetVersion)"
        let writer = WalletSkinService()
        var written = 0
        let chunkSize = 512
        var start = 0
        while start < files.count {
            try Task.checkCancellation()
            let end = min(start + chunkSize, files.count)
            let chunk = Array(files[start..<end])
            await progress("Escribiendo teclas (end)/(files.count) en (targetVersion)…")
            guard try await writer.writeFiles(
                device: device,
                target: target,
                files: chunk,
                progress: progress
            ) else {
                throw AirCardError.processFailed("No se pudieron escribir las teclas en la caché de (targetVersion).")
            }
            written += chunk.count
            start = end
        }

        await progress("Color aplicado. Bloquea el iPhone para comprobar el teclado.")
        return PasscodeFlashResult(themeName: theme.name, targetVersion: targetVersion, assetCount: written)
    }

    private static func recoloredFiles(
        _ assets: [PasscodeAsset],
        tint: PasscodeTint
    ) throws -> [(String, Data)] {
        var output: [String: Data] = [:]
        for asset in assets {
            if !asset.isImage {
                output[asset.name] = asset.data
                continue
            }
            let outputName = imageNameAsPNG(asset.name)
            let tinted = try recolor(asset.data, tint: tint)
            output[outputName] = tinted

            // iOS TelephonyUI uses the suffix as part of the cache key. Keep
            // the original file and also emit both appearance variants so a
            // theme that only ships --white can be tested against --black.
            for variant in colorVariantNames(outputName) {
                output[variant] = tinted
            }
        }
        return output
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    private static func colorVariantNames(_ name: String) -> [String] {
        let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let lowerStem = stem.lowercased()
        let markers = ["--white-bold", "--black-bold", "--white", "--black"]
        var base = stem
        var bold = false

        for marker in markers where lowerStem.hasSuffix(marker) {
            let end = stem.index(stem.endIndex, offsetBy: -marker.count)
            base = String(stem[..<end])
            bold = marker.hasSuffix("-bold")
            break
        }

        let boldSuffix = bold ? "-bold" : ""
        return [
            "\(base)--white\(boldSuffix).png",
            "\(base)--black\(boldSuffix).png"
        ]
    }

    private static func recolor(_ data: Data, tint: PasscodeTint) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw AirCardError.processFailed("No pude leer una imagen de tecla.")
        }

        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.clear(rect)
        context.interpolationQuality = .high
        context.draw(image, in: rect)

        if containsTransparency(context: context, width: image.width, height: image.height) {
            // Transparent keypad assets are already masks for the glyph/artwork.
            // Tint the visible pixels while preserving their alpha edges.
            context.setBlendMode(.sourceIn)
            context.setFillColor(red: tint.red, green: tint.green, blue: tint.blue, alpha: 1)
            context.fill(rect)
        } else {
            // Some .passthm packages flatten the key onto an opaque background.
            // In those assets, recolor only the bright pixels (the --white
            // number/subtext) and leave the darker button artwork intact.
            recolorBrightGlyphs(
                context: context,
                width: image.width,
                height: image.height,
                tint: tint
            )
        }

        guard let output = context.makeImage() else {
            throw AirCardError.processFailed("No pude generar la imagen recoloreada.")
        }
        let destinationData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            destinationData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw AirCardError.processFailed("No pude crear el PNG recoloreado.")
        }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AirCardError.processFailed("No pude finalizar el PNG recoloreado.")
        }
        return destinationData as Data
    }

    private static func containsTransparency(context: CGContext, width: Int, height: Int) -> Bool {
        guard let data = context.data else { return true }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                if pixels[(y * context.bytesPerRow) + x * 4 + 3] < 250 {
                    return true
                }
            }
        }
        return false
    }

    private static func recolorBrightGlyphs(
        context: CGContext,
        width: Int,
        height: Int,
        tint: PasscodeTint
    ) {
        guard let data = context.data else { return }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let target = (red: tint.red * 255, green: tint.green * 255, blue: tint.blue * 255)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * context.bytesPerRow + x * 4
                let red = Double(pixels[offset])
                let green = Double(pixels[offset + 1])
                let blue = Double(pixels[offset + 2])
                let brightness = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
                let mask = min(1, max(0, (brightness - 0.55) / 0.35))
                guard mask > 0 else { continue }

                pixels[offset] = UInt8((red * (1 - mask) + target.red * mask).rounded())
                pixels[offset + 1] = UInt8((green * (1 - mask) + target.green * mask).rounded())
                pixels[offset + 2] = UInt8((blue * (1 - mask) + target.blue * mask).rounded())
            }
        }
    }

    private func normalizedLeafName(_ name: String) -> String {
        Self.imageNameAsPNG(name)
    }

    private static func imageNameAsPNG(_ name: String) -> String {
        let lower = name.lowercased()
        guard lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") else { return name }
        return String(name.dropLast(name.split(separator: ".").last?.count ?? 0)) + "png"
    }

    private static func hex(_ color: PasscodeTint) -> String {
        let values = [color.red, color.green, color.blue].map { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", values[0], values[1], values[2])
    }
}
