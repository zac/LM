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

    var immersiveSpaceID: String { moonSpaceID }
    var immersiveSpaceState = ImmersiveSpaceState.closed
    var descentSpaceState = ImmersiveSpaceState.closed
    var session = PoweredDescentSession()
}
