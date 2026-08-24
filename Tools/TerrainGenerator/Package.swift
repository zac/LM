// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Apollo11TerrainGenerator",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Apollo11TerrainGenerator", targets: ["Apollo11TerrainGenerator"])
    ],
    targets: [
        .executableTarget(
            name: "Apollo11TerrainGenerator",
            resources: [
                .copy("NAC_DTM_APOLLO11.LBL")
            ],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO")
            ]
        )
    ]
)
