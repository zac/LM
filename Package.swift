// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "LMKit",
    platforms: [.macOS(.v15), .iOS(.v18), .visionOS(.v2)],
    products: [.library(name: "LMKit", targets: ["LMKit"])],
    targets: [
        .target(name: "LMKit", resources: [.copy("Resources/Legacy"), .copy("Resources/DSKY"), .copy("Resources/FDAI"), .copy("Resources/ControlLibrary"), .copy("Resources/Cabin"), .copy("Resources/HandControllers")]),
        .testTarget(name: "LMKitTests", dependencies: ["LMKit"])
    ]
)
