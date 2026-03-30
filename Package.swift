// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GroundLoop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "GroundLoop", targets: ["GroundLoop"]),
        .executable(name: "groundloop", targets: ["groundloop-cli"]),
        .executable(name: "groundloop-menubar", targets: ["groundloop-menubar"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "GroundLoop",
            dependencies: [],
            path: "Sources/GroundLoop"
        ),
        .executableTarget(
            name: "groundloop-cli",
            dependencies: [
                "GroundLoop",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/groundloop-cli"
        ),
        .executableTarget(
            name: "groundloop-menubar",
            dependencies: ["GroundLoop"],
            path: "Sources/groundloop-menubar",
            exclude: ["Resources/Info.plist"],
            resources: [.copy("Resources/ServiceLogos")]
        ),
        .testTarget(
            name: "GroundLoopTests",
            dependencies: ["GroundLoop"],
            path: "Tests/GroundLoopTests"
        )
    ]
)
