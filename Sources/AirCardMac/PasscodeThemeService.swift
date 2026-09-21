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

        await progress("Recoloreando las teclas a (Self.hex(color))…")
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
        try assets.map { asset in
            if !asset.isImage {
                return (asset.name, asset.data)
            }
            let outputName = imageNameAsPNG(asset.name)
            return (outputName, try recolor(asset.data, tint: tint))
        }
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
        context.setBlendMode(.sourceIn)
        context.setFillColor(red: tint.red, green: tint.green, blue: tint.blue, alpha: 1)
        context.fill(rect)

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
