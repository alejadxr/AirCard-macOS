import AppKit
import Foundation

struct CardHistoryEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let date: Date
    var id: URL { url }
    var thumbnailURL: URL { url.appendingPathComponent("thumbnail.png") }
    var skinURL: URL { url.appendingPathComponent("skin.\(SkinDocument.fileExtension)") }
}

enum CardHistoryStore {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AirCard/Cards", isDirectory: true)
    }

    static func folder(for hash: String) -> URL {
        let safe = hash
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return root.appendingPathComponent(safe, isDirectory: true)
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter
    }()

    @discardableResult
    static func save(hash: String, document: SkinDocument, artwork: PreparedArtwork) throws -> CardHistoryEntry {
        let date = Date()
        let entry = folder(for: hash).appendingPathComponent(stampFormatter.string(from: date), isDirectory: true)
        try SkinExporter.write(document: document, artwork: artwork, to: entry)
        let thumbnail = try SkinRenderer.thumbnailPNG(document, width: 480)
        try thumbnail.write(to: entry.appendingPathComponent("thumbnail.png"), options: .atomic)
        try thumbnail.write(to: folder(for: hash).appendingPathComponent("thumbnail.png"), options: .atomic)
        return CardHistoryEntry(url: entry, date: date)
    }

    static func entries(for hash: String) -> [CardHistoryEntry] {
        let folder = folder(for: hash)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  let date = stampFormatter.date(from: url.lastPathComponent) else { return nil }
            return CardHistoryEntry(url: url, date: date)
        }
        .sorted { $0.date > $1.date }
    }

    static func thumbnail(for hash: String) -> NSImage? {
        NSImage(contentsOf: folder(for: hash).appendingPathComponent("thumbnail.png"))
    }

    static func removeAll(for hash: String) {
        try? FileManager.default.removeItem(at: folder(for: hash))
    }
}

enum SkinExporter {
    static func write(document: SkinDocument, artwork: PreparedArtwork, to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, data) in WalletSkinService.artworkFiles(artwork) {
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        }
        try SkinFile.encode(document).write(
            to: folder.appendingPathComponent("skin.\(SkinDocument.fileExtension)"),
            options: .atomic
        )
        for layer in document.layers {
            guard case .image(let style) = layer.content, let data = document.assets[style.assetID] else { continue }
            let name = sanitized(layer.name)
            let ext = URL(fileURLWithPath: name).pathExtension.isEmpty ? ".\(imageExtension(data))" : ""
            try data.write(to: folder.appendingPathComponent("original-\(name)\(ext)"), options: .atomic)
        }
    }

    private static func sanitized(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "imagen" : cleaned
    }

    private static func imageExtension(_ data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String? else { return "png" }
        switch type {
        case "public.jpeg": return "jpg"
        case "org.webmproject.webp": return "webp"
        case "public.heic": return "heic"
        default: return "png"
        }
    }
}

enum SkinFile {
    static func encode(_ document: SkinDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> SkinDocument {
        do {
            return try JSONDecoder().decode(SkinDocument.self, from: data)
        } catch {
            throw AirCardError.processFailed("El archivo .\(SkinDocument.fileExtension) no es válido: \(error.localizedDescription)")
        }
    }
}
