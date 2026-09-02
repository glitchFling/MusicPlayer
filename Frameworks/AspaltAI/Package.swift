// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AspaltAI",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AspaltAI", targets: ["AspaltAI"])
    ],
    dependencies: [
        // MLX Swift examples provide MLXLMCommon: LLM loading + generation on device.
        .package(
            url: "https://github.com/ml-explore/mlx-swift-examples.git",
            branch: "main"
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
