// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "M2MaxFanController",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FanControllerCore", targets: ["FanControllerCore"]),
    ],
    targets: [
        .target(name: "FanControllerCore"),
        .testTarget(
            name: "FanControllerCoreTests",
            dependencies: ["FanControllerCore"]
        ),
    ]
)
