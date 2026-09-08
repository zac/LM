import Foundation

/// Host-owned launch configuration. Order and duplicate arguments are retained
/// because session presets and overrides deliberately apply in order.
public struct LunarMapLaunchOptions: Sendable {
    package let arguments: [String]
    package let profilingEnabled: Bool

    public init(arguments: [String]) {
        self.arguments = arguments
        self.profilingEnabled = arguments.contains("--lunar-explorer-profile")
    }

    /// Process-wide renderer diagnostics, installed before creating scenes.
    package static var current = LunarMapLaunchOptions(arguments: [])
}

extension LunarMap {
    /// Call once at host startup, before creating sessions or resources.
    public static func configure(options: LunarMapLaunchOptions, logSubsystem: String) {
        LunarMapLaunchOptions.current = options
        LunarMapLog.subsystem = logSubsystem
    }
}
