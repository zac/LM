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
    let lunarExplorerSpaceID = "LunarExplorer"
    let descentSpaceID = "PoweredDescent"
    let cockpitSpaceID = "TerminalDescentCockpit"
    let descentConsoleWindowID = "PoweredDescentConsole"
    let lunarExplorerControlsWindowID = "LunarExplorerControls"
    let cockpitMissionControlWindowID = "CockpitMissionControl"

    var immersiveSpaceID: String { moonSpaceID }
    var immersiveSpaceState = ImmersiveSpaceState.closed
    var lunarExplorerSpaceState = ImmersiveSpaceState.closed
    var descentSpaceState = ImmersiveSpaceState.closed
    var cockpitSpaceState = ImmersiveSpaceState.closed
    var cockpitRecenterRequest = 0
    var lunarExplorerSession = LunarExplorerSession()
    var session = PoweredDescentSession()

    func requestCockpitRecenter() {
        cockpitRecenterRequest &+= 1
    }
}
