import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum InspectorTab: String, CaseIterable, Identifiable {
    case layers, adjustments

    var id: String { rawValue }
    var label: String { AirCardL10n.text(self == .layers ? "Capas" : "Ajustes") }
}

@MainActor
final class StudioModel: ObservableObject {
    @Published var document: SkinDocument {
        didSet {
            guard document != oldValue else { return }
            isDirty = true
            recordUndo(oldValue)
            schedulePreview()
        }
    }
    @Published var selectedLayerID: UUID?
    @Published private(set) var preview: CGImage?
    @Published private(set) var presetThumbnails: [String: CGImage] = [:]
    @Published var liveTilt: Double?
    @Published var showSafeZones = true
    @Published var inspectorTab = InspectorTab.layers
    @Published var showInspector = true
    @Published private(set) var isDirty = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var errorMessage: String?

    private(set) var documentURL: URL?
    private var previewTask: Task<Void, Never>?
    private var undoStack: [SkinDocument] = []
    private var redoStack: [SkinDocument] = []
    private var lastUndoRecord = Date.distantPast
    private var isRestoring = false

    static let previewWidth: CGFloat = 1_152

    init() {
        document = SkinPresets.aurora.document(photo: nil)
        selectedLayerID = document.layers.last?.id
        isDirty = false
        schedulePreview()
        renderPresetThumbnails()
    }

    var selectedLayer: SkinLayer? {
        document.layers.first { $0.id == selectedLayerID }
    }

    var effectiveTilt: Double { liveTilt ?? document.tilt }

    var usesTilt: Bool {
        document.layers.contains { $0.isVisible && $0.content.usesTilt }
    }

    var hasPhoto: Bool { firstPhoto != nil }

    private var firstPhoto: (UUID, Data)? {
        for layer in document.layers {
            if case .image(let style) = layer.content, let data = document.assets[style.assetID] {
                return (style.assetID, data)
            }
        }
        return nil
    }

