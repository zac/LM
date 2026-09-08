import Foundation
import LMKit
import RealityKit
import Testing
@testable import LM

@MainActor
@Suite(.serialized)
struct LMSystemsIntegrationTests {
    @Test func downGestureReturningThroughCenterDoesNotSelectUp() throws {
        var state = LMEventTimerState()
        state.update(.init(timelineID: 1, elapsedSeconds: 0))
        let id = "EventTimer_ResetCount"
        #expect(LMEventTimerControlRouting.command(id: id, position: 1) == nil)
        state.send(try #require(LMEventTimerControlRouting.command(id: id, position: 2)))
        #expect(state.selectedDirection == .down)
        #expect(LMEventTimerControlRouting.command(id: id, position: 1) == nil)
        state.cancelSlew()
        #expect(state.selectedDirection == .down)
        state.send(try #require(LMEventTimerControlRouting.command(id: id, position: 1, explicitCenterSelection: true)))
        #expect(state.selectedDirection == .up)
    }

    @Test func timerInputTokensInvalidateOnPauseSceneLossAndRestart() {
        let session = PoweredDescentSession()
        session.start(from: .p65TerminalDescent)
        defer { session.stop() }
        let first = session.eventTimerInteractionGeneration
        session.pause()
        session.resume()
        #expect(!session.sendEventTimer(.start, generation: first))
        let second = session.eventTimerInteractionGeneration
        session.setSceneActive(false)
        session.setSceneActive(true)
        #expect(!session.sendEventTimer(.secondSlew(.tens), generation: second))
        let timeline = session.eventTimerTimeline
        session.restart()
        #expect(session.eventTimerTimeline != timeline)
        #expect(session.eventTimer.minuteSlew == nil && session.eventTimer.secondSlew == nil)
    }

    @Test func terminalPadOutcomeWithoutProbeDataDoesNotAnnounceProbeContact() {
        var director = LMCockpitExperienceDirector()
        let cues = director.consume(program: 66, altitudeMeters: 0, outcome: .softLanding, hasSurfaceContact: nil)
        #expect(!cues.contains { $0.id == .contact })
        #expect(cues.contains { $0.id == .softLanding })
    }

    @Test func engineDefersUntilDescentRateThenPreservesPeerAndRejectsDuplicates() throws {
        let scene = LMCommanderStationScene()
        #expect(scene.installCommanderAssembly())
        let assembly = try #require(scene.commanderAssembly)
        #expect(!scene.installSystemsHardware("EngineButtons"))
        #expect(assembly.slotOccupancy["Panel5__Engine"] == nil)
        #expect(scene.installDescentControl(.descentRate))
        let rate = try #require(scene.importedDescentRate)
        let parent = rate.root.parent
        let transform = rate.root.transform
        #expect(scene.installSystemsHardware("EngineButtons"))
        #expect(rate.root.parent === parent && rate.root.transform == transform)
        #expect(assembly.slotOccupancy["Panel5__Engine"]?.componentIDs == ["DescentRate", "EngineButtons"])
        let hardware = try #require(scene.systemsHardware["EngineButtons"])
        #expect(LMCommanderStationAssembly.descendants(hardware.root).allSatisfy {
            $0.components[InputTargetComponent.self] == nil && $0.components[CollisionComponent.self] == nil
        })
        let count = parent?.children.count
        #expect(scene.installSystemsHardware("EngineButtons"))
        #expect(parent?.children.count == count)
        let second = try LMImportedSystemsHardware(asset: Entity.load(contentsOf: LMKitAssets.engineButtonsURL),
            interfaceData: Data(contentsOf: LMKitAssets.engineControlsInterfaceURL), kind: "EngineButtons")
        #expect(throws: (any Error).self) { try assembly.installComplementaryEngineButtons(second.root) }
        #expect(second.root.parent == nil)
    }

