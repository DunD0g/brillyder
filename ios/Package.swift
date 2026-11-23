// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrillyDer",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "BrillyDerCore",
            targets: ["BrillyDerCore"]
        ),
        .library(
            name: "BrillyDerUI",
            targets: ["BrillyDerUI"]
        ),
    ],
    targets: [
        .target(
            name: "BrillyDerCore",
            path: "Sources/BrillyDerCore",
            resources: [
                .copy("Resources/starterCourses.json"),
            ]
        ),
        .target(
            name: "BrillyDerUI",
            dependencies: ["BrillyDerCore"],
            path: "Sources/BrillyDerUI"
        ),
        .testTarget(
            name: "BrillyDerCoreTests",
            dependencies: ["BrillyDerCore"],
            path: "Tests/BrillyDerCoreTests"
        ),
    ]
)
