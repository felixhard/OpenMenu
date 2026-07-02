// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WindowManager",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "WindowManager", targets: ["WindowManager"]),
    ],
    dependencies: [
        .package(path: "../OpenMenuCore"),
    ],
    targets: [
        .target(
            name: "WindowManager",
            dependencies: ["OpenMenuCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WindowManagerTests",
            dependencies: ["WindowManager"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
