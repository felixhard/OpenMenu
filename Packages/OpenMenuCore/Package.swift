// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenMenuCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "OpenMenuCore", targets: ["OpenMenuCore"]),
    ],
    targets: [
        .target(
            name: "OpenMenuCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OpenMenuCoreTests",
            dependencies: ["OpenMenuCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
