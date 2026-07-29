// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "M2MaxFanController",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FanControllerCore", targets: ["FanControllerCore"]),
        .library(name: "SMCKit", targets: ["SMCKit"]),
        .executable(name: "FanDiagnostics", targets: ["FanDiagnostics"]),
    ],
    targets: [
        .target(name: "FanControllerCore"),
        .target(
            name: "SMCKit",
            dependencies: ["FanControllerCore"]
        ),
        .executableTarget(
            name: "FanDiagnostics",
            dependencies: ["FanControllerCore", "SMCKit"]
        ),
        .testTarget(
            name: "FanControllerCoreTests",
            dependencies: ["FanControllerCore"]
        ),
        .testTarget(
            name: "SMCKitTests",
            dependencies: ["SMCKit"]
        ),
    ]
)
