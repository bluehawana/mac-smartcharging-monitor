// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmartCharging",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SmartCharging",
            path: "Sources/SmartCharging",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
