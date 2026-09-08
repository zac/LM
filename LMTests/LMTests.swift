@testable import LunarMapExplorer
@testable import LunarMap
import Foundation
import CryptoKit
import CoreGraphics
import ImageIO
import RealityKit
import Testing
import simd
import AGC
import LMCore
@testable import LM

struct LMTests {

    @Test @MainActor func rodSwitchIsSpringLoadedAndMutuallyExclusive() {
        let session = PoweredDescentSession()

        session.setROD(.descendPlus, held: true)
        #expect(session.rodSwitchPosition == .descendPlus)

        session.setROD(.descendMinus, held: true)
        #expect(session.rodSwitchPosition == .descendMinus)

        session.setROD(.descendPlus, held: false)
        #expect(session.rodSwitchPosition == .descendMinus)

        session.setROD(.descendMinus, held: false)
        #expect(session.rodSwitchPosition == .neutral)
    }

    @Test func bundledAutomaticReplayIsContactGatedAndStaysAutomatic() throws {
        let recording = try PoweredDescentSession.bundledAutomaticRecording()
        let final = try #require(recording.frames.last)

        #expect(recording.controlMode == .automatic)
        #expect(recording.frames.first?.programNumber == 65)
        #expect(recording.frames.allSatisfy { $0.panelState == .automatic })
        #expect(recording.frames.allSatisfy {
            $0.rhcPitch == 0 && $0.rhcYaw == 0 && $0.rhcRoll == 0
        })
        #expect(recording.frames.allSatisfy { $0.descentRateChannel16 == 0 })
        #expect(final.vehicleState.flightOutcome == .softLanding)
        #expect(final.vehicleState.surfaceContact != nil)
    }

    @Test func bundledP66ReplayIsContactGatedAndContainsCrewInputs() throws {
        let recording = try PoweredDescentSession.bundledP66Recording()
        let final = try #require(recording.frames.last)

        #expect(recording.controlMode == .astronautP66)
        #expect(recording.frames.first?.programNumber == 65)
        #expect(recording.frames.contains { $0.programNumber == 66 })
        #expect(recording.frames.contains { $0.panelState == .p66AttitudeHold })
        #expect(recording.frames.contains { $0.rhcPitch != 0 || $0.rhcYaw != 0 || $0.rhcRoll != 0 })
        #expect(recording.frames.contains { $0.descentRateChannel16 != 0 })
        #expect(final.vehicleState.flightOutcome == .softLanding)
        #expect(final.vehicleState.surfaceContact != nil)
    }





    @Test func fdaiGASTAMapsSimulationPitchToTheFDAIInnerGimbal() {
        let angle = 30.0 * .pi / 180.0
        let attitude = LMQuaternion.fromAxisAngle(
            axis: LMVector3D(x: 1),
            radians: angle
        )
        let neutral = FDAIOrientation.ballOrientation(for: .identity)
        let rotated = FDAIOrientation.ballOrientation(for: attitude)
        let relative = simd_normalize(rotated * neutral.inverse)
        let redYawPole = rotated.act(SIMD3<Float>(0, 1, 0))

        #expect(abs(relative.angle - Float(angle)) < 1e-5)
        #expect(abs(redYawPole.x) < 1e-5)
        #expect(abs(redYawPole.y - 1) < 1e-5)
        #expect(abs(redYawPole.z) < 1e-5)
    }

    @Test func fdaiCaptionUsesNASAGimbalsForPDIPitch() {
        let pdi = LMQuaternion.fromAxisAngle(
            axis: LMVector3D(x: 1),
            radians: 95 * .pi / 180
        )
        let gimbals = FDAIOrientation.nasaGimbalDegrees(for: pdi)
        #expect(abs(gimbals.q - 95) < 0.5)
        #expect(abs(gimbals.p) < 2)
        #expect(abs(gimbals.r) < 2)
    }

    @Test func fdaiKeepsTheRedGimbalLockPoleOutOfNormalPoweredDescentView() throws {
        let pdi = LMPoweredDescentScenario.apollo11SourceBacked.initialState.attitude
        let pdiOrientation = FDAIOrientation.ballOrientation(for: pdi)
        let pdiRedPole = pdiOrientation.act(SIMD3<Float>(0, 1, 0))
        let terminal = try PoweredDescentSession.bundledP65Checkpoint().vehicleState.attitude
        let terminalRedPole = FDAIOrientation.ballOrientation(for: terminal)
            .act(SIMD3<Float>(0, 1, 0))
        let gimbals = FDAIOrientation.nasaGimbalDegrees(for: pdi)

        #expect(abs(pdiRedPole.x) < 1e-5)
        #expect(abs(pdiRedPole.y - 1) < 1e-5)
        #expect(abs(pdiRedPole.z) < 1e-5)
        #expect(terminalRedPole.y > 0.99)
        #expect(abs(gimbals.p) < 1e-5)
        #expect(abs(gimbals.q - 95) < 0.5)
        #expect(abs(gimbals.r) < 1e-5)
    }



    @Test func rcsJetMapCoversEveryLuminaryJetUniquely() {
        #expect(LMRCSJetMapping.table.count == LMRCSJet.allCases.count)
        #expect(Set(LMRCSJetMapping.table.values).count == LMRCSJet.allCases.count)
        #expect(Set(LMRCSJetMapping.table.keys) == Set(LMRCSJet.allCases))
    }

    @Test func effectAnchorUsesTheNozzleFaceWithoutDriftingAcrossOtherAxes() {
        let bounds = BoundingBox(
            min: SIMD3<Float>(-1, -2, -3),
            max: SIMD3<Float>(1, 2, 3)
        )

        #expect(LunarModuleModel.effectAnchor(in: bounds, direction: SIMD3(0, -1, 0)) == SIMD3(0, -2, 0))
        #expect(LunarModuleModel.effectAnchor(in: bounds, direction: SIMD3(1, 0, 0)) == SIMD3(1, 0, 0))
        #expect(LunarModuleModel.effectAnchor(in: bounds, direction: SIMD3(0, 0, 1)) == SIMD3(0, 0, 3))
    }

    @Test func tabletopContactConstraintKeepsEveryRotatedModelCornerAboveThePad() {
        let bounds = BoundingBox(
            min: SIMD3<Float>(-0.16, -0.16, -0.16),
            max: SIMD3<Float>(0.16, 0.10, 0.16)
        )
        let orientation = simd_quatf(angle: .pi / 5, axis: simd_normalize(SIMD3<Float>(1, 0, 1)))
        let position = LunarModuleModel.position(
            .zero,
            keeping: bounds,
            orientation: orientation,
            above: 0
        )

        for x in [bounds.min.x, bounds.max.x] {
            for y in [bounds.min.y, bounds.max.y] {
                for z in [bounds.min.z, bounds.max.z] {
                    let worldY = position.y + orientation.act(SIMD3(x, y, z)).y
                    #expect(worldY >= -1e-6)
                }
            }
        }
    }

    @Test @MainActor func loadedLMAnchorsDPSAndRCSPlumesToTheirRealNozzleMeshes() throws {
        let model = LunarModuleModel(mode: .kinematicGuidance)
        let root = model.rootEntity
        let bell = try #require(root.findEntity(named: "group13_pC"))
        let dpsPlume = try #require(root.findEntity(named: "DPSPlume"))
        let bellBounds = bell.visualBounds(relativeTo: root)

        #expect(abs(dpsPlume.position(relativeTo: root).y - bellBounds.min.y) < 1e-5)
        #expect(dpsPlume.parent?.name == "LunarModuleRoot")
        #expect(simd_dot(
            dpsPlume.orientation(relativeTo: root).act(SIMD3<Float>(0, 1, 0)),
            SIMD3<Float>(0, -1, 0)
        ) > 0.999)

        for (entityName, thruster) in LunarModuleModel.thrusterEntityNames {
            let nozzle = try #require(root.findEntity(named: entityName))
            let plume = try #require(root.findEntity(named: "rcs-plume-\(thruster.rawValue)"))
            let thrustDirection = try #require(LunarModuleModel.thrusterDirections[thruster])
            let exhaustDirection = -simd_normalize(thrustDirection)
            let expectedAnchor = LunarModuleModel.effectAnchor(
                in: nozzle.visualBounds(relativeTo: root),
                direction: exhaustDirection
            )

            #expect(simd_distance(plume.position(relativeTo: root), expectedAnchor) < 1e-5)
            #expect(plume.parent?.name == "LunarModuleRoot")
            #expect(simd_dot(
                plume.orientation(relativeTo: root).act(SIMD3<Float>(0, 1, 0)),
                exhaustDirection
            ) > 0.999)
        }
    }
}

@Suite("ACA analog input mapping")
struct ACAInputMappingTests {
    let mapper = LMACAInputMapper()

    @Test func centerDeadZoneSuppressesSmallDeflections() {
        #expect(mapper.counts(for: 0) == 0)
        #expect(mapper.counts(for: 0.07) == 0)
        #expect(mapper.counts(for: -0.08) == 0)
        #expect(mapper.counts(for: 0.081) != 0)
    }

    @Test func nominalFullTravelMapsTo42CountsBothWays() {
        #expect(mapper.counts(for: 1) == 42)
        #expect(mapper.counts(for: -1) == -42)
        #expect(mapper.counts(for: 0.5) == 21)
    }

    @Test func outOfRangeExcursionStopsAtTheMechanicalClamp() {
        #expect(mapper.counts(for: 1.4) == 57)
        #expect(mapper.counts(for: -3.0) == -57)
        #expect(mapper.counts(for: .infinity) == 57)
        #expect(mapper.counts(for: -.infinity) == -57)
    }

    @Test func combinedButtonAndAnalogCommandsClampAtMechanicalStops() {
        #expect(mapper.combined(buttonCounts: 42, normalizedAxis: 0.5) == 63.clampedToMechanicalStops)
        #expect(mapper.combined(buttonCounts: 42, normalizedAxis: -1) == 0)
        #expect(mapper.combined(buttonCounts: -42, normalizedAxis: -1) == -57)
        #expect(mapper.combined(buttonCounts: 0, normalizedAxis: 0) == 0)
    }

