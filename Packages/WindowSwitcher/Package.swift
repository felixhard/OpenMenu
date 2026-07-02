// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WindowSwitcher",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WindowSwitcher", targets: ["WindowSwitcher"]),
    ],
    dependencies: [
        .package(path: "../OpenMenuCore"),
    ],
    targets: [
        .target(
            name: "WindowSwitcher",
            dependencies: ["OpenMenuCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WindowSwitcherTests",
            dependencies: ["WindowSwitcher"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