    func layerBinding(_ id: UUID) -> Binding<SkinLayer>? {
        guard document.layers.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in
                self?.document.layers.first { $0.id == id } ?? SkinLayer(name: "", content: .solid(.black))
            },
            set: { [weak self] newValue in
                guard let self, let index = self.document.layers.firstIndex(where: { $0.id == id }) else { return }
                self.document.layers[index] = newValue
            }
        )
    }

    func schedulePreview() {
        previewTask?.cancel()
        let document = document
        let tilt = effectiveTilt
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(12))
            guard !Task.isCancelled else { return }
            let size = CGSize(
                width: Self.previewWidth,
                height: (Self.previewWidth * SkinDocument.canvasSize.height / SkinDocument.canvasSize.width).rounded()
            )
            let result = await Task.detached(priority: .userInitiated) { () -> Result<CGImage, Error> in
                Result { try SkinRenderer.render(document, size: size, tilt: tilt) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let image):
                self?.preview = image
            case .failure(let error):
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func setLiveTilt(_ value: Double?) {
        liveTilt = value.map { min(1, max(0, $0)) }
        if usesTilt { schedulePreview() }
    }

    private func renderPresetThumbnails() {
        let photo = firstPhoto
        Task { [weak self] in
            for preset in SkinPresets.all {
                let document = preset.document(photo: photo)
                let size = CGSize(width: 320, height: 202)
                let image = await Task.detached(priority: .utility) {
                    try? SkinRenderer.render(document, size: size)
                }.value
                if let image { self?.presetThumbnails[preset.id] = image }
            }
        }
    }

    func applyPreset(_ preset: SkinPreset) {
        let photoName = document.layers.first { $0.content.image != nil }?.name
        var next = preset.document(photo: firstPhoto)
        next.tilt = document.tilt
        if let photoName, let index = next.layers.firstIndex(where: { $0.content.image != nil }) {
            next.layers[index].name = photoName
        }
        document = next
        selectedLayerID = next.layers.last?.id
    }

    func newDocument() {
        document = SkinDocument(name: AirCardL10n.text("Sin título"), layers: [SkinLayerKind.solid.defaultLayer])
        selectedLayerID = document.layers.first?.id
        documentURL = nil
    }

    func addLayer(_ kind: SkinLayerKind) {
        let layer = kind.defaultLayer
        insert(layer)
    }

    func importPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP, .heic, .image]
        panel.allowsMultipleSelection = true
        panel.message = AirCardL10n.text("Elige una o varias imágenes para añadirlas como capas.")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            addPhoto(url: url)
        }
        renderPresetThumbnails()
    }

    func addPhoto(url: URL) {
        guard let data = try? Data(contentsOf: url),
              CGImageSourceCreateWithData(data as CFData, nil) != nil else {
            errorMessage = AirCardL10n.format("No pude leer la imagen %@.", url.lastPathComponent)
            return
        }
        let id = UUID()
        let hasImage = document.layers.contains { if case .image = $0.content { return true } else { return false } }
        let style = ImageLayerStyle(assetID: id, fit: hasImage ? .fit : .fitBlurred)
        var layer = SkinLayer(name: url.lastPathComponent, content: .image(style))
        if hasImage { layer.blend = .normal }
        var next = document
        next.assets[id] = data
        if hasImage {
            let index = selectedIndex.map { $0 + 1 } ?? next.layers.count
            next.layers.insert(layer, at: min(index, next.layers.count))
        } else {
            let replaceBase = next.layers.first.map { base -> Bool in
                if case .image = base.content { return false }
                return next.layers.count <= 1
            } ?? false
            if replaceBase { next.layers.removeFirst() }
            next.layers.insert(layer, at: 0)
        }
        document = next
        selectedLayerID = layer.id
    }

    private var selectedIndex: Int? {
        document.layers.firstIndex { $0.id == selectedLayerID }
    }

    private func insert(_ layer: SkinLayer) {
        let index = selectedIndex.map { $0 + 1 } ?? document.layers.count
        document.layers.insert(layer, at: min(index, document.layers.count))
        selectedLayerID = layer.id
    }

    func removeLayer(_ id: UUID) {
        guard let index = document.layers.firstIndex(where: { $0.id == id }) else { return }
        var next = document
        next.layers.remove(at: index)
        next.garbageCollectAssets()
        document = next
        selectedLayerID = document.layers.indices.contains(index)
            ? document.layers[index].id
            : document.layers.last?.id
    }

    func duplicateLayer(_ id: UUID) {
        guard let layer = document.layers.first(where: { $0.id == id }) else { return }
        var copy = layer
        copy.id = UUID()
        copy.name = AirCardL10n.format("%@ copia", layer.name)
        insert(copy)
    }

    func toggleVisibility(_ id: UUID) {
        guard let index = document.layers.firstIndex(where: { $0.id == id }) else { return }
        document.layers[index].isVisible.toggle()
    }

    func moveLayers(fromDisplay source: IndexSet, toDisplay destination: Int) {
        var display = Array(document.layers.reversed())
        display.move(fromOffsets: source, toOffset: destination)
        document.layers = display.reversed()
    }

    func moveSelected(up: Bool) {
        guard let index = selectedIndex else { return }
        let target = up ? index + 1 : index - 1
        guard document.layers.indices.contains(target) else { return }
        document.layers.swapAt(index, target)
    }

    private func recordUndo(_ previous: SkinDocument) {
        guard !isRestoring else { return }
        let now = Date()
        if now.timeIntervalSince(lastUndoRecord) > 0.6 || undoStack.isEmpty {
            undoStack.append(previous)
            if undoStack.count > 80 { undoStack.removeFirst() }
        }
        lastUndoRecord = now
        redoStack.removeAll()
        canUndo = !undoStack.isEmpty
        canRedo = false
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        restore(next)
    }

    private func restore(_ snapshot: SkinDocument) {
        isRestoring = true
        document = snapshot
        isRestoring = false
        lastUndoRecord = .distantPast
        if !document.layers.contains(where: { $0.id == selectedLayerID }) {
            selectedLayerID = document.layers.last?.id
        }
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: SkinDocument.fileExtension) ?? .json, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url)
    }

    func load(url: URL) {
        do {
            let loaded = try SkinFile.decode(Data(contentsOf: url))
            document = loaded
            documentURL = url
            selectedLayerID = loaded.layers.last?.id
            isDirty = false
            renderPresetThumbnails()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(as: Bool = false) {
        var url = documentURL
        if url == nil || `as` {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: SkinDocument.fileExtension) ?? .json]
            panel.nameFieldStringValue = "\(document.name).\(SkinDocument.fileExtension)"
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            url = chosen
        }
        guard let url else { return }
        do {
            var named = document
            named.name = url.deletingPathExtension().lastPathComponent
            try SkinFile.encode(named).write(to: url, options: .atomic)
            isRestoring = true
            document = named
            isRestoring = false
            documentURL = url
            isDirty = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renderArtwork() async throws -> PreparedArtwork {
        let document = document
        return try await Task.detached(priority: .userInitiated) {
            try SkinRenderer.prepare(document)
        }.value
    }

    func exportAssets() async throws -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = AirCardL10n.text("Guardar aquí")
        panel.message = AirCardL10n.format("Se creará una carpeta con los 11 archivos de Wallet, el .%@ y tus imágenes originales.", SkinDocument.fileExtension)
        guard panel.runModal() == .OK, let directory = panel.url else { return nil }
        let document = document
        let folder = directory.appendingPathComponent("\(document.name)-wallet", isDirectory: true)
        try await Task.detached(priority: .userInitiated) {
            let artwork = try SkinRenderer.prepare(document)
            try SkinExporter.write(document: document, artwork: artwork, to: folder)
        }.value
        return folder
    }
}
