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
