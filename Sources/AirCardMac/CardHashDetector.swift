import Foundation

struct CardDetection: Sendable, Equatable {
    let hash: String
    let name: String?
    let isFocus: Bool
}

enum CardHashDetector {
    private static let walletMarkers = [
        "passd", "passbook", "passkit", "stockholm", "nanopassd", "npkcompanion",
        "wallet", "/cards/", "/passes/", "pkpass", "passbookuiservice", "passkituiservice"
    ]

    // iOS 18 logs "Passbook(PassKitUI) … Dashboard loading (…): for <hash>"
    // when a card's detail view is opened.
    private static let focusMarkers = [
        "dashboard loading", "didselect", "selected", "frontmost", "present", "detail", "foreground",
        "tapped", "expanded", "barcode", "showing", "viewcontroller"
    ]

    private static let dummyHashes: Set<String> = [
        "M6nDwZrkYbFlsodLgCbvyFZQ1cc=",
        "kJL-D0rr-SZhbj2c8nK-OQ9hCMY=",
        "hwAtAmHKYwsQrJbT5cTNDsaxVME="
    ]

    private static let rejectedFragments = [
        "mobileasset", "com_apple", "com.", "apple.", "curtain", "binder", "optimizer",
        "system", "uaf", "siri", "dialog", "planner", "linguistic", "timing", "model",
        "translation", "visual", "device", "override", "motion", "search"
    ]

    private static let hashPatterns: [NSRegularExpression] = [
        #"/(?:Cards|Passes/Cards)/([A-Za-z0-9+/_-]{27,44}=?)(?:\.pkpass|\.cache|\.pkcache|/|\s|"|'|\)|,|$)"#,
        #"/([A-Za-z0-9+/_-]{27,44}=?)\.(?:pkpass|cache|pkcache)"#,
        #"(?i)(?:card[_\s]?(?:hash|id)|pass[_\s]?(?:hash|id)|(?:pass)?unique[_\s]?id(?:entifier)?)\s*[:=]\s*['"]?([A-Za-z0-9+/=_-]{27,44})"#,
        #"(?:^|[^A-Za-z0-9+/_-])([A-Za-z0-9+/_-]{27}=)(?:$|[^A-Za-z0-9+/=_-])"#,
        #"(?:^|[^A-Za-z0-9+/_-])([A-Za-z0-9+/_-]{43}=)(?:$|[^A-Za-z0-9+/=_-])"#
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private static let namePattern = try? NSRegularExpression(
        pattern: #"(?i)(?:localizedDescription|description|passName|organizationName|localizedName|displayName|title)\s*[:=]\s*['"]([^'"]{2,60})['"]"#
    )

    static func detect(in line: String) -> CardDetection? {
        let lower = line.lowercased()
        guard walletMarkers.contains(where: { lower.contains($0) }) else { return nil }
        guard let hash = extractHash(from: line) else { return nil }
        return CardDetection(
            hash: hash,
            name: extractName(from: line),
            isFocus: focusMarkers.contains(where: { lower.contains($0) })
        )
    }

    static func walletName(in line: String) -> String? {
        let lower = line.lowercased()
        guard walletMarkers.contains(where: { lower.contains($0) }) else { return nil }
        return extractName(from: line)
    }

    static func extractHash(from line: String) -> String? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        for regex in hashPatterns {
            for match in regex.matches(in: line, range: range) {
                guard let candidateRange = Range(match.range(at: 1), in: line) else { continue }
                if let hash = normalizedHash(String(line[candidateRange])) {
                    return hash
                }
            }
        }
        return nil
    }

    static func extractName(from line: String) -> String? {
        guard let namePattern else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = namePattern.firstMatch(in: line, range: range),
              let nameRange = Range(match.range(at: 1), in: line) else { return nil }
        let name = line[nameRange].trimmingCharacters(in: .whitespaces)
        guard name.count > 1, !name.lowercased().contains("<private>") else { return nil }
        return name
    }

    static func normalizedHash(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        guard [27, 28, 43, 44].contains(trimmed.count),
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/_-=".contains($0)) })
        else { return nil }
        guard trimmed.filter({ $0 == "_" }).count <= 1, trimmed.filter({ $0 == "-" }).count <= 2 else {
            return nil
        }
        if let equals = trimmed.firstIndex(of: "="),
           trimmed.distance(from: equals, to: trimmed.endIndex) > 2 {
            return nil
        }
        let lower = trimmed.lowercased()
        guard !rejectedFragments.contains(where: { lower.contains($0) }) else { return nil }

        var base64 = trimmed.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64), data.count == 20 || data.count == 32 else {
            return nil
        }
        let bytes = [UInt8](data)
        guard bytes.contains(where: { $0 >= 128 }),
              bytes.contains(where: { $0 < 128 }),
              Set(bytes).count >= 12
        else { return nil }

        let hash = trimmed.count == 27 || trimmed.count == 43 ? "\(trimmed)=" : trimmed
        guard !dummyHashes.contains(hash) else { return nil }
        return hash
    }
}
