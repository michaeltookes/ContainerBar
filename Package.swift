// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DockerBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DockerBar", targets: ["DockerBar"]),
        .library(name: "DockerBarCore", targets: ["DockerBarCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "DockerBar",
            dependencies: [
                "DockerBarCore",
                .product(name: "Logging", package: "swift-log"),
                "KeyboardShortcuts",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "DockerBarCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DockerBarTests",
            dependencies: ["DockerBar", "DockerBarCore"]
        ),
        .testTarget(
            name: "DockerBarCoreTests",
            dependencies: ["DockerBarCore"]
        ),
    ]
)
