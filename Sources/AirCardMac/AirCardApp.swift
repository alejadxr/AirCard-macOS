import SwiftUI

@main
struct AirCardMacApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("AirCard") {
            RootView(model: model)
        }
        .defaultSize(width: 1_320, height: 840)
        .windowToolbarStyle(.unified)
        .commands {
            AirCardCommands(model: model, studio: model.studio)
        }
    }
}

struct AirCardCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var studio: StudioModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nuevo diseño") { studio.newDocument() }
                .keyboardShortcut("n")
            Button("Abrir diseño…") { studio.open() }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Guardar diseño") { studio.save() }
                .keyboardShortcut("s")
            Button("Guardar diseño como…") { studio.save(as: true) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("Descargar assets…") { model.exportStudioAssets() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Deshacer") { studio.undo() }
                .keyboardShortcut("z")
                .disabled(!studio.canUndo)
            Button("Rehacer") { studio.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!studio.canRedo)
        }
        CommandMenu("Diseño") {
            Button("Añadir imagen…") { studio.importPhoto() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Menu("Añadir capa") {
                ForEach(SkinLayerKind.allCases) { kind in
                    Button(SkinLayerContent.defaultContent(for: kind).kindLabel) { studio.addLayer(kind) }
                }
            }
            Menu("Estilos") {
                ForEach(SkinPresets.all) { preset in
                    Button(preset.name) { studio.applyPreset(preset) }
                }
            }
            Divider()
            Button("Duplicar capa") {
                if let id = studio.selectedLayerID { studio.duplicateLayer(id) }
            }
            .keyboardShortcut("d")
            .disabled(studio.selectedLayerID == nil)
            Button("Eliminar capa") {
                if let id = studio.selectedLayerID { studio.removeLayer(id) }
            }
            .keyboardShortcut(.delete)
            .disabled(studio.selectedLayerID == nil)
            Divider()
            Button("Mostrar zonas de Wallet") { studio.showSafeZones.toggle() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Mostrar inspector") { studio.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
            Button("Aplicar a la tarjeta") { model.flashSkin() }
                .keyboardShortcut(.return)
                .disabled(model.isBusy || !model.isCardHashValid || model.selectedDeviceID.isEmpty)
        }
    }
}
