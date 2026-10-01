// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Watchtower",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Watchtower", path: "Sources/Watchtower")
    ],
    swiftLanguageModes: [.v5]
)
