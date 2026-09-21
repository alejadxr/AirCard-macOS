import Foundation

struct DeviceInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let product: String
    let version: String
    let build: String

    var summary: String {
        let versionText = version.isEmpty ? "iOS desconocido" : "iOS \(version)"
        let buildText = build.isEmpty ? "" : " (\(build))"
        return "\(name) · \(product) · \(versionText)\(buildText)"
    }
}

struct PreparedArtwork: Sendable {
    let png: Data
    let pdf: Data
    let sourceWidth: Int
    let sourceHeight: Int
}

struct PasscodeTint: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double

    static let white = PasscodeTint(red: 1, green: 1, blue: 1)
}

struct PasscodeAsset: Sendable {
    let name: String
    let data: Data
    let isImage: Bool
}

struct PasscodeTheme: Sendable {
    let name: String
    let detectedVersion: String
    let assetsByVersion: [String: [PasscodeAsset]]
    let unversionedAssets: [PasscodeAsset]

    func assets(for version: String) -> [PasscodeAsset] {
        assetsByVersion[version] ?? unversionedAssets
    }

    var previewAsset: PasscodeAsset? {
        let assets = assets(for: detectedVersion)
        return assets.first(where: { $0.isImage && $0.name.range(of: #"[0-9]"#, options: .regularExpression) != nil })
            ?? assets.first(where: \ .isImage)
    }
}

struct PasscodeFlashResult: Sendable {
    let themeName: String
    let targetVersion: String
    let assetCount: Int
}

struct FlashResult: Sendable {
    let cardHash: String
    let artworkFiles: Int
    let cacheFiles: Int
}

enum AirCardError: LocalizedError {
    case helperMissing
    case invalidHelperOutput(String)
    case noDevice
    case invalidCardHash
    case invalidTarget(String)
    case processFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            return "No encuentro los helpers nativos de macOS. Ejecuta Scripts/build_helpers.sh."
        case .invalidHelperOutput(let output):
            return "El helper devolvió una respuesta inválida: \(output)"
        case .noDevice:
            return "No hay un iPhone emparejado y conectado. Desbloquéalo y pulsa ‘Confiar’."
        case .invalidCardHash:
            return "El hash de la tarjeta no parece un identificador Base64 válido."
        case .invalidTarget(let target):
            return "Ruta de destino no permitida: \(target)"
        case .processFailed(let message):
            return message
        case .cancelled:
            return "Operación cancelada."
        }
    }
}
