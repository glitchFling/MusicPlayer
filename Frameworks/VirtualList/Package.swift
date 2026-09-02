// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VirtualList",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "VirtualList", type: .dynamic, targets: ["VirtualList"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "VirtualList",
            dependencies: ["Core"]
        )
    ]
)
