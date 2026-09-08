import Foundation
import Testing
@testable import LM

@MainActor
@Suite(.serialized)
struct LMDescentControlLifecycleTests {
    @Test func rodRejectsStaleSamplesAfterReleasePauseAndSceneChanges() throws {
        let session = PoweredDescentSession()
        #expect(session.beginRODInteraction() == nil)
        session.start(from: .p65TerminalDescent)
        defer { session.stop() }
        let first = try #require(session.beginRODInteraction())
        #expect(session.updateRODInteraction(.descendPlus, generation: first))
        #expect(session.rodSwitchPosition == .descendPlus)
        #expect(session.updateRODInteraction(.descendMinus, generation: first))
        #expect(session.rodSwitchPosition == .descendMinus)
        session.releaseRODInteraction()
        #expect(session.rodSwitchPosition == .neutral)
        #expect(!session.updateRODInteraction(.descendMinus, generation: first))
        let beforePause = try #require(session.beginRODInteraction())
        #expect(session.updateRODInteraction(.descendMinus, generation: beforePause))
        session.pause()
        #expect(session.rodSwitchPosition == .neutral)
        #expect(session.beginRODInteraction() == nil)
        session.resume()
        #expect(!session.updateRODInteraction(.descendPlus, generation: beforePause))
        let beforeInactive = try #require(session.beginRODInteraction())
        session.setSceneActive(false)
        session.setSceneActive(true)
        #expect(!session.updateRODInteraction(.descendPlus, generation: beforeInactive))
        let beforeStop = try #require(session.beginRODInteraction())
        session.stop()
        session.start(from: .p65TerminalDescent)
        #expect(!session.updateRODInteraction(.descendPlus, generation: beforeStop))
    }

    @Test func physicalModeSelectionIsGuardedAndReleaseRetainsMaintainedState() {
        let session = PoweredDescentSession()
        #expect(!session.selectPhysicalAttitudeMode(.attitudeHold))
        session.start(from: .p65TerminalDescent)
        defer { session.stop() }
        #expect(session.selectPhysicalAttitudeMode(.attitudeHold))
        session.releaseCrewControls()
        #expect(session.attitudeMode == .attitudeHold)
        session.pause()
        #expect(!session.selectPhysicalAttitudeMode(.automatic))
        #expect(session.attitudeMode == .attitudeHold)
        session.resume()
        #expect(session.selectPhysicalAttitudeMode(.automatic))
    }
}
