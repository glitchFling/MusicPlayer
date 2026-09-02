// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Core", type: .dynamic, targets: ["Core"])
    ],
    targets: [
        .target(name: "Core")
    ]
)
