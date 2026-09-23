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
    @Published var cardThumbnails: [String: NSImage] = [:]
    @Published var historyRevision = 0
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

    let studio = StudioModel()
    private let service = WalletSkinService()
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
        reloadThumbnails()
        refreshDevices()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { _ in
            DeviceLogScanner.terminateAll()
        }
    }

    func reloadThumbnails() {
        var thumbnails: [String: NSImage] = [:]
        for card in cards {
            if let image = CardHistoryStore.thumbnail(for: card.hash) { thumbnails[card.hash] = image }
        }
        cardThumbnails = thumbnails
        historyRevision += 1
    }

    func history(for card: WalletCard) -> [CardHistoryEntry] {
        CardHistoryStore.entries(for: card.hash)
    }

    func exportBackup(_ entry: CardHistoryEntry, card: WalletCard) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Guardar respaldo aquí"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        let destination = directory.appendingPathComponent(
            "\(card.name)-\(entry.url.lastPathComponent)",
            isDirectory: true
        )
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: entry.url, to: destination)
            status = "Respaldo guardado: \(destination.lastPathComponent)."
            log("Respaldo de \(card.name) guardado en \(destination.path)")
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            status = error.localizedDescription
            log("No pude guardar el respaldo: \(error.localizedDescription)")
        }
    }

    func openInStudio(_ entry: CardHistoryEntry) {
        studio.load(url: entry.skinURL)
    }

    func exportStudioAssets() {
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let folder = try await studio.exportAssets() else { return }
                status = "Assets exportados en \(folder.lastPathComponent)."
                log("Assets del estudio exportados en \(folder.path)")
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            } catch {
                status = error.localizedDescription
                log("No pude exportar los assets: \(error.localizedDescription)")
            }
        }
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
        guard studio.document.hasVisibleContent else {
            status = "El diseño no tiene capas visibles."
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
        let document = studio.document
        let studio = studio
        currentTask = Task { [weak self] in
            do {
                self?.status = "Renderizando el diseño a 1536 × 969…"
                let artwork = try await studio.renderArtwork()
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
                do {
                    try await Task.detached(priority: .utility) {
                        _ = try CardHistoryStore.save(hash: result.cardHash, document: document, artwork: artwork)
                    }.value
                    self?.reloadThumbnails()
                } catch {
                    self?.log("No pude guardar el historial local: \(error.localizedDescription)")
                }
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
        CardHistoryStore.removeAll(for: card.hash)
        cardThumbnails[card.hash] = nil
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
