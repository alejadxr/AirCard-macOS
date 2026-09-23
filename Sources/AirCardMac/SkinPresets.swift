import Foundation

struct SkinPreset: Identifiable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let build: @Sendable (_ photo: (UUID, Data)?) -> SkinDocument

    func document(photo: (UUID, Data)?) -> SkinDocument {
        var document = build(photo)
        document.name = name
        return document
    }
}

enum SkinPresets {
    static let all: [SkinPreset] = [titanium, holo, aurora, carbon, guilloche, frosted, sunset, noir]

    private static func stops(_ colors: [(UInt32, Double, Double)]) -> [GradientStop] {
        colors.map { GradientStop(color: SkinColor(hex: $0.0, alpha: $0.2), location: $0.1) }
    }

    private static func photoLayers(_ photo: (UUID, Data)?, blur: Double = 0) -> ([SkinLayer], [UUID: Data]) {
        guard let photo else { return ([], [:]) }
        let layer = SkinLayer(name: "Foto", content: .image(ImageLayerStyle(assetID: photo.0, fit: .fill, blur: blur)))
        return ([layer], [photo.0: photo.1])
    }

    static let titanium = SkinPreset(id: "titanium", name: "Titanio", subtitle: "Metal cepillado con reflejo") { _ in
        SkinDocument(layers: [
            SkinLayer(name: "Titanio", content: .brushedMetal(MetalStyle(tint: SkinColor(hex: 0xB9B7B2), angle: 0, grain: 0.55, sheen: 0.5))),
            SkinLayer(name: "Profundidad", blend: .multiply, content: .linearGradient(LinearGradientStyle(stops: stops([
                (0xFFFFFF, 0, 1), (0x6E6C68, 1, 1)
            ]), angle: 100))),
            SkinLayer(name: "Brillo", opacity: 0.55, blend: .screen, content: .sheen(SheenStyle(angle: 115, position: 0.45, width: 0.18))),
            SkinLayer(name: "Grano", opacity: 0.08, blend: .overlay, content: .grain(GrainStyle(size: 1.2)))
        ], adjustments: SkinAdjustments(contrast: 1.05, vignette: 0.15))
    }

    static let holo = SkinPreset(id: "holo", name: "Holo", subtitle: "Iridiscente con destellos") { photo in
        let (photo, assets) = photoLayers(photo)
        let base = photo.isEmpty
            ? [SkinLayer(name: "Base", content: .linearGradient(LinearGradientStyle(stops: stops([
                (0xC9CBD6, 0, 1), (0x7C7F93, 1, 1)
            ]), angle: 140)))]
            : photo
        return SkinDocument(layers: base + [
            SkinLayer(name: "Holográfico", opacity: 0.9, blend: .softLight, content: .holographic(HolographicStyle(scale: 1.6, angle: 30, turbulence: 0.7, sparkle: 0.6))),
            SkinLayer(name: "Brillo", opacity: 0.5, blend: .screen, content: .sheen(SheenStyle(angle: 120, position: 0.5, width: 0.25))),
            SkinLayer(name: "Grano", opacity: 0.1, blend: .overlay, content: .grain(GrainStyle(size: 1.3)))
        ], adjustments: SkinAdjustments(contrast: 1.08, saturation: 1.25), assets: assets)
    }

    static let aurora = SkinPreset(id: "aurora", name: "Aurora", subtitle: "Mesh gradient orgánico") { _ in
        SkinDocument(layers: [
            SkinLayer(name: "Aurora", content: .meshGradient(MeshGradientStyle(colors: SkinPalette.aurora, warp: 0.45, seed: 2))),
            SkinLayer(name: "Luz", blend: .softLight, content: .radialGradient(RadialGradientStyle(stops: stops([
                (0xFFFFFF, 0, 0.6), (0xFFFFFF, 1, 0)
            ]), centerX: 0.8, centerY: 0.15, radius: 0.6))),
            SkinLayer(name: "Grano", opacity: 0.12, blend: .overlay, content: .grain(GrainStyle(size: 1.6)))
        ], adjustments: SkinAdjustments(saturation: 1.1))
    }

    static let carbon = SkinPreset(id: "carbon", name: "Carbono", subtitle: "Fibra tejida y reflejo") { _ in
        SkinDocument(layers: [
            SkinLayer(name: "Base", content: .solid(SkinColor(hex: 0x111214))),
            SkinLayer(name: "Tejido", content: .pattern(PatternLayerStyle(style: .carbon, color: SkinColor(hex: 0x4A4E57), spacing: 12, thickness: 0.4, angle: 45))),
            SkinLayer(name: "Brillo", opacity: 0.4, blend: .screen, content: .sheen(SheenStyle(angle: 110, position: 0.4, width: 0.3))),
            SkinLayer(name: "Acento", opacity: 0.9, blend: .screen, content: .linearGradient(LinearGradientStyle(stops: stops([
                (0xFF453A, 0, 0), (0xFF453A, 0.66, 0), (0xFF453A, 0.68, 0.85), (0xFF453A, 0.71, 0.85), (0xFF453A, 0.73, 0)
            ]), angle: 20)))
        ], adjustments: SkinAdjustments(vignette: 0.25))
    }