    @Test func releaseReturnsEveryAxisToNeutralWithinOneFrame() {
        let mapper = LMACAInputMapper()
        var axes = LMACANormalizedInput(pitch: 1, yaw: -0.6, roll: 0.3)
        let deflected = (
            mapper.combined(buttonCounts: 0, normalizedAxis: axes.pitch),
            mapper.combined(buttonCounts: 0, normalizedAxis: axes.yaw),
            mapper.combined(buttonCounts: 0, normalizedAxis: axes.roll)
        )
        #expect(deflected == (42, -25, 13))

        axes = .neutral
        let released = (
            mapper.combined(buttonCounts: 0, normalizedAxis: axes.pitch),
            mapper.combined(buttonCounts: 0, normalizedAxis: axes.yaw),
            mapper.combined(buttonCounts: 0, normalizedAxis: axes.roll)
        )
        #expect(released == (0, 0, 0))
    }

    @Test @MainActor func sessionEncodesNegativeACAAsAGCOnesComplement() {
        let session = PoweredDescentSession()
        session.setACA(pitch: -1, yaw: 1, roll: -0.5)

        let input = session.effectiveRHCInput
        #expect(input.pitch == AGCSinglePrecision.encode(value: -42, scale: 14).word)
        #expect(input.yaw == AGCSinglePrecision.encode(value: 42, scale: 14).word)
        #expect(input.roll == AGCSinglePrecision.encode(value: -21, scale: 14).word)
        #expect(input.pitch != (-42 & 0o77777))
    }
}

extension Int {
    /// ±57-count ACA mechanical stops.
    fileprivate var clampedToMechanicalStops: Int {
        Swift.min(Swift.max(self, -LMACAInputMapper.mechanicalClampCounts), LMACAInputMapper.mechanicalClampCounts)
    }
}

/// Live checkpoint-resumed flight against the bundled P65 fixture.
@Suite("Powered-descent checkpoint session", .serialized)
struct PoweredDescentCheckpointSessionTests {
    @Test @MainActor func bundledP64CheckpointMatchesBundledCoreImageAndScenario() throws {
        let checkpoint = try PoweredDescentSession.bundledP64Checkpoint()

        #expect(checkpoint.schemaVersion == LMSimulationCheckpoint.schemaVersion)
        #expect(checkpoint.scenarioID == LMPoweredDescentScenario.apollo11SourceBacked.id)
        #expect(checkpoint.vehicleState.flightOutcome == .inFlight)
        #expect(checkpoint.vehicleState.altitudeMeters > 100)
    }

    @Test @MainActor func startFromP64RestoresLiveLandingPointDisplay() async throws {
        let session = PoweredDescentSession()
        guard case .idle = session.status else {
            Issue.record("session should load idle, got \(session.status)")
            return
        }

        session.start(from: .p64Approach)
        defer { session.stop() }

        try await waitUntil("P64 checkpoint restore", timeoutSeconds: 10) {
            session.isLandingPointDisplayActive
        }
        #expect(session.programNumber == 64)
        #expect(session.dsky?.verb == "06")
        #expect(session.dsky?.noun == "64")
        #expect(!session.isLandingPointRedesignationEnabled)
        let lookAngle = try #require(
            session.landingPointLookAngleDegrees,
            "N64 R1 was \(session.dsky?.r1 ?? "nil")"
        )
        let redesignationTime = try #require(
            session.landingPointRedesignationTimeRemainingSeconds,
            "N64 R1 was \(session.dsky?.r1 ?? "nil")"
        )
        #expect((0...75).contains(lookAngle))
        #expect(redesignationTime > 0)
        #expect(session.vehicleState?.flightOutcome == .inFlight)

        session.sendDSKYKey(.pro)
        try await waitUntil("P64 redesignation enable", timeoutSeconds: 10) {
            session.isLandingPointRedesignationEnabled
                && session.dsky?.proKeyPressed == false
        }
    }

    @Test func p64PROAndACAChangeLuminaryLandingTarget() async throws {
        let checkpoint = try PoweredDescentSession.bundledP64Checkpoint()
        let binURL = try #require(Bundle.main.url(forResource: "Luminary099", withExtension: "bin"))
        let neutralRuntime = try LMSimulationRuntime(binFile: binURL, scenario: .apollo11SourceBacked)
        let redesignationRuntime = try LMSimulationRuntime(binFile: binURL, scenario: .apollo11SourceBacked)
        var neutral = try await neutralRuntime.restore(from: checkpoint)
        var redesigned = try await redesignationRuntime.restore(from: checkpoint)

        for runtime in [neutralRuntime, redesignationRuntime] {
            await runtime.sendPRO(pressed: true)
        }
        neutral = await neutralRuntime.step(
            deltaTime: 0.15,
            input: .autoLand(from: neutral.vehicleState)
        )
        redesigned = await redesignationRuntime.step(
            deltaTime: 0.15,
            input: .autoLand(from: redesigned.vehicleState)
        )
        for runtime in [neutralRuntime, redesignationRuntime] {
            await runtime.sendPRO(pressed: false)
        }
        #expect(!neutral.agc.dsky.verbNounFlash)
        #expect(!redesigned.agc.dsky.verbNounFlash)

        let landBefore = await landingTargetWords(redesignationRuntime)
        let neutralLandBefore = await landingTargetWords(neutralRuntime)
        #expect(landBefore == neutralLandBefore)

        // P64 maps the ACA pitch breakout to LPD elevation and the roll
        // breakout to LPD azimuth. REDESMON counts the requested increment
        // when the controller is released back into detent.
        let aca = LMRotationalHandControllerInput.signedCounts(pitch: 42, roll: 42)
        for _ in 0..<40 {
            neutral = await neutralRuntime.step(
                deltaTime: 0.05,
                input: .autoLand(from: neutral.vehicleState)
            )
            redesigned = await redesignationRuntime.step(
                deltaTime: 0.05,
                input: .autoLand(
                    from: redesigned.vehicleState,
                    rotationalHandController: aca
                )
            )
        }
        let heldChannel31 = try #require(redesigned.agc.inputChannels[0o31])
        #expect(
            (heldChannel31 & LMPoweredDescentPanel.channel31PositivePitch) == 0,
            "held CH31 was \(String(heldChannel31, radix: 8))"
        )
        #expect(
            (heldChannel31 & LMPoweredDescentPanel.channel31PositiveRoll) == 0,
            "held CH31 was \(String(heldChannel31, radix: 8))"
        )
        let heldCheckpoint = await redesignationRuntime.captureCheckpoint()
        let heldMonitorBits = await redesignationRuntime.readErasable(ecadr: 0o1265)
        #expect(!heldCheckpoint.agc.trap31A, "CH31 trap never fired")
        #expect(heldMonitorBits != 0, "PITFALL/REDESMON never latched CH31 directions")
        // An omitted ACA sample means "keep holding the prior hardware state."
        // Send an explicit centered controller so REDESMON sees the detent
        // transition, then allow the next P64 guidance passes to consume it.
        let centeredACA = LMRotationalHandControllerInput.signedCounts()
        for _ in 0..<100 {
            neutral = await neutralRuntime.step(
                deltaTime: 0.05,
                input: .autoLand(from: neutral.vehicleState)
            )
            redesigned = await redesignationRuntime.step(
                deltaTime: 0.05,
                input: .autoLand(
                    from: redesigned.vehicleState,
                    rotationalHandController: centeredACA
                )
            )
        }

        let neutralLand = await landingTargetWords(neutralRuntime)
        let redesignedLand = await landingTargetWords(redesignationRuntime)
        #expect(neutral.agc.dsky.programNumber == 64)
        #expect(redesigned.agc.dsky.programNumber == 64)
        #expect(redesignedLand != neutralLand)
        #expect(redesignedLand != landBefore)
    }

    @Test @MainActor func bundledP65CheckpointMatchesBundledCoreImageAndScenario() throws {
        let checkpoint = try PoweredDescentSession.bundledP65Checkpoint()

        #expect(checkpoint.schemaVersion == LMSimulationCheckpoint.schemaVersion)
        #expect(checkpoint.scenarioID == LMPoweredDescentScenario.apollo11SourceBacked.id)
        // Terminal-descent entry at approximately 143 ft.
        #expect(abs(checkpoint.vehicleState.altitudeMeters - 43.8) < 5)
    }

    @Test @MainActor func startFromP65RestoresLiveLuminaryAndAttHoldSelectsP66() async throws {
        let session = PoweredDescentSession()
        guard case .idle = session.status else {
            Issue.record("session should load idle, got \(session.status)")
            return
        }

        session.start(from: .p65TerminalDescent)
        defer { session.stop() }

        try await waitUntil("checkpoint restore", timeoutSeconds: 10) {
            session.snapshot?.agc.dsky.programNumber == 65
        }
        let restored = try #require(session.snapshot)
        #expect(restored.vehicleState.flightOutcome == .inFlight)
        // Restored checkpoint time is the captured P65 entry time (~775 s).
        #expect(abs(restored.timeSeconds - 775.82) < 2)

        // ATT HOLD transitions the live AGC from P65 into P66. Luminary's
        // GUILDENSTERN selects P66 on the attitude-hold discrete only together
        // with a ROD switch click, so follow the crew flow: select ATT HOLD,
        // then momentarily press DESCEND+ before releasing to center.
        session.attitudeMode = .attitudeHold
        try await Task.sleep(for: .milliseconds(120))
        session.setROD(.descendPlus, held: true)
        try await Task.sleep(for: .milliseconds(150))
        session.setROD(.descendPlus, held: false)
        try await waitUntil(
            "P66 transition",
            timeoutSeconds: 90,
            describe: {
                "prog=\(session.programNumber.map(String.init) ?? "none")"
                    + " t=\(String(format: "%.1f", session.snapshot?.timeSeconds ?? -1))"
                    + " alt=\(String(format: "%.1f", session.snapshot?.vehicleState.altitudeMeters ?? -1))"
            },
            condition: { session.programNumber == 66 }
        )

        // Releasing the ACA returns all axes to neutral for the next frame.
        session.setACA(pitch: 1, yaw: 0.4, roll: -0.2)
        #expect(session.effectiveRHCPitch == 42)
        session.releaseACA()
        #expect(session.effectiveRHCPitch == 0)
        #expect(session.effectiveRHCYaw == 0)
        #expect(session.effectiveRHCRoll == 0)

        session.stop()
        #expect(!session.isRunning)
    }

    @Test @MainActor func rapidRestartReRestoresTheCheckpointWithoutABootCycle() async throws {
        let session = PoweredDescentSession()
        session.start(from: .p65TerminalDescent)
        defer { session.stop() }

        try await waitUntil("first restore", timeoutSeconds: 10) {
            session.snapshot?.agc.dsky.programNumber == 65
        }
        session.stop()

        let restartWallStart = Date()
        session.restart()
        try await waitUntil("rapid restart", timeoutSeconds: 10) {
            session.isRunning && session.snapshot?.agc.dsky.programNumber == 65
        }
        let wallSeconds = Date().timeIntervalSince(restartWallStart)
        #expect(wallSeconds < 5, "restart must re-restore quickly, took \(wallSeconds)s")
        let snapshot = try #require(session.snapshot)
        // The restored cycle must be the captured checkpoint cycle, not a
        // fresh Luminary boot (which lands near one million MCTs).
        let checkpoint = try PoweredDescentSession.bundledP65Checkpoint()
        #expect(
            abs(Int64(snapshot.agc.cycle) - Int64(checkpoint.agc.cycleCounter)) < 400_000,
            "restart must resume from the checkpoint cycle, got \(snapshot.agc.cycle)"
        )
    }

    @Test @MainActor func bundledP65CheckpointFliesLiveToContact() async throws {
        let checkpoint = try PoweredDescentSession.bundledP65Checkpoint()
        let binURL = try #require(Bundle.main.url(forResource: "Luminary099", withExtension: "bin"))
        let runtime = try LMSimulationRuntime(
            binFile: binURL,
            scenario: .apollo11SourceBacked
        )
        var snapshot = try await runtime.restore(from: checkpoint)
        let deadline = snapshot.timeSeconds + 240

        while snapshot.timeSeconds < deadline,
              !snapshot.vehicleState.flightOutcome.isTerminal {
            snapshot = await runtime.step(
                deltaTime: LMSimulationPace.acceleratedDeltaSeconds,
                input: .autoLand(from: snapshot.vehicleState)
            )
        }

        #expect(snapshot.agc.dsky.programNumber == 65)
        #expect(snapshot.vehicleState.surfaceContact != nil)
        #expect(snapshot.vehicleState.flightOutcome == .softLanding)
        #expect(!snapshot.vehicleCommands.isMainEngineProducingThrust(
            outcome: snapshot.vehicleState.flightOutcome
        ))
    }

    @Test @MainActor func sceneDeactivationNeutralizesEveryMomentaryCrewControl() {
        let session = PoweredDescentSession()
        session.setRHC(pitch: true, yaw: true, roll: true)
        session.setACA(pitch: -0.4, yaw: 0.7, roll: -1)
        session.setROD(.descendPlus, held: true)

        session.setSceneActive(false)

        #expect(session.effectiveRHCPitch == 0)
        #expect(session.effectiveRHCYaw == 0)
        #expect(session.effectiveRHCRoll == 0)
        #expect(session.aca == .neutral)
        #expect(session.rodSwitchPosition == .neutral)
    }

    @Test @MainActor func missionPauseFreezesTheRunAndNeutralizesMomentaryControls() {
        let session = PoweredDescentSession()
        session.start(from: .p65TerminalDescent)
        session.setACA(pitch: 0.7, yaw: -0.4, roll: 0.2)
        session.setROD(.descendPlus, held: true)

        session.pause()

        #expect(session.isPaused)
        #expect(session.aca == .neutral)
        #expect(session.rodSwitchPosition == .neutral)
        session.resume()
        #expect(!session.isPaused)
        session.stop()
    }

    @MainActor
    private func waitUntil(
        _ label: String,
        timeoutSeconds: Double,
        describe: (() -> String)? = nil,
        condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        var description = "timed out after \(timeoutSeconds)s waiting for \(label)"
        if let describe {
            description += " (\(describe()))"
        }
        throw TimeoutError(label: label, timeoutSeconds: timeoutSeconds, stateDescription: description)
    }

    private func landingTargetWords(_ runtime: LMSimulationRuntime) async -> [Int] {
        var words = [Int]()
        for offset in 0..<6 {
            words.append(await runtime.readErasable(ecadr: Luminary099Erasable.land + offset))
        }
        return words
    }

    private struct TimeoutError: Error, CustomStringConvertible {
        let label: String
        let timeoutSeconds: Double
        let stateDescription: String?
        var description: String { stateDescription ?? "timed out after \(timeoutSeconds)s waiting for \(label)" }
    }
}

