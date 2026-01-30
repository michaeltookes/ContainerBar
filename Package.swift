// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ContainerBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ContainerBar", targets: ["ContainerBar"]),
        .library(name: "ContainerBarCore", targets: ["ContainerBarCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "ContainerBar",
            dependencies: [
                "ContainerBarCore",
                .product(name: "Logging", package: "swift-log"),
                "KeyboardShortcuts",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "ContainerBarCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ContainerBarTests",
            dependencies: ["ContainerBar", "ContainerBarCore"]
        ),
        .testTarget(
            name: "ContainerBarCoreTests",
            dependencies: ["ContainerBarCore"]
        ),
    ]
)
