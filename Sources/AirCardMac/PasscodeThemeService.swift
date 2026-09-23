import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PasscodeThemeService: Sendable {
    private static let telephonyVersions = PasscodeCache.versions
    private static let imageExtensions = Set(["png", "jpg", "jpeg"])

    private static let subtextsEN: [String: String] = [
        "0": "+", "1": "", "2": "A B C", "3": "D E F", "4": "G H I",
        "5": "J K L", "6": "M N O", "7": "P Q R S", "8": "T U V", "9": "W X Y Z"
    ]
    private static let subtextsRU: [String: String] = [
        "0": "+", "1": "", "2": "А Б В Г", "3": "Д Е Ж З", "4": "И Й К Л",
        "5": "М Н О П", "6": "Р С Т У", "7": "Ф Х Ц Ч", "8": "Ш Щ Ъ Ы", "9": "Ь Э Ю Я"
    ]
    private static let subtextsUK: [String: String] = [
        "0": "+", "1": "", "2": "А Б В Г Ґ", "3": "Д Е Є Ж З", "4": "И І Ї Й",
        "5": "К Л М Н", "6": "О П Р С", "7": "Т У Ф Х", "8": "Ц Ч Ш Щ", "9": "Ь Ю Я"
    ]
    private static let universalPrefixes = [
        "en", "other", "ru", "uk", "ja", "es", "fr", "de", "it", "pt", "tr", "pl", "ko", "zh"
    ]

    func load(url: URL) async throws -> PasscodeTheme {
        let work = try NativeTools.temporaryDirectory(prefix: "aircard-passthm")
        defer { try? FileManager.default.removeItem(at: work) }

        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-q", url.path, "-d", work.path],
            timeout: .seconds(30)
        )
        guard result.status == 0 else {
            throw AirCardError.processFailed("No pude abrir el paquete .passthm: \(result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines))")
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

    func keyPreviews(theme: PasscodeTheme, color: PasscodeTint, targetVersion: String) throws -> [PasscodeKeyPreview] {
        var byKey: [String: PasscodeAsset] = [:]
        for asset in theme.assets(for: targetVersion) where asset.isImage {
            guard let key = Self.keypadKey(for: asset.name)?.digit, byKey[key] == nil else { continue }
            byKey[key] = asset
        }
        return try PasscodeKeyPreview.keypadOrder.compactMap { key in
            guard let asset = byKey[key] else { return nil }
            return PasscodeKeyPreview(key: key, png: try Self.recolor(asset.data, tint: color))
        }
    }

    func plannedFileNames(
        theme: PasscodeTheme,
        variant: PasscodeVariant,
        language: PasscodeLanguage,
        bold: Bool,
        targetVersion: String
    ) -> [String] {
        var names: Set<String> = ["_big"]
        for asset in theme.assets(for: targetVersion) {
            if asset.isImage {
                names.formUnion(Self.outputNames(for: asset.name, variant: variant, language: language, bold: bold))
            } else {
                names.insert(asset.name)
            }
        }
        return names.sorted()
    }

    func preparedFiles(
        theme: PasscodeTheme,
        color: PasscodeTint,
        variant: PasscodeVariant,
        language: PasscodeLanguage,
        bold: Bool,
        targetVersion: String
    ) async throws -> [(String, Data)] {
        let selectedAssets = theme.assets(for: targetVersion)
        guard !selectedAssets.isEmpty else {
            throw AirCardError.processFailed("El tema no tiene assets para \(targetVersion).")
        }
        let files = try await Task.detached(priority: .userInitiated) {
            try Self.recoloredFiles(
                selectedAssets,
                tint: color,
                variant: variant,
                language: language,
                bold: bold
            )
        }.value
        guard !files.isEmpty else {
            throw AirCardError.processFailed("No encontré imágenes válidas para recolorear.")
        }
        return files
    }

    func export(files: [(String, Data)], targetVersion: String, to destination: URL) async throws {
        let work = try NativeTools.temporaryDirectory(prefix: "aircard-export")
        defer { try? FileManager.default.removeItem(at: work) }
        let folder = work.appendingPathComponent(targetVersion, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, data) in files {
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        }
        let archive = work.appendingPathComponent("theme.zip")
        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-c", "-k", "--norsrc", "--keepParent", folder.path, archive.path],
            timeout: .seconds(60)
        )
        guard result.status == 0 else {
            throw AirCardError.processFailed("No pude crear el .passthm: \(result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: archive, to: destination)
    }

    func flash(
        theme: PasscodeTheme,
        device: DeviceInfo,
        color: PasscodeTint,
        variant: PasscodeVariant,
        language: PasscodeLanguage,
        bold: Bool,
        targetVersion: String,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> PasscodeFlashResult {
        try Task.checkCancellation()
        let boldText = bold ? "-bold" : ""
        await progress("Preparando variante --\(variant.rawValue)\(boldText) (\(language.label)) con glifos \(Self.hex(color))…")
        let files = try await preparedFiles(
            theme: theme,
            color: color,
            variant: variant,
            language: language,
            bold: bold,
            targetVersion: targetVersion
        )

        let target = "/var/mobile/Library/Caches/\(targetVersion)"
        let writer = WalletSkinService()
        var written = 0
        let chunkSize = 512
        var start = 0
        while start < files.count {
            try Task.checkCancellation()
            let end = min(start + chunkSize, files.count)
            let chunk = Array(files[start..<end])
            await progress("Escribiendo teclas \(end)/\(files.count) en \(targetVersion)…")
            guard try await writer.writeFiles(
                device: device,
                target: target,
                files: chunk,
                progress: progress
            ) else {
                throw AirCardError.processFailed("No se pudieron escribir las teclas en la caché de \(targetVersion).")
            }
            written += chunk.count
            start = end
        }

        await progress("Color aplicado. Bloquea el iPhone para comprobar el teclado.")
        return PasscodeFlashResult(themeName: theme.name, targetVersion: targetVersion, assetCount: written)
    }

    private static func recoloredFiles(
        _ assets: [PasscodeAsset],
        tint: PasscodeTint,
        variant: PasscodeVariant,
        language: PasscodeLanguage,
        bold: Bool
    ) throws -> [(String, Data)] {
        var output: [String: Data] = [:]
        for asset in assets {
            if !asset.isImage {
                output[asset.name] = asset.data
                continue
            }
            let tinted = try recolor(asset.data, tint: tint)
            for name in outputNames(for: asset.name, variant: variant, language: language, bold: bold) {
                output[name] = tinted
            }
        }

        output["_big"] = Data()
        return output
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    private static func outputNames(
        for name: String,
        variant: PasscodeVariant,
        language: PasscodeLanguage,
        bold: Bool
    ) -> [String] {
        let outputName = imageNameAsPNG(name)
        return [outputName, selectedVariantName(outputName, variant: variant)]
            + keypadNames(for: outputName, language: language, variant: variant, bold: bold)
    }

    static func keypadNames(
        for name: String,
        language: PasscodeLanguage,
        variant: PasscodeVariant,
        bold: Bool
    ) -> [String] {
        guard !name.hasPrefix("_"), !name.hasPrefix("."),
              let key = keypadKey(for: name) else { return [] }
        let digit = key.digit
        let suffix = "--\(variant.rawValue)\(bold ? "-bold" : "")"
        var names = Set<String>()

        func add(_ prefix: String, _ subtext: String) {
            names.insert("\(prefix)-\(digit)-\(subtext)\(suffix).png")
            let compact = subtext.replacingOccurrences(of: " ", with: "")
            if compact != subtext {
                names.insert("\(prefix)-\(digit)-\(compact)\(suffix).png")
            }
        }
        func addWithLetters(_ prefixes: [String], _ tables: [[String: String]]) {
            for prefix in prefixes {
                add(prefix, "")
                for table in tables {
                    if let letters = table[digit], !letters.isEmpty { add(prefix, letters) }
                }
            }
        }

        switch language {
        case .english:
            addWithLetters(["en", "other"], [subtextsEN])
        case .russian:
            addWithLetters(["ru", "other", "en"], [subtextsRU, subtextsEN])
        case .ukrainian:
            addWithLetters(["uk", "other", "en"], [subtextsUK, subtextsEN])
        case .japanese:
            addWithLetters(["ja", "other", "en"], [subtextsEN])
        case .universal:
            for prefix in universalPrefixes {
                let local = prefix == "ru" ? subtextsRU : prefix == "uk" ? subtextsUK : [:]
                addWithLetters([prefix], [local, subtextsEN])
            }
        }

        if let subtext = key.subtext, !subtext.isEmpty {
            for prefix in ["en", "other", "ru", "uk", "ja"] { add(prefix, subtext) }
        }
        return names.sorted()
    }

    private static func keypadKey(for name: String) -> (digit: String, subtext: String?)? {
        let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let clean = stem.replacingOccurrences(
            of: #"--?(white|black)(-bold)?$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        if let match = firstMatch(#"(?:^[a-zA-Z]+-)?([0-9*#])(?:-([^-\n]+))?"#, in: clean),
           let digit = match[1] {
            return (digit, match[2]?.trimmingCharacters(in: .whitespaces))
        }
        if let match = firstMatch(#"([0-9*#])"#, in: name), let digit = match[1] {
            return (digit, nil)
        }
        return nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    private static func selectedVariantName(_ name: String, variant: PasscodeVariant) -> String {
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
        return "\(base)--\(variant.rawValue)\(boldSuffix).png"
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