@Suite("Cockpit world mapping")
struct CockpitWorldMappingTests {
    let mapper = LMCockpitWorldMapper.fullScale

    @Test func vehicleOriginIsAlwaysAtTheFixedCockpitOrigin() {
        let position = LMVector3D(x: 18, y: -42, z: 43.8)
        let attitude = LMQuaternion.fromAxisAngle(
            axis: LMVector3D(z: 1),
            radians: 12 * .pi / 180
        )
        let vehiclePosition = mapper.realityPosition(from: position)
        let vehiclePoint = SIMD4(vehiclePosition.x, vehiclePosition.y, vehiclePosition.z, 1)
        let cockpitPoint = mapper.lunarWorldMatrix(
            position: position,
            attitude: attitude
        ) * vehiclePoint

        #expect(abs(cockpitPoint.x) < 1e-4)
        #expect(abs(cockpitPoint.y) < 1e-4)
        #expect(abs(cockpitPoint.z) < 1e-4)
    }

    @Test func identityAttitudePlacesSurfaceAtTrueAltitudeBelowTheCockpit() {
        let altitude = 43.8
        let transform = mapper.lunarWorldMatrix(
            position: LMVector3D(z: altitude),
            attitude: .identity
        )
        let siteInCockpit = transform * SIMD4<Float>(0, 0, 0, 1)

        #expect(abs(siteInCockpit.x) < 1e-5)
        #expect(abs(siteInCockpit.y + Float(altitude)) < 1e-4)
        #expect(abs(siteInCockpit.z) < 1e-5)
    }

    @Test func fullScaleMappingDoesNotCompressTerminalDescent() {
        let mapped = mapper.realityPosition(from: LMVector3D(x: 12, y: -25, z: 43.8))

        #expect(abs(mapped.x - 12) < 1e-5)
        #expect(abs(mapped.y - 43.8) < 1e-5)
        #expect(abs(mapped.z - 25) < 1e-5)
    }

    @Test func localTerrainElevationIsNormalizedUnderTheVehicle() {
        let position = LMVector3D(x: -547, y: 732, z: 0)
        let surfaceElevation = -5.4
        let transform = mapper.lunarWorldMatrix(
            position: position,
            attitude: .identity,
            surfaceElevationMeters: surfaceElevation
        )
        let surface = mapper.realityPosition(from: LMVector3D(
            x: position.x,
            y: position.y,
            z: surfaceElevation
        ))
        let underVehicle = transform * SIMD4(surface.x, surface.y, surface.z, 1)

        #expect(abs(underVehicle.x) < 1e-4)
        #expect(abs(underVehicle.y) < 1e-4)
        #expect(abs(underVehicle.z) < 1e-4)
    }
}

@Suite("Source-backed terrain tiles")
struct SourceBackedTerrainTileTests {

