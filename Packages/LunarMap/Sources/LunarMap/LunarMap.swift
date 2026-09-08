import Foundation

/// Pinned terrain, imagery, Metal kernels and the appearance-only Core ML model.
public enum LunarMap {
    public static let resources = Bundle.module
}

/// Each app may select its own subsystem before creating the map session.
public enum LunarMapLog {
    public static var subsystem = "io.positron.LM"
}
