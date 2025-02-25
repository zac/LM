//
//  MainMenuViewModel.swift
//  LM
//
//  Created by Zac White on 1/25/25.
//

import SwiftUI

/// Maintains app-wide state
@MainActor
@Observable
class MainMenuViewModel {
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed
}