    @MainActor @Test func preparedBaseMeshPreservesDescriptorGeometry() async throws {
        let normal = simd_normalize(SIMD3<Float>(-0.25, 1, 0.125))
        let grid = LMTerrainMeshBuilder.VertexData(
            positions: [SIMD3(0, 0, 0), SIMD3(0, 0.25, -2),
                        SIMD3(2, 0.5, 0), SIMD3(2, 0.75, -2)],
            normals: Array(repeating: normal, count: 4),
            texCoords: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)],
            triangles: [0, 1, 2, 1, 3, 2])
        let original = try LMTerrainMeshBuilder.mesh(from: grid)
        let prepared = try await LMTerrainMeshBuilder.meshAsync(from: grid)
        let before = try #require(original.contents.models.first?.parts.first)
        let after = try #require(prepared.contents.models.first?.parts.first)
        #expect(before.positions.elements == after.positions.elements)
        #expect(before.normals?.elements == after.normals?.elements)
        #expect(before.textureCoordinates?.elements == after.textureCoordinates?.elements)
        #expect(before.triangleIndices?.elements == after.triangleIndices?.elements)
        #expect(original.expectedMaterialCount == prepared.expectedMaterialCount)
        #expect(original.bounds == prepared.bounds)
    }








    @Test func manifestPinsMeasuredNearAndProgressiveSLDEMCoverage() throws {
        let manifest = try LMTerrainManifest.load()
        #expect(manifest.schemaVersion == LMTerrainManifest.schemaVersion)
        #expect(manifest.scenarioID == "apollo11-progressive-real-data-terrain")
        #expect(abs(manifest.landingOrigin.latitudeDegrees - 0.673433) < 1e-9)
        #expect(abs(manifest.landingOrigin.longitudeDegrees - 23.473113) < 1e-9)
        let eagle = try #require(manifest.landmark(id: LMTerrainManifest.eagleLandmarkID))
        #expect(abs(eagle.latitudeDegrees - 0.67408) < 1e-9)
        #expect(abs(eagle.longitudeDegrees - 23.47297) < 1e-9)
        #expect(eagle.sourceURL == "https://ssd.jpl.nasa.gov/doc/lunar_cmd_2005_jpl_d32296.pdf")
        let eagleLocal = manifest.localPosition(of: eagle)
        #expect(abs(eagleLocal.x - 19.61920772442715) < 1e-6)
        #expect(abs(eagleLocal.y - -4.335939305713085) < 1e-6)
        #expect(abs(manifest.projection.sphereRadiusMeters - 1_737_400) < 1)
        #expect(manifest.projection.sourceSamples == 2_111)
        #expect(manifest.projection.sourceLines == 13_978)
        #expect(manifest.sources.count == 11)
        #expect(manifest.sourceCatalog == manifest.sources)
        #expect(manifest.sources.allSatisfy {
            $0.coverage.minimumLatitudeDegrees <= $0.coverage.maximumLatitudeDegrees
                && $0.coverage.easternmostLongitudeDegrees
                    > $0.coverage.westernmostLongitudeDegrees
        })
        #expect(manifest.toolSHA256 == "aef1d32c2580d206269364771116dd5538ec5d1d7dbcebb371658cebb2633d8d")
        let craterCatalog = try #require(manifest.craterCatalog)
        #expect(craterCatalog.file == "apollo11-nac-craters-v1.json")
        #expect(craterCatalog.catalogID == "apollo11-near-field-nac-craters-v1")
        #expect(craterCatalog.generatorVersion == "nac-parametric-correlation-v1")
        #expect(craterCatalog.sha256 == "b2bdfada9d6df68623dcfd8c99a5b7b7d1bc2c6000b997d04afd80a79a6e630f")
        #expect(craterCatalog.detectorSHA256 == "d01e3ed540e29a54bde5afc283688bd38b0f0013b0317d1b395608e34a839558")
        #expect(craterCatalog.detectionParameters.maximumCandidates == 1_200)
        #expect(craterCatalog.detectionParameters.minimumDiameterMeters == 2)
        #expect(craterCatalog.detectionParameters.maximumDiameterMeters == 8)

        let nac = try #require(manifest.sources.first { $0.id == "nac-dtm-apollo11" })
        #expect(nac.productId == "NAC_DTM_APOLLO11")
        #expect(nac.role == "geometry")
        #expect(nac.sha256 == "920da622e3d7c3f047c67a970b5429aaadf00f886804e3fc6c72f6e5298043e9")
        #expect(abs((nac.postSpacingMeters ?? 0) - 2.000_000_000_000_6) < 1e-12)
        #expect(nac.residualCapRatio == 0.12)
        #expect(abs((nac.maximumResidualMeters ?? 0) - 0.24) < 1e-12)
        #expect(nac.coverage.contains(
            latitudeDegrees: manifest.landingOrigin.latitudeDegrees,
            longitudeDegrees: manifest.landingOrigin.longitudeDegrees
        ))
        #expect(abs((manifest.measuredFloorMeters(
            at: manifest.landingOriginCoordinate
        ) ?? 0) - 2.000_000_000_000_6) < 1e-12)

        let mediumSource = try #require(manifest.sources.first {
            $0.id == "sldem2015-512-apollo11-slab"
        })
        #expect(mediumSource.productId == "SLDEM2015_512_00N_30N_000_045_FLOAT")
        #expect(mediumSource.bytes == 26_081_280)
        #expect(mediumSource.sourceBytes == 1_415_577_600)
        #expect(mediumSource.byteRangeStart == 1_370_787_840)
        #expect(mediumSource.byteRangeEnd == 1_396_869_119)
        #expect(mediumSource.sourceRowStart == 14_874)
        #expect(mediumSource.sourceRowEnd == 15_156)
        #expect(mediumSource.sha256 == "9ef0cf5d054c295d21b02ccf463c0f246dc78871c344f4fe01c5f077ba8d7698")
        #expect(abs((mediumSource.postSpacingMeters ?? 0) - 59.225_293_8) < 1e-9)
        #expect(mediumSource.residualCapRatio == 0.12)

        let farSource = try #require(manifest.sources.first {
            $0.id == "sldem2015-128-apollo11-slab"
        })
        #expect(farSource.productId == "SLDEM2015_128_60S_60N_000_360_FLOAT")
        #expect(farSource.bytes == 205_148_160)
        #expect(farSource.sourceBytes == 2_831_155_200)
        #expect(farSource.byteRangeStart == 1_297_244_160)
        #expect(farSource.byteRangeEnd == 1_502_392_319)
        #expect(farSource.sourceRowStart == 7_038)
        #expect(farSource.sourceRowEnd == 8_150)
        #expect(farSource.sha256 == "f02bb39e4b11f664a77ce3ed8ab0f12087fd89a01d534942564fba5d643122f9")
        #expect(abs((farSource.postSpacingMeters ?? 0) - 236.901) < 1e-9)
        #expect(farSource.residualCapRatio == 0.12)
        #expect(farSource.coverage.contains(
            latitudeDegrees: manifest.landingOrigin.latitudeDegrees,
            longitudeDegrees: manifest.landingOrigin.longitudeDegrees - 360
        ))

        let nacOrthoA = try #require(manifest.sources.first {
            $0.id == "nac-ortho-m150361817-50cm-slab"
        })
        #expect(nacOrthoA.productId == "NAC_DTM_APOLLO11_M150361817_50CM")
        #expect(nacOrthoA.role == "near-field-high-frequency-reflectance")
        #expect(nacOrthoA.bytes == 69_174_240)
        #expect(nacOrthoA.sourceBytes == 943_743_920)
        #expect(nacOrthoA.byteRangeStart == 541_864_880)
        #expect(nacOrthoA.byteRangeEnd == 611_039_119)
        #expect(nacOrthoA.sourceRowStart == 32_100)
        #expect(nacOrthoA.sourceRowEnd == 36_197)
        #expect(nacOrthoA.sourceRowBytes == 16_880)
        #expect(nacOrthoA.sourceMD5 == "c3784f010eb6d6c2d84d6ee7b4088331")
        #expect(nacOrthoA.sha256 == "b6e9df38ddae806b66c6dc3afbe7f1e94b932421292e3af07f048606d9d6e961")
        #expect(nacOrthoA.postSpacingMeters == nil)
        #expect(nacOrthoA.residualCapRatio == nil)

        let nacOrthoB = try #require(manifest.sources.first {
            $0.id == "nac-ortho-m150368601-50cm-slab"
        })
        #expect(nacOrthoB.productId == "NAC_DTM_APOLLO11_M150368601_50CM")
        #expect(nacOrthoB.sourceMD5 == "95decbebbf283e46d6146c47fec988ed")
        #expect(nacOrthoB.sha256 == "e93a51b8f18dd549aa7b3b22e708c7d06775273a6605b43026679d54e380a207")

        let wacMedium = try #require(manifest.sources.first {
            $0.id == "wac-emp-643nm-304p-apollo11-slab"
        })
        #expect(wacMedium.productId == "WAC_EMP_643NM_E300N0450_304P")
        #expect(wacMedium.role == "near-and-medium-photometric-reflectance")
        #expect(wacMedium.bytes == 18_385_920)
        #expect(wacMedium.sourceBytes == 1_996_295_040)
        #expect(wacMedium.byteRangeStart == 1_964_666_880)
        #expect(wacMedium.byteRangeEnd == 1_983_052_799)
        #expect(wacMedium.sourceMD5 == "97af2366068cffb38415b3658993b4f1")
        #expect(wacMedium.sha256 == "08829725710d9e4dba155372369e6bf5c268eac37023ae6ed77f15902640072a")

        let wacNorth = try #require(manifest.sources.first {
            $0.id == "wac-emp-643nm-64p-north-apollo11-slab"
        })
        #expect(wacNorth.productId == "WAC_EMP_643NM_E300N0450_064P")
        #expect(wacNorth.sourceMD5 == "37e0144f3fa52cf91f9cb0aa605d9200")
        #expect(wacNorth.sha256 == "831255f649b8184f7e8ea339ced80878c840052971fd0fcd761d6c30c6395e42")

        let wacSouth = try #require(manifest.sources.first {
            $0.id == "wac-emp-643nm-64p-south-apollo11-slab"
        })
        #expect(wacSouth.productId == "WAC_EMP_643NM_E300S0450_064P")
        #expect(wacSouth.sourceMD5 == "53eb43347e3a96bc8fdb17c1f3207546")
        #expect(wacSouth.sha256 == "9a8bcc140296ddf9dd8289e95f85f112a30776cc8c441955a56347d66b1b7c86")

        let near = try #require(manifest.tile(id: LMTerrainWorld.nearFieldTileID))
        #expect(near.postsPerSide == 1_025)
        #expect(near.extentMeters == 2_048)
        #expect(abs(near.postSpacingMeters - 2) < 1e-9)
        #expect(near.heightEncoding.centimetersPerCount == 1)
        #expect(near.sourceIDs == ["nac-dtm-apollo11"])
        #expect(near.albedoEncoding.colorSpace == "sRGB encoding of a linear 643 nm reflectance proxy")
        #expect(near.albedoEncoding.texelsPerSide == 4_097)
        #expect(near.albedoEncoding.metersPerTexel == 0.5)
        #expect(near.albedoEncoding.sourceIDs == [
            "wac-emp-643nm-304p-apollo11-slab",
            "nac-ortho-m150361817-50cm-slab",
            "nac-ortho-m150368601-50cm-slab",
        ])
        #expect(near.albedoEncoding.edgeHandling == "wac-base-with-radial-nac-high-pass-fade")
        #expect((near.albedoEncoding.maximumLinearReflectance ?? 0)
            - (near.albedoEncoding.minimumLinearReflectance ?? 0) > 0.04)

        let medium = try #require(manifest.tile(id: LMTerrainWorld.mediumFieldTileID))
        #expect(medium.postsPerSide == 513)
        #expect(medium.extentMeters == 16_384)
        #expect(abs(medium.postSpacingMeters - 32) < 1e-9)
        #expect(abs((medium.nativeSourceSpacingMeters ?? 0) - 59.2252938) < 1e-8)
        #expect(medium.transitionWidthMeters == 1_024)
        #expect(medium.heightEncoding.centimetersPerCount == 1)
        #expect(medium.albedoEncoding.texelsPerSide == 513)
        #expect(abs((medium.albedoEncoding.metersPerTexel ?? 0) - 99.747863237334) < 1e-9)
        #expect(medium.albedoEncoding.edgeHandling == "photometrically-normalized-source")

        let far = try #require(manifest.tile(id: LMTerrainWorld.farFieldTileID))
        #expect(far.postsPerSide == 513)
        #expect(far.extentMeters == 262_144)
        #expect(abs(far.postSpacingMeters - 512) < 1e-9)
        #expect(abs((far.nativeSourceSpacingMeters ?? 0) - 236.901) < 1e-8)
        #expect(far.transitionWidthMeters == 16_384)
        #expect(far.heightEncoding.centimetersPerCount == 25)
        #expect(far.maximumHeightMeters - far.minimumHeightMeters > 10_000)
        #expect(far.albedoEncoding.texelsPerSide == 513)
        #expect(abs((far.albedoEncoding.metersPerTexel ?? 0) - 473.80235037734) < 1e-9)
        #expect(far.albedoEncoding.edgeHandling == "inner-boundary-registered-reflectance-blend")

        let p64Altitude = try PoweredDescentSession.bundledP64Checkpoint().vehicleState.altitudeMeters
        let geometricHorizon = sqrt(
            2 * manifest.projection.sphereRadiusMeters * p64Altitude
                + p64Altitude * p64Altitude
        )
        #expect(far.extentMeters / 2 > geometricHorizon)
    }


    @Test func terminalDescentIsGeoreferencedToEagleWithoutChangingLiveDeviations() throws {
        let manifest = try LMTerrainManifest.load()
        let alignment = try LMTerrainFrameAlignment(manifest: manifest)
        let recording = try PoweredDescentSession.bundledP66Recording()
        let recordedTouchdown = try #require(recording.frames.last).vehicleState.positionMeters

        #expect(abs(recordedTouchdown.x
            - LMTerrainFrameAlignment.nominalP66GuidanceTouchdown.x) < 1e-9)
        #expect(abs(recordedTouchdown.y
            - LMTerrainFrameAlignment.nominalP66GuidanceTouchdown.y) < 1e-9)
        #expect(abs(recordedTouchdown.z
            - LMTerrainFrameAlignment.nominalP66GuidanceTouchdown.z) < 1e-9)

        let alignedTouchdown = alignment.terrainPosition(from: recordedTouchdown)
        #expect(abs(alignedTouchdown.x - alignment.terrainReferenceTouchdown.x) < 1e-9)
        #expect(abs(alignedTouchdown.y - alignment.terrainReferenceTouchdown.y) < 1e-9)
        #expect(alignedTouchdown.z == recordedTouchdown.z)

        let deviated = alignment.terrainPosition(from: LMVector3D(
            x: recordedTouchdown.x + 10,
            y: recordedTouchdown.y - 7,
            z: recordedTouchdown.z + 2
        ))
        #expect(abs(deviated.x - alignedTouchdown.x - 10) < 1e-9)
        #expect(abs(deviated.y - alignedTouchdown.y + 7) < 1e-9)
        #expect(abs(deviated.z - alignedTouchdown.z - 2) < 1e-9)

        let p64 = try PoweredDescentSession.bundledP64Checkpoint().vehicleState.positionMeters
        let p65 = try PoweredDescentSession.bundledP65Checkpoint().vehicleState.positionMeters
        let alignedP64 = alignment.terrainPosition(from: p64)
        let alignedP65 = alignment.terrainPosition(from: p65)
        let near = try #require(manifest.tile(id: LMTerrainWorld.nearFieldTileID))
        let far = try #require(manifest.tile(id: LMTerrainWorld.farFieldTileID))
        #expect(abs(alignedP64.x) < far.extentMeters / 2)
        #expect(abs(alignedP64.y) < far.extentMeters / 2)
        #expect(abs(alignedP65.x) < near.extentMeters / 2)
        #expect(abs(alignedP65.y) < near.extentMeters / 2)
        #expect(alignedP64.y < alignedP65.y)
    }








}


