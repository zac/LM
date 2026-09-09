import Testing
@testable import LM

@MainActor
struct LMOneMinuteDemoTests {
    @Test func cockpitDefaultsToTwoMinutesAndPreservesExplicitCheckpoints() {
        #expect(PoweredDescentSession.StartPoint.cockpitLaunch(arguments: []) == .twoMinuteApproach)
        #expect(PoweredDescentSession.StartPoint.cockpitLaunch(arguments: ["--cockpit-start-p65"]) == .p65TerminalDescent)
        #expect(PoweredDescentSession.StartPoint.cockpitLaunch(arguments: ["--cockpit-start-p64"]) == .p64Approach)
    }
}
