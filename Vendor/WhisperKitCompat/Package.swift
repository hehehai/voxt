// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let package = Package(
    name: "whisperkit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "WhisperKit",
            targets: ["WhisperKit"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.1.6"),
    ] + (isServerEnabled() ? [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.1"),
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.10.2"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.8.2"),
        .package(url: "https://github.com/swift-server/swift-openapi-vapor", from: "1.0.1"),

    ] : []),
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
        )
    ],
    swiftLanguageVersions: [.v5]
)

func isServerEnabled() -> Bool {
    if let enabledValue = Context.environment["BUILD_ALL"] {
        return enabledValue.lowercased() == "true" || enabledValue == "1"
    }

    // Default disabled, change to true temporarily for local development
    return false
}
