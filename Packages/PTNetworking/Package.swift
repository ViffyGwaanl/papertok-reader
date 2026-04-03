// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PTNetworking",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PTNetworking", targets: ["PTNetworking"]),
    ],
    dependencies: [
        .package(path: "../PTCore"),
    ],
    targets: [
        .target(
            name: "PTNetworking",
            dependencies: ["PTCore"]
        ),
        .testTarget(
            name: "PTNetworkingTests",
            dependencies: ["PTNetworking"]
        ),
    ]
)
