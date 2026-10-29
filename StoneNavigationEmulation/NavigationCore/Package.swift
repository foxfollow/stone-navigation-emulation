// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NavigationCore",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "NavigationCore", targets: ["NavigationCore"]),
    ],
    targets: [
        .target(name: "NavigationCore"),
        .testTarget(
            name: "NavigationCoreTests",
            dependencies: ["NavigationCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
