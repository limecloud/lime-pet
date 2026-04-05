// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "LimePet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "LimePet",
            targets: ["LimePet"]
        )
    ],
    targets: [
        .executableTarget(
            name: "LimePet",
            path: "LimePet",
            exclude: [
                "Info.plist",
                "Resources/live2d-model-presets.json",
                "Resources/live2d-models"
            ],
            resources: [
                .process("Resources/character-library.json"),
                .process("Resources/live2d-model-catalog.json"),
                .process("Resources/dewy-lime-cutout.png"),
                .process("Resources/dewy-lime-shadow.png"),
                .process("Resources/dewy-lime.png"),
                .process("Resources/dewy-lime-transparent.png"),
                .copy("Resources/live2d-runtime")
            ]
        )
    ]
)
