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
                .copy("NAC_DTM_APOLLO11.LBL"),
                .copy("NAC_DTM_APOLLO11_M150361817_50CM.xml"),
                .copy("NAC_DTM_APOLLO11_M150368601_50CM.xml"),
                .copy("SLDEM2015_128_60S_60N_000_360_FLOAT.LBL"),
                .copy("SLDEM2015_512_00N_30N_000_045_FLOAT.LBL"),
                .copy("WAC_EMP_643NM_E300N0450_064P.xml"),
                .copy("WAC_EMP_643NM_E300N0450_304P.xml"),
                .copy("WAC_EMP_643NM_E300S0450_064P.xml")
            ],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO")
            ]
        )
    ]
)
