// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "LMCheckpointValidation", platforms: [.macOS(.v14)], targets: [.target(name: "AGC"), .target(name: "LMCore", dependencies: ["AGC"]), .executableTarget(name: "LMFlightRecorder", dependencies: ["LMCore"])])
