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

    var majorVersion: Int? {
        version.split(separator: ".").first.flatMap { Int($0) }
    }

    var compatibilityNote: String {
        guard let major = majorVersion else { return "Versión de iOS desconocida" }
        switch major {
        case 18: return "iOS \(version) · detección compatible (iOS 18)"
        case 26...: return "iOS \(version) · detección compatible"
        default: return "iOS \(version) · no probado; la detección puede fallar"
        }
    }

    var isDetectionTested: Bool {
        guard let major = majorVersion else { return false }
        return major == 18 || major >= 26
    }
}

struct WalletCard: Identifiable, Codable, Hashable, Sendable {
    var id: String { hash }
    let hash: String
    var name: String
    var firstSeen: Date
    var lastSeen: Date
    var hits: Int

    var shortHash: String {
        hash.count > 14 ? "\(hash.prefix(8))…\(hash.suffix(5))" : hash
    }
}

enum CardStore {
    private static let key = "AirCard.savedCards.v1"

    static func load() -> [WalletCard] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cards = try? JSONDecoder().decode([WalletCard].self, from: data) else { return [] }
        return cards.filter { WalletSkinService().validateCardHash($0.hash) != nil }
    }

    static func save(_ cards: [WalletCard]) {
        guard let data = try? JSONEncoder().encode(cards) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct PreparedArtwork: Sendable {
    let png: Data
    let png2x: Data
    let pdf: Data
    let sourceWidth: Int
    let sourceHeight: Int
}

struct PasscodeTint: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double

    static let white = PasscodeTint(red: 1, green: 1, blue: 1)
    static let black = PasscodeTint(red: 0, green: 0, blue: 0)
}

enum PasscodeVariant: String, CaseIterable, Hashable, Identifiable, Sendable {
    case white
    case black

    var id: String { rawValue }
    var label: String { "--\(rawValue)" }
    var tint: PasscodeTint {
        self == .white ? .white : .black
    }
}

enum PasscodeLanguage: String, CaseIterable, Hashable, Identifiable, Sendable {
    case english
    case russian
    case ukrainian
    case japanese
    case universal

    var id: String { rawValue }
    var label: String {
        switch self {
        case .english: return "English"
        case .russian: return "Russian (Русский)"
        case .ukrainian: return "Ukrainian (Українська)"
        case .japanese: return "Japanese (日本語)"
        case .universal: return "Universal (todos)"
        }
    }
}

enum PasscodeCache {
    static let auto = "Auto"
    static let versions = ["TelephonyUI-10", "TelephonyUI-9", "TelephonyUI-8"]

    static func resolve(_ selection: String, device: DeviceInfo?) -> String {
        guard selection == auto else { return selection }
        guard let major = device?.majorVersion else { return "TelephonyUI-10" }
        switch major {
        case 18...: return "TelephonyUI-10"
        case 16...17: return "TelephonyUI-9"
        default: return "TelephonyUI-8"
        }
    }
}

struct PasscodeKeyPreview: Identifiable, Sendable {
    static let keypadOrder = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]

    let key: String
    let png: Data
    var id: String { key }
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
        if let assets = assetsByVersion[version] { return assets }
        if !unversionedAssets.isEmpty { return unversionedAssets }
        return assetsByVersion[detectedVersion] ?? []
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
    case airTrafficUnavailable
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
        case .airTrafficUnavailable:
            return "Desbloquea el iPhone, mantén la pantalla encendida y abre Apple Books una vez."
        case .cancelled:
            return "Operación cancelada."
        }
    }
}
