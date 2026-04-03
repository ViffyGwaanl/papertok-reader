// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PTReader",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PTReader", targets: ["PTReader"]),
    ],
    dependencies: [
        .package(path: "../PTCore"),
    ],
    targets: [
        .target(
            name: "PTReader",
            dependencies: ["PTCore"]
        ),
        .testTarget(
            name: "PTReaderTests",
            dependencies: ["PTReader"]
        ),
    ]
)
