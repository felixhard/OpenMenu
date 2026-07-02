// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SystemMonitor",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SystemMonitor", targets: ["SystemMonitor"]),
    ],
    targets: [
        .target(
            name: "SystemMonitor",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
