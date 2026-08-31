// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FocusOnMe",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "FocusOnMe", targets: ["FocusOnMe"])
    ],
    targets: [
        .target(name: "FocusOnMe")
    ]
)