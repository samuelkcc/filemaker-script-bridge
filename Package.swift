// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FileMakerScriptBridge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "FileMakerBridgeCore", targets: ["FileMakerBridgeCore"]),
        .executable(name: "FileMakerScriptBridge", targets: ["FileMakerScriptBridgeApp"])
    ],
    targets: [
        .target(
            name: "FileMakerBridgeCore",
            path: "Sources/FileMakerBridgeCore"
        ),
        .executableTarget(
            name: "FileMakerScriptBridgeApp",
            dependencies: ["FileMakerBridgeCore"],
            path: "Sources/FileMakerScriptBridgeApp"
        ),
        .testTarget(
            name: "FileMakerBridgeCoreTests",
            dependencies: ["FileMakerBridgeCore"],
            path: "Tests/FileMakerBridgeCoreTests"
        ),
        .testTarget(
            name: "FileMakerScriptBridgeAppTests",
            dependencies: ["FileMakerScriptBridgeApp", "FileMakerBridgeCore"],
            path: "Tests/FileMakerScriptBridgeAppTests"
        )
    ]
)
