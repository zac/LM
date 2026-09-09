import Testing
@testable import LM

@MainActor
struct LMOneMinuteDemoTests {
    @Test func shortCockpitDemoUsesExistingTerminalCheckpointAndPreservesLongApproach() {
        #expect(PoweredDescentSession.StartPoint.cockpitLaunch(arguments: []) == .p65TerminalDescent)
        #expect(PoweredDescentSession.StartPoint.cockpitLaunch(arguments: ["--cockpit-start-p65"]) == .p65TerminalDescent)
        #expect(PoweredDescentSession.StartPoint.cockpitLaunch(arguments: ["--cockpit-start-p64"]) == .p64Approach)
    }
}
