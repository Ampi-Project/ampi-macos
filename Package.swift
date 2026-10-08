// swift-tools-version: 6.0
import PackageDescription

/// macOS executable, internal playback/layout library, bundled themes, and native/core tests.
let package = Package(
    name: "Ampi",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Ampi", targets: ["Ampi"])],
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: [
        .target(name: "AmpiCore", dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")],
                resources: [.process("Themes")]),
        .executableTarget(name: "Ampi", dependencies: ["AmpiCore"]),
        .testTarget(name: "AmpiCoreTests", dependencies: ["AmpiCore", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
                    resources: [.copy("Fixtures")]),
        .testTarget(name: "AmpiUITests", dependencies: ["Ampi"])
    ]
)
