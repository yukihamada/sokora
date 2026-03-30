// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "sokora",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "vendor/mlx-swift-examples"),
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.25.0")),
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "sokora",
            dependencies: [
                .product(name: "MLXLLM",         package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon",    package: "mlx-swift-examples"),
                .product(name: "MLX",            package: "mlx-swift"),
                .product(name: "Hummingbird",    package: "hummingbird"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging",        package: "swift-log"),
            ],
            path: "Sources/Sokora",
            swiftSettings: [.unsafeFlags(["-O"])]
        ),
    ]
)
