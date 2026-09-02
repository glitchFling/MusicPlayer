// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AspaltAI",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AspaltAI", targets: ["AspaltAI"])
    ],
    dependencies: [
        // MLX Swift examples provide MLXLMCommon: LLM loading + generation on device.
        // Pinned to a stable release series (main branch is a moving target).
        .package(
            url: "https://github.com/ml-explore/mlx-swift-examples.git",
            .upToNextMajor(from: "2.29.1")
        )
    ],
    targets: [
        .target(
            name: "AspaltAI",
            dependencies: [
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
                .product(name: "MLXLLM", package: "mlx-swift-examples")
            ]
        )
    ]
)
