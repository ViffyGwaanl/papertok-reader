// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PTUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PTUI", targets: ["PTUI"]),
    ],
    dependencies: [
        .package(path: "../PTCore"),
    ],
    targets: [
        .target(name: "PTUI", dependencies: ["PTCore"]),
        .testTarget(name: "PTUITests", dependencies: ["PTUI"]),
    ]
)
