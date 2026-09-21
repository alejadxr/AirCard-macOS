import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var devices: [DeviceInfo] = []
    @Published var selectedDeviceID = ""
    @Published var cardHash = ""
    @Published var artwork: PreparedArtwork?
    @Published var artworkPreview: NSImage?
    @Published var imageName = ""
    @Published var passcodeTheme: PasscodeTheme?
    @Published var passcodePreview: NSImage?
    @Published var passcodeThemeName = ""
    @Published var passcodeColor = Color.white
    @Published var passcodeTargetVersion = "TelephonyUI-10"
    @Published var cardTextColor = Color.white
    @Published var status = "Listo. Conecta y desbloquea el iPhone."
    @Published var logs: [String] = []
    @Published var isBusy = false
    @Published var isScanning = false

    private let service = WalletSkinService()
    private var currentTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var passcodePreviewTask: Task<Void, Never>?

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
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try ImageProcessor.prepare(url: url)
                }.value
                guard !Task.isCancelled else { return }
                self?.artwork = prepared
                self?.artworkPreview = NSImage(data: prepared.png)
                self?.imageName = url.lastPathComponent
                self?.status = "Imagen lista: \(prepared.sourceWidth) × \(prepared.sourceHeight) → 1536 × 969, conservando bordes."
                self?.log("Artwork preparado: \(url.lastPathComponent)")
            } catch {
                self?.status = error.localizedDescription
                self?.log("No pude preparar la imagen: \(error.localizedDescription)")
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
        let tint = currentPasscodeTint()
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
                self?.passcodeTargetVersion = loaded.detectedVersion
                self?.passcodePreview = NSImage(data: previewData)
                self?.status = "Tema listo: \(loaded.name). Elige un color y aplícalo."
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
        let tint = currentPasscodeTint()
        let target = passcodeTargetVersion
        passcodePreviewTask = Task { [weak self] in
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try PasscodeThemeService().preview(theme: theme, color: tint, targetVersion: target)
                }.value
                guard !Task.isCancelled else { return }
                self?.passcodePreview = NSImage(data: data)
            } catch {
                self?.log("No pude actualizar la previsualización: \(error.localizedDescription)")
            }
        }
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
        let tint = currentPasscodeTint()
        let target = passcodeTargetVersion
        currentTask = Task { [weak self] in
            do {
                if let scanToStop {
                    await scanToStop.value
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(300))
                }
                self?.log("Inicio de color de teclado para \(device.name).")
                let result = try await PasscodeThemeService().flash(
                    theme: theme,
                    device: device,
                    color: tint,
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

    func currentPasscodeTint() -> PasscodeTint {
        let color = NSColor(passcodeColor).usingColorSpace(.deviceRGB) ?? .white
        return PasscodeTint(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent)
        )
    }

    func currentCardTextColor() -> PasscodeTint {
        let color = NSColor(cardTextColor).usingColorSpace(.deviceRGB) ?? .white
        return PasscodeTint(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent)
        )
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
        let textColor = currentCardTextColor()
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
                    artwork: artwork,
                    cardTextColor: textColor
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
            status = "Abre Wallet y toca la tarjeta para detectarla…"
            log("Escuchando syslog de \(device.name).")
            scanTask = Task { [weak self] in
                do {
                    for try await line in DeviceLogScanner.lines(helper: helper, udid: device.id) {
                        guard !Task.isCancelled else { return }
                        if let hash = WalletSkinService().extractCardHash(from: line) {
                            self?.cardHash = hash
                            self?.status = "Tarjeta detectada: \(hash)"
                            self?.log("Hash detectado automáticamente.")
                        }
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