    static let guilloche = SkinPreset(id: "guilloche", name: "Guilloché", subtitle: "Grabado de billete en oro") { _ in
        SkinDocument(layers: [
            SkinLayer(name: "Base", content: .linearGradient(LinearGradientStyle(stops: stops([
                (0x0A1F44, 0, 1), (0x122E63, 0.6, 1), (0x081631, 1, 1)
            ]), angle: 125))),
            SkinLayer(name: "Guilloché", opacity: 0.55, blend: .screen, content: .pattern(PatternLayerStyle(style: .guilloche, color: SkinColor(hex: 0xE5C07B), spacing: 46, thickness: 0.22))),
            SkinLayer(name: "Oro", opacity: 0.35, blend: .overlay, content: .holographic(HolographicStyle(scale: 0.6, angle: 60, turbulence: 0.3, sparkle: 0.1))),
            SkinLayer(name: "Brillo", opacity: 0.35, blend: .screen, content: .sheen(SheenStyle(color: SkinColor(hex: 0xFFE7B0), angle: 120, position: 0.5, width: 0.2)))
        ], adjustments: SkinAdjustments(vignette: 0.2))
    }

    static let frosted = SkinPreset(id: "frosted", name: "Vidrio", subtitle: "Tu foto esmerilada") { photo in
        let (photo, assets) = photoLayers(photo, blur: 38)
        let base = photo.isEmpty
            ? [SkinLayer(name: "Base", content: .meshGradient(MeshGradientStyle(colors: [
                SkinColor(hex: 0x64D2FF), SkinColor(hex: 0x5E5CE6), SkinColor(hex: 0xBF5AF2),
                SkinColor(hex: 0x30D158), SkinColor(hex: 0x64D2FF), SkinColor(hex: 0x5E5CE6),
                SkinColor(hex: 0xFFD60A), SkinColor(hex: 0xFF9F0A), SkinColor(hex: 0xFF375F)
            ], warp: 0.5, seed: 5)))]
            : photo
        return SkinDocument(layers: base + [
            SkinLayer(name: "Velo", opacity: 0.18, content: .solid(.white)),
            SkinLayer(name: "Reflejo", blend: .softLight, content: .linearGradient(LinearGradientStyle(stops: stops([
                (0xFFFFFF, 0, 0.7), (0xFFFFFF, 0.45, 0), (0xFFFFFF, 1, 0.2)
            ]), angle: 115))),
            SkinLayer(name: "Grano", opacity: 0.12, blend: .overlay, content: .grain(GrainStyle(size: 1.1)))
        ], adjustments: SkinAdjustments(saturation: 1.2), assets: assets)
    }

    static let sunset = SkinPreset(id: "sunset", name: "Atardecer", subtitle: "Degradado cálido con grano") { _ in
        SkinDocument(layers: [
            SkinLayer(name: "Cielo", content: .linearGradient(LinearGradientStyle(stops: stops([
                (0xFF5E3A, 0, 1), (0xFF2A68, 0.5, 1), (0x5B2A86, 1, 1)
            ]), angle: 160))),
            SkinLayer(name: "Sol", blend: .screen, content: .radialGradient(RadialGradientStyle(stops: stops([
                (0xFFD60A, 0, 0.85), (0xFF9F0A, 0.35, 0.3), (0xFF9F0A, 1, 0)
            ]), centerX: 0.78, centerY: 0.78, radius: 0.55))),
            SkinLayer(name: "Grano", opacity: 0.16, blend: .overlay, content: .grain(GrainStyle(size: 1.8)))
        ])
    }

    static let noir = SkinPreset(id: "noir", name: "Noir", subtitle: "Negro mate con ondas") { _ in
        SkinDocument(layers: [
            SkinLayer(name: "Base", content: .solid(SkinColor(hex: 0x0B0B0C))),
            SkinLayer(name: "Ondas", opacity: 0.5, content: .pattern(PatternLayerStyle(style: .waves, color: SkinColor(hex: 0xFFFFFF, alpha: 0.12), spacing: 18, thickness: 0.12, angle: 12))),
            SkinLayer(name: "Brillo", opacity: 0.25, blend: .screen, content: .sheen(SheenStyle(angle: 125, position: 0.35, width: 0.35)))
        ], adjustments: SkinAdjustments(vignette: 0.35))
    }
}
