import Foundation

struct WalletSkinService: Sendable {
    private let zip = ZipArchive()

    func listDevices() async throws -> [DeviceInfo] {
        let helper = try NativeTools.helperURL(named: "device_helper")
        let result = try await ProcessRunner.run(executable: helper, arguments: ["list"], timeout: .seconds(30))
        guard let rows = try NativeTools.jsonObject(from: result.stdoutString) as? [[String: Any]] else {
            throw AirCardError.invalidHelperOutput(result.stdoutString)
        }
        return rows.compactMap { row in
            guard let udid = row["udid"] as? String, !udid.isEmpty else { return nil }
            let product = row["product"] as? String ?? ""
            guard product.hasPrefix("iPhone") else { return nil }
            return DeviceInfo(
                id: udid,
                name: row["name"] as? String ?? "iPhone",
                product: product,
                version: row["version"] as? String ?? "",
                build: row["buildVersion"] as? String ?? ""
            )
        }
    }

    func validateCardHash(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\".,"))
        guard trimmed.count == 27 || trimmed.count == 28 || trimmed.count == 43 || trimmed.count == 44 else {
            return nil
        }
        guard trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/_-=\"".contains($0)) }) else {
            return nil
        }
        var normalized = trimmed.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while normalized.count % 4 != 0 { normalized.append("=") }
        guard let data = Data(base64Encoded: normalized), data.count == 20 || data.count == 32 else {
            return nil
        }
        return trimmed.count == 27 ? "\(trimmed)=" : trimmed
    }

    func extractCardHash(from line: String) -> String? {
        let lower = line.lowercased()
        let walletMarkers = ["passd", "passbook", "passkit", "stockholm", "nanopassd", "wallet", "/cards/"]
        guard walletMarkers.contains(where: { lower.contains($0) }) else { return nil }
        guard let regex = try? NSRegularExpression(pattern: #"([A-Za-z0-9+/_-]{27,44}={0,2})"#) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let candidateRange = Range(match.range(at: 1), in: line) else { return nil }
        return validateCardHash(String(line[candidateRange]))
    }

    func flash(
        device: DeviceInfo,
        cardHash rawHash: String,
        artwork: PreparedArtwork,
        cardTextColor: PasscodeTint? = nil,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> FlashResult {
        guard let cardHash = validateCardHash(rawHash) else {
            throw AirCardError.invalidCardHash
        }
        try Task.checkCancellation()

        var assets: [(String, Data)] = [
            ("cardBackgroundCombined@3x.png", artwork.png),
            ("cardBackgroundCombined@2x.png", artwork.png),
            ("cardBackgroundCombined.pdf", artwork.pdf)
        ]
        let cardTarget = "/var/mobile/Library/Passes/Cards/\(cardHash).pkpass"

        if let cardTextColor {
            await progress("Leyendo los colores del texto de la tarjeta…")
            do {
                let original = try await readFile(device: device, path: "\(cardTarget)/pass.json")
                let updated = try recoloredPassJSON(original, color: cardTextColor)
                assets.append(("pass.json", updated))
                await progress("Color de números preparado para (Self.rgb(cardTextColor)).")
            } catch {
                await progress("No pude leer pass.json; se aplicará solo el artwork de Wallet.")
            }
        }

        let cacheTargets = [
            "/var/mobile/Library/Passes/Cards/\(cardHash).cache",
            "/var/mobile/Library/Passes/Cards/\(cardHash).pkcache"
        ]

        await progress("Desbloquea el iPhone y abre Apple Books una vez antes de continuar…")
        await progress("Preparando la escritura atómica de la tarjeta…")
        var artworkWritten = false
        do {
            artworkWritten = try await writeBatch(
                device: device,
                target: cardTarget,
                files: assets,
                progress: progress
            )
        } catch {
            await progress("El lote de artwork falló; probando escritura individual…")
        }
        if !artworkWritten {
            var individualWritesSucceeded = true
            for asset in assets {
                try Task.checkCancellation()
                let wrote = try await writeBatch(
                    device: device,
                    target: cardTarget,
                    files: [asset],
                    progress: progress
                )
                if !wrote {
                    individualWritesSucceeded = false
                    break
                }
            }
            artworkWritten = individualWritesSucceeded
        }
        guard artworkWritten else {
            throw AirCardError.processFailed("No se pudo escribir el artwork de la tarjeta.")
        }

        var cacheWrites = 0
        for cacheTarget in cacheTargets {
            try Task.checkCancellation()
            await progress("Invalidando caché: \(URL(fileURLWithPath: cacheTarget).pathExtension)…")
            let cacheAssets = [
                ("FrontFace", Data("corrupted".utf8)),
                ("PlaceHolder", Data("corrupted".utf8)),
                ("Preview", Data("corrupted".utf8))
            ]
            do {
                if try await writeBatch(device: device, target: cacheTarget, files: cacheAssets, progress: progress) {
                    cacheWrites += cacheAssets.count
                }
            } catch {
                // Cache invalidation is best-effort in the reference client;
                // the artwork write remains the success criterion.
                await progress("No se pudo invalidar \(URL(fileURLWithPath: cacheTarget).pathExtension); continúo con el artwork.")
            }
        }

        await progress("Skin escrita. Cierra y abre Wallet en el iPhone.")
        return FlashResult(cardHash: cardHash, artworkFiles: assets.count, cacheFiles: cacheWrites)
    }

    func writeFiles(
        device: DeviceInfo,
        target: String,
        files: [(String, Data)],
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> Bool {
        guard !files.isEmpty else { return true }
        if try await writeBatch(device: device, target: target, files: files, progress: progress) {
            return true
        }

        await progress("El lote falló; escribiendo las teclas individualmente…")
        for file in files {
            try Task.checkCancellation()
            guard try await writeBatch(
                device: device,
                target: target,
                files: [file],
                progress: progress
            ) else { return false }
        }
        return true
    }

    private func writeBatch(
        device: DeviceInfo,
        target: String,
        files: [(String, Data)],
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> Bool {
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let succeeded = try await writeBatchAttempt(
                    device: device,
                    target: target,
                    files: files,
                    progress: progress
                )
                if succeeded { return true }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }

            if attempt < 3 {
                await progress("Reintentando la escritura \(attempt + 1)/3…")
                try await Task.sleep(for: .milliseconds(400 * attempt))
            }
        }
        if let lastError { throw lastError }
        return false
    }

    private func writeBatchAttempt(
        device: DeviceInfo,
        target: String,
        files: [(String, Data)],
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> Bool {
        let token = randomToken()
        let source = "airlift-src-\(token)"
        let link = "airlift-link-\(token)"
        let recovered = "airlift-recovered-\(token)"

        let work = try NativeTools.temporaryDirectory(prefix: "aircard-write")
        defer { try? FileManager.default.removeItem(at: work) }
        let archiveURL = work.appendingPathComponent("payload.zip")
        let booksURL = work.appendingPathComponent("Books.plist")
        let snapshotURL = work.appendingPathComponent("books-snapshot", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotURL, withIntermediateDirectories: true)

        let archive = try zip.build(target: target, files: files)
        try archive.write(to: archiveURL, options: .atomic)

        let identifiers = ["../../\(source)/p0/p1/p2/link"]
            + files.indices.map { "../../\(source)/payload_\($0)" }
        let books = try PropertyListSerialization.data(
            fromPropertyList: [
                "Books": identifiers.enumerated().map { index, identifier in
                    ["Persistent ID": identifier, "Item ID": "\(index + 1)", "DSID": "1"]
                }
            ],
            format: .binary,
            options: 0
        )
        try books.write(to: booksURL, options: .atomic)

        await progress("Preservando el estado de Books…")
        let snapshot = try await native(device: device, arguments: ["snapshot-books", snapshotURL.path])
        await progress("Books snapshot: \(diagnostic(snapshot))")
        guard operationOK(snapshot) else { return false }
        let stage = try await native(
            device: device,
            arguments: ["stage", source, link, recovered, archiveURL.path, booksURL.path, snapshotURL.path]
        )
        await progress("Stage: \(diagnostic(stage))")
        guard operationOK(stage) else { return false }

        await progress("Enviando assets al iPhone…")
        var atcArguments = [device.id]
        let destinations = [link] + files.map { "\(link)/\($0.0)" }
        for (identifier, destination) in Swift.zip(identifiers, destinations) {
            atcArguments.append(contentsOf: [identifier, destination])
        }
        let atc = try await nativeAirTraffic(arguments: atcArguments)
        await progress("AirTraffic: \(diagnostic(atc))")

        await progress("Limpiando el área temporal y restaurando Books…")
        let finish = try await native(
            device: device,
            arguments: ["finish-write", source, link, recovered, snapshotURL.path]
        )
        await progress("Cleanup: \(diagnostic(finish))")
        return atc["ok"] as? Bool == true && operationOK(finish)
    }

    private func native(device: DeviceInfo, arguments: [String]) async throws -> [String: Any] {
        let helper = try NativeTools.helperURL(named: "device_helper")
        guard let command = arguments.first else {
            throw AirCardError.invalidHelperOutput("comando nativo vacío")
        }
        let helperArguments = [command, device.id] + Array(arguments.dropFirst())
        let result = try await ProcessRunner.run(
            executable: helper,
            arguments: helperArguments,
            timeout: .seconds(90)
        )
        guard let object = try? NativeTools.jsonObject(from: result.stdoutString) as? [String: Any] else {
            let stdout = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AirCardError.invalidHelperOutput(
                "status=\(result.status), stdout=\(stdout.isEmpty ? "<vacío>" : stdout), stderr=\(stderr.isEmpty ? "<vacío>" : stderr)"
            )
        }
        return object
    }

    private func readFile(device: DeviceInfo, path: String) async throws -> Data {
        let result = try await native(device: device, arguments: ["read-file", path])
        guard operationOK(result),
              let operation = result["operation"] as? [String: Any],
              let encoded = operation["dataBase64"] as? String,
              let data = Data(base64Encoded: encoded) else {
            throw AirCardError.processFailed("No se pudo leer el pass.json de la tarjeta.")
        }
        return data
    }

    private func recoloredPassJSON(_ data: Data, color: PasscodeTint) throws -> Data {
        guard var pass = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AirCardError.processFailed("El pass.json no tiene un formato válido.")
        }
        let rgb = Self.rgb(color)
        pass["foregroundColor"] = rgb
        pass["labelColor"] = rgb
        return try JSONSerialization.data(withJSONObject: pass, options: [.sortedKeys])
    }

    private static func rgb(_ color: PasscodeTint) -> String {
        let values = [color.red, color.green, color.blue].map { Int(($0 * 255).rounded()) }
        return "rgb(\(values[0]), \(values[1]), \(values[2]))"
    }

    private func nativeAirTraffic(arguments: [String]) async throws -> [String: Any] {
        let helper = try NativeTools.helperURL(named: "airtraffic_host")
        let result = try await ProcessRunner.run(
            executable: helper,
            arguments: arguments,
            timeout: .seconds(120)
        )
        guard let object = try? NativeTools.jsonObject(from: result.stdoutString) as? [String: Any] else {
            let stdout = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AirCardError.invalidHelperOutput(
                "status=\(result.status), stdout=\(stdout.isEmpty ? "<vacío>" : stdout), stderr=\(stderr.isEmpty ? "<vacío>" : stderr)"
            )
        }
        return object
    }

    private func operationOK(_ result: [String: Any]) -> Bool {
        let targetGatePassed = result["targetGatePassed"] as? Bool ?? false
        let operation = result["operation"] as? [String: Any]
        return targetGatePassed && operation?["ok"] as? Bool == true
    }

    private func diagnostic(_ result: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "resultado no serializable"
        }
        return text
    }

    private func randomToken() -> String {
        // The native helper validates exactly 20 lowercase hex characters,
        // matching Python's secrets.token_hex(10) in the reference port.
        (0..<10).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined()
    }
}