@Suite("Landing Point Designator")
struct LandingPointDesignatorTests {
    let lpd = LMLandingPointDesignator()

    @Test func grummanDesignEyeMapsIntoTheSceneDatum() {
        #expect(simd_distance(
            lpd.scenePoint(sourceBodyInches: LMLandingPointDesignator.sourceDesignEyeInches),
            lpd.commanderEyeMeters
        ) < 1e-6)
        #expect(LMLandingPointDesignator.sourceDesignEyeInches == SIMD3<Float>(
            279.25,
            22,
            54
        ))
        #expect(abs(
            lpd.commanderEyeMeters.x
                - LMCommanderStationGeometry.commanderStationCenterXMeters
        ) < 0.000_001)
    }

    @Test func reconstructedWindowMatchesPhysicalSidesAndDesignEyeEnvelope() {
        let outboard = lpd.windowCorner(.upperOutboard, on: .inner)
        let inboard = lpd.windowCorner(.upperInboard, on: .inner)
        let lower = lpd.windowCorner(.lower, on: .inner)
        let expected = LMLandingPointDesignator.windowSideLengthsMeters

        #expect(abs(simd_distance(outboard, inboard) - expected.x) < 0.000_01)
        #expect(abs(simd_distance(inboard, lower) - expected.y) < 0.000_01)
        #expect(abs(simd_distance(lower, outboard) - expected.z) < 0.000_01)

        for corner in LMLPDWindowCorner.allCases {
            let actual = lpd.sourceVisualAnglesDegrees(
                for: lpd.windowCorner(corner, on: .inner)
            )
            let source = LMLandingPointDesignator.sourceCornerVisualAnglesDegrees[corner]!
            #expect(abs(actual.x - source.x) < 0.000_1)
            #expect(abs(actual.y - source.y) < 0.000_1)
        }
    }

    @Test func paneIsObliqueAndOuterMarksRemainOnTheSameSightRays() {
        let plane = lpd.panePlane(.inner)
        let sceneForward = SIMD3<Float>(0, 0, 1)
        #expect(simd_dot(plane.normalTowardEye, sceneForward) < 0.9)

        for corner in LMLPDWindowCorner.allCases {
            let inner = lpd.windowCorner(corner, on: .inner) - lpd.commanderEyeMeters
            let outer = lpd.windowCorner(corner, on: .outer) - lpd.commanderEyeMeters
            #expect(simd_length(outer) > simd_length(inner))
            #expect(simd_dot(simd_normalize(inner), simd_normalize(outer)) > 0.999_999)
        }
    }

    @Test func everyFlightScaleMarkStaysInsideBothPanes() {
        for pane in LMLPDPane.allCases {
            let corners = lpd.windowCorners(on: pane)
            for elevation in LMLandingPointDesignator.elevationMarkDegrees {
                #expect(point(
                    lpd.point(elevationDegrees: Double(elevation), on: pane),
                    isInsideTriangle: corners
                ))
                let endpoints = lpd.elevationTickEndpoints(
                    elevationDegrees: elevation,
                    on: pane
                )
                #expect(point(endpoints.start, isInsideTriangle: corners))
                #expect(point(endpoints.end, isInsideTriangle: corners))
            }
            for azimuth in LMLandingPointDesignator.azimuthMarkDegrees {
                #expect(point(
                    lpd.point(
                        elevationDegrees: 0,
                        azimuthDegrees: Double(azimuth),
                        on: pane
                    ),
                    isInsideTriangle: corners
                ))
                let endpoints = lpd.azimuthTickEndpoints(
                    azimuthDegrees: azimuth,
                    on: pane
                )
                #expect(point(endpoints.start, isInsideTriangle: corners))
                #expect(point(endpoints.end, isInsideTriangle: corners))
            }
        }
    }

    @Test func dualPaneMarksCollimateAtTheCommanderEye() {
        for angle in [0.0, 10, 30, 47, 60] {
            #expect(lpd.alignmentErrorRadians(
                eyeMeters: lpd.commanderEyeMeters,
                elevationDegrees: angle
            ) < 0.0005)
        }
    }

    @Test func completeTickGeometryCollimatesAcrossBothPanes() {
        for elevation in LMLandingPointDesignator.elevationMarkDegrees {
            let inner = lpd.elevationTickEndpoints(elevationDegrees: elevation, on: .inner)
            let outer = lpd.elevationTickEndpoints(elevationDegrees: elevation, on: .outer)
            expectSameSightRay(inner.start, outer.start)
            expectSameSightRay(inner.end, outer.end)
        }

        for azimuth in LMLandingPointDesignator.azimuthMarkDegrees {
            let inner = lpd.azimuthTickEndpoints(azimuthDegrees: azimuth, on: .inner)
            let outer = lpd.azimuthTickEndpoints(azimuthDegrees: azimuth, on: .outer)
            expectSameSightRay(inner.start, outer.start)
            expectSameSightRay(inner.end, outer.end)
        }
    }

    @Test func aDisplacedHeadProducesVisibleParallax() {
        let displacedEye = lpd.commanderEyeMeters + SIMD3<Float>(0.05, 0.03, 0)
        #expect(lpd.alignmentErrorRadians(
            eyeMeters: displacedEye,
            elevationDegrees: 47
        ) > 0.001)
    }

    @Test func lookAngleIsMeasuredDownFromTheForwardBodyAxis() {
        let forward = SIMD3<Float>(0, 0, -1)
        let direction = lpd.sightDirection(elevationDegrees: 47)
        let angle = acos(simd_dot(forward, direction)) * 180 / .pi

        #expect(abs(angle - 47) < 0.001)
        #expect(direction.y < 0)
    }

    @Test func apollo11ScaleAndRedesignationIncrementsStayMissionSpecific() {
        #expect(LMLandingPointDesignator.elevationMarkDegrees == Array(
            stride(from: 0, through: 60, by: 2)
        ))
        #expect(LMLandingPointDesignator.azimuthMarkDegrees == [-10, -5, 0, 5, 10])
        #expect(LMLandingPointDesignator.horizontalScaleElevations == [0])
        #expect(LMLandingPointDesignator.apollo11InPlaneRedesignationDegrees == 0.5)
        #expect(LMLandingPointDesignator.apollo11CrossRangeRedesignationDegrees == 2)
    }

    @Test @MainActor func trainingCueSelectsTheLiveN64MarkWithoutMovingTheGrid() {
        let station = LMCommanderStationScene()
        let expected = lpd.point(elevationDegrees: 47, on: .inner)
            + lpd.panePlane(.inner).normalTowardEye * 0.004

        station.setLandingPointCalledAngle(47, trainingOverlayVisible: true)
        #expect(station.landingPointCalledAngleMarker.isEnabled)
        #expect(simd_distance(
            station.landingPointCalledAngleMarker.position,
            expected
        ) < 0.000_01)

        station.setLandingPointCalledAngle(47, trainingOverlayVisible: false)
        #expect(!station.landingPointCalledAngleMarker.isEnabled)
    }

    @Test @MainActor func commanderEntryPlacementStartsAtDesignEyeHeightAndSlightlyAft() {
        let station = LMCommanderStationScene()

        #expect(station.root.parent === station.commanderEntryAnchor)
        #expect(simd_distance(
            station.root.position + LMCommanderStationGeometry.comfortableEntryEyeMeters,
            .zero
        ) < 1e-6)
        #expect(
            LMCommanderStationGeometry.comfortableEntryOffsetFromDesignEyeMeters.z >= 0.50
        )
        #expect(
            LMCommanderStationGeometry.comfortableEntryOffsetFromDesignEyeMeters.z <= 0.60
        )
        #expect(
            abs(LMCommanderStationGeometry.comfortableEntryOffsetFromDesignEyeMeters.y) < 0.001
        )
    }

    @Test @MainActor func cockpitRecenterReplacesTheOneShotHeadAnchorWithoutRebuildingTheScene() {
        let station = LMCommanderStationScene()
        let originalAnchor = station.commanderEntryAnchor
        let originalRoot = station.root
        let originalLunarWorld = station.lunarWorld

        station.recenterAtCurrentHeadPose()

        #expect(station.commanderEntryAnchor !== originalAnchor)
        #expect(station.root === originalRoot)
        #expect(station.lunarWorld === originalLunarWorld)
        #expect(station.root.parent === station.commanderEntryAnchor)
        #expect(originalAnchor.children.isEmpty)
        #expect(simd_distance(
            station.root.position + LMCommanderStationGeometry.comfortableEntryEyeMeters,
            .zero
        ) < 1e-6)

        let retired = station.takeRetiredCommanderEntryAnchors()
        #expect(retired.count == 1)
        #expect(retired.first === originalAnchor)
        #expect(station.takeRetiredCommanderEntryAnchors().isEmpty)
    }

    private func point(
        _ point: SIMD3<Float>,
        isInsideTriangle corners: [SIMD3<Float>]
    ) -> Bool {
        let edge0 = corners[1] - corners[0]
        let edge1 = corners[2] - corners[0]
        let offset = point - corners[0]
        let dot00 = simd_dot(edge0, edge0)
        let dot01 = simd_dot(edge0, edge1)
        let dot11 = simd_dot(edge1, edge1)
        let dot20 = simd_dot(offset, edge0)
        let dot21 = simd_dot(offset, edge1)
        let denominator = dot00 * dot11 - dot01 * dot01
        let v = (dot11 * dot20 - dot01 * dot21) / denominator
        let w = (dot00 * dot21 - dot01 * dot20) / denominator
        let u = 1 - v - w
        let tolerance: Float = -0.0001
        return u >= tolerance && v >= tolerance && w >= tolerance
    }

    private func expectSameSightRay(_ inner: SIMD3<Float>, _ outer: SIMD3<Float>) {
        let innerDirection = simd_normalize(inner - lpd.commanderEyeMeters)
        let outerDirection = simd_normalize(outer - lpd.commanderEyeMeters)
        #expect(simd_dot(innerDirection, outerDirection) > 0.999_999)
    }
}

