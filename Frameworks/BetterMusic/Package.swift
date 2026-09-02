// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BetterMusic",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "BetterMusic", type: .dynamic, targets: ["BetterMusic"])
    ],
    targets: [
        .target(name: "BetterMusic")
    ]
)
