import Foundation

enum NativeTools {
    static var rootURL: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    static func helperURL(named name: String) throws -> URL {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("bin/\(name)"),
            rootURL.appendingPathComponent("Resources/bin/\(name)"),
            rootURL.appendingPathComponent("bin/\(name)"),
        ].compactMap { $0 }

        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return match.standardizedFileURL
        }
        throw AirCardError.helperMissing
    }

    static func jsonObject(from output: String) throws -> Any {
        let lines = output.split(whereSeparator: \ .isNewline).reversed()
        for line in lines {
            if let data = line.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                return object
            }
        }
        throw AirCardError.invalidHelperOutput(output)
    }

    static func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
