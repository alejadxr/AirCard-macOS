import Foundation

struct SkinColor: Codable, Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    static let white = SkinColor(red: 1, green: 1, blue: 1)
    static let black = SkinColor(red: 0, green: 0, blue: 0)

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    var floats: [Float] { [Float(red), Float(green), Float(blue), Float(alpha)] }
}

struct GradientStop: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var color: SkinColor
    var location: Double
}

enum SkinBlendMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal, multiply, screen, overlay, softLight, hardLight
    case colorDodge, colorBurn, add, darken, lighten, difference
    case hue, saturation, color, luminosity

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .multiply: return "Multiplicar"
        case .screen: return "Trama"
        case .overlay: return "Superponer"
        case .softLight: return "Luz suave"
        case .hardLight: return "Luz fuerte"
        case .colorDodge: return "Sobreexponer color"
        case .colorBurn: return "Subexponer color"
        case .add: return "Sumar"
        case .darken: return "Oscurecer"
        case .lighten: return "Aclarar"
        case .difference: return "Diferencia"
        case .hue: return "Tono"
        case .saturation: return "Saturación"
        case .color: return "Color"
        case .luminosity: return "Luminosidad"
        }
    }

    var filterName: String {
        switch self {
        case .normal: return "CISourceOverCompositing"
        case .multiply: return "CIMultiplyBlendMode"
        case .screen: return "CIScreenBlendMode"
        case .overlay: return "CIOverlayBlendMode"
        case .softLight: return "CISoftLightBlendMode"
        case .hardLight: return "CIHardLightBlendMode"
        case .colorDodge: return "CIColorDodgeBlendMode"
        case .colorBurn: return "CIColorBurnBlendMode"
        case .add: return "CIAdditionCompositing"
        case .darken: return "CIDarkenBlendMode"
        case .lighten: return "CILightenBlendMode"
        case .difference: return "CIDifferenceBlendMode"
        case .hue: return "CIHueBlendMode"
        case .saturation: return "CISaturationBlendMode"
        case .color: return "CIColorBlendMode"
        case .luminosity: return "CILuminosityBlendMode"
        }
    }
}

enum ImageFit: String, Codable, CaseIterable, Identifiable, Sendable {
    case fitBlurred, fill, fit, stretch

    var id: String { rawValue }
    var label: String {
        switch self {
        case .fitBlurred: return "Ajustar con fondo difuminado"
        case .fill: return "Rellenar"
        case .fit: return "Ajustar"
        case .stretch: return "Estirar"
        }
    }
}

enum PatternStyle: Int, Codable, CaseIterable, Identifiable, Sendable {
    case lines, dots, grid, carbon, guilloche, waves

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .lines: return "Líneas"
        case .dots: return "Puntos"
        case .grid: return "Cuadrícula"
        case .carbon: return "Fibra de carbono"
        case .guilloche: return "Guilloché"
        case .waves: return "Ondas"
        }
    }
}

struct ImageLayerStyle: Codable, Equatable, Sendable {
    var assetID: UUID
    var fit: ImageFit = .fitBlurred
    var scale: Double = 1
    var offsetX: Double = 0
    var offsetY: Double = 0
    var blur: Double = 0
}

struct LinearGradientStyle: Codable, Equatable, Sendable {
    var stops: [GradientStop]
    var angle: Double = 135
}

struct RadialGradientStyle: Codable, Equatable, Sendable {
    var stops: [GradientStop]
    var centerX: Double = 0.5
    var centerY: Double = 0.5
    var radius: Double = 0.8
}

struct ConicGradientStyle: Codable, Equatable, Sendable {
    var stops: [GradientStop]
    var centerX: Double = 0.5
    var centerY: Double = 0.5
    var angle: Double = 0
}

struct MeshGradientStyle: Codable, Equatable, Sendable {
    var colors: [SkinColor]
    var warp: Double = 0.35
    var seed: Double = 1
}

struct HolographicStyle: Codable, Equatable, Sendable {
    var scale: Double = 1.4
    var angle: Double = 35
    var turbulence: Double = 0.6
    var sparkle: Double = 0.4
    var seed: Double = 3
}

struct MetalStyle: Codable, Equatable, Sendable {
    var tint: SkinColor
    var angle: Double = 0
    var grain: Double = 0.5
    var sheen: Double = 0.45
}

struct SheenStyle: Codable, Equatable, Sendable {
    var color: SkinColor = .white
    var angle: Double = 120
    var position: Double = 0.4
    var width: Double = 0.22
}

struct GrainStyle: Codable, Equatable, Sendable {
    var size: Double = 1.5
    var monochrome: Bool = true
    var seed: Double = 7
}

struct PatternLayerStyle: Codable, Equatable, Sendable {
    var style: PatternStyle
    var color: SkinColor
    var spacing: Double = 24
    var thickness: Double = 0.18
    var angle: Double = 45
}

struct TextLayerStyle: Codable, Equatable, Sendable {
    var text: String
    var fontName: String = "SFProDisplay-Semibold"
    var size: Double = 64
    var color: SkinColor = .white
    var x: Double = 0.07
    var y: Double = 0.12
    var tracking: Double = 0
}

enum SkinLayerContent: Codable, Equatable, Sendable {
    case solid(SkinColor)
    case image(ImageLayerStyle)
    case linearGradient(LinearGradientStyle)
    case radialGradient(RadialGradientStyle)
    case conicGradient(ConicGradientStyle)
    case meshGradient(MeshGradientStyle)
    case holographic(HolographicStyle)
    case brushedMetal(MetalStyle)
    case sheen(SheenStyle)
    case grain(GrainStyle)
    case pattern(PatternLayerStyle)
    case text(TextLayerStyle)