    @Test func contactRetainsUnknownFalseTrueAndHasNoControlInput() throws {
        let contact = try LMImportedLunarContact(asset: Entity.load(contentsOf: LMKitAssets.lunarContactURL),
            interfaceData: Data(contentsOf: LMKitAssets.engineControlsInterfaceURL), pilot: false)
        contact.apply(nil)
        #expect(contact.probeContact == nil)
        contact.apply(false)
        #expect(contact.probeContact == false)
        contact.apply(true)
        #expect(contact.probeContact == true)
        contact.apply(nil)
        #expect(contact.probeContact == nil)
        #expect(LMCommanderStationAssembly.descendants(contact.root).allSatisfy { $0.components[InputTargetComponent.self] == nil })
    }

    @Test func neutralSystemsAndMappedCautionWarningPreserveUnsupportedSignals() throws {
        let scene = LMCommanderStationScene()
        #expect(scene.installCommanderAssembly())
        #expect(scene.installAltitudeRate())
        let altitude = try #require(scene.importedAltitudeRate)
        let pose = altitude.root.transform
        #expect(scene.installSystemsHardware("PropulsionInstruments"))
        #expect(altitude.root.transform == pose)
        let propulsion = try #require(scene.systemsHardware["PropulsionInstruments"])
        for node in LMCommanderStationAssembly.descendants(propulsion.root) where node.name.hasPrefix("Segment") {
            #expect(!node.isEnabled)
        }
        #expect(scene.installStaticOverlay("CautionWarning", assetURL: LMKitAssets.cautionWarningURL,
            interfaceURL: LMKitAssets.cautionWarningInterfaceURL, schema: "lmkit.caution-warning.interface.v1"))
        #expect(scene.commanderAssembly?.slotOccupancy["Panel1__Warning"]?.note == "Visual hardware only")
        #expect(scene.commanderAssembly?.slotOccupancy["Panel2__Caution"]?.note == "Visual hardware only")
    }

    @Test func timerReadoutsAndControlsInstallTogetherMissionRemainsUnavailable() throws {
        let scene = LMCommanderStationScene()
        #expect(scene.installCommanderAssembly())
        #expect(!scene.installTimers { throw LMImportedSystemsHardware.invalid("Missing timer package") })
        #expect(scene.commanderAssembly?.slotOccupancy["Panel1__Timers"] == nil)
        #expect(scene.commanderAssembly?.slotOccupancy["Panel3__TimerHeaters"] == nil)
        #expect(scene.installTimers())
        let timers = try #require(scene.importedTimers)
        #expect(!timers.missionTimeAvailable)
        let countPivot = try LMCommanderStationAssembly.unique("EventTimer_ResetCount_Pivot", in: timers.controls)
        let fixedPosition = countPivot.position
        timers.setControl("EventTimer_ResetCount", position: 2)
        #expect(abs(countPivot.orientation.real - 1) > 0.01)
        timers.releaseControls(direction: .down)
        #expect(abs(countPivot.orientation.real) > 0.99999 && countPivot.position == fixedPosition)
        var state = LMEventTimerState()
        timers.apply(state)
        #expect(timers.displayedEventDigits == nil)
        state.update(.init(timelineID: 1, elapsedSeconds: 10))
        state.send(.set(minutes: 12, seconds: 34))
        timers.apply(state)
        #expect(timers.displayedEventDigits == [1, 2, 3, 4])
        state.update(.init(timelineID: 1, elapsedSeconds: 11, isReplay: true))
        timers.apply(state)
        #expect(timers.displayedEventDigits == nil && !timers.missionTimeAvailable)
        #expect(scene.commanderAssembly?.slotOccupancy["Panel5__Timer"] == nil)
        #expect(scene.commanderAssembly?.slotOccupancy["Panel1__Timers"]?.coverage == .partialRegion)
        #expect(scene.commanderAssembly?.slotOccupancy["Panel3__TimerHeaters"]?.coverage == .partialRegion)
    }
}
