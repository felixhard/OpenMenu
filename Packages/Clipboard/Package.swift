// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clipboard",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Clipboard", targets: ["Clipboard"]),
    ],
    dependencies: [
        .package(path: "../OpenMenuCore"),
    ],
    targets: [
        .target(
            name: "Clipboard",
            dependencies: ["OpenMenuCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ClipboardTests",
            dependencies: ["Clipboard"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
