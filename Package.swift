// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SketchBookPlayer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SketchBookPlayer", targets: ["SketchBookPlayer"])
    ],
    targets: [
        .executableTarget(
            name: "SketchBookPlayer",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