@Suite("Apollo 11 commander-station geometry")
struct Apollo11CommanderStationGeometryTests {
    @Test func primarySourceDimensionsRemainExplicitAndUnscaled() {
        #expect(LMCommanderStationGeometry.operationsHandbookSource.contains("LM 10"))
        #expect(LMCommanderStationGeometry.newsReferenceSource.contains("Apollo News Reference"))
        #expect(abs(LMCommanderStationGeometry.crewCompartmentDiameterMeters - 2.336_8) < 0.000_001)
        #expect(abs(LMCommanderStationGeometry.crewCompartmentDepthMeters - 1.066_8) < 0.000_001)
        #expect(abs(LMCommanderStationGeometry.flightStationCenterlineSeparationMeters - 1.117_6) < 0.000_001)
        #expect(abs(LMCommanderStationGeometry.deckWidthMeters - 1.397) < 0.000_001)
        #expect(abs(LMCommanderStationGeometry.deckDepthMeters - 0.914_4) < 0.000_001)
        #expect(abs(LMCommanderStationGeometry.mainPanelSandwichDepthMeters - 0.050_8) < 0.000_001)
        #expect(LMCommanderStationGeometry.acaProportionalTravelDegrees == 11)
        #expect(LMCommanderStationGeometry.acaHardoverDegrees == 12)
        #expect(LMCommanderStationGeometry.descentRateIncrementFeetPerSecond == 1)
    }

    @Test func panelRelationshipsFollowTheOperationsHandbook() {
        let one = LMCommanderStationGeometry.surface(.panelOne)
        let two = LMCommanderStationGeometry.surface(.panelTwo)
        let three = LMCommanderStationGeometry.surface(.panelThree)
        let four = LMCommanderStationGeometry.surface(.panelFour)

        #expect(one.pitchDegrees == -10)
        #expect(two.pitchDegrees == -10)
        #expect(three.pitchDegrees == -45)
        #expect(four.pitchDegrees == -45)
        #expect(one.sizeMeters.z == LMCommanderStationGeometry.mainPanelSandwichDepthMeters)
        #expect(two.sizeMeters.z == LMCommanderStationGeometry.mainPanelSandwichDepthMeters)
        #expect(one.centerMeters.x == -two.centerMeters.x)
        #expect(one.centerMeters.y == two.centerMeters.y)
        #expect(three.sizeMeters.x >= one.sizeMeters.x + two.sizeMeters.x)
        #expect(four.centerMeters.x == 0)
        #expect(four.centerMeters.y < three.centerMeters.y)
    }

    @Test func standingPanelStackKeepsUpperInstrumentsAtEyeLevelAndControlsAtWaist() {
        let eye = LMLandingPointDesignator().commanderEyeMeters
        let one = LMCommanderStationGeometry.surface(.panelOne)
        let three = LMCommanderStationGeometry.surface(.panelThree)
        let four = LMCommanderStationGeometry.surface(.panelFour)
        let five = LMCommanderStationGeometry.surface(.panelFive)

        #expect(abs(one.centerMeters.y - eye.y) < 0.30)
        #expect(one.centerMeters.y > three.centerMeters.y)
        #expect(three.centerMeters.y > four.centerMeters.y)
        #expect(five.centerMeters.y >= 0.80)
        #expect(five.centerMeters.y <= 1.0)
        #expect(LMCommanderStationGeometry.acaPivotPositionMeters.y >= 0.85)
        #expect(LMCommanderStationGeometry.acaPivotPositionMeters.y <= 1.0)
    }

    @Test func flightStationsAndFlightDSKYFitTheReconstructedBlockout() {
        #expect(abs(
            LMCommanderStationGeometry.lmpStationCenterXMeters
                - LMCommanderStationGeometry.commanderStationCenterXMeters
                - LMCommanderStationGeometry.flightStationCenterlineSeparationMeters
        ) < 0.000_001)

        let panelFour = LMCommanderStationGeometry.surface(.panelFour)
        #expect(LMDSKYGeometry.faceWidthMeters < panelFour.sizeMeters.x)
        #expect(LMDSKYGeometry.faceHeightMeters < panelFour.sizeMeters.y)
        #expect(LMCommanderStationGeometry.shellSegments.count == 10)
        #expect(LMCommanderStationGeometry.shellSegments.allSatisfy {
            abs($0.sizeMeters.z - LMCommanderStationGeometry.crewCompartmentDepthMeters) < 0.000_001
        })

        let panelFive = LMCommanderStationGeometry.surface(.panelFive)
        let switchOffset = LMCommanderStationGeometry.rodPivotPositionMeters
            - panelFive.centerMeters
        #expect(abs(simd_dot(
            switchOffset,
            panelFive.faceNormalTowardCrew
        ) - (panelFive.sizeMeters.z / 2 + 0.020)) < 0.000_001)
        #expect(simd_dot(
            LMCommanderStationGeometry.rodActuationAxis,
            panelFive.orientation.act(SIMD3<Float>(0, 1, 0))
        ) > 0.999_999)
    }

    @Test @MainActor func proceduralStationPublishesEveryArtistContractNode() {
        let station = LMCommanderStationScene()
        for node in LMCockpitAssetContract.Node.allCases {
            #expect(station.root.findEntity(named: node.rawValue) != nil)
        }
        for placement in LMDSKYGeometry.keyPlacements {
            #expect(station.root.findEntity(
                named: LMDSKYGeometry.artistNodeName(for: placement.code)
            ) != nil)
        }
    }

    @Test @MainActor func proceduralPressureVesselClosesEverySurfaceExceptTheWindows() {
        let station = LMCommanderStationScene()

        #expect(station.root.findEntity(named: "Pressure vessel floor") != nil)
        #expect(station.root.findEntity(named: "Aft pressure bulkhead") != nil)
        #expect(station.root.findEntity(named: "Forward pressure bulkhead") != nil)
        #expect(station.root.findEntity(named: "Commander lower pressure wall") != nil)
        #expect(station.root.findEntity(named: "LMP lower pressure wall") != nil)
        #expect(station.root.findEntity(
            named: LMCockpitAssetContract.Node.commanderWindowInner.rawValue
        ) != nil)
        #expect(station.root.findEntity(
            named: LMCockpitAssetContract.Node.commanderWindowOuter.rawValue
        ) != nil)
    }

    @Test @MainActor func proceduralCabinUsesStableInteriorShadowPolicy() throws {
        let station = LMCommanderStationScene()
        let panel = try #require(station.root.findEntity(named: "Panel_1"))
        let shellSegment = try #require(
            station.root.findEntity(named: "Cabin shell segment 01")
        )
        let panelModel = try #require(panel.components[ModelComponent.self])
        let shellModel = try #require(shellSegment.components[ModelComponent.self])

        #expect(
            panel.components[DynamicLightShadowComponent.self]?.castsShadow == false
        )
        #expect(
            shellSegment.components[DynamicLightShadowComponent.self]?.castsShadow == true
        )
        #expect(panelModel.materials.allSatisfy { $0 is UnlitMaterial })
        #expect(shellModel.materials.allSatisfy { $0 is UnlitMaterial })
    }
}

