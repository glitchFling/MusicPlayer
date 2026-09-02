// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeBlytes",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DeBlytes", type: .dynamic, targets: ["DeBlytes"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "DeBlytes",
            dependencies: ["Core"]
        )
    ]
)
