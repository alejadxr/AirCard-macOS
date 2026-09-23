import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AirCard macOS")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("Wallet card skin · Swift Concurrency · v0.3.0")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Actualizar dispositivos") { model.refreshDevices() }
                    .disabled(model.isBusy)
            }

            GroupBox("1. iPhone") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Picker("Dispositivo", selection: $model.selectedDeviceID) {
                            Text("Seleccionar…").tag("")
                            ForEach(model.devices) { device in
                                Text(device.summary).tag(device.id)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .onChange(of: model.selectedDeviceID) { _, _ in
                            model.recolorPasscodePreview()
                        }
                        if model.devices.isEmpty {
                            Text("Sin dispositivo")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let device = model.selectedDevice {
                        Label(device.compatibilityNote, systemImage: device.isDetectionTested ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(device.isDetectionTested ? .green : .orange)
                    }
                }
            }

            GroupBox("2. Tarjeta") {
                CardPickerView(model: model)
            }

            GroupBox("3. Artwork") {
                HStack(spacing: 16) {
                    VStack(spacing: 6) {
                        if let image = model.artworkPreview {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 280, height: 176)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.quaternary)
                                .frame(width: 280, height: 176)
                                .overlay { Text("Sin imagen") .foregroundStyle(.secondary) }
                        }
                        Label(
                            model.isCardHashValid ? "Para: \(model.targetCardLabel)" : "Aún no hay tarjeta vinculada",
                            systemImage: model.isCardHashValid ? "link" : "link.badge.plus"
                        )
                        .font(.caption)
                        .foregroundStyle(model.isCardHashValid ? Color.accentColor : .secondary)
                        .lineLimit(1)
                    }
                    .overlay(alignment: .bottom) {
                        if model.artwork != nil {
                            Text("Así se escribirá · 1536 × 969")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.thinMaterial, in: Capsule())
                                .padding(6)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button("Elegir imagen…") { model.chooseArtwork() }
                            Button("Descargar assets…") { model.exportArtwork() }
                                .disabled(model.isBusy || model.artwork == nil)
                                .help("Guarda los 11 archivos (PNG 3x/2x y PDF) que se escriben en la tarjeta.")
                        }
                        Text(model.imageName.isEmpty ? "PNG, JPG o WebP" : model.imageName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Se ajusta al lienzo conservando los bordes y se genera el PNG/PDF que espera Wallet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Divider()
                        HStack {
                            Text("Overlays PNG")
                                .font(.headline)
                            Spacer()
                            Button("Añadir PNG…") { model.chooseOverlays() }
                                .disabled(model.isBusy || model.artwork == nil)
                        }
                        if model.overlays.isEmpty {
                            Text("Puedes añadir uno o varios PNG transparentes. Se combinan en el orden mostrado.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(model.overlays) { overlay in
                                    HStack(spacing: 8) {
                                        Image(systemName: "square.3.layers.3d")
                                            .foregroundStyle(.blue)
                                        Text(overlay.name)
                                            .lineLimit(1)
                                        Spacer()
                                        Button {
                                            model.moveOverlayUp(overlay)
                                        } label: {
                                            Image(systemName: "chevron.up")
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(model.isBusy || model.overlays.first?.id == overlay.id)
                                        Button {
                                            model.moveOverlayDown(overlay)
                                        } label: {
                                            Image(systemName: "chevron.down")
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(model.isBusy || model.overlays.last?.id == overlay.id)
                                        Button(role: .destructive) {
                                            model.removeOverlay(overlay)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(model.isBusy)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        Text("El PNG se escala al lienzo de la tarjeta conservando transparencia y proporción.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Se escriben las variantes canónicas 3x, 2x y PDF que usan Wallet: cardBackgroundCombined, diffuse, background y strip. No necesitas un .passthm.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Antes de aplicar: iPhone desbloqueado y Apple Books abierto al menos una vez.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            HStack {
                Button(model.isBusy ? "Cancelar" : "Aplicar skin a «\(model.targetCardLabel)»") {
                    model.isBusy ? model.cancel() : model.flashSkin()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.isBusy && (model.selectedDeviceID.isEmpty || !model.isCardHashValid || model.artwork == nil))
                Text(model.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            GroupBox("5. Teclado de código (opcional)") {
                HStack(spacing: 16) {
                    Group {
                        if !model.passcodeKeyTiles.isEmpty {
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 6), count: 3), spacing: 6) {
                                ForEach(model.passcodeKeyTiles) { tile in
                                    Group {
                                        if let image = tile.image {
                                            Image(nsImage: image)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                        } else {
                                            Circle()
                                                .strokeBorder(.gray.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3]))
                                                .overlay { Text(tile.key).font(.caption2).foregroundStyle(.gray) }
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                                    .help(tile.image == nil ? "El tema no trae la tecla \(tile.key)" : "Tecla \(tile.key)")
                                }
                            }
                            .padding(10)
                            .background(
                                model.passcodeVariant == .white ? Color.black.opacity(0.85) : Color.white,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(.quaternary, lineWidth: 1)
                            }
                        } else if let image = model.passcodePreview {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 150, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(.quaternary, lineWidth: 1)
                                }
                        } else {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.quaternary)
                                .frame(width: 150, height: 100)
                                .overlay { Text("Sin tema").foregroundStyle(.secondary) }
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Button("Elegir .passthm…") { model.choosePasscodeTheme() }
                            Text(model.passcodeThemeName.isEmpty ? "Tema de teclado" : model.passcodeThemeName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 14) {
                            Picker("Variante", selection: $model.passcodeVariant) {
                                ForEach(PasscodeVariant.allCases) { variant in
                                    Text(variant.label).tag(variant)
                                }
                            }
                            .frame(width: 170)
                            .onChange(of: model.passcodeVariant) { _, _ in
                                model.recolorPasscodePreview()
                            }
                            Picker("Caché", selection: $model.passcodeTargetVersion) {
                                Text(model.passcodeAutoCacheLabel).tag(PasscodeCache.auto)
                                ForEach(PasscodeCache.versions, id: \.self) { version in
                                    Text(version).tag(version)
                                }
                            }
                            .frame(width: 230)
                            .onChange(of: model.passcodeTargetVersion) { _, _ in
                                model.recolorPasscodePreview()
                            }
                        }
                        HStack(spacing: 14) {
                            Picker("Idioma", selection: $model.passcodeLanguage) {
                                ForEach(PasscodeLanguage.allCases) { language in
                                    Text(language.label).tag(language)
                                }
                            }
                            .frame(width: 250)
                            .onChange(of: model.passcodeLanguage) { _, _ in
                                model.recolorPasscodePreview()
                            }
                            Toggle("Texto en negrita", isOn: $model.passcodeBold)
                                .onChange(of: model.passcodeBold) { _, _ in
                                    model.recolorPasscodePreview()
                                }
                        }
                        Text("Elige el sufijo que probará iOS (--white o --black) y el idioma del teclado del iPhone. Negrita añade -bold. Auto elige la caché según la versión de iOS.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !model.passcodePlannedFiles.isEmpty {
                            DisclosureGroup("\(model.passcodePlannedFiles.count) archivos a escribir en \(model.passcodeResolvedCache)") {
                                ScrollView {
                                    Text(model.passcodePlannedFiles.joined(separator: "\n"))
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                                .frame(height: 90)
                            }
                            .font(.caption)
                        }
                        HStack {
                            Button("Aplicar color al teclado") { model.flashPasscodeTheme() }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isBusy || model.devices.isEmpty || model.passcodeTheme == nil)
                            Button("Descargar .passthm…") { model.exportPasscodeTheme() }
                                .disabled(model.isBusy || model.passcodeTheme == nil)
                                .help("Guarda las teclas recoloreadas con los nombres exactos que se escribirán.")
                        }
                    }
                }
            }

            DisclosureGroup("Registro") {
                ScrollView {
                    Text(model.logs.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 120)
            }
        }
        .padding(24)
        }
        .frame(minWidth: 780, minHeight: 720)
    }
}

private struct CardPickerView: View {
    @ObservedObject var model: AppModel
    @State private var renaming: WalletCard?
    @State private var renameText = ""
    @State private var showManualEntry = false

    private var sortedCards: [WalletCard] {
        model.cards.sorted { $0.lastSeen > $1.lastSeen }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    model.toggleScan()
                } label: {
                    Label(
                        model.isScanning ? "Detener detección" : "Detectar desde Wallet",
                        systemImage: model.isScanning ? "stop.circle.fill" : "wave.3.right.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isScanning ? .red : .accentColor)
                .disabled(model.devices.isEmpty || model.isBusy)

                Toggle("Seguir la última tarjeta que abra", isOn: $model.followLatestCard)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
            }

            if model.isScanning {
                HStack(alignment: .top, spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Escuchando el iPhone…")
                            .font(.callout.weight(.semibold))
                        Text("1. Abre Wallet  ·  2. Toca la tarjeta que quieres personalizar  ·  3. Se vinculará aquí sola")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(model.scanLineCount) líneas de syslog · \(model.walletEventCount) eventos de Wallet")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if sortedCards.isEmpty {
                Text("Todavía no hay tarjetas. Pulsa “Detectar desde Wallet” y abre la tarjeta en el iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(sortedCards) { card in
                        cardRow(card)
                    }
                }
            }

            DisclosureGroup("Pegar hash manualmente", isExpanded: $showManualEntry) {
                HStack {
                    TextField("Hash de la tarjeta (Base64)", text: $model.cardHash)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    if !model.cardHash.isEmpty {
                        Image(systemName: model.isCardHashValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(model.isCardHashValid ? .green : .red)
                            .help(model.isCardHashValid ? "Hash válido" : "No parece un hash de Wallet (SHA-1/SHA-256 en Base64)")
                    }
                    Button("Guardar") { model.saveManualCard() }
                        .disabled(!model.isCardHashValid || model.selectedCard != nil)
                }
                .padding(.top, 4)
            }
            .font(.caption)
        }
        .alert("Renombrar tarjeta", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Nombre", text: $renameText)
            Button("Guardar") {
                if let card = renaming { model.renameCard(card, to: renameText) }
                renaming = nil
            }
            Button("Cancelar", role: .cancel) { renaming = nil }
        }
    }

    private func cardRow(_ card: WalletCard) -> some View {
        let isSelected = model.selectedCard?.hash == card.hash
        let isLatest = model.isScanning && model.lastDetectedHash == card.hash
        return HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .font(.title3)
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 34, height: 22)
                .overlay { Image(systemName: "creditcard.fill").font(.caption2).foregroundStyle(.white) }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(card.name).fontWeight(isSelected ? .semibold : .regular)
                    if isLatest {
                        Text("RECIÉN ABIERTA")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.2), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                HStack(spacing: 6) {
                    Text(card.shortHash).font(.caption.monospaced())
                    Text("·")
                    Text(card.lastSeen, style: .relative) + Text(" atrás")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Usar esta tarjeta") { model.selectCard(card) }
                Button("Renombrar…") {
                    renameText = card.name
                    renaming = card
                }
                Button("Copiar hash") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(card.hash, forType: .string)
                }
                Divider()
                Button("Olvidar", role: .destructive) { model.forgetCard(card) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.selectCard(card) }
        .help(card.hash)
    }
}
