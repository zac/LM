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
}
