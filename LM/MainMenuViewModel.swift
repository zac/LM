import SwiftUI

/// Maintains app-wide state
@MainActor
@Observable
class MainMenuViewModel {
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    let moonSpaceID = "ImmersiveSpace"
    let descentSpaceID = "PoweredDescent"
    let cockpitSpaceID = "TerminalDescentCockpit"
    let descentConsoleWindowID = "PoweredDescentConsole"
    let cockpitMissionControlWindowID = "CockpitMissionControl"

    var immersiveSpaceID: String { moonSpaceID }
    var immersiveSpaceState = ImmersiveSpaceState.closed
    var descentSpaceState = ImmersiveSpaceState.closed
    var cockpitSpaceState = ImmersiveSpaceState.closed
    var session = PoweredDescentSession()
}
