import AppKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct PasscodeKeyTile: Identifiable {
    let key: String
    let image: NSImage?
    var id: String { key }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var devices: [DeviceInfo] = []
    @Published var selectedDeviceID = ""
    @Published var cardHash = ""
    @Published var artwork: PreparedArtwork?
    @Published var artworkPreview: NSImage?
    @Published var imageName = ""
    @Published var overlays: [ArtworkOverlay] = []
    @Published var passcodeTheme: PasscodeTheme?
    @Published var passcodePreview: NSImage?
    @Published var passcodeKeyTiles: [PasscodeKeyTile] = []
    @Published var passcodePlannedFiles: [String] = []
    @Published var passcodeThemeName = ""
    @Published var passcodeVariant = PasscodeVariant.white
    @Published var passcodeLanguage = PasscodeLanguage.english
    @Published var passcodeBold = false
    @Published var passcodeTargetVersion = PasscodeCache.auto
    @Published var status = "Listo. Conecta y desbloquea el iPhone."
    @Published var logs: [String] = []
    @Published var isBusy = false
    @Published var isScanning = false
    @Published var cards: [WalletCard] = CardStore.load()
    @Published var followLatestCard = true
    @Published var scanLineCount = 0
    @Published var walletEventCount = 0
    @Published var lastDetectedHash: String?

    private let service = WalletSkinService()
    private var artworkSourceURL: URL?
    private var currentTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var passcodePreviewTask: Task<Void, Never>?
    private var lastFocusDetection: Date?
    private var rawLineCount = 0

    var selectedDevice: DeviceInfo? {
        devices.first { $0.id == selectedDeviceID }
    }

    var selectedCard: WalletCard? {
        guard let hash = service.validateCardHash(cardHash) else { return nil }
        return cards.first { $0.hash == hash }
    }

    var isCardHashValid: Bool {
        service.validateCardHash(cardHash) != nil
    }

    var targetCardLabel: String {
        if let card = selectedCard { return card.name }
        return isCardHashValid ? "tarjeta manual" : "sin tarjeta"
    }

    init() {
        refreshDevices()
    }

    func refreshDevices() {
        scanTask?.cancel()
        isScanning = false
        currentTask?.cancel()
        status = "Buscando iPhone emparejados…"
        currentTask = Task { [weak self] in
            do {
                let devices = try await WalletSkinService().listDevices()
                guard !Task.isCancelled else { return }
                self?.devices = devices
                if self?.selectedDeviceID.isEmpty == true {
                    self?.selectedDeviceID = devices.first?.id ?? ""
                }
                self?.status = devices.isEmpty
                    ? "No encontré un iPhone. Conéctalo por USB y pulsa ‘Confiar’."
                    : "Encontré \(devices.count) iPhone(s)."
                self?.log(devices.isEmpty ? "No hay dispositivos disponibles." : "Dispositivos: \(devices.map(\.name).joined(separator: ", "))")
            } catch {
                self?.status = error.localizedDescription
                self?.log("Error de detección: \(error.localizedDescription)")
            }
        }
    }

    func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP, .image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isBusy = true
        status = "Preparando imagen a 1536 × 969…"
        artworkSourceURL = url
        currentTask?.cancel()
        let overlaySnapshot = overlays
        currentTask = Task { [weak self] in
            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try ImageProcessor.prepare(url: url, overlays: overlaySnapshot)
                }.value
                guard !Task.isCancelled else { return }
                self?.artwork = prepared
                self?.artworkPreview = NSImage(data: prepared.png)
                self?.imageName = url.lastPathComponent
                let overlayText = overlaySnapshot.isEmpty
                    ? "sin overlays"
                    : "\(overlaySnapshot.count) overlay(s)"
                self?.status = "Imagen lista: \(prepared.sourceWidth) × \(prepared.sourceHeight) → 1536 × 969, \(overlayText)."
                self?.log("Artwork preparado: \(url.lastPathComponent) [\(overlayText)]")
            } catch {
                self?.status = error.localizedDescription
                self?.log("No pude preparar la imagen: \(error.localizedDescription)")
            }
            self?.isBusy = false
        }
    }

    func chooseOverlays() {
        guard artworkSourceURL != nil else {
            status = "Selecciona primero la imagen base de la tarjeta."
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }

        do {
            let imported = try panel.urls.map { url in
                let data = try Data(contentsOf: url)
                guard CGImageSourceCreateWithData(data as CFData, nil) != nil else {
                    throw AirCardError.processFailed("No pude leer el PNG \(url.lastPathComponent).")
                }
                return ArtworkOverlay(name: url.lastPathComponent, data: data)
            }
            guard !imported.isEmpty else { return }
            overlays.append(contentsOf: imported)
            log("Overlays añadidos: \(imported.map(\.name).joined(separator: ", "))")
            rebuildArtwork(status: "Aplicando \(overlays.count) overlay(s) PNG…")
        } catch {
            status = error.localizedDescription
            log("No pude añadir el overlay: \(error.localizedDescription)")
        }
    }

    func removeOverlay(_ overlay: ArtworkOverlay) {
        overlays.removeAll { $0.id == overlay.id }
        log("Overlay quitado: \(overlay.name)")
        rebuildArtwork(status: overlays.isEmpty ? "Quitando overlays PNG…" : "Actualizando overlays PNG…")
    }

    func moveOverlayUp(_ overlay: ArtworkOverlay) {
        guard let index = overlays.firstIndex(where: { $0.id == overlay.id }), index > 0 else { return }
        overlays.swapAt(index, index - 1)
        rebuildArtwork(status: "Reordenando overlays PNG…")
    }

    func moveOverlayDown(_ overlay: ArtworkOverlay) {
        guard let index = overlays.firstIndex(where: { $0.id == overlay.id }), index + 1 < overlays.count else { return }
        overlays.swapAt(index, index + 1)
        rebuildArtwork(status: "Reordenando overlays PNG…")
    }

    private func rebuildArtwork(status message: String) {
        guard let sourceURL = artworkSourceURL else { return }
        currentTask?.cancel()
        isBusy = true
        status = message
        let overlaySnapshot = overlays
        currentTask = Task { [weak self] in
            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try ImageProcessor.prepare(url: sourceURL, overlays: overlaySnapshot)
                }.value
                guard !Task.isCancelled else { return }
                self?.artwork = prepared
                self?.artworkPreview = NSImage(data: prepared.png)
                self?.status = overlaySnapshot.isEmpty
                    ? "Imagen lista: \(prepared.sourceWidth) × \(prepared.sourceHeight) → 1536 × 969."
                    : "Artwork actualizado con \(overlaySnapshot.count) overlay(s) PNG."
            } catch is CancellationError {
                return
            } catch {
                self?.status = error.localizedDescription
                self?.log("No pude actualizar los overlays: \(error.localizedDescription)")
            }
            self?.isBusy = false
        }
    }

    func choosePasscodeTheme() {
        let panel = NSOpenPanel()
        let passcodeType = UTType(filenameExtension: "passthm") ?? .zip
        panel.allowedContentTypes = [passcodeType, .zip]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isBusy = true
        status = "Abriendo el tema del teclado…"
        currentTask?.cancel()
        let tint = passcodeVariant.tint
        let selection = passcodeTargetVersion
        currentTask = Task { [weak self] in
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try await PasscodeThemeService().load(url: url)
                }.value
                let previewData = try await Task.detached(priority: .userInitiated) {
                    try PasscodeThemeService().preview(
                        theme: loaded,
                        color: tint,
                        targetVersion: loaded.detectedVersion
                    )
                }.value
                guard !Task.isCancelled else { return }
                self?.passcodeTheme = loaded
                self?.passcodeThemeName = loaded.name
                if selection != PasscodeCache.auto {
                    self?.passcodeTargetVersion = loaded.detectedVersion
                }
                self?.passcodePreview = NSImage(data: previewData)
                self?.recolorPasscodePreview()
                self?.status = "Tema listo: \(loaded.name). Elige --white o --black y aplícalo."
                self?.log("Tema de teclado preparado: \(loaded.name) [\(loaded.detectedVersion)]")
            } catch is CancellationError {
                self?.status = "Operación cancelada."
            } catch {
                self?.status = error.localizedDescription
                self?.log("No pude abrir el tema del teclado: \(error.localizedDescription)")
            }
            self?.isBusy = false
        }
    }

    func recolorPasscodePreview() {
        guard let theme = passcodeTheme else { return }
        passcodePreviewTask?.cancel()
        let tint = passcodeVariant.tint
        let variant = passcodeVariant
        let language = passcodeLanguage
        let bold = passcodeBold
        let target = PasscodeCache.resolve(passcodeTargetVersion, device: selectedDevice)
        passcodePlannedFiles = PasscodeThemeService().plannedFileNames(
            theme: theme,
            variant: variant,
            language: language,
            bold: bold,
            targetVersion: target
        )
        passcodePreviewTask = Task { [weak self] in
            do {
                let (data, keys) = try await Task.detached(priority: .userInitiated) {
                    let service = PasscodeThemeService()
                    return (
                        try service.preview(theme: theme, color: tint, targetVersion: target),
                        try service.keyPreviews(theme: theme, color: tint, targetVersion: target)
                    )
                }.value
                guard !Task.isCancelled else { return }
                self?.passcodePreview = NSImage(data: data)
                let images = Dictionary(uniqueKeysWithValues: keys.map { ($0.key, $0.png) })
                self?.passcodeKeyTiles = keys.isEmpty ? [] : PasscodeKeyPreview.keypadOrder.map { key in
                    PasscodeKeyTile(key: key, image: images[key].flatMap { NSImage(data: $0) })
                }
            } catch {
                self?.log("No pude actualizar la previsualización: \(error.localizedDescription)")
            }
        }
    }

    func exportPasscodeTheme() {
        guard let theme = passcodeTheme else {
            status = "Selecciona un tema .passthm primero."
            return
        }
        let tint = passcodeVariant.tint
        let variant = passcodeVariant
        let language = passcodeLanguage
        let bold = passcodeBold
        let target = PasscodeCache.resolve(passcodeTargetVersion, device: selectedDevice)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "passthm") ?? .zip]
        panel.nameFieldStringValue = "\(theme.name)-\(variant.rawValue)\(bold ? "-bold" : "").passthm"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        currentTask?.cancel()
        isBusy = true
        status = "Exportando el teclado recoloreado…"
        currentTask = Task { [weak self] in
            do {
                let service = PasscodeThemeService()
                let files = try await service.preparedFiles(
                    theme: theme,
                    color: tint,
                    variant: variant,
                    language: language,
                    bold: bold,
                    targetVersion: target
                )
                try await service.export(files: files, targetVersion: target, to: url)
                self?.status = "Tema exportado: \(url.lastPathComponent) (\(files.count) archivos)."
                self?.log("Teclado exportado en \(url.path) [\(target)]")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch is CancellationError {
                self?.status = "Operación cancelada."
            } catch {
                self?.status = error.localizedDescription
                self?.log("No pude exportar el teclado: \(error.localizedDescription)")
            }
            self?.isBusy = false
        }
    }

    func exportArtwork() {
        guard let artwork else {
            status = "Selecciona una imagen primero."
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Guardar aquí"
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        let baseName = URL(fileURLWithPath: imageName).deletingPathExtension().lastPathComponent
        let folder = directory.appendingPathComponent(
            "\(baseName.isEmpty ? "AirCard" : baseName)-wallet",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let files = WalletSkinService.artworkFiles(artwork)
            for (name, data) in files {
                try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            }
            var count = files.count
            if let source = artworkSourceURL {
                let original = folder.appendingPathComponent("original-\(source.lastPathComponent)")
                if FileManager.default.fileExists(atPath: original.path) {
                    try FileManager.default.removeItem(at: original)
                }
                try FileManager.default.copyItem(at: source, to: original)
                count += 1
            }
            status = "Artwork exportado: \(folder.lastPathComponent) (\(count) archivos)."
            log("Artwork exportado en \(folder.path)")
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            status = error.localizedDescription
            log("No pude exportar el artwork: \(error.localizedDescription)")
        }
    }

    var passcodeResolvedCache: String {
        PasscodeCache.resolve(passcodeTargetVersion, device: selectedDevice)
    }

    var passcodeAutoCacheLabel: String {
        "Auto (\(PasscodeCache.resolve(PasscodeCache.auto, device: selectedDevice)))"
    }

    func flashPasscodeTheme() {
        guard let device = devices.first(where: { $0.id == selectedDeviceID }) else {
            status = "Selecciona un iPhone conectado."
            return
        }
        guard let theme = passcodeTheme else {
            status = "Selecciona un tema .passthm primero."
            return
        }

        currentTask?.cancel()
        isBusy = true
        status = "Escribiendo color del teclado en \(device.name)…"
        let scanToStop = scanTask
        if let scanToStop {
            scanToStop.cancel()
            isScanning = false
            log("Escaneo detenido; esperando el cierre del helper nativo…")
        }
        let tint = passcodeVariant.tint
        let variant = passcodeVariant
        let language = passcodeLanguage
        let bold = passcodeBold
        let target = PasscodeCache.resolve(passcodeTargetVersion, device: device)
        currentTask = Task { [weak self] in
            do {
                if let scanToStop {
                    await scanToStop.value
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(300))
                }
                self?.log("Inicio de color de teclado para \(device.name) en \(target).")
                let result = try await PasscodeThemeService().flash(
                    theme: theme,
                    device: device,
                    color: tint,
                    variant: variant,
                    language: language,
                    bold: bold,
                    targetVersion: target
                ) { message in
                    await MainActor.run {
                        self?.status = message
                        self?.log(message)
                    }
                }
                guard !Task.isCancelled else { return }
                self?.status = "Color aplicado. Bloquea el iPhone para ver el teclado."
                self?.log("Completado: \(result.assetCount) assets en \(result.targetVersion).")
            } catch is CancellationError {
                self?.status = "Operación cancelada."
            } catch {
                self?.status = error.localizedDescription
                self?.log("Color de teclado fallido: \(error.localizedDescription)")
            }
            self?.isBusy = false
        }
    }

    func flashSkin() {
        guard let device = devices.first(where: { $0.id == selectedDeviceID }) else {
            status = "Selecciona un iPhone conectado."
            return
        }
        guard let artwork else {
            status = "Selecciona una imagen primero."
            return
        }
        guard service.validateCardHash(cardHash) != nil else {
            status = "Introduce un hash de tarjeta válido."
            return
        }

        currentTask?.cancel()
        isBusy = true
        status = "Escribiendo skin en \(device.name)…"
        let scanToStop = scanTask
        if let scanToStop {
            scanToStop.cancel()
            isScanning = false
            log("Escaneo detenido; esperando el cierre del helper nativo…")
        }
        let rawCardHash = cardHash
        currentTask = Task { [weak self] in
            do {
                if let scanToStop {
                    await scanToStop.value
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(300))
                }
                self?.log("Inicio de flash para \(device.name).")
                let result = try await WalletSkinService().flash(
                    device: device,
                    cardHash: rawCardHash,
                    artwork: artwork
                ) { message in
                    await MainActor.run {
                        self?.status = message
                        self?.log(message)
                    }
                }
                guard !Task.isCancelled else { return }
                self?.status = "Skin aplicada a \(result.cardHash). Cierra y abre Wallet en el iPhone."
                self?.log("Completado: \(result.artworkFiles) assets; \(result.cacheFiles) cachés tocadas.")
            } catch is CancellationError {
                self?.status = "Operación cancelada."
            } catch {
                self?.status = error.localizedDescription
                self?.log("Flash fallido: \(error.localizedDescription)")
            }
            self?.isBusy = false
        }
    }

    func toggleScan() {
        if isScanning {
            scanTask?.cancel()
            isScanning = false
            status = "Escaneo detenido."
            log("Escaneo de syslog detenido.")
            return
        }
        guard let device = devices.first(where: { $0.id == selectedDeviceID }) else {
            status = "Selecciona un iPhone conectado."
            return
        }
        do {
            let helper = try NativeTools.helperURL(named: "device_helper")
            isScanning = true
            scanLineCount = 0
            rawLineCount = 0
            walletEventCount = 0
            lastFocusDetection = nil
            status = "Abre Wallet en el iPhone y toca la tarjeta que quieres personalizar…"
            log("Escuchando syslog de \(device.name) (\(device.compatibilityNote)).")
            scanTask = Task { [weak self] in
                do {
                    for try await line in DeviceLogScanner.lines(helper: helper, udid: device.id) {
                        guard !Task.isCancelled else { return }
                        self?.handleSyslog(line: line)
                    }
                } catch is CancellationError {
                    // User stopped the scanner.
                } catch {
                    self?.status = error.localizedDescription
                    self?.log("Escaneo fallido: \(error.localizedDescription)")
                }
                self?.isScanning = false
            }
        } catch {
            status = error.localizedDescription
        }
    }

    private func handleSyslog(line: String) {
        rawLineCount += 1
        if rawLineCount % 50 == 0 { scanLineCount = rawLineCount }
        guard let detection = CardHashDetector.detect(in: line) else {

            if let name = CardHashDetector.walletName(in: line),
               let hash = lastDetectedHash,
               let index = cards.firstIndex(where: { $0.hash == hash }),
               cards[index].name.hasPrefix("Tarjeta "),
               Date.now.timeIntervalSince(cards[index].lastSeen) < 2 {
                cards[index].name = name
                CardStore.save(cards)
            }
            return
        }
        walletEventCount += 1
        let now = Date.now
        let isNew: Bool
        if let index = cards.firstIndex(where: { $0.hash == detection.hash }) {
            isNew = false
            cards[index].lastSeen = now
            cards[index].hits += 1
            if let name = detection.name, cards[index].name.hasPrefix("Tarjeta ") {
                cards[index].name = name
            }
        } else {
            isNew = true
            cards.append(WalletCard(
                hash: detection.hash,
                name: detection.name ?? "Tarjeta \(cards.count + 1)",
                firstSeen: now,
                lastSeen: now,
                hits: 1
            ))
        }
        CardStore.save(cards)
        lastDetectedHash = detection.hash

        let focusIsRecent = lastFocusDetection.map { now.timeIntervalSince($0) < 3 } ?? false
        if detection.isFocus { lastFocusDetection = now }
        let shouldSelect = (followLatestCard && (detection.isFocus || !focusIsRecent))
            || service.validateCardHash(cardHash) == nil
        if shouldSelect, cardHash != detection.hash {
            cardHash = detection.hash
            let name = cards.first { $0.hash == detection.hash }?.name ?? detection.hash
            status = "Tarjeta vinculada: \(name). Elige la imagen y pulsa ‘Aplicar skin’."
        }
        if isNew {
            log("Tarjeta detectada: \(detection.name ?? detection.hash) [\(detection.hash)]")
        }
    }

    func selectCard(_ card: WalletCard) {
        cardHash = card.hash
        followLatestCard = false
        status = "Tarjeta seleccionada: \(card.name)."
    }

    func renameCard(_ card: WalletCard, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = cards.firstIndex(where: { $0.hash == card.hash }) else { return }
        cards[index].name = trimmed
        CardStore.save(cards)
    }

    func forgetCard(_ card: WalletCard) {
        cards.removeAll { $0.hash == card.hash }
        CardStore.save(cards)
        if service.validateCardHash(cardHash) == card.hash { cardHash = "" }
        log("Tarjeta olvidada: \(card.name)")
    }

    func saveManualCard() {
        guard let hash = service.validateCardHash(cardHash) else {
            status = "El hash pegado no es válido."
            return
        }
        cardHash = hash
        if !cards.contains(where: { $0.hash == hash }) {
            cards.append(WalletCard(hash: hash, name: "Tarjeta \(cards.count + 1)", firstSeen: .now, lastSeen: .now, hits: 0))
            CardStore.save(cards)
        }
        status = "Hash guardado en la lista de tarjetas."
    }

    func cancel() {
        currentTask?.cancel()
        scanTask?.cancel()
        passcodePreviewTask?.cancel()
        isScanning = false
        isBusy = false
        status = "Operación cancelada."
    }

    func log(_ message: String) {
        logs.append("[\(Date.now.formatted(date: .omitted, time: .standard))] \(message)")
        if logs.count > 100 { logs.removeFirst(logs.count - 100) }
    }
}
