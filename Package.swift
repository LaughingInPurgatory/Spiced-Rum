// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpicedRum",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SpicedRum", targets: ["SpicedRum"])],
    targets: [
        .target(name: "SpicedRumCore"),
        .executableTarget(name: "SpicedRum", dependencies: ["SpicedRumCore"], exclude: ["Resources"]),
        .testTarget(name: "SpicedRumCoreTests", dependencies: ["SpicedRumCore"])
    ]
)
