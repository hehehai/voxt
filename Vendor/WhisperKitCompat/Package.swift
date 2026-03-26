// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "whisperkitcompat",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "WhisperKit",
            targets: ["WhisperKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "ArgmaxCore",
            dependencies: [
                .product(name: "Hub", package: "swift-transformers"),
            ]
        ),
        .target(
            name: "WhisperKit",
            dependencies: [
                "ArgmaxCore",
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
