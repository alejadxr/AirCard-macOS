import SwiftUI

struct StudioInspector: View {
    @ObservedObject var studio: StudioModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $studio.inspectorTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            switch studio.inspectorTab {
            case .layers:
                LayerListView(studio: studio)
                Divider()
                if let id = studio.selectedLayerID, let binding = studio.layerBinding(id) {
                    LayerEditor(layer: binding)
                        .id(id)
                } else {
                    ContentUnavailableView("Sin capa", systemImage: "square.3.layers.3d", description: Text("Selecciona o añade una capa."))
                        .frame(maxHeight: .infinity)
                }
            case .adjustments:
                AdjustmentsEditor(adjustments: $studio.document.adjustments, tilt: $studio.document.tilt)
            }
        }
        .frame(minWidth: 300)
    }
}

struct LayerListView: View {
    @ObservedObject var studio: StudioModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $studio.selectedLayerID) {
                ForEach(studio.document.layers.reversed()) { layer in
                    LayerRow(layer: layer) { studio.toggleVisibility(layer.id) }
                        .tag(layer.id)
                        .contextMenu {
                            Button("Duplicar") { studio.duplicateLayer(layer.id) }
                            Button(layer.isVisible ? "Ocultar" : "Mostrar") { studio.toggleVisibility(layer.id) }
                            Divider()
                            Button("Eliminar", role: .destructive) { studio.removeLayer(layer.id) }
                        }
                }
                .onMove { studio.moveLayers(fromDisplay: $0, toDisplay: $1) }
            }
            .listStyle(.inset)
            .frame(height: 210)

            HStack(spacing: 2) {
                Menu {
                    Button {
                        studio.importPhoto()
                    } label: {
                        Label("Imagen…", systemImage: "photo")
                    }
                    Divider()
                    ForEach(SkinLayerKind.allCases) { kind in
                        let content = SkinLayerContent.defaultContent(for: kind)
                        Button {
                            studio.addLayer(kind)
                        } label: {
                            Label(content.kindLabel, systemImage: content.symbol)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuIndicator(.hidden)
                .help("Añadir capa")

                Button {
                    if let id = studio.selectedLayerID { studio.removeLayer(id) }
                } label: {
                    Image(systemName: "minus")
                }
                .help("Eliminar capa")
                .disabled(studio.selectedLayerID == nil)

                Button {
                    if let id = studio.selectedLayerID { studio.duplicateLayer(id) }
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .help("Duplicar capa")
                .disabled(studio.selectedLayerID == nil)

                Spacer()

                Button { studio.moveSelected(up: true) } label: { Image(systemName: "arrow.up") }
                    .help("Subir capa")
                Button { studio.moveSelected(up: false) } label: { Image(systemName: "arrow.down") }
                    .help("Bajar capa")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

private struct LayerRow: View {
    let layer: SkinLayer
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: layer.content.symbol)
                .frame(width: 18)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(layer.name).lineLimit(1)
                Text("\(layer.content.kindLabel) · \(layer.blend.label) · \(PercentFormat.percent(layer.opacity))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: toggle) {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(layer.isVisible ? .secondary : .tertiary)
            }
            .buttonStyle(.borderless)
        }
        .opacity(layer.isVisible ? 1 : 0.55)
    }
}

struct LayerEditor: View {
    @Binding var layer: SkinLayer

    var body: some View {
        Form {
            Section("Capa") {
                TextField("Nombre", text: $layer.name)
                SliderRow(title: "Opacidad", value: $layer.opacity, range: 0...1, format: PercentFormat.percent)
                Picker("Mezcla", selection: $layer.blend) {
                    ForEach(SkinBlendMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }
            contentSections
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var contentSections: some View {
        switch layer.content {
        case .solid:
            Section("Color") {
                ColorRow(title: "Color", color: binding(\.solid, SkinLayerContent.solid, default: .black))
            }
        case .image:
            ImageSection(style: binding(\.image, SkinLayerContent.image, default: ImageLayerStyle(assetID: UUID())))
        case .linearGradient:
            let style = binding(\.linear, SkinLayerContent.linearGradient, default: LinearGradientStyle(stops: []))
            Section("Degradado lineal") {
                GradientStopsEditor(stops: style.stops)
                SliderRow(title: "Ángulo", value: style.angle, range: 0...360, format: PercentFormat.degrees)
            }
        case .radialGradient:
            let style = binding(\.radial, SkinLayerContent.radialGradient, default: RadialGradientStyle(stops: []))
            Section("Degradado radial") {
                GradientStopsEditor(stops: style.stops)
                SliderRow(title: "Centro X", value: style.centerX, range: -0.5...1.5, format: PercentFormat.percent)
                SliderRow(title: "Centro Y", value: style.centerY, range: -0.5...1.5, format: PercentFormat.percent)
                SliderRow(title: "Radio", value: style.radius, range: 0.05...2, format: PercentFormat.percent)
            }
        case .conicGradient:
            let style = binding(\.conic, SkinLayerContent.conicGradient, default: ConicGradientStyle(stops: []))
            Section("Degradado cónico") {
                GradientStopsEditor(stops: style.stops)
                SliderRow(title: "Centro X", value: style.centerX, range: 0...1, format: PercentFormat.percent)
                SliderRow(title: "Centro Y", value: style.centerY, range: 0...1, format: PercentFormat.percent)
                SliderRow(title: "Rotación", value: style.angle, range: 0...360, format: PercentFormat.degrees)
            }
        case .meshGradient:
            MeshSection(style: binding(\.mesh, SkinLayerContent.meshGradient, default: MeshGradientStyle(colors: SkinPalette.aurora)))
        case .holographic:
            let style = binding(\.holo, SkinLayerContent.holographic, default: HolographicStyle())
            Section("Holográfico") {
                SliderRow(title: "Escala", value: style.scale, range: 0.2...4)
                SliderRow(title: "Ángulo", value: style.angle, range: 0...360, format: PercentFormat.degrees)
                SliderRow(title: "Turbulencia", value: style.turbulence, range: 0...2)
                SliderRow(title: "Destellos", value: style.sparkle, range: 0...1, format: PercentFormat.percent)
                SeedRow(seed: style.seed)
            }
        case .brushedMetal:
            let style = binding(\.metal, SkinLayerContent.brushedMetal, default: MetalStyle(tint: .white))
            Section("Metal cepillado") {
                ColorRow(title: "Tono", color: style.tint)
                SliderRow(title: "Dirección", value: style.angle, range: 0...180, format: PercentFormat.degrees)
                SliderRow(title: "Cepillado", value: style.grain, range: 0...1, format: PercentFormat.percent)
                SliderRow(title: "Reflejo", value: style.sheen, range: 0...1, format: PercentFormat.percent)
            }
        case .sheen:
            let style = binding(\.sheen, SkinLayerContent.sheen, default: SheenStyle())
            Section("Brillo") {
                ColorRow(title: "Color", color: style.color)
                SliderRow(title: "Ángulo", value: style.angle, range: 0...360, format: PercentFormat.degrees)
                SliderRow(title: "Posición", value: style.position, range: 0...1, format: PercentFormat.percent)
                SliderRow(title: "Ancho", value: style.width, range: 0.02...1, format: PercentFormat.percent)
            }
        case .grain:
            let style = binding(\.grain, SkinLayerContent.grain, default: GrainStyle())
            Section("Grano") {
                SliderRow(title: "Tamaño", value: style.size, range: 0.5...6)
                Toggle("Monocromo", isOn: style.monochrome)
                SeedRow(seed: style.seed)
            }
        case .pattern:
            let style = binding(\.pattern, SkinLayerContent.pattern, default: PatternLayerStyle(style: .lines, color: .white))
            Section("Patrón") {
                Picker("Estilo", selection: style.style) {
                    ForEach(PatternStyle.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                ColorRow(title: "Color", color: style.color)
                SliderRow(title: "Separación", value: style.spacing, range: 4...120, format: PercentFormat.points)
                SliderRow(title: "Grosor", value: style.thickness, range: 0.02...0.9, format: PercentFormat.percent)
                SliderRow(title: "Ángulo", value: style.angle, range: 0...180, format: PercentFormat.degrees)
            }
        case .text:
            TextSection(style: binding(\.text, SkinLayerContent.text, default: TextLayerStyle(text: "")))
        }
    }

    private func binding<T>(
        _ extract: KeyPath<SkinLayerContent, T?>,
        _ embed: @escaping (T) -> SkinLayerContent,
        default fallback: T
    ) -> Binding<T> {
        Binding(
            get: { layer.content[keyPath: extract] ?? fallback },
            set: { layer.content = embed($0) }
        )
    }
}

private struct SeedRow: View {
    @Binding var seed: Double

    var body: some View {
        LabeledContent("Variación") {
            Button {
                seed = Double.random(in: 0...100)
            } label: {
                Label("Aleatorio", systemImage: "dice")
            }
        }
    }
}

private struct ImageSection: View {
    @Binding var style: ImageLayerStyle

    var body: some View {
        Section("Imagen") {
            Picker("Encaje", selection: $style.fit) {
                ForEach(ImageFit.allCases) { fit in
                    Text(fit.label).tag(fit)
                }
            }
            SliderRow(title: "Escala", value: $style.scale, range: 0.2...3, format: PercentFormat.percent)
            SliderRow(title: "Desplazar X", value: $style.offsetX, range: -0.6...0.6, format: PercentFormat.percent)
            SliderRow(title: "Desplazar Y", value: $style.offsetY, range: -0.6...0.6, format: PercentFormat.percent)
            SliderRow(title: "Desenfoque", value: $style.blur, range: 0...80, format: PercentFormat.points)
            Button("Restablecer posición") {
                style.scale = 1
                style.offsetX = 0
                style.offsetY = 0
            }
        }
    }
}

private struct MeshSection: View {
    @Binding var style: MeshGradientStyle

    var body: some View {
        Section("Mesh gradient") {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(0..<3, id: \.self) { row in
                    GridRow {
                        ForEach(0..<3, id: \.self) { column in
                            let index = row * 3 + column
                            ColorPicker("", selection: Binding(
                                get: { style.colors.indices.contains(index) ? style.colors[index].swiftUIColor : .black },
                                set: { value in
                                    while style.colors.count < 9 { style.colors.append(.black) }
                                    style.colors[index] = SkinColor(value)
                                }
                            ), supportsOpacity: true)
                            .labelsHidden()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            SliderRow(title: "Ondulación", value: $style.warp, range: 0...1.2)
            LabeledContent("Variación") {
                HStack {
                    Button {
                        style.seed = Double.random(in: 0...100)
                    } label: {
                        Label("Forma", systemImage: "dice")
                    }
                    Button {
                        style.colors.shuffle()
                    } label: {
                        Label("Colores", systemImage: "shuffle")
                    }
                }
            }
        }
    }
}

private struct TextSection: View {
    @Binding var style: TextLayerStyle

    private static let fonts: [(String, String)] = [
        ("SF Pro Display Semibold", "SFProDisplay-Semibold"),
        ("SF Pro Display Bold", "SFProDisplay-Bold"),
        ("SF Pro Rounded", "SFProRounded-Semibold"),
        ("New York", "NewYorkMedium-Semibold"),
        ("Avenir Next", "AvenirNext-DemiBold"),
        ("Futura", "Futura-Medium"),
        ("Didot", "Didot-Bold"),
        ("Menlo", "Menlo-Bold")
    ]

    var body: some View {
        Section("Texto") {
            TextField("Texto", text: $style.text)
            Picker("Fuente", selection: $style.fontName) {
                ForEach(Self.fonts, id: \.1) { font in
                    Text(font.0).tag(font.1)
                }
            }
            ColorRow(title: "Color", color: $style.color)
            SliderRow(title: "Tamaño", value: $style.size, range: 12...220, format: PercentFormat.points)
            SliderRow(title: "Espaciado", value: $style.tracking, range: -4...30, format: PercentFormat.points)
            SliderRow(title: "Posición X", value: $style.x, range: 0...1, format: PercentFormat.percent)
            SliderRow(title: "Posición Y", value: $style.y, range: 0...1, format: PercentFormat.percent)
        }
    }
}

struct AdjustmentsEditor: View {
    @Binding var adjustments: SkinAdjustments
    @Binding var tilt: Double

    var body: some View {
        Form {
            Section("Color") {
                SliderRow(title: "Brillo", value: $adjustments.brightness, range: -0.5...0.5)
                SliderRow(title: "Contraste", value: $adjustments.contrast, range: 0.5...1.8)
                SliderRow(title: "Saturación", value: $adjustments.saturation, range: 0...2)
                SliderRow(title: "Tono", value: $adjustments.hue, range: -180...180, format: PercentFormat.degrees)
            }
            Section("Efectos") {
                SliderRow(title: "Viñeta", value: $adjustments.vignette, range: 0...1, format: PercentFormat.percent)
                SliderRow(title: "Bloom", value: $adjustments.bloom, range: 0...1.5)
                SliderRow(title: "Desenfoque", value: $adjustments.blur, range: 0...40, format: PercentFormat.points)
                SliderRow(title: "Nitidez", value: $adjustments.sharpen, range: 0...2)
            }
            Section {
                SliderRow(title: "Inclinación", value: $tilt, range: 0...1, format: PercentFormat.percent)
            } header: {
                Text("Reflejo exportado")
            } footer: {
                Text("Wallet recibe una imagen fija: elige en qué ángulo quedan congelados los brillos, el metal y el holográfico.")
            }
            Section {
                Button("Restablecer ajustes") { adjustments = SkinAdjustments() }
            }
        }
        .formStyle(.grouped)
    }
}

extension SkinLayerContent {
    var solid: SkinColor? { if case .solid(let v) = self { return v } else { return nil } }
    var image: ImageLayerStyle? { if case .image(let v) = self { return v } else { return nil } }
    var linear: LinearGradientStyle? { if case .linearGradient(let v) = self { return v } else { return nil } }
    var radial: RadialGradientStyle? { if case .radialGradient(let v) = self { return v } else { return nil } }
    var conic: ConicGradientStyle? { if case .conicGradient(let v) = self { return v } else { return nil } }
    var mesh: MeshGradientStyle? { if case .meshGradient(let v) = self { return v } else { return nil } }
    var holo: HolographicStyle? { if case .holographic(let v) = self { return v } else { return nil } }
    var metal: MetalStyle? { if case .brushedMetal(let v) = self { return v } else { return nil } }
    var sheen: SheenStyle? { if case .sheen(let v) = self { return v } else { return nil } }
    var grain: GrainStyle? { if case .grain(let v) = self { return v } else { return nil } }
    var pattern: PatternLayerStyle? { if case .pattern(let v) = self { return v } else { return nil } }
    var text: TextLayerStyle? { if case .text(let v) = self { return v } else { return nil } }
}
