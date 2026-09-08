import LunarMapExplorer
import LunarMap
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
    var cockpitCoordinate: LMSelenographicCoordinate?
    var lunarExplorerSession = LunarExplorerSession()
    var session = PoweredDescentSession()

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        // Configure before any restorable window is created. visionOS can
        // relaunch directly into the Explorer controls window, bypassing the
        // powered-descent view that normally handles automation arguments.
        lunarExplorerSession.configure(arguments: arguments)
        if let value = arguments.first(where: { $0.hasPrefix("--cockpit-coordinate=") }) {
            cockpitCoordinate = LMLunarNavigation.parse(String(value.dropFirst("--cockpit-coordinate=".count)))
        }
    }

    func requestCockpitRecenter() {
        cockpitRecenterRequest &+= 1
    }
}
