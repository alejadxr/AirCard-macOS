import SwiftUI
import UniformTypeIdentifiers

struct StudioView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var studio: StudioModel

    var body: some View {
        VStack(spacing: 0) {
            CardCanvas(studio: studio)
            Divider()
            PresetStrip(studio: studio)
        }
        .inspector(isPresented: $studio.showInspector) {
            StudioInspector(studio: studio)
                .inspectorColumnWidth(min: 300, ideal: 330, max: 420)
        }
        .navigationTitle(studio.document.name)
        .navigationSubtitle(studio.isDirty ? "Editado" : "")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { studio.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("Deshacer")
                    .disabled(!studio.canUndo)
                Button { studio.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .help("Rehacer")
                    .disabled(!studio.canRedo)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Nuevo diseño") { studio.newDocument() }
                    Button("Abrir .\(SkinDocument.fileExtension)…") { studio.open() }
                    Divider()
                    Button("Guardar") { studio.save() }
                    Button("Guardar como…") { studio.save(as: true) }
                    Divider()
                    Button("Descargar assets…") { model.exportStudioAssets() }
                } label: {
                    Label("Archivo", systemImage: "doc")
                }
                .help("Abrir, guardar o descargar el diseño")

                Button { studio.importPhoto() } label: {
                    Label("Añadir imagen", systemImage: "photo.badge.plus")
                }
                .help("Añadir una imagen como capa")

                TargetCardMenu(model: model)

                Button {
                    model.isBusy ? model.cancel() : model.flashSkin()
                } label: {
                    Label(model.isBusy ? "Cancelar" : "Aplicar", systemImage: model.isBusy ? "xmark.circle" : "iphone.and.arrow.forward")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.isBusy && (model.selectedDeviceID.isEmpty || !model.isCardHashValid))
                .help(model.isCardHashValid ? "Escribir el diseño en «\(model.targetCardLabel)»" : "Primero elige una tarjeta en la barra lateral")

                Button {
                    studio.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help("Mostrar u ocultar el inspector")
            }
        }
        .alert("No se pudo completar", isPresented: Binding(
            get: { studio.errorMessage != nil },
            set: { if !$0 { studio.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { studio.errorMessage = nil }
        } message: {
            Text(studio.errorMessage ?? "")
        }
    }
}

private struct TargetCardMenu: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Menu {
            if model.cards.isEmpty {
                Text("Sin tarjetas: usa «Detectar desde Wallet»")
            }
            ForEach(model.cards.sorted { $0.lastSeen > $1.lastSeen }) { card in
                Button {
                    model.selectCard(card)
                } label: {
                    if model.selectedCard?.hash == card.hash {
                        Label(card.name, systemImage: "checkmark")
                    } else {
                        Text(card.name)
                    }
                }
            }
        } label: {
            Label(model.isCardHashValid ? model.targetCardLabel : "Elegir tarjeta", systemImage: "creditcard")
                .labelStyle(.titleAndIcon)
        }
        .help("Tarjeta destino")
    }
}

struct CardCanvas: View {
    @ObservedObject var studio: StudioModel
    @State private var rotation = CGSize.zero
    @State private var isDragging = false
    @State private var isDropTarget = false

    private let aspect = SkinDocument.canvasSize.width / SkinDocument.canvasSize.height

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width - 96, (geometry.size.height - 120) * aspect, 980)
            let height = width / aspect
            ZStack {
                backdrop
                VStack(spacing: 22) {
                    card(width: max(width, 200), height: max(height, 126))
                    controls
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in studio.addPhoto(url: url) }
                }
            }
            return true
        }
    }

    private var backdrop: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            RadialGradient(
                colors: [Color.accentColor.opacity(0.12), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 700
            )
            if isDropTarget {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .padding(18)
            }
        }
    }

    private func card(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            if let preview = studio.preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                ProgressView()
            }
            if studio.showSafeZones {
                SafeZonesOverlay()
            }
            LinearGradient(
                colors: [.white.opacity(isDragging ? 0.18 : 0.08), .clear, .black.opacity(0.08)],
                startPoint: UnitPoint(x: 0.5 - rotation.width / 40, y: 0),
                endPoint: UnitPoint(x: 0.5 + rotation.width / 40, y: 1)
            )
            .blendMode(.softLight)
            .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
        .clipShape(CardShape())
        .overlay(CardShape().stroke(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 28, x: -rotation.width * 0.8, y: 20 + rotation.height * 0.6)
        .rotation3DEffect(.degrees(rotation.height), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
        .rotation3DEffect(.degrees(-rotation.width), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        .scaleEffect(isDragging ? 1.015 : 1)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    let x = max(-1, min(1, value.translation.width / (width * 0.6)))
                    let y = max(-1, min(1, value.translation.height / (height * 0.6)))
                    rotation = CGSize(width: -x * 14, height: -y * 10)
                    studio.setLiveTilt(studio.document.tilt + Double(x) * 0.5)
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        rotation = .zero
                        isDragging = false
                    }
                    studio.setLiveTilt(nil)
                }
        )
        .help("Arrastra la tarjeta para inclinarla y ver cómo se mueven los reflejos")
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Label {
                Slider(
                    value: Binding(get: { studio.document.tilt }, set: { studio.document.tilt = $0 }),
                    in: 0...1
                )
                .frame(width: 180)
            } icon: {
                Image(systemName: "gyroscope")
            }
            .help("Inclinación con la que se exportan los reflejos")

            Toggle(isOn: $studio.showSafeZones) {
                Label("Zonas de Wallet", systemImage: "rectangle.dashed")
            }
            .toggleStyle(.button)
            .help("Muestra la franja visible en la pila de Wallet y las esquinas")

            Text(studio.usesTilt ? "Arrastra la tarjeta para ver los reflejos" : "1536 × 969 · PNG 3x/2x + PDF")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
    }
}

private struct SafeZonesOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let stackHeight = geometry.size.height * 0.2
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.black.opacity(0.25))
                    .frame(height: geometry.size.height - stackHeight)
                    .offset(y: stackHeight)
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(height: stackHeight)
                Text("Visible en la pila de Wallet (aprox.)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.35), in: Capsule())
                    .offset(y: stackHeight + 6)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .allowsHitTesting(false)
    }
}

private struct PresetStrip: View {
    @ObservedObject var studio: StudioModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(SkinPresets.all) { preset in
                    Button {
                        studio.applyPreset(preset)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Group {
                                if let image = studio.presetThumbnails[preset.id] {
                                    Image(decorative: image, scale: 1)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else {
                                    Rectangle().fill(.quaternary)
                                }
                            }
                            .frame(width: 128, height: 81)
                            .clipShape(CardShape())
                            .overlay(CardShape().stroke(.white.opacity(0.15), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                            Text(preset.name)
                                .font(.caption.weight(.semibold))
                            Text(preset.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 128, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .help(studio.hasPhoto ? "Aplicar \(preset.name) conservando tu foto cuando el estilo la usa" : "Aplicar \(preset.name)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(.bar)
    }
}
