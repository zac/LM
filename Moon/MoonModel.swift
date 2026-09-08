import LunarMap
import LunarMapExplorer
import SwiftUI

@MainActor @Observable
final class MoonModel {
    enum SpaceState { case closed, inTransition, open }
    static let controlsID = "MoonControls"
    static let spaceID = "MoonExplorer"
    let session = LunarExplorerSession()
    let arguments: [String]
    var spaceState = SpaceState.closed

    init(options: LunarMapLaunchOptions, arguments: [String]) {
        self.arguments = arguments
        session.configure(options: options)
    }
}
