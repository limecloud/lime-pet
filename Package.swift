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
                "Info.plist"
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
