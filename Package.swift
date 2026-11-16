// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BatteryChargeLimit",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BCLShared"),
        .target(name: "BCLCore", dependencies: ["BCLShared"]),
        .target(name: "BCLSMC", dependencies: ["BCLShared"]),
        .executableTarget(name: "bcl-helper", dependencies: ["BCLShared", "BCLCore", "BCLSMC"]),
        .executableTarget(
            name: "battery-charge-limit",
            dependencies: ["BCLShared", "BCLCore"]
        ),
        .executableTarget(name: "bcl-uninstaller", dependencies: ["BCLShared"]),
        .testTarget(name: "BCLCoreTests", dependencies: ["BCLCore", "BCLShared"]),
    ]
)
