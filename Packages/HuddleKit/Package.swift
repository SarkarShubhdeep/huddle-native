// swift-tools-version: 6.0
import PackageDescription

// HuddleKit holds everything that isn't UI: networking, models, services and the
// refresh engine. It has no third-party dependencies and builds on macOS and Linux
// too, so its tests run without a simulator.
let package = Package(
    name: "HuddleKit",
    platforms: [
        .iOS("26.0"),
        .macOS("15.0"),
    ],
    products: [
        .library(name: "HuddleKit", targets: ["HuddleKit"]),
    ],
    targets: [
        .target(name: "HuddleKit"),
        .testTarget(name: "HuddleKitTests", dependencies: ["HuddleKit"]),
    ]
)
