import SwiftUI
import Testing
@testable import LM

@Suite("LM cockpit immersion policy")
struct LMCockpitImmersionPolicyTests {
    @Test func sealedCockpitRequiresFullImmersionWithoutPassthrough() {
        #expect(LMCockpitImmersionPolicy.mode == .full)
        #expect(!LMCockpitImmersionPolicy.passthroughIsVisible)
        #expect(LMCockpitImmersionPolicy.style is FullImmersionStyle)
    }

    @Test func fullImmersionRetainsMissionWindowsAndPhysicalHandInteraction() {
        #expect(LMCockpitImmersionPolicy.keepsApplicationWindowsVisible)
        #expect(LMCockpitImmersionPolicy.keepsUpperLimbsVisible)
        #expect(LMCockpitImmersionPolicy.appleImmersiveSpacesURL.contains("apple.com"))
    }
}
