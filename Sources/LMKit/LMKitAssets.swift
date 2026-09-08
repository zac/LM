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
    /// Enclosed provisional interior foundation; instruments and glazing load separately.
    public static var cabinURL: URL {
        Bundle.module.url(forResource: "Cabin", withExtension: "usdz", subdirectory: "Cabin")!
    }
    /// Compatibility alias. The resource now contains the enclosed foundation.
    public static var cabinSkeletonURL: URL { cabinURL }
    public static var cabinInterfaceURL: URL {
        Bundle.module.url(forResource: "interface-v2", withExtension: "json", subdirectory: "Cabin")!
    }
    public static var cabinMigrationURL: URL {
        Bundle.module.url(forResource: "migration", withExtension: "json", subdirectory: "Cabin")!
    }
    /// Positions and rotations are Cabin-root-relative, even for nested instrument nodes.
    public static var cabinMountsURL: URL {
        Bundle.module.url(forResource: "mounts", withExtension: "json", subdirectory: "Cabin")!
    }
    /// Provisional instrument surrounds; install at identity under the Cabin root.
    public static var commanderPanelsURL: URL {
        Bundle.module.url(forResource: "CommanderPanels", withExtension: "usdz", subdirectory: "CommanderPanels")!
    }
    /// Explicit parent-local and Cabin-relative interfaces; mechanical seating is unresolved.
    public static var commanderPanelMountsURL: URL {
        Bundle.module.url(forResource: "mounting", withExtension: "json", subdirectory: "CommanderPanels")!
    }
    /// Glazed windows and approximate physical LPD artwork; no angular targeting qualification.
    public static var windowsURL: URL {
        Bundle.module.url(forResource: "WindowsLPD", withExtension: "usdz", subdirectory: "WindowsLPD")!
    }
    /// Versioned window openings, provisional eye/pane datums and marking qualifications.
    public static var windowInterfacesURL: URL {
        Bundle.module.url(forResource: "interface-v1", withExtension: "json", subdirectory: "WindowsLPD")!
    }
    /// Exported pane bases and mesh bounds in the WindowsLPD root datum.
    public static var windowManifestURL: URL {
        Bundle.module.url(forResource: "manifest", withExtension: "json", subdirectory: "WindowsLPD")!
    }
    /// Independent blank panel regions; no instrument behavior is inferred from slot names.
    public static var panelInventoryURL: URL {
        Bundle.module.url(forResource: "PanelInventory", withExtension: "usdz", subdirectory: "PanelInventory")!
    }
    /// Full paths, local poses, external occupants and explicit replacement permission gates.
    public static var panelInventoryManifestURL: URL {
        Bundle.module.url(forResource: "inventory", withExtension: "json", subdirectory: "PanelInventory")!
    }
    /// Standalone hand-controller prototypes; installation and input mappings are app-owned.
    public enum HandController: String, CaseIterable, Sendable {
        case aca = "ACA"
        case ttca = "TTCA"
    }
    public static func handControllerURL(_ controller: HandController) -> URL {
        Bundle.module.url(forResource: controller.rawValue, withExtension: "usdz", subdirectory: "HandControllers")!
    }
    /// Neutral origins are parent-local; demonstration offsets are not mechanical limits.
    public static var handControllerInterfacesURL: URL {
        Bundle.module.url(forResource: "interface", withExtension: "json", subdirectory: "HandControllers")!
    }

    // Neutral landing-station components. The consuming app owns every live binding.
    public static var altitudeRateURL: URL {
        Bundle.module.url(forResource: "AltitudeRate", withExtension: "usdz", subdirectory: "AltitudeRate")!
    }
    public static var attitudeModeURL: URL {
        Bundle.module.url(forResource: "AttitudeMode", withExtension: "usdz", subdirectory: "DescentControls")!
    }
    public static var descentRateURL: URL {
        Bundle.module.url(forResource: "DescentRate", withExtension: "usdz", subdirectory: "DescentControls")!
    }
    public static var crossPointerURL: URL {
        Bundle.module.url(forResource: "CrossPointer", withExtension: "usdz", subdirectory: "CrossPointer")!
    }
    public static var interiorDetailsURL: URL {
        Bundle.module.url(forResource: "InteriorDetails", withExtension: "usdz", subdirectory: "InteriorDetails")!
    }
    public static var breakerBanksURL: URL {
        Bundle.module.url(forResource: "BreakerBanks", withExtension: "usdz", subdirectory: "BreakerBanks")!
    }
    public static var altitudeRateInterfaceURL: URL {
        Bundle.module.url(forResource: "interface", withExtension: "json", subdirectory: "AltitudeRate")!
    }
    public static var descentControlsInterfaceURL: URL {
        Bundle.module.url(forResource: "interface", withExtension: "json", subdirectory: "DescentControls")!
    }
    public static var crossPointerInterfaceURL: URL {
        Bundle.module.url(forResource: "interface", withExtension: "json", subdirectory: "CrossPointer")!
    }
    public static var interiorDetailsInterfaceURL: URL {
        Bundle.module.url(forResource: "interface", withExtension: "json", subdirectory: "InteriorDetails")!
    }
    public static var breakerBanksInterfaceURL: URL {
        Bundle.module.url(forResource: "interface", withExtension: "json", subdirectory: "BreakerBanks")!
    }


    // Systems hardware is neutral. Availability and behavior are host-owned.
    public static var missionTimerURL: URL {
        Bundle.module.url(forResource: "MissionTimer", withExtension: "usdz", subdirectory: "Timers")!
    }
    public static var eventTimerURL: URL {
        Bundle.module.url(forResource: "EventTimer", withExtension: "usdz", subdirectory: "Timers")!
    }
    public static var missionTimerControlsURL: URL {
        Bundle.module.url(forResource: "MissionTimerControls", withExtension: "usdz", subdirectory: "Timers")!
    }
    public static var eventTimerControlsURL: URL {
        Bundle.module.url(forResource: "EventTimerControls", withExtension: "usdz", subdirectory: "Timers")!
    }
    public static var engineButtonsURL: URL {
        Bundle.module.url(forResource: "EngineButtons", withExtension: "usdz", subdirectory: "EngineControls")!
    }
    public static var lunarContactURL: URL {
        Bundle.module.url(forResource: "LunarContact", withExtension: "usdz", subdirectory: "EngineControls")!
    }
    public static var propulsionInstrumentsURL: URL {
        Bundle.module.url(forResource: "PropulsionInstruments", withExtension: "usdz", subdirectory: "PropulsionInstruments")!
    }
    public static var cautionWarningURL: URL {
        Bundle.module.url(forResource: "CautionWarning", withExtension: "usdz", subdirectory: "CautionWarning")!
    }
    public static var timersInterfaceURL: URL {
        Bundle.module.url(forResource: "interface", withExtension: "json", subdirectory: "Timers")!
    }
    public static var engineControlsInterfaceURL: URL {
        Bundle.module.url(forResource: "interface", withExtension: "json", subdirectory: "EngineControls")!
    }
    public static var propulsionInstrumentsInterfaceURL: URL {
        Bundle.module.url(forResource: "interface", withExtension: "json", subdirectory: "PropulsionInstruments")!
    }
    public static var cautionWarningInterfaceURL: URL {
        Bundle.module.url(forResource: "interface", withExtension: "json", subdirectory: "CautionWarning")!
    }
}
