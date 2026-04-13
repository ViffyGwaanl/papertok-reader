// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PTCore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PTCore", targets: ["PTCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "PTCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "PTCoreTests",
            dependencies: ["PTCore"],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
