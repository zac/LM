// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LunarMap",
    platforms: [.visionOS("2.2")],
    products: [
        .library(name: "LunarMap", targets: ["LunarMap"]),
        .library(name: "LunarMapExplorer", targets: ["LunarMapExplorer"]),
    ],
    dependencies: [.package(path: "../../../AGC")],
    targets: [
        .target(
            name: "LunarMap",
            dependencies: [.product(name: "LMCore", package: "AGC")],
            resources: [.copy("Resources/Terrain"), .process("Resources/LunarTerrainSR.mlpackage")]
        ),
        .target(name: "LunarMapExplorer", dependencies: ["LunarMap"]),
        .testTarget(name: "LunarMapTests", dependencies: ["LunarMap", "LunarMapExplorer", .product(name: "LMCore", package: "AGC")]),
    ],
    swiftLanguageModes: [.v5]
)