@Suite("Apollo 11 LM DSKY geometry")
struct Apollo11LMDSKYGeometryTests {
    @Test func faceEnvelopeAndNineteenKeyLayoutMatchTheMITDrawing() {
        #expect(LMDSKYGeometry.sourceAssembly == "2003994-091")
        #expect(LMDSKYGeometry.sourceOutlineDrawing == "2003956 Rev B")
        #expect(abs(LMDSKYGeometry.faceWidthMeters - 0.206_349_6) < 0.000_001)
        #expect(abs(LMDSKYGeometry.faceHeightMeters - 0.203_2) < 0.000_001)
        #expect(abs(LMDSKYGeometry.maximumDepthMeters - 0.175_514) < 0.000_001)
        #expect(LMDSKYGeometry.keyPlacements.count == 19)
        #expect(
            Set(LMDSKYGeometry.keyPlacements.map(\.code.rawValue))
                == Set(DSKYKeyCode.allCases.map(\.rawValue))
        )
        #expect(LMDSKYGeometry.fallbackRows == [
            [.verb, .plus, .digit7, .digit8, .digit9, .clear, .enter],
            [.noun, .minus, .digit4, .digit5, .digit6, .pro, .reset],
            [.digit0, .digit1, .digit2, .digit3, .keyRelease],
        ])
    }

    @Test @MainActor func proceduralStationMakesEveryDSKYKeyAnInputTarget() {
        let station = LMCommanderStationScene()

        #expect(station.dskyKeyEntities.count == 19)
        for entity in station.dskyKeyEntities {
            #expect(entity.components[InputTargetComponent.self] != nil)
            #expect(entity.components[CollisionComponent.self] != nil)
            #expect(station.dskyKeyCode(for: entity) != nil)
        }
    }

    @Test @MainActor func physicalDSKYMirrorsLiveRegistersAndAnnunciators() {
        let station = LMCommanderStationScene()
        let snapshot = DSKYSnapshot(
            r1: "+00123",
            r2: "-00456",
            r3: "+07890",
            verb: "06",
            noun: "64",
            mode: "65",
            compActy: true,
            indicators: [14: true, 27: true]
        )

        station.applyDSKY(snapshot)
        let displayed = station.physicalDSKYDisplayedText

        #expect(station.physicalDSKYDisplayEntityNames == [
            "DSKY annunciator legends",
            "DSKY illuminated annunciators",
            "DSKY physical registers",
        ])
        #expect(displayed.registers.contains("PROG 65"))
        #expect(displayed.registers.contains("VERB 06  NOUN 64"))
        #expect(displayed.registers.contains("+00123"))
        #expect(displayed.annunciators.contains("COMP ACTY"))
        #expect(displayed.annunciators.contains("KEY REL"))
        #expect(displayed.annunciators.contains("VEL"))
    }

    @Test @MainActor func dskyAndMissionHitTestingAcceptsAuthoredChildGeometry() {
        let station = LMCommanderStationScene()
        let proKey = station.dskyKeyEntities.first {
            station.dskyKeyCode(for: $0) == .pro
        }
        #expect(proKey != nil)

        let keyLegend = Entity()
        proKey?.addChild(keyLegend)
        #expect(station.dskyKeyCode(for: keyLegend) == .pro)

        let missionLegend = Entity()
        station.missionControlButton.addChild(missionLegend)
        #expect(station.isMissionControlButton(missionLegend))
    }
}

@Suite("Artist cockpit asset contract")
struct ArtistCockpitAssetContractTests {
    @Test @MainActor func completeIdentityScaledAssetPassesValidation() {
        let root = Entity()
        let lpd = LMLandingPointDesignator()
        for node in LMCockpitAssetContract.Node.allCases {
            let entity = Entity()
            entity.name = node.rawValue
            switch node {
            case .commanderEye:
                entity.position = lpd.commanderEyeMeters
            case .commanderWindowInner:
                entity.position = lpd.panePlane(.inner).referencePointMeters
                entity.orientation = lpd.paneOrientation(.inner)
            case .commanderWindowOuter:
                entity.position = lpd.panePlane(.outer).referencePointMeters
                entity.orientation = lpd.paneOrientation(.outer)
            case .fdaiMount:
                entity.position = LMCommanderStationGeometry.fdaiMountPositionMeters
                entity.orientation = LMCommanderStationGeometry.fdaiMountOrientation
            case .dskyMount:
                entity.position = LMCommanderStationGeometry.dskyMountPositionMeters
                entity.orientation = LMCommanderStationGeometry.dskyMountOrientation
            case .acaPivot:
                entity.position = LMCommanderStationGeometry.acaPivotPositionMeters
            case .rodPivot:
                entity.position = LMCommanderStationGeometry.rodPivotPositionMeters
            case .attitudeHoldPivot:
                entity.position = LMCommanderStationGeometry.attitudeHoldPivotPositionMeters
                entity.orientation = LMCommanderStationGeometry.attitudeHoldOrientation
            default:
                if let surfaceID = LMCommanderStationGeometry.SurfaceID(rawValue: node.rawValue) {
                    let surface = LMCommanderStationGeometry.surface(surfaceID)
                    entity.position = surface.centerMeters
                    entity.orientation = surface.orientation
                }
            }
            root.addChild(entity)
        }
        for placement in LMDSKYGeometry.keyPlacements {
            let key = Entity()
            key.name = LMDSKYGeometry.artistNodeName(for: placement.code)
            root.addChild(key)
        }

        #expect(LMCockpitAssetContract.validate(root).isEmpty)
    }

    @Test @MainActor func missingDatumsAndNonIdentityScaleFailValidation() {
        let root = Entity()
        root.scale = SIMD3(repeating: 0.01)
        let issues = LMCockpitAssetContract.validate(root)

        #expect(issues.contains(.rootScaleMustBeIdentity))
        #expect(issues.contains(.missingNode(.commanderEye)))
        #expect(issues.contains(.missingNode(.landingPointDesignatorOuter)))
        #expect(issues.contains(.missingDSKYKey(DSKYKeyCode.pro.rawValue)))
    }

    @Test @MainActor func opticalDatumsMustMatchTheFlightCalibration() {
        let root = Entity()
        for node in LMCockpitAssetContract.Node.allCases {
            let entity = Entity()
            entity.name = node.rawValue
            root.addChild(entity)
        }

        let issues = LMCockpitAssetContract.validate(root)
        #expect(issues.contains(.nodePositionOutsideTolerance(.commanderEye)))
        #expect(issues.contains(.nodePositionOutsideTolerance(.commanderWindowInner)))
        #expect(issues.contains(.nodeNormalOutsideTolerance(.commanderWindowInner)))
    }
}

@Suite("Spatial cockpit controls")
struct SpatialCockpitControlTests {
    let mapper = LMSpatialControlMapper()

    @Test func threeDimensionalGripMapsOntoAllACAAxesAndClamps() {
        let input = mapper.acaInput(for: SIMD3(
            mapper.acaTravelMeters * 2,
            mapper.acaTravelMeters * -0.5,
            mapper.acaTravelMeters * -0.75
        ))

        #expect(abs(input.pitch - 0.75) < 1e-6)
        #expect(abs(input.yaw + 0.5) < 1e-6)
        #expect(abs(input.roll - 1) < 1e-6)
    }

    @Test func rodUsesSpringLoadedDetentsAroundNeutral() {
        #expect(mapper.rodPosition(for: 0) == .neutral)
        #expect(mapper.rodPosition(for: mapper.rodTravelMeters * 0.2) == .neutral)
        #expect(mapper.rodPosition(for: mapper.rodTravelMeters * 0.5) == .descendPlus)
        #expect(mapper.rodPosition(for: mapper.rodTravelMeters * -0.5) == .descendMinus)
        #expect(mapper.visualRODDeflectionRadians(for: .neutral) == 0)
        #expect(mapper.visualRODDeflectionRadians(for: .descendPlus) > 0)
        #expect(mapper.visualRODDeflectionRadians(for: .descendMinus) < 0)
    }

    @Test func rodGestureProjectsOntoThePhysicalPanelFiveAxis() {
        let axis = simd_normalize(SIMD3<Float>(0.2, 0.3, -0.9))
        let lateral = simd_normalize(simd_cross(axis, SIMD3<Float>(1, 0, 0)))
        #expect(mapper.rodPosition(
            for: axis * mapper.rodTravelMeters,
            along: axis
        ) == .descendPlus)
        #expect(mapper.rodPosition(
            for: -axis * mapper.rodTravelMeters,
            along: axis
        ) == .descendMinus)
        #expect(mapper.rodPosition(
            for: lateral * mapper.rodTravelMeters,
            along: axis
        ) == .neutral)
    }

    @Test @MainActor func proceduralControlsPivotAtTheirFlightDatums() {
        let station = LMCommanderStationScene()
        station.setACAVisual(LMACANormalizedInput(pitch: 1, yaw: 0, roll: 0))
        #expect(simd_distance(
            station.acaHandle.position,
            LMCommanderStationGeometry.acaPivotPositionMeters
        ) < 0.000_001)
        let acaAngle = 2 * acos(min(max(abs(station.acaHandle.orientation.real), 0), 1))
        #expect(abs(
            acaAngle - LMCommanderStationGeometry.acaProportionalTravelDegrees * .pi / 180
        ) < 0.000_001)

        station.setRODVisual(.descendPlus)
        #expect(simd_distance(
            station.rodSwitch.position,
            LMCommanderStationGeometry.rodPivotPositionMeters
        ) < 0.000_001)
        let rodDelta = LMCommanderStationGeometry.rodNeutralOrientation.inverse
            * station.rodSwitch.orientation
        let rodAngle = 2 * acos(min(max(abs(rodDelta.real), 0), 1))
        #expect(abs(
            rodAngle - mapper.visualRODDeflectionRadians(for: .descendPlus)
        ) < 0.000_001)
    }
}

@Suite("Cockpit experience events")
struct CockpitExperienceEventTests {
    @Test func phaseCalloutsFireOnlyAtTheirRealGates() {
        var director = LMCockpitExperienceDirector()

        let prematureP64 = director.consume(
            program: 64,
            altitudeMeters: 2_271,
            outcome: .inFlight,
            hasSurfaceContact: false
        )
        #expect(prematureP64.isEmpty)

        let p64 = director.consume(
            program: 64,
            landingPointDisplayActive: true,
            altitudeMeters: 2_271,
            outcome: .inFlight,
            hasSurfaceContact: false
        )
        #expect(p64.map(\.id) == [.p64])

        let p65 = director.consume(
            program: 65,
            altitudeMeters: nil,
            outcome: .inFlight,
            hasSurfaceContact: false
        )
        #expect(p65.map(\.id) == [.p65])

        let p66 = director.consume(
            program: 66,
            altitudeMeters: nil,
            outcome: .inFlight,
            hasSurfaceContact: false
        )
        #expect(p66.map(\.id) == [.p66])

        let duplicates = director.consume(
            program: 66,
            altitudeMeters: nil,
            outcome: .inFlight,
            hasSurfaceContact: false
        )
        #expect(duplicates.isEmpty)
    }

