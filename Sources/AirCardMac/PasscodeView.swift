import SwiftUI

struct PasscodeView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HSplitView {
            preview
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            settings
                .frame(minWidth: 360, idealWidth: 420, maxWidth: 520)
        }
        .navigationTitle("Teclado de código")
        .navigationSubtitle(model.passcodeThemeName)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.choosePasscodeTheme() } label: {
                    Label("Elegir .passthm…", systemImage: "square.and.arrow.down")
                }
                Button { model.exportPasscodeTheme() } label: {
                    Label("Descargar .passthm…", systemImage: "arrow.down.doc")
                }
                .disabled(model.isBusy || model.passcodeTheme == nil)
                Button {
                    model.isBusy ? model.cancel() : model.flashPasscodeTheme()
                } label: {
                    Label(model.isBusy ? "Cancelar" : "Aplicar", systemImage: model.isBusy ? "xmark.circle" : "iphone.and.arrow.forward")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.isBusy && (model.devices.isEmpty || model.passcodeTheme == nil))
            }
        }
    }

    private var preview: some View {
        ZStack {
            LinearGradient(
                colors: model.passcodeVariant == .white
                    ? [Color(white: 0.16), Color(white: 0.05)]
                    : [Color(white: 0.96), Color(white: 0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            if model.passcodeKeyTiles.isEmpty {
                ContentUnavailableView {
                    Label("Sin tema", systemImage: "circle.grid.3x3")
                } description: {
                    Text("Elige un archivo .passthm para previsualizar el teclado.")
                } actions: {
                    Button("Elegir .passthm…") { model.choosePasscodeTheme() }
                }
                .foregroundStyle(model.passcodeVariant == .white ? .white : .black)
            } else {
                VStack(spacing: 18) {
                    Text("Introduce el código")
                        .font(.title3)
                        .foregroundStyle(model.passcodeVariant == .white ? .white : .black)
                    Grid(horizontalSpacing: 22, verticalSpacing: 16) {
                        ForEach(0..<4, id: \.self) { row in
                            GridRow {
                                ForEach(0..<3, id: \.self) { column in
                                    keyTile(model.passcodeKeyTiles[row * 3 + column])
                                }
                            }
                        }
                    }
                }
                .padding(30)
            }
        }
    }

    private func keyTile(_ tile: PasscodeKeyTile) -> some View {
        Group {
            if let image = tile.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Circle()
                    .strokeBorder(.gray.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3]))
                    .overlay { Text(tile.key).font(.caption).foregroundStyle(.gray) }
            }
        }
        .frame(width: 72, height: 72)
        .help(tile.image == nil ? "El tema no trae la tecla \(tile.key)" : "Tecla \(tile.key)")
    }

    private var settings: some View {
        Form {
            Section("Estilo") {
                Picker("Variante", selection: $model.passcodeVariant) {
                    ForEach(PasscodeVariant.allCases) { variant in
                        Text(variant.label).tag(variant)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: model.passcodeVariant) { _, _ in model.recolorPasscodePreview() }
                Toggle("Texto en negrita", isOn: $model.passcodeBold)
                    .onChange(of: model.passcodeBold) { _, _ in model.recolorPasscodePreview() }
            }
            Section {
                Picker("Idioma del teclado", selection: $model.passcodeLanguage) {
                    ForEach(PasscodeLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
                .onChange(of: model.passcodeLanguage) { _, _ in model.recolorPasscodePreview() }
                Picker("Caché", selection: $model.passcodeTargetVersion) {
                    Text(model.passcodeAutoCacheLabel).tag(PasscodeCache.auto)
                    ForEach(PasscodeCache.versions, id: \.self) { version in
                        Text(version).tag(version)
                    }
                }
                .onChange(of: model.passcodeTargetVersion) { _, _ in model.recolorPasscodePreview() }
            } header: {
                Text("iPhone")
            } footer: {
                Text("Usa el idioma del teclado del iPhone. Auto elige la caché según la versión de iOS: 18+ → 10, 16–17 → 9, anteriores → 8.")
            }
            if !model.passcodePlannedFiles.isEmpty {
                Section("\(model.passcodePlannedFiles.count) archivos en \(model.passcodeResolvedCache)") {
                    ScrollView {
                        Text(model.passcodePlannedFiles.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 160)
                }
            }
            Section {
                Label("Después de aplicar, bloquea el iPhone para que TelephonyUI recargue la caché.", systemImage: "lock.iphone")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
