// swift-tools-version: 6.0
import PackageDescription

/// macOS executable, internal playback/layout library, bundled themes, and native/core tests.
let package = Package(
    name: "Ampi",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Ampi", targets: ["Ampi"])],
    targets: [
        .target(name: "AmpiCore", resources: [.process("Themes")]),
        .executableTarget(name: "Ampi", dependencies: ["AmpiCore"]),
        .testTarget(name: "AmpiCoreTests", dependencies: ["AmpiCore"]),
        .testTarget(name: "AmpiUITests", dependencies: ["Ampi"])
    ]
)
