// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Suitcase",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "Suitcase", targets: ["Suitcase"])
    ],
    targets: [
        .target(name: "Suitcase")
    ]
)