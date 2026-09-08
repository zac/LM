import Foundation

/// Model resources only. The consuming app owns simulation and interaction.
public enum LMKitAssets {
    public static var legacySceneURL: URL {
        Bundle.module.url(forResource: "lm", withExtension: "usda", subdirectory: "Legacy")!
    }
    public static var lunarModuleURL: URL {
        Bundle.module.url(forResource: "lunar_module", withExtension: "usdz", subdirectory: "Legacy")!
    }
    /// Neutral, unpowered DSKY. Live digits, lamps and key inputs require app bindings.
    public static var dskyURL: URL {
        Bundle.module.url(forResource: "DSKY", withExtension: "usdz", subdirectory: "DSKY")!
    }
    /// Standalone FDAI with provisional dimensions; state and calibration are app-owned.
    public static var fdaiURL: URL {
        Bundle.module.url(forResource: "FDAI", withExtension: "usdz", subdirectory: "FDAI")!
    }
    /// Generic control specimens. Mounting dimensions and per-panel semantics are provisional.
    public enum ControlFamily: String, CaseIterable, Sendable {
        case maintainedToggle = "MaintainedToggle"
        case momentaryToggle = "MomentaryToggle"
        case guardedSwitch = "GuardedSwitch"
        case rotarySelector = "RotarySelector"
        case circuitBreaker = "CircuitBreaker"
        case talkback = "Talkback"
    }
    public static func controlURL(_ family: ControlFamily) -> URL {
        Bundle.module.url(forResource: family.rawValue, withExtension: "usdz", subdirectory: "ControlLibrary")!
    }
    public static var controlInterfacesURL: URL {
        Bundle.module.url(forResource: "components", withExtension: "json", subdirectory: "ControlLibrary")!
    }
    /// Optional open structural skeleton; proposed panel placement is not runtime-approved.
    public static var cabinSkeletonURL: URL {
        Bundle.module.url(forResource: "Cabin", withExtension: "usdz", subdirectory: "Cabin")!
    }
    /// Positions and rotations are Cabin-root-relative, even for nested instrument nodes.
    public static var cabinMountsURL: URL {
        Bundle.module.url(forResource: "mounts", withExtension: "json", subdirectory: "Cabin")!
    }
}
