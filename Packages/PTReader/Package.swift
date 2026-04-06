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
        .package(
            url: "https://github.com/readium/swift-toolkit.git",
            from: "3.0.0"
        ),
    ],
    targets: [
        .target(
            name: "PTReader",
            dependencies: [
                "PTCore",
                .product(name: "ReadiumShared", package: "swift-toolkit"),
                .product(name: "ReadiumStreamer", package: "swift-toolkit"),
                .product(name: "ReadiumNavigator", package: "swift-toolkit"),
            ]
        ),
        .testTarget(
            name: "PTReaderTests",
            dependencies: [
                "PTReader",
                "PTCore",
                .product(name: "ReadiumShared", package: "swift-toolkit"),
            ]
        ),
    ]
)
