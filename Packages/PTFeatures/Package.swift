// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PTFeatures",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PTFeatures", targets: ["PTFeatures"])],
    dependencies: [
        .package(path: "../PTCore"),
        .package(path: "../PTNetworking"),
        .package(path: "../PTReader"),
        .package(path: "../PTUI"),
        .package(path: "../PTAIServices"),
    ],
    targets: [
        .target(name: "PTFeatures", dependencies: ["PTCore", "PTNetworking", "PTReader", "PTUI", "PTAIServices"]),
        .testTarget(name: "PTFeaturesTests", dependencies: ["PTFeatures"]),
    ]
)
