// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AirCardMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AirCardMac", targets: ["AirCardMac"])
    ],
    targets: [
        .executableTarget(
            name: "AirCardMac",
            path: "Sources/AirCardMac",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