    @Test func apollo11AltitudeCalloutsUseLiveRatesAtDescendingThresholdCrossings() {
        var director = LMCockpitExperienceDirector()
        let metersPerFoot = 0.3048

        _ = director.consume(
            program: 66,
            altitudeMeters: 301 * metersPerFoot,
            verticalSpeedMetersPerSecond: -3.5 * metersPerFoot,
            downrangeSpeedMetersPerSecond: 47 * metersPerFoot,
            outcome: .inFlight,
            hasSurfaceContact: false
        )

        let thresholds: [(feet: Double, event: LMCockpitExperienceDirector.Event)] = [
            (299, .threeHundredFeet),
            (219, .twoHundredTwentyFeet),
            (199, .twoHundredFeet),
            (159, .oneHundredSixtyFeet),
            (119, .oneHundredTwentyFeet),
            (99, .oneHundredFeet),
            (74, .seventyFiveFeet),
            (39, .fortyFeet),
            (29, .thirtyFeet),
        ]
        var observed = [LMCockpitExperienceDirector.Event]()
        var firstCallout: LMCockpitCue?
        for threshold in thresholds {
            let cues = director.consume(
                program: 66,
                altitudeMeters: threshold.feet * metersPerFoot,
                verticalSpeedMetersPerSecond: -3.5 * metersPerFoot,
                downrangeSpeedMetersPerSecond: 47 * metersPerFoot,
                outcome: .inFlight,
                hasSurfaceContact: false
            )
            firstCallout = firstCallout ?? cues.first { $0.id == .threeHundredFeet }
            observed.append(contentsOf: cues.map(\.id).filter { $0 != .p66 })
        }

        #expect(observed == thresholds.map(\.event))
        #expect(firstCallout?.title == "300 FT · DOWN 3.5 · FWD 47")
        #expect(firstCallout?.spokenText == "300 feet. Down 3.5. 47 forward.")

        let duplicates = director.consume(
            program: 66,
            altitudeMeters: 20 * metersPerFoot,
            verticalSpeedMetersPerSecond: -3.5 * metersPerFoot,
            downrangeSpeedMetersPerSecond: 47 * metersPerFoot,
            outcome: .inFlight,
            hasSurfaceContact: false
        )
        #expect(duplicates.isEmpty)
    }

    @Test func contactAndLandingOutcomeRemainDistinctAndContactGated() {
        var director = LMCockpitExperienceDirector()

        let contact = director.consume(
            program: 66,
            altitudeMeters: 0,
            outcome: .softLanding,
            hasSurfaceContact: true
        )
        #expect(contact.map(\.id) == [
            .p66,
            .contact,
            .softLanding
        ])
        #expect(!contact.contains { $0.id == .hardLanding || $0.id == .crashed })

        let duplicates = director.consume(
            program: 66,
            altitudeMeters: 0,
            outcome: .softLanding,
            hasSurfaceContact: true
        )
        #expect(duplicates.isEmpty)
    }

    @Test func crashNeverProducesAContactOrSuccessCalloutWithoutContact() {
        var director = LMCockpitExperienceDirector()
        let cues = director.consume(
            program: 66,
            altitudeMeters: 0,
            outcome: .crashed,
            hasSurfaceContact: false
        )

        #expect(cues.map(\.id) == [.p66, .crashed])
        #expect(!cues.contains { $0.id == .contact || $0.id == .softLanding })
    }
}

@Suite("Cockpit headset validation")
struct CockpitHeadsetValidationTests {
    @Test func onlyPhysicalPROCompletesTheDSKYGate() {
        var recorder = LMCockpitValidationRecorder()

        recorder.observeDirectDSKY(.verb)
        recorder.observeDirectDSKY(.enter)
        #expect(!recorder.completed.contains(.dskyPRO))

        recorder.observeDirectDSKY(.pro)
        #expect(recorder.completed.contains(.dskyPRO))
    }

    @Test func directControlsAndFlightEventsCompleteEveryGate() {
        var recorder = LMCockpitValidationRecorder()

        recorder.observeTerrainLoaded()
        recorder.observe(events: [.p64, .p65])
        recorder.observeDirectDSKY(.pro)
        recorder.observeDirectACA(.init(pitch: 0.3, yaw: 0, roll: 0))
        recorder.observeDirectACA(.init(pitch: 0, yaw: -0.3, roll: 0.3))
        recorder.observeDirectACARelease()
        recorder.observeDirectROD(.descendPlus)
        recorder.observeDirectROD(.descendMinus)
        recorder.observeDirectROD(.neutral)
        recorder.observeDirectAttitudeHold()
        recorder.confirmComfort()
        recorder.observe(events: [
            .p66,
            .oneHundredFeet,
            .fortyFeet,
            .contact,
            .softLanding,
        ])

        #expect(recorder.isComplete)
        #expect(recorder.completedCount == recorder.totalCount)
        #expect(recorder.terminalResult == .softLanding)
        #expect(recorder.summary().contains("missing=[]"))
    }

    @Test func neutralReturnsRequirePriorDirectDeflection() {
        var recorder = LMCockpitValidationRecorder()

        recorder.observeDirectACARelease()
        recorder.observeDirectROD(.neutral)
        #expect(!recorder.completed.contains(.acaNeutral))
        #expect(!recorder.completed.contains(.rodNeutral))

        recorder.observeDirectACA(.init(pitch: 0.19, yaw: 0, roll: 0))
        recorder.observeDirectACARelease()
        recorder.observeDirectROD(.descendPlus)
        recorder.observeDirectROD(.neutral)
        #expect(!recorder.completed.contains(.acaNeutral))
        #expect(recorder.completed.contains(.rodNeutral))
    }

    @Test func restartPreservesTerrainButClearsRunEvidence() {
        var recorder = LMCockpitValidationRecorder()
        recorder.observeTerrainLoaded()
        recorder.observe(events: [.p65, .hardLanding])
        recorder.observeDirectACA(.init(pitch: 1, yaw: 1, roll: 1))
        recorder.confirmComfort()

        recorder.resetForRun()

        #expect(recorder.completed == [.terrainLoaded])
        #expect(recorder.terminalResult == nil)
        recorder.observeDirectACARelease()
        #expect(!recorder.completed.contains(.acaNeutral))
    }
}



@Suite("Terrain-relative descent")
struct TerrainRelativeDescentTests {
    /// Fly the bundled P65 checkpoint live, with the landing gear touching the
    /// same terrain the clipmap draws, and report what the gear did.
    ///
    /// This is the end-to-end check that the contact surface, the gear model,
    /// and the AGC still compose: the vehicle has to reach the ground, stop,
    /// and stay stopped rather than being flown off it again by guidance that
    /// references altitude to a sphere.
    @Test @MainActor func bundledP65CheckpointLandsOnTheDrawnTerrain() async throws {
        let checkpoint = try PoweredDescentSession.bundledP65Checkpoint()
        let binURL = try #require(
            Bundle.main.url(forResource: "Luminary099", withExtension: "bin")
        )
        let runtime = try LMSimulationRuntime(binFile: binURL, scenario: .apollo11SourceBacked)
        let heightField = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let alignment = try LMTerrainFrameAlignment(manifest: LMTerrainManifest.load())
        let planner = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: heightField.spacingMeters
        )

        var snapshot = try await runtime.restore(from: checkpoint)
        var surface: LMTerrainContactSurface?
        let deadline = snapshot.timeSeconds + 300

        while snapshot.timeSeconds < deadline,
              !snapshot.vehicleState.flightOutcome.isTerminal {
            let state = snapshot.vehicleState
            let terrain = alignment.terrainPosition(from: state.positionMeters)
            if state.altitudeMeters <= LMTerrainContactSurfaceBuilder.buildAltitudeMeters {
                let drift = surface.map {
                    hypot(
                        terrain.y - $0.centerEastMeters,
                        terrain.x - $0.centerNorthMeters
                    )
                } ?? .infinity
                if drift > LMTerrainContactSurfaceBuilder.rebuildDriftMeters {
                    let plans = planner.focusedPlans(
                        focusEastMeters: terrain.y,
                        focusNorthMeters: terrain.x,
                        altitudeMeters: state.altitudeMeters
                    )
                    surface = try LMTerrainContactSurfaceBuilder.build(
                        heightField: heightField,
                        alignment: alignment,
                        activePlans: plans,
                        altitudeMeters: state.altitudeMeters,
                        centerTerrainEastMeters: terrain.y,
                        centerTerrainNorthMeters: terrain.x
                    )
                    await runtime.setLandingSurface(surface)
                }
            }
            snapshot = await runtime.step(
                deltaTime: LMSimulationPace.acceleratedDeltaSeconds,
                input: .autoLand(from: state)
            )
        }

        let final = snapshot.vehicleState
        let contact = try #require(final.surfaceContact)
        let gear = try #require(final.landingGear)
        let ground = try #require(surface)

        // It reached the ground and stopped there.
        #expect(final.flightOutcome.isTerminal)
        #expect(gear.isProbeContact)
        #expect(gear.isAnyFootpadInContact)
        #expect(final.velocityMetersPerSecond.magnitude < 0.2)

        // It touched down where the terrain actually is, not at the sphere.
        // The live P65 arc lands well off Eagle, where the mare is meters away
        // from the guidance datum, which is exactly what the old spherical
        // contact test could not represent.
        let touchdownHeight = ground.surfaceHeightMeters(
            northMeters: final.positionMeters.x,
            eastMeters: final.positionMeters.y
        )
        #expect(abs(final.positionMeters.z - touchdownHeight) < 0.5)

        // Arrival was inside the gear's rated envelope, and the honeycomb took
        // the part of it that the regolith could not.
        #expect(
            contact.horizontalSpeedMetersPerSecond
                <= LMLandingContactCriteria.maximumHorizontalSpeedMetersPerSecond
        )
        #expect(
            contact.verticalSpeedMetersPerSecond
                <= LMLandingContactCriteria.maximumVerticalSpeedMetersPerSecond(
                    horizontalSpeedMetersPerSecond: contact.horizontalSpeedMetersPerSecond
                )
        )
        #expect(gear.failure == nil)
        #expect(final.flightOutcome != .crashed)
        #expect(gear.maximumStrokeMeters < LMLandingGearGeometry.primaryStrutStrokeMeters)

        // The descent engine is not still flying a vehicle that has landed.
        #expect(
            snapshot.vehicleCommands.isMainEngineProducingThrust(state: final) == false
        )
    }
}