    var kindLabel: String {
        switch self {
        case .solid: return "Color"
        case .image: return "Imagen"
        case .linearGradient: return "Degradado lineal"
        case .radialGradient: return "Degradado radial"
        case .conicGradient: return "Degradado cónico"
        case .meshGradient: return "Mesh gradient"
        case .holographic: return "Holográfico"
        case .brushedMetal: return "Metal cepillado"
        case .sheen: return "Brillo"
        case .grain: return "Grano"
        case .pattern: return "Patrón"
        case .text: return "Texto"
        }
    }

    var symbol: String {
        switch self {
        case .solid: return "square.fill"
        case .image: return "photo"
        case .linearGradient: return "square.bottomhalf.filled"
        case .radialGradient: return "circle.dotted.circle"
        case .conicGradient: return "circle.lefthalf.striped.horizontal"
        case .meshGradient: return "circle.hexagongrid.fill"
        case .holographic: return "rainbow"
        case .brushedMetal: return "rectangle.pattern.checkered"
        case .sheen: return "light.max"
        case .grain: return "circle.grid.3x3.fill"
        case .pattern: return "square.grid.3x3"
        case .text: return "textformat"
        }
    }

    var usesTilt: Bool {
        switch self {
        case .holographic, .brushedMetal, .sheen: return true
        default: return false
        }
    }
}

struct SkinLayer: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var isVisible = true
    var opacity: Double = 1
    var blend: SkinBlendMode = .normal
    var content: SkinLayerContent
}

struct SkinAdjustments: Codable, Equatable, Sendable {
    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var hue: Double = 0
    var vignette: Double = 0
    var blur: Double = 0
    var bloom: Double = 0
    var sharpen: Double = 0

    var isIdentity: Bool { self == SkinAdjustments() }
}

struct SkinDocument: Codable, Equatable, Sendable {
    static let fileExtension = "aircardskin"
    static let canvasSize = CGSize(width: 1_536, height: 969)
    static let canvas2xSize = CGSize(width: 1_024, height: 646)

    var name: String = "Sin título"
    var layers: [SkinLayer] = []
    var adjustments = SkinAdjustments()
    var tilt: Double = 0.5
    var assets: [UUID: Data] = [:]

    var hasVisibleContent: Bool { layers.contains { $0.isVisible && $0.opacity > 0 } }

    mutating func garbageCollectAssets() {
        let used = Set(layers.compactMap { layer -> UUID? in
            if case .image(let style) = layer.content { return style.assetID }
            return nil
        })
        assets = assets.filter { used.contains($0.key) }
    }
}

extension SkinLayerContent {
    static func defaultContent(for kind: SkinLayerKind) -> SkinLayerContent {
        switch kind {
        case .solid:
            return .solid(SkinColor(hex: 0x1C1C1E))
        case .linearGradient:
            return .linearGradient(LinearGradientStyle(stops: [
                GradientStop(color: SkinColor(hex: 0x5E5CE6), location: 0),
                GradientStop(color: SkinColor(hex: 0xFF375F), location: 1)
            ]))
        case .radialGradient:
            return .radialGradient(RadialGradientStyle(stops: [
                GradientStop(color: SkinColor(hex: 0xFFFFFF, alpha: 0.55), location: 0),
                GradientStop(color: SkinColor(hex: 0xFFFFFF, alpha: 0), location: 1)
            ], centerX: 0.25, centerY: 0.2, radius: 0.7))
        case .conicGradient:
            return .conicGradient(ConicGradientStyle(stops: [
                GradientStop(color: SkinColor(hex: 0xFF9F0A), location: 0),
                GradientStop(color: SkinColor(hex: 0xBF5AF2), location: 0.5),
                GradientStop(color: SkinColor(hex: 0xFF9F0A), location: 1)
            ]))
        case .meshGradient:
            return .meshGradient(MeshGradientStyle(colors: SkinPalette.aurora))
        case .holographic:
            return .holographic(HolographicStyle())
        case .brushedMetal:
            return .brushedMetal(MetalStyle(tint: SkinColor(hex: 0x8E8E93)))
        case .sheen:
            return .sheen(SheenStyle())
        case .grain:
            return .grain(GrainStyle())
        case .pattern:
            return .pattern(PatternLayerStyle(style: .guilloche, color: SkinColor(hex: 0xFFFFFF, alpha: 0.35)))
        case .text:
            return .text(TextLayerStyle(text: "AirCard"))
        }
    }
}

enum SkinLayerKind: String, CaseIterable, Identifiable, Sendable {
    case solid, linearGradient, radialGradient, conicGradient, meshGradient
    case holographic, brushedMetal, sheen, grain, pattern, text

    var id: String { rawValue }

    var defaultLayer: SkinLayer {
        let content = SkinLayerContent.defaultContent(for: self)
        var layer = SkinLayer(name: content.kindLabel, content: content)
        switch self {
        case .holographic:
            layer.blend = .overlay
            layer.opacity = 0.7
        case .sheen:
            layer.blend = .screen
            layer.opacity = 0.6
        case .grain:
            layer.blend = .overlay
            layer.opacity = 0.18
        case .radialGradient:
            layer.blend = .softLight
        default:
            break
        }
        return layer
    }
}

enum SkinPalette {
    static let aurora: [SkinColor] = [
        SkinColor(hex: 0x0B1026), SkinColor(hex: 0x1B2A6B), SkinColor(hex: 0x0E3B43),
        SkinColor(hex: 0x3A1C71), SkinColor(hex: 0x1FD1A5), SkinColor(hex: 0x2B5876),
        SkinColor(hex: 0xD76D77), SkinColor(hex: 0x6A3093), SkinColor(hex: 0x0B1026)
    ]
}
