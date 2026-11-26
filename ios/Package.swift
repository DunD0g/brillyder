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
            name: "BrillyDerActivityKit",
            targets: ["BrillyDerActivityKit"]
        ),
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
            name: "BrillyDerActivityKit",
            path: "Sources/BrillyDerActivityKit"
        ),
        .target(
            name: "CRenegadeEngine",
            path: "Sources/CRenegadeEngine",
            exclude: [
                "LICENSE",
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("src"),
                .define("NDEBUG", .when(configuration: .release)),
            ]
        ),
        .target(
            name: "BrillyDerCore",
            dependencies: ["CRenegadeEngine"],
            path: "Sources/BrillyDerCore",
            resources: [
                .copy("Resources/starterCourses.json"),
                .copy("Resources/renegade-net-36.bin"),
            ]
        ),
        .target(
            name: "BrillyDerUI",
            dependencies: ["BrillyDerCore", "BrillyDerActivityKit"],
            path: "Sources/BrillyDerUI",
            resources: [
                .process("Resources/Pieces"),
            ]
        ),
        .testTarget(
            name: "BrillyDerCoreTests",
            dependencies: ["BrillyDerCore"],
            path: "Tests/BrillyDerCoreTests"
        ),
    ],
    cxxLanguageStandard: .cxx20
)
