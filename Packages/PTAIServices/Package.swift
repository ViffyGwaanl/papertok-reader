// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PTAIServices",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PTAIServices", targets: ["PTAIServices"]),
    ],
    dependencies: [
        .package(path: "../PTCore"),
        .package(path: "../PTNetworking"),
    ],
    targets: [
        .target(name: "PTAIServices", dependencies: ["PTCore", "PTNetworking"]),
        .testTarget(name: "PTAIServicesTests", dependencies: ["PTAIServices"]),
    ]
)
