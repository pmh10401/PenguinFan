// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "M2MaxFanController",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FanControllerCore", targets: ["FanControllerCore"]),
        .library(name: "SMCKit", targets: ["SMCKit"]),
        .library(name: "FanControlIPC", targets: ["FanControlIPC"]),
        .executable(name: "FanDiagnostics", targets: ["FanDiagnostics"]),
        .executable(
            name: "FanControllerAgent",
            targets: ["FanControllerAgent"]
        ),
        .executable(
            name: "FanControllerApp",
            targets: ["FanControllerApp"]
        ),
    ],
    targets: [
        .target(name: "FanControllerCore"),
        .target(
            name: "SMCKit",
            dependencies: ["FanControllerCore"]
        ),
        .target(
            name: "FanControlIPC",
            dependencies: ["FanControllerCore"]
        ),
        .executableTarget(
            name: "FanDiagnostics",
            dependencies: ["FanControllerCore", "SMCKit"]
        ),
        .executableTarget(
            name: "FanControllerAgent",
            dependencies: [
                "FanControllerCore",
                "FanControlIPC",
                "SMCKit",
            ]
        ),
        .executableTarget(
            name: "FanControllerApp",
            dependencies: [
                "FanControllerCore",
                "FanControlIPC",
                "SMCKit",
            ]
        ),
        .testTarget(
            name: "FanControllerCoreTests",
            dependencies: ["FanControllerCore"]
        ),
        .testTarget(
            name: "SMCKitTests",
            dependencies: ["SMCKit"]
        ),
        .testTarget(
            name: "FanControlIPCTests",
            dependencies: [
                "FanControlIPC",
                "FanControllerAgent",
                "SMCKit",
            ]
        ),
        .testTarget(
            name: "FanControllerAppTests",
            dependencies: [
                "FanControllerApp",
                "FanControllerCore",
            ]
        ),
    ]
)
