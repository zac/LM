import SwiftUI

/// Presentation contract for the sealed LM cockpit.
///
/// Apple's full immersion style replaces passthrough while preserving this
/// app's windows in front of virtual content. That is the required composition
/// for an opaque pressure vessel whose windows reveal only the lunar scene.
enum LMCockpitImmersionPolicy {
    enum Mode: Equatable, Sendable {
        case full
    }

    static let mode = Mode.full
    static let passthroughIsVisible = false
    static let keepsApplicationWindowsVisible = true
    static let keepsUpperLimbsVisible = true
    static let appleImmersiveSpacesURL =
        "https://developer.apple.com/documentation/swiftui/immersive-spaces"

    static var style: any ImmersionStyle {
        switch mode {
        case .full:
            return .full
        }
    }
}
