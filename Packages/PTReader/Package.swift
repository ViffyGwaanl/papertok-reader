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
        .package(path: "../PTNetworking"),
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
                "PTNetworking",
                .product(name: "ReadiumShared", package: "swift-toolkit", condition: .when(platforms: [.iOS])),
                .product(name: "ReadiumStreamer", package: "swift-toolkit", condition: .when(platforms: [.iOS])),
                .product(name: "ReadiumNavigator", package: "swift-toolkit", condition: .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(
            name: "PTReaderTests",
            dependencies: [
                "PTReader",
                "PTCore",
                .product(name: "ReadiumShared", package: "swift-toolkit", condition: .when(platforms: [.iOS])),
            ],
            resources: [
                .copy("Fonts/Resources/iAWriterDuospace-Regular.ttf"),
                .copy("Fonts/Resources/LICENSE-iAWriterDuospace.md"),
            ]
        ),
    ]
)
