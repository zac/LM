import Foundation
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

    @Test func worldMapperSendsSimUpToRealityKitUp() {
        let mapper = LMWorldMapper.tabletop
        let up = mapper.direction(from: LMVector3D(z: 1))
        #expect(abs(up.x) < 1e-5)
        #expect(abs(up.y - 1) < 1e-5)
        #expect(abs(up.z) < 1e-5)

        let forward = mapper.direction(from: LMVector3D(y: 1))
        #expect(abs(forward.x) < 1e-5)
        #expect(abs(forward.y) < 1e-5)
        #expect(abs(forward.z + 1) < 1e-5)

        let right = mapper.direction(from: LMVector3D(x: 1))
        #expect(abs(right.x - 1) < 1e-5)
        #expect(abs(right.y) < 1e-5)
        #expect(abs(right.z) < 1e-5)
    }

    @Test func worldMapperCompressesHighAltitudeAndExpandsNearField() {
        let mapper = LMWorldMapper.tabletop
        let high = mapper.visualAltitude(mapper.highAltitudeMeters)
        let near = mapper.visualAltitude(mapper.nearAltitudeMeters)
        let landed = mapper.visualAltitude(0)
        #expect(abs(high - mapper.highVisualMeters - mapper.nearVisualMeters) < 1e-6)
        #expect(abs(near - mapper.nearVisualMeters) < 1e-6)
        #expect(landed == 0)
        #expect(mapper.position(from: LMVector3D(z: 0)).y == 0)
    }

    @Test func worldMapperKeepsUprangeOverThePadAndShowsNearFieldHorizontal() {
        let mapper = LMWorldMapper.tabletop
        let pdi = LMVector3D(
            x: Luminary99LandingPadLoad.rignXMeters,
            y: Luminary99LandingPadLoad.rignZMeters,
            z: 48_814.0 * 0.3048
        )
        let braking = mapper.position(from: pdi, program: 64)
        #expect(abs(braking.x) < 1e-5)
        #expect(abs(braking.z) < 1e-5)
        #expect(braking.y > 0.5)
        #expect(!mapper.showsSiteRelativeHorizontal(rangeMeters: mapper.pdiRangeMeters))

        let near = LMVector3D(x: 0, y: -500, z: 200)
        let approach = mapper.position(from: near, rangeMeters: 500)
        #expect(mapper.showsSiteRelativeHorizontal(rangeMeters: 500))
        #expect(approach.z > 0)
        #expect(abs(approach.x) < 1e-4)
    }

    @Test func worldMapperPoseKeepsPDIAboveThePad() {
        let state = LMPoweredDescentScenario.apollo11SourceBacked.initialState
        let pose = LMWorldMapper.tabletop.pose(from: state, program: 63)
        #expect(pose.position.y > 0.5)
        #expect(abs(pose.position.x) < 1e-5)
        #expect(abs(pose.position.z) < 1e-5)
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

    @Test func worldMapperPlacesPDIBeadAtTheFarEndOfTheRangeStrip() {
        let mapper = LMWorldMapper.tabletop
        let pdi = mapper.stripBeadOffset(rangeMeters: mapper.pdiRangeMeters)
        let site = mapper.stripBeadOffset(rangeMeters: 0)
        #expect(abs(pdi.z + Float(mapper.stripLengthMeters)) < 1e-5)
        #expect(abs(site.z) < 1e-5)
    }

    @Test func worldMapperBeadContinuesPastTheSiteOnOvershoot() {
        let mapper = LMWorldMapper.tabletop
        let past = mapper.stripBeadOffset(downrangeMeters: 80_000)
        let uprange = mapper.stripBeadOffset(downrangeMeters: -mapper.pdiRangeMeters)
        #expect(past.z > 0)
        #expect(uprange.z < 0)
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
    @Test @MainActor func terrainSamplingMinifiesDenseBandsWithoutAliasing() {
        let colorOptions = LMTerrainWorld.terrainTextureCreateOptions(
            semantic: .color
        )
        #expect(colorOptions.semantic == .color)
        #expect(colorOptions.mipmapsMode == .allocateAndGenerateAll)

        let sampler = LMTerrainWorld.terrainTextureSampler()
        sampler.access { descriptor in
            #expect(descriptor.minFilter == .linear)
            #expect(descriptor.magFilter == .linear)
            #expect(descriptor.mipFilter == .linear)
            #expect(descriptor.maxAnisotropy == 8)
            #expect(descriptor.sAddressMode == .clampToEdge)
            #expect(descriptor.tAddressMode == .clampToEdge)
        }
    }

    @Test func missionSunDirectionAndExposureFloorPreserveLowSunRelief() throws {
        let manifest = try LMTerrainManifest.load()
        let illuminationDirection = LMFullDescentMapper
            .sunLightOrientation(from: manifest)
            .act(SIMD3<Float>(0, 0, -1))
        let expectedDirection = -LMFullDescentMapper.sunDirection(from: manifest)

        #expect(simd_dot(illuminationDirection, expectedDirection) > 0.999_99)
        #expect(illuminationDirection.y < 0)
        #expect(LMTerrainWorld.missionSunIlluminanceLux == 25_000)
        #expect(LMTerrainWorld.missionShadowMinimumDistanceMeters == 12)
        #expect(LMTerrainWorld.missionShadowMaximumDistanceMeters == 45)
        #expect(LMTerrainWorld.missionShadowDistance(altitudeMeters: 0) == 12)
        #expect(LMTerrainWorld.missionShadowDistance(altitudeMeters: 20) == 35)
        #expect(LMTerrainWorld.missionShadowDistance(altitudeMeters: 100) == 45)
        #expect(LMTerrainWorld.regolithExposureFloor > 0)
        #expect(LMTerrainWorld.regolithExposureFloor < 1)
    }

    @Test func missionSunMeanGeometryShadingDoesNotNeedGlobalLODGain() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let sun = LMFullDescentMapper.sunDirection(from: try LMTerrainManifest.load())
        let centers: [(east: Double, north: Double)] = [
            (-4.336, 19.619),
            (-20, 4),
            (12, 36),
            (28, 12),
        ]

        func meanShading(spacing: Double, level: Int) throws -> Double {
            var total = Double.zero
            var count = 0
            for center in centers {
                let plan = LMTerrainTilePlan(
                    id: .init(level: level, eastIndex: 0, northIndex: 0),
                    centerEastMeters: center.east,
                    centerNorthMeters: center.north,
                    sizeMeters: 16,
                    sampleSpacingMeters: spacing,
                    containsProceduralSubresolution: spacing < field.spacingMeters,
                    transitionEdges: []
                )
                let generated = try Apollo11TerrainResource.makeProgressiveTileMeshData(
                    heightField: field,
                    plan: plan,
                    activePlans: [plan]
                )
                let mesh = try #require(generated)
                let posts = Int(plan.sizeMeters / spacing) + 1
                for row in 1..<(posts - 1) {
                    for column in 1..<(posts - 1) {
                        let normal = mesh.normals[row * posts + column]
                        total += Double(max(simd_dot(normal, sun), 0))
                        count += 1
                    }
                }
            }
            return total / Double(count)
        }

        let measured = try meanShading(spacing: 2, level: 2)
        let terminal = try meanShading(spacing: 0.5, level: 0)
        let landing = try meanShading(spacing: 0.125, level: 1)
        #expect(measured > 0)
        #expect(terminal > 0)
        #expect(landing > 0)
        #expect(abs(measured / terminal - 1) < 0.005)
        #expect(abs(measured / landing - 1) < 0.005)
    }

    @Test func progressiveMeshCarriesItsSunIndependentAddedReliefDistribution() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let plan = LMTerrainTilePlan(
            id: .init(level: 1, eastIndex: 0, northIndex: 0),
            centerEastMeters: -4.336,
            centerNorthMeters: 19.619,
            sizeMeters: 16,
            sampleSpacingMeters: 0.125,
            containsProceduralSubresolution: true,
            transitionEdges: []
        )
        let generated = try Apollo11TerrainResource.makeProgressiveTileMeshData(
            heightField: field,
            plan: plan,
            activePlans: [plan]
        )
        let mesh = try #require(generated)
        let posts = Int(plan.sizeMeters / plan.sampleSpacingMeters) + 1
        let distribution = mesh.addedReliefNormalDistribution

        #expect(distribution.sampleCount == posts * posts)
        #expect(distribution.counts.reduce(0, +) == UInt32(posts * posts))
        #expect(distribution != .flat)
        let overhead = distribution.meanLambertianResponse(
            sunDirectionTangentSpace: SIMD3(0, 0, 1)
        )
        let grazing = distribution.meanLambertianResponse(
            sunDirectionTangentSpace: simd_normalize(SIMD3(0.8, 0, 0.6))
        )
        #expect(overhead > 0.9)
        #expect(grazing > 0)
        #expect(grazing < overhead)
    }

    @Test func explorerLandingTileMissionSunShadingVariationNeedsNoPerTileGain() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: field.spacingMeters)
        let focusEast = -4.336
        let focusNorth = 19.619
        let forward = planner.prefetchedPlans(
            focusEastMeters: focusEast,
            focusNorthMeters: focusNorth,
            velocityEastMetersPerSecond: 48.0 / 6.0,
            velocityNorthMetersPerSecond: 0,
            altitudeMeters: 2
        )
        let rear = planner.focusedPlans(
            focusEastMeters: focusEast - 32,
            focusNorthMeters: focusNorth,
            altitudeMeters: 2
        )
        let plans = planner.mergedPlans(forward + rear)
        let surface = LMProgressiveTerrainSurfaceSampler(
            heightField: field,
            planner: planner
        )
        let sun = LMFullDescentMapper.sunDirection(from: try LMTerrainManifest.load())

        func shading(
            east: Double,
            north: Double,
            plan: LMTerrainTilePlan
        ) -> Double? {
            let step = plan.sampleSpacingMeters
            guard let west = surface.renderedElevation(
                eastMeters: east - step,
                northMeters: north,
                plan: plan,
                activePlans: plans
            ), let eastHeight = surface.renderedElevation(
                eastMeters: east + step,
                northMeters: north,
                plan: plan,
                activePlans: plans
            ), let south = surface.renderedElevation(
                eastMeters: east,
                northMeters: north - step,
                plan: plan,
                activePlans: plans
            ), let northHeight = surface.renderedElevation(
                eastMeters: east,
                northMeters: north + step,
                plan: plan,
                activePlans: plans
            ) else { return nil }
            let eastSlope = (eastHeight - west) / Float(2 * step)
            let northSlope = (northHeight - south) / Float(2 * step)
            let normal = simd_normalize(SIMD3<Float>(-northSlope, 1, eastSlope))
            return Double(max(simd_dot(normal, sun), 0))
        }

        var ratios = [Double]()
        for child in plans where child.sampleSpacingMeters == 0.125 {
            let parent = try #require(surface.parentPlan(
                for: child,
                eastMeters: child.centerEastMeters,
                northMeters: child.centerNorthMeters,
                activePlans: plans
            ))
            var childTotal = Double.zero
            var parentTotal = Double.zero
            var count = 0
            for northOffset in -3...3 {
                for eastOffset in -3...3 {
                    let east = child.centerEastMeters + Double(eastOffset)
                    let north = child.centerNorthMeters + Double(northOffset)
                    guard let childShade = shading(east: east, north: north, plan: child),
                          let parentShade = shading(east: east, north: north, plan: parent) else {
                        continue
                    }
                    childTotal += childShade
                    parentTotal += parentShade
                    count += 1
                }
            }
            #expect(count > 0)
            ratios.append(parentTotal / childTotal)
        }

        #expect(!ratios.isEmpty)
        #expect(ratios.allSatisfy { abs($0 - 1) < 0.02 })
        let meanRatio = ratios.reduce(0, +) / Double(ratios.count)
        #expect(abs(meanRatio - 1) < 0.005)
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
        #expect(manifest.sources.count == 10)
        #expect(manifest.toolSHA256 == "f7e715e21c2c495ac871a6253924a8cb963534bb899156808eb0f7c68fa8a1f1")
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

    @Test func nestedAlbedoBandsAreNonFlatAndShareBoundaryReflectance() throws {
        let manifest = try LMTerrainManifest.load()
        let nearTile = try #require(manifest.tile(id: LMTerrainWorld.nearFieldTileID))
        let mediumTile = try #require(manifest.tile(id: LMTerrainWorld.mediumFieldTileID))
        let farTile = try #require(manifest.tile(id: LMTerrainWorld.farFieldTileID))
        let near = try albedoImage(for: nearTile)
        let medium = try albedoImage(for: mediumTile)
        let far = try albedoImage(for: farTile)

        #expect(near.width == 4_097 && near.height == 4_097)
        #expect(medium.width == 513 && medium.height == 513)
        #expect(far.width == 513 && far.height == 513)
        #expect(Int(near.pixels.max() ?? 0) - Int(near.pixels.min() ?? 0) > 20)
        #expect(Int(medium.pixels.max() ?? 0) - Int(medium.pixels.min() ?? 0) > 10)
        #expect(Int(far.pixels.max() ?? 0) - Int(far.pixels.min() ?? 0) > 70)

        // The 2,048 m near texture boundary lands on medium indices 224...288.
        for index in 0...64 {
            let nearIndex = index * 64
            let mediumIndex = 224 + index
            expectSameAlbedo(near, 0, nearIndex, medium, 224, mediumIndex)
            expectSameAlbedo(near, 4_096, nearIndex, medium, 288, mediumIndex)
            expectSameAlbedo(near, nearIndex, 0, medium, mediumIndex, 224)
            expectSameAlbedo(near, nearIndex, 4_096, medium, mediumIndex, 288)
        }

        // The 16,384 m medium texture boundary lands on far indices 240...272.
        for index in 0...32 {
            let mediumIndex = index * 16
            let farIndex = 240 + index
            expectSameAlbedo(medium, 0, mediumIndex, far, 240, farIndex)
            expectSameAlbedo(medium, 512, mediumIndex, far, 272, farIndex)
            expectSameAlbedo(medium, mediumIndex, 0, far, farIndex, 240)
            expectSameAlbedo(medium, mediumIndex, 512, far, farIndex, 272)
        }
    }

    @Test func nearAlbedoKeepsLandingDetailWithoutExposingSquareCrop() throws {
        let manifest = try LMTerrainManifest.load()
        let nearTile = try #require(manifest.tile(id: LMTerrainWorld.nearFieldTileID))
        let mediumTile = try #require(manifest.tile(id: LMTerrainWorld.mediumFieldTileID))
        let near = try albedoImage(for: nearTile)
        let medium = try albedoImage(for: mediumTile)

        // At the landing-site origin the 0.5 m NAC residual remains plainly
        // present over the WAC parent value.
        let centerResidual = abs(Int(near[2_048, 2_048]) - Int(medium[256, 256]))
        #expect(centerResidual >= 8)

        // At equal-radius samples near the first tile edge, and outside the
        // inscribed radial footprint, the result has returned to the WAC
        // parent. A square edge-distance mask would retain detail at the
        // diagonal sample and make the crop visible in regional views.
        let handoffSamples = [
            (nearRow: 2_048, nearColumn: 3_968, mediumRow: 256, mediumColumn: 286),
            (nearRow: 2_048, nearColumn: 128, mediumRow: 256, mediumColumn: 226),
            (nearRow: 128, nearColumn: 2_048, mediumRow: 226, mediumColumn: 256),
            (nearRow: 3_968, nearColumn: 2_048, mediumRow: 286, mediumColumn: 256),
            (nearRow: 512, nearColumn: 512, mediumRow: 232, mediumColumn: 232),
        ]
        for sample in handoffSamples {
            expectSameAlbedo(
                near,
                sample.nearRow,
                sample.nearColumn,
                medium,
                sample.mediumRow,
                sample.mediumColumn
            )
        }
    }

    @Test func nativeNearFieldDrivesTheProductionSampler() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        #expect(field.width == 1_025)
        #expect(field.height == 1_025)
        #expect(abs(field.spacingMeters - 2) < 1e-9)
        #expect(field.heights.count == 1_025 * 1_025)
        #expect(field.heights.allSatisfy { $0.isFinite })

        let origin = try #require(field.relativeElevation(eastMeters: 0, northMeters: 0))
        #expect(abs(origin) < 5)
        #expect(field.relativeElevation(eastMeters: 757, northMeters: -540) != nil)
    }

    @Test func nestedTerrainBandsShareQuantizedBoundaryHeights() throws {
        let manifest = try LMTerrainManifest.load()
        let near = try #require(manifest.tile(id: LMTerrainWorld.nearFieldTileID))
        let medium = try #require(manifest.tile(id: LMTerrainWorld.mediumFieldTileID))
        let far = try #require(manifest.tile(id: LMTerrainWorld.farFieldTileID))
        let nearMap = try heightMap(for: near)
        let mediumMap = try heightMap(for: medium)
        let farMap = try heightMap(for: far)

        // The 2,048 m NAC boundary lands on medium indices 224...288.
        for index in 0...64 {
            let nearIndex = index * 16
            let mediumIndex = 224 + index
            try expectSameHeight(nearMap, near, 0, nearIndex, mediumMap, medium, 224, mediumIndex, 0.02)
            try expectSameHeight(nearMap, near, 1_024, nearIndex, mediumMap, medium, 288, mediumIndex, 0.02)
            try expectSameHeight(nearMap, near, nearIndex, 0, mediumMap, medium, mediumIndex, 224, 0.02)
            try expectSameHeight(nearMap, near, nearIndex, 1_024, mediumMap, medium, mediumIndex, 288, 0.02)
        }

        // The 16,384 m medium boundary lands on far indices 240...272.
        for index in 0...32 {
            let mediumIndex = index * 16
            let farIndex = 240 + index
            try expectSameHeight(mediumMap, medium, 0, mediumIndex, farMap, far, 240, farIndex, 0.27)
            try expectSameHeight(mediumMap, medium, 512, mediumIndex, farMap, far, 272, farIndex, 0.27)
            try expectSameHeight(mediumMap, medium, mediumIndex, 0, farMap, far, farIndex, 240, 0.27)
            try expectSameHeight(mediumMap, medium, mediumIndex, 512, farMap, far, farIndex, 272, 0.27)
        }
    }

    @Test func nestedMeshHolesEndOnSharedGridLines() throws {
        let manifest = try LMTerrainManifest.load()
        let medium = try #require(manifest.tile(id: LMTerrainWorld.mediumFieldTileID))
        let far = try #require(manifest.tile(id: LMTerrainWorld.farFieldTileID))
        let mediumGrid = try LMTerrainMeshBuilder.grid(
            tile: medium,
            heightMap: heightMap(for: medium),
            holeHalfExtentMeters: 1_024
        )
        let farGrid = try LMTerrainMeshBuilder.grid(
            tile: far,
            heightMap: heightMap(for: far),
            holeHalfExtentMeters: 8_192
        )
        #expect(mediumGrid.triangles.count == (512 * 512 - 64 * 64) * 6)
        #expect(farGrid.triangles.count == (512 * 512 - 32 * 32) * 6)
    }

    @Test func measuredTerrainTriangleWindingFacesUpward() throws {
        let manifest = try LMTerrainManifest.load()
        let near = try #require(manifest.tile(id: LMTerrainWorld.nearFieldTileID))
        let grid = try LMTerrainMeshBuilder.grid(
            tile: near,
            heightMap: heightMap(for: near)
        )
        let i0 = Int(grid.triangles[0])
        let i1 = Int(grid.triangles[1])
        let i2 = Int(grid.triangles[2])
        let geometricNormal = simd_normalize(simd_cross(
            grid.positions[i1] - grid.positions[i0],
            grid.positions[i2] - grid.positions[i0]
        ))

        #expect(geometricNormal.y > 0.9)
        #expect(simd_dot(geometricNormal, grid.normals[i0]) > 0.9)
    }

    private func heightMap(for tile: LMTerrainManifest.Tile) throws -> LMTerrainHeightMap {
        let name = (tile.heightFile as NSString).deletingPathExtension
        let ext = (tile.heightFile as NSString).pathExtension
        let url = try #require(
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Terrain")
                ?? Bundle.main.url(forResource: name, withExtension: ext)
        )
        return try LMTerrainHeightMap.load(contentsOf: url)
    }

    private struct AlbedoImage {
        let width: Int
        let height: Int
        let pixels: [UInt8]

        subscript(row: Int, column: Int) -> UInt8 {
            pixels[row * width + column]
        }
    }

    private func albedoImage(for tile: LMTerrainManifest.Tile) throws -> AlbedoImage {
        let name = (tile.albedoFile as NSString).deletingPathExtension
        let ext = (tile.albedoFile as NSString).pathExtension
        let url = try #require(
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Terrain")
                ?? Bundle.main.url(forResource: name, withExtension: ext)
        )
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height)
        let context = try #require(CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return AlbedoImage(width: image.width, height: image.height, pixels: pixels)
    }

    private func expectSameAlbedo(
        _ first: AlbedoImage,
        _ firstRow: Int,
        _ firstColumn: Int,
        _ second: AlbedoImage,
        _ secondRow: Int,
        _ secondColumn: Int
    ) {
        #expect(abs(Int(first[firstRow, firstColumn]) - Int(second[secondRow, secondColumn])) <= 1)
    }

    private func expectSameHeight(
        _ firstMap: LMTerrainHeightMap,
        _ firstTile: LMTerrainManifest.Tile,
        _ firstRow: Int,
        _ firstColumn: Int,
        _ secondMap: LMTerrainHeightMap,
        _ secondTile: LMTerrainManifest.Tile,
        _ secondRow: Int,
        _ secondColumn: Int,
        _ tolerance: Double
    ) throws {
        let first = firstMap.heightMeters(
            atPost: firstRow,
            column: firstColumn,
            zeroPointMeters: firstTile.zeroPointMeters,
            centimetersPerCount: firstTile.heightEncoding.centimetersPerCount
        )
        let second = secondMap.heightMeters(
            atPost: secondRow,
            column: secondColumn,
            zeroPointMeters: secondTile.zeroPointMeters,
            centimetersPerCount: secondTile.heightEncoding.centimetersPerCount
        )
        #expect(abs(first - second) <= tolerance)
    }

    @Test func measuredMeshUsesNorthUpAndEastBackCoordinates() throws {
        let posts = 8
        let spacing = 2.0
        let tile = LMTerrainManifest.Tile(
            id: "test",
            postsPerSide: posts,
            postSpacingMeters: spacing,
            extentMeters: Double(posts - 1) * spacing,
            zeroPointMeters: 0,
            minimumHeightMeters: 0,
            maximumHeightMeters: 10,
            curvatureCorrected: false,
            edgeHandling: nil,
            sourceIDs: nil,
            nativeSourceSpacingMeters: nil,
            transitionWidthMeters: nil,
            heightFile: "test-height.png",
            albedoFile: "test-albedo.png",
            heightEncoding: .init(format: "PNG_GRAYSCALE_16LE", centimetersPerCount: 1, detail: ""),
            albedoEncoding: .init(format: "PNG_RGB_8", detail: ""),
            detail: nil
        )
        var counts = [UInt16](repeating: 0, count: posts * posts)
        for column in 0..<posts { counts[column] = 1_000 }
        let map = LMTerrainHeightMap(width: posts, height: posts, counts: counts)
        let grid = try LMTerrainMeshBuilder.grid(tile: tile, heightMap: map)

        let halfSpan = Float(Double(posts - 1) / 2 * spacing)
        let northeast = grid.positions[posts - 1]
        #expect(abs(northeast.x - halfSpan) < 1e-4)
        #expect(abs(northeast.z + halfSpan) < 1e-4)
        #expect(abs(northeast.y - 10) < 0.02)
        #expect(grid.normals[(posts - 1) * posts + posts - 1].y > 0.95)
    }

    @Test func measuredMeshNormalsFollowNorthAndEastSlopes() throws {
        let posts = 8
        let spacing = 2.0
        let tile = LMTerrainManifest.Tile(
            id: "slope-test",
            postsPerSide: posts,
            postSpacingMeters: spacing,
            extentMeters: Double(posts - 1) * spacing,
            zeroPointMeters: 0,
            minimumHeightMeters: 0,
            maximumHeightMeters: 100,
            curvatureCorrected: false,
            edgeHandling: nil,
            sourceIDs: nil,
            nativeSourceSpacingMeters: nil,
            transitionWidthMeters: nil,
            heightFile: "test-height.png",
            albedoFile: "test-albedo.png",
            heightEncoding: .init(format: "PNG_GRAYSCALE_16LE", centimetersPerCount: 1, detail: ""),
            albedoEncoding: .init(format: "PNG_RGB_8", detail: ""),
            detail: nil
        )
        let halfSpan = Double(posts - 1) * spacing / 2
        var counts = [UInt16](repeating: 0, count: posts * posts)
        for row in 0..<posts {
            let north = halfSpan - Double(row) * spacing
            for column in 0..<posts {
                let east = Double(column) * spacing - halfSpan
                let heightMeters = 50 + 0.5 * north + 0.25 * east
                counts[row * posts + column] = UInt16((heightMeters * 100).rounded())
            }
        }
        let map = LMTerrainHeightMap(width: posts, height: posts, counts: counts)
        let grid = try LMTerrainMeshBuilder.grid(tile: tile, heightMap: map)
        let normal = grid.normals[3 * posts + 3]
        let expected = simd_normalize(SIMD3<Float>(-0.5, 1, 0.25))

        #expect(simd_distance(normal, expected) < 1e-5)
    }

    @Test func measuredGeometryAndNormalLODHandOffRadiallyToParent() throws {
        func tile(id: String, posts: Int, spacing: Double) -> LMTerrainManifest.Tile {
            LMTerrainManifest.Tile(
                id: id,
                postsPerSide: posts,
                postSpacingMeters: spacing,
                extentMeters: Double(posts - 1) * spacing,
                zeroPointMeters: 0,
                minimumHeightMeters: 0,
                maximumHeightMeters: 100,
                curvatureCorrected: false,
                edgeHandling: nil,
                sourceIDs: nil,
                nativeSourceSpacingMeters: nil,
                transitionWidthMeters: nil,
                heightFile: "test-height.png",
                albedoFile: "test-albedo.png",
                heightEncoding: .init(
                    format: "PNG_GRAYSCALE_16LE",
                    centimetersPerCount: 1,
                    detail: ""
                ),
                albedoEncoding: .init(format: "PNG_RGB_8", detail: ""),
                detail: nil
            )
        }
        func heightMap(
            tile: LMTerrainManifest.Tile,
            northSlope: Double,
            eastSlope: Double
        ) -> LMTerrainHeightMap {
            let posts = tile.postsPerSide
            let spacing = tile.postSpacingMeters
            let halfExtent = tile.extentMeters / 2
            var counts = [UInt16](repeating: 0, count: posts * posts)
            for row in 0..<posts {
                let north = halfExtent - Double(row) * spacing
                for column in 0..<posts {
                    let east = Double(column) * spacing - halfExtent
                    let height = 50 + northSlope * north + eastSlope * east
                    counts[row * posts + column] = UInt16((height * 100).rounded())
                }
            }
            return LMTerrainHeightMap(width: posts, height: posts, counts: counts)
        }

        let parentTile = tile(id: "parent", posts: 5, spacing: 2)
        let childTile = tile(id: "child", posts: 5, spacing: 1)
        let parent = try LMTerrainMeshBuilder.grid(
            tile: parentTile,
            heightMap: heightMap(tile: parentTile, northSlope: 0.2, eastSlope: 0.1)
        )
        let child = try LMTerrainMeshBuilder.grid(
            tile: childTile,
            heightMap: heightMap(tile: childTile, northSlope: 0.8, eastSlope: -0.3)
        )
        let morphed = try LMTerrainMeshBuilder.morphToParent(
            child: child,
            parent: parent,
            parentTile: parentTile,
            childHalfExtentMeters: childTile.extentMeters / 2
        )

        #expect(morphed.triangles == child.triangles)
        let parentNormal = simd_normalize(SIMD3<Float>(-0.2, 1, 0.1))
        let childNormal = simd_normalize(SIMD3<Float>(-0.8, 1, -0.3))
        let northEdge = 2
        let halfRadius = 1 * childTile.postsPerSide + 2
        let center = 2 * childTile.postsPerSide + 2
        #expect(abs(morphed.positions[northEdge].y - 50.4) < 1e-5)
        #expect(morphed.positions[center] == child.positions[center])
        #expect(abs(morphed.positions[halfRadius].y - 50.5) < 1e-5)
        #expect(simd_distance(morphed.normals[northEdge], parentNormal) < 1e-5)
        #expect(simd_distance(morphed.normals[center], childNormal) < 1e-5)
        let halfwayNormal = simd_normalize(parentNormal + (childNormal - parentNormal) * 0.5)
        #expect(simd_distance(morphed.normals[halfRadius], halfwayNormal) < 1e-5)
    }
}

@Suite("Progressive lunar terrain")
struct ProgressiveLunarTerrainTests {
    @Test func measuredPostsRemainExactAndProceduralDetailIsBounded() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let sampler = LMProgressiveTerrainSampler(heightField: field)

        let measuredPost = try #require(sampler.sample(
            eastMeters: 0,
            northMeters: 0,
            requestedSpacingMeters: 0.5
        ))
        #expect(abs(measuredPost.proceduralResidualMeters) < 1e-7)
        #expect(measuredPost.elevationMeters == measuredPost.measuredElevationMeters)
        #expect(measuredPost.provenance == .measuredWithProceduralSubresolution)

        let subPost = try #require(stride(from: -7.75, through: 7.75, by: 0.25)
            .lazy
            .flatMap { north in
                stride(from: -7.75, through: 7.75, by: 0.25).lazy.map { east in
                    sampler.sample(
                        eastMeters: east,
                        northMeters: north,
                        requestedSpacingMeters: 0.125
                    )
                }
            }
            .compactMap { $0 }
            .first { abs($0.proceduralResidualMeters) > 1e-5 })
        #expect(abs(subPost.proceduralResidualMeters) <= sampler.maximumResidualMeters)
        #expect(abs(subPost.proceduralResidualMeters) > 1e-5)
        #expect(abs(
            subPost.elevationMeters
                - subPost.measuredElevationMeters
                - subPost.proceduralResidualMeters
        ) < 1e-6)
    }

    @Test func geologyModelPinsSurveyorDistributionAndProducesCraterMorphology() throws {
        #expect(LMLunarGeologyModel.modelID == "surveyor-degraded-microrelief-v3")
        #expect(LMLunarGeologyModel.cumulativeCraterDiameterExponent == -2)
        #expect(LMLunarGeologyModel.minimumCraterDiameterMeters >= 0.13)
        #expect(LMLunarGeologyModel.maximumCraterDiameterMeters <= 3)
        #expect(LMLunarGeologyModel.surveyorSourceURL.contains("usgs.gov"))
        #expect(LMLunarGeologyModel.apollo11SourceURL.contains("nasa.gov"))
        #expect(LMLunarGeologyModel(seed: 0).candidateAcceptance < 0.25)

        let crater = LMLunarGeologyModel.Crater(
            eastMeters: 0,
            northMeters: 0,
            diameterMeters: 1,
            aspectRatio: 1,
            rotationRadians: 0,
            sharpness: 0.8,
            rimPhase: 0,
            rimLobes: 5,
            ejectaPhase: 0
        )
        let center = LMLunarGeologyModel.craterReliefMeters(
            eastMeters: 0,
            northMeters: 0,
            crater: crater
        )
        let rim = LMLunarGeologyModel.craterReliefMeters(
            eastMeters: 0.5,
            northMeters: 0,
            crater: crater
        )
        let outside = LMLunarGeologyModel.craterReliefMeters(
            eastMeters: 1,
            northMeters: 0,
            crater: crater
        )
        #expect(center < -0.06)
        #expect(rim > 0.008)
        #expect(outside == 0)
    }

    @Test func postAnchoringIsContinuousAcrossMeasuredCellBoundaries() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let sampler = LMProgressiveTerrainSampler(heightField: field)
        let epsilon = 1e-6
        let west = try #require(sampler.sample(
            eastMeters: -epsilon,
            northMeters: 1.13,
            requestedSpacingMeters: 0.125
        ))
        let east = try #require(sampler.sample(
            eastMeters: epsilon,
            northMeters: 1.13,
            requestedSpacingMeters: 0.125
        ))
        #expect(abs(west.proceduralResidualMeters - east.proceduralResidualMeters) < 1e-4)
    }

    /// Procedural relief now reaches the landing-gear contact surface, but it
    /// still has to stay separable: the measured LROC value must remain
    /// readable on its own so a regenerated DTM can replace it.
    @Test func synthesizedReliefStaysSeparableFromTheMeasuredElevation() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let sampler = LMProgressiveTerrainSampler(heightField: field)
        let measured = try #require(field.relativeElevation(
            eastMeters: 0.75,
            northMeters: -0.75
        ))
        let visual = try #require(sampler.sample(
            eastMeters: 0.75,
            northMeters: -0.75,
            requestedSpacingMeters: 0.125
        ))
        #expect(visual.measuredElevationMeters == measured)
        #expect(visual.proceduralResidualMeters != 0)
        #expect(
            visual.elevationMeters
                == visual.measuredElevationMeters + visual.proceduralResidualMeters
        )
        #expect(abs(visual.elevationMeters - measured) <= sampler.maximumResidualMeters)
    }

    @Test func proceduralResidualIsDeterministicAndNeverFillsUnknownCoverage() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let first = LMProgressiveTerrainSampler(heightField: field)
        let second = LMProgressiveTerrainSampler(heightField: field)

        #expect(first.sample(
            eastMeters: 103.5,
            northMeters: -47.25,
            requestedSpacingMeters: 1
        ) == second.sample(
            eastMeters: 103.5,
            northMeters: -47.25,
            requestedSpacingMeters: 1
        ))
        #expect(first.sample(
            eastMeters: 50_000,
            northMeters: 50_000,
            requestedSpacingMeters: 0.5
        ) == nil)
    }

    @Test func coarseRequestsReturnOnlyMeasuredInterpolation() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let sample = try #require(LMProgressiveTerrainSampler(heightField: field).sample(
            eastMeters: 11,
            northMeters: 17,
            requestedSpacingMeters: field.spacingMeters
        ))

        #expect(sample.provenance == .measuredInterpolated)
        #expect(sample.proceduralResidualMeters == 0)
    }

    @Test func tileIDsStayStableUntilTheFocusCrossesATileBoundary() throws {
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: 2)
        let first = planner.plan(focusEastMeters: -547, focusNorthMeters: 732)
        let sameTile = planner.plan(focusEastMeters: -546.5, focusNorthMeters: 732.5)
        let crossed = planner.plan(focusEastMeters: -511.5, focusNorthMeters: 732.5)

        #expect(first.map(\.id) == sameTile.map(\.id))
        #expect(first.map(\.id) != crossed.map(\.id))
        #expect(first.contains { $0.containsProceduralSubresolution })
        #expect(first.contains { !$0.containsProceduralSubresolution })
        #expect(Set(first.map(\.id)).count == first.count)
    }

    @Test func altitudePolicyStreamsOnlyUsefulNestedDetail() throws {
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: 2)

        #expect(planner.focusedPlans(
            focusEastMeters: -547,
            focusNorthMeters: 732,
            altitudeMeters: 15_000
        ).isEmpty)

        let approach = planner.focusedPlans(
            focusEastMeters: -547,
            focusNorthMeters: 732,
            altitudeMeters: 2_000
        )
        #expect(approach.isEmpty)

        let terminal = planner.focusedPlans(
            focusEastMeters: -547,
            focusNorthMeters: 732,
            altitudeMeters: 100
        )
        #expect(terminal.map(\.sampleSpacingMeters) == [0.5])
        #expect(terminal.allSatisfy { $0.containsProceduralSubresolution })

        let landingPreload = planner.focusedPlans(
            focusEastMeters: -547,
            focusNorthMeters: 732,
            altitudeMeters: 50
        )
        #expect(landingPreload.contains { $0.sampleSpacingMeters == 0.5 })
        // The 16 m landing safety radius intentionally covers a bounded 3x3
        // working set around this off-center focus.
        #expect(landingPreload.filter { $0.sampleSpacingMeters == 0.125 }.count == 9)

        let aboveLandingPreload = planner.focusedPlans(
            focusEastMeters: -547,
            focusNorthMeters: 732,
            altitudeMeters: 61
        )
        #expect(aboveLandingPreload.map(\.sampleSpacingMeters) == [0.5])

        let landing = planner.focusedPlans(
            focusEastMeters: -547,
            focusNorthMeters: 732,
            altitudeMeters: 20
        )
        #expect(Set(landing.map(\.sampleSpacingMeters)) == Set([0.5, 0.125]))
        #expect(Set(landing.map(\.sizeMeters)) == Set([64, 16]))

        let manifestSpacing = 2.000_000_000_000_6
        let manifestPlanner = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: manifestSpacing
        )
        #expect(manifestPlanner.focusedPlans(
            focusEastMeters: -547,
            focusNorthMeters: 732,
            altitudeMeters: 100
        ).map(\.sampleSpacingMeters) == [0.5])
        let measuredScalePlan = try #require(manifestPlanner.plan(
            focusEastMeters: -547,
            focusNorthMeters: 732
        ).first { $0.sampleSpacingMeters == 2 })
        #expect(!measuredScalePlan.containsProceduralSubresolution)
    }

    @Test func finerLandingTileMorphsExactlyToTheRenderedParentAtEveryBoundary() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let plans = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: field.spacingMeters
        ).focusedPlans(
            focusEastMeters: 2,
            focusNorthMeters: 2,
            altitudeMeters: 20
        )
        let parentPlan = try #require(plans.first { $0.sampleSpacingMeters == 0.5 })
        let finePlan = try #require(plans.first { $0.sampleSpacingMeters == 0.125 })
        let generatedParentMesh = try Apollo11TerrainResource.makeProgressiveTileMeshData(
            heightField: field,
            plan: parentPlan
        )
        let generatedFineMesh = try Apollo11TerrainResource.makeProgressiveTileMeshData(
            heightField: field,
            plan: finePlan
        )
        let parentMesh = try #require(generatedParentMesh)
        let fineMesh = try #require(generatedFineMesh)
        let samples = 129
        #expect(parentMesh.positions.count == samples * samples)
        #expect(fineMesh.positions.count == samples * samples)
        #expect(fineMesh.indices.count == (samples - 1) * (samples - 1) * 6)
        let i0 = Int(fineMesh.indices[0])
        let i1 = Int(fineMesh.indices[1])
        let i2 = Int(fineMesh.indices[2])
        let geometricNormal = simd_normalize(simd_cross(
            fineMesh.positions[i1] - fineMesh.positions[i0],
            fineMesh.positions[i2] - fineMesh.positions[i0]
        ))
        #expect(geometricNormal.y > 0.9)
        #expect(simd_dot(geometricNormal, fineMesh.normals[i0]) > 0.9)

        func parentHeight(eastMeters: Double, northMeters: Double) -> Float {
            let halfSize = parentPlan.sizeMeters / 2
            let column = Int((
                (eastMeters - (parentPlan.centerEastMeters - halfSize))
                    / parentPlan.sampleSpacingMeters
            ).rounded())
            let row = Int((
                (parentPlan.centerNorthMeters + halfSize - northMeters)
                    / parentPlan.sampleSpacingMeters
            ).rounded())
            return parentMesh.positions[row * samples + column].y
        }

        let fineHalfSize = finePlan.sizeMeters / 2
        for index in stride(from: 0, through: samples - 1, by: 4) {
            let east = finePlan.centerEastMeters - fineHalfSize
                + Double(index) * finePlan.sampleSpacingMeters
            let north = finePlan.centerNorthMeters + fineHalfSize
                - Double(index) * finePlan.sampleSpacingMeters
            let northEdge = fineMesh.positions[index].y
            let southEdge = fineMesh.positions[(samples - 1) * samples + index].y
            let westEdge = fineMesh.positions[index * samples].y
            let eastEdge = fineMesh.positions[index * samples + samples - 1].y
            #expect(abs(northEdge - parentHeight(
                eastMeters: east,
                northMeters: finePlan.centerNorthMeters + fineHalfSize
            )) < 1e-6)
            #expect(abs(southEdge - parentHeight(
                eastMeters: east,
                northMeters: finePlan.centerNorthMeters - fineHalfSize
            )) < 1e-6)
            #expect(abs(westEdge - parentHeight(
                eastMeters: finePlan.centerEastMeters - fineHalfSize,
                northMeters: north
            )) < 1e-6)
            #expect(abs(eastEdge - parentHeight(
                eastMeters: finePlan.centerEastMeters + fineHalfSize,
                northMeters: north
            )) < 1e-6)
        }
    }

    @Test func landingPerimeterNormalsMatchRenderedParent() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: field.spacingMeters)
        let plans = planner.focusedPlans(
            focusEastMeters: 2,
            focusNorthMeters: 2,
            altitudeMeters: 20
        )
        let sampler = LMProgressiveTerrainSurfaceSampler(
            heightField: field,
            planner: planner
        )
        let finePlan = try #require(plans.first {
            $0.sampleSpacingMeters == 0.125 && !$0.transitionEdges.isEmpty
        })
        let parentPlan = try #require(sampler.parentPlan(
            for: finePlan,
            eastMeters: finePlan.centerEastMeters,
            northMeters: finePlan.centerNorthMeters,
            activePlans: plans
        ))
        let generatedFine = try Apollo11TerrainResource.makeProgressiveTileMeshData(
            heightField: field,
            plan: finePlan,
            activePlans: plans
        )
        let generatedParent = try Apollo11TerrainResource.makeProgressiveTileMeshData(
            heightField: field,
            plan: parentPlan,
            activePlans: plans
        )
        let fine = try #require(generatedFine)
        let parent = try #require(generatedParent)

        func normal(
            plan: LMTerrainTilePlan,
            mesh: LMProgressiveTerrainMeshData,
            east: Double,
            north: Double
        ) -> SIMD3<Float> {
            let samples = Int(plan.sizeMeters / plan.sampleSpacingMeters) + 1
            let halfSize = plan.sizeMeters / 2
            let column = Int(((east - (plan.centerEastMeters - halfSize))
                / plan.sampleSpacingMeters).rounded())
            let row = Int(((plan.centerNorthMeters + halfSize - north)
                / plan.sampleSpacingMeters).rounded())
            return mesh.normals[row * samples + column]
        }

        let halfSize = finePlan.sizeMeters / 2
        let samples = Int(finePlan.sizeMeters / finePlan.sampleSpacingMeters) + 1
        var dots = [Float]()
        for index in stride(from: 0, through: samples - 1, by: 4) {
            let east = finePlan.centerEastMeters - halfSize
                + Double(index) * finePlan.sampleSpacingMeters
            let north = finePlan.centerNorthMeters + halfSize
                - Double(index) * finePlan.sampleSpacingMeters
            if finePlan.transitionEdges.contains(.north) {
                dots.append(simd_dot(
                    normal(plan: finePlan, mesh: fine, east: east,
                           north: finePlan.centerNorthMeters + halfSize),
                    normal(plan: parentPlan, mesh: parent, east: east,
                           north: finePlan.centerNorthMeters + halfSize)
                ))
            }
            if finePlan.transitionEdges.contains(.south) {
                dots.append(simd_dot(
                    normal(plan: finePlan, mesh: fine, east: east,
                           north: finePlan.centerNorthMeters - halfSize),
                    normal(plan: parentPlan, mesh: parent, east: east,
                           north: finePlan.centerNorthMeters - halfSize)
                ))
            }
            if finePlan.transitionEdges.contains(.west) {
                dots.append(simd_dot(
                    normal(plan: finePlan, mesh: fine,
                           east: finePlan.centerEastMeters - halfSize, north: north),
                    normal(plan: parentPlan, mesh: parent,
                           east: finePlan.centerEastMeters - halfSize, north: north)
                ))
            }
            if finePlan.transitionEdges.contains(.east) {
                dots.append(simd_dot(
                    normal(plan: finePlan, mesh: fine,
                           east: finePlan.centerEastMeters + halfSize, north: north),
                    normal(plan: parentPlan, mesh: parent,
                           east: finePlan.centerEastMeters + halfSize, north: north)
                ))
            }
        }

        #expect(!dots.isEmpty)
        #expect(dots.allSatisfy { $0 > 0.999_9 })
    }

    @Test func adjacentFineTilesKeepFullDetailAcrossTheirSharedEdge() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: field.spacingMeters)
        let plans = planner.focusedPlans(
            focusEastMeters: 12,
            focusNorthMeters: 2,
            altitudeMeters: 20
        )
        let fine = plans.filter { $0.sampleSpacingMeters == 0.125 }
        let west = try #require(fine.first { candidate in
            fine.contains {
                $0.id.level == candidate.id.level
                    && $0.id.eastIndex == candidate.id.eastIndex + 1
                    && $0.id.northIndex == candidate.id.northIndex
            }
        })
        let east = try #require(fine.first {
            $0.id.level == west.id.level
                && $0.id.eastIndex == west.id.eastIndex + 1
                && $0.id.northIndex == west.id.northIndex
        })
        let sharedEast = west.centerEastMeters + west.sizeMeters / 2
        // Sample the shared edge away from a measured post. Tile boundaries and
        // centers both land on even metres, which are exactly 2 m LROC posts,
        // and the anchoring contract forces the procedural residual to zero
        // there at every level. On a post the fine surface therefore equals its
        // parent by construction, so the detail assertion below would hold no
        // matter how much detail the level actually contributes.
        let sharedNorth = west.centerNorthMeters + 1
        let sampler = LMProgressiveTerrainSurfaceSampler(
            heightField: field,
            planner: planner
        )
        let westHeight = try #require(sampler.renderedElevation(
            eastMeters: sharedEast,
            northMeters: sharedNorth,
            plan: west,
            activePlans: plans
        ))
        let eastHeight = try #require(sampler.renderedElevation(
            eastMeters: sharedEast,
            northMeters: sharedNorth,
            plan: east,
            activePlans: plans
        ))
        let parent = try #require(sampler.parentPlan(
            for: west,
            eastMeters: sharedEast,
            northMeters: sharedNorth,
            activePlans: plans
        ))
        let parentHeight = try #require(sampler.renderedElevation(
            eastMeters: sharedEast,
            northMeters: sharedNorth,
            plan: parent,
            activePlans: plans
        ))

        #expect(!west.transitionEdges.contains(.east))
        #expect(!east.transitionEdges.contains(.west))
        #expect(abs(westHeight - eastHeight) < 1e-6)
        #expect(abs(westHeight - parentHeight) > 1e-5)

        let generatedWestMesh = try Apollo11TerrainResource
            .makeProgressiveTileMeshData(
            heightField: field,
            plan: west,
            activePlans: plans
        )
        let generatedEastMesh = try Apollo11TerrainResource
            .makeProgressiveTileMeshData(
            heightField: field,
            plan: east,
            activePlans: plans
        )
        let westMesh = try #require(generatedWestMesh)
        let eastMesh = try #require(generatedEastMesh)
        let sampleCount = Int(west.sizeMeters / west.sampleSpacingMeters) + 1
        let midpointRow = sampleCount / 2
        let westIndex = midpointRow * sampleCount + sampleCount - 1
        let eastIndex = midpointRow * sampleCount
        #expect(abs(
            westMesh.positions[westIndex].y - eastMesh.positions[eastIndex].y
        ) < 1e-6)
        #expect(simd_dot(
            westMesh.normals[westIndex],
            eastMesh.normals[eastIndex]
        ) > 0.999_99)
    }

    @Test func finerResidentTilesReplaceCoveredParentTriangles() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let plans = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: field.spacingMeters
        ).focusedPlans(
            focusEastMeters: 2,
            focusNorthMeters: 2,
            altitudeMeters: 20
        )
        let finePlans = plans.filter { $0.sampleSpacingMeters == 0.125 }
        let parentPlan = try #require(plans.first { candidate in
            guard candidate.sampleSpacingMeters == 0.5 else { return false }
            let halfSize = candidate.sizeMeters / 2
            return finePlans.contains {
                $0.centerEastMeters > candidate.centerEastMeters - halfSize
                    && $0.centerEastMeters < candidate.centerEastMeters + halfSize
                    && $0.centerNorthMeters > candidate.centerNorthMeters - halfSize
                    && $0.centerNorthMeters < candidate.centerNorthMeters + halfSize
            }
        })
        let generated = try Apollo11TerrainResource.makeProgressiveTileMeshData(
            heightField: field,
            plan: parentPlan,
            activePlans: plans
        )
        let mesh = try #require(generated)
        let sampleCount = Int(parentPlan.sizeMeters / parentPlan.sampleSpacingMeters) + 1
        let completeIndexCount = (sampleCount - 1) * (sampleCount - 1) * 6

        #expect(mesh.indices.count < completeIndexCount)
        for triangle in stride(from: 0, to: mesh.indices.count, by: 3) {
            let first = mesh.positions[Int(mesh.indices[triangle])]
            let second = mesh.positions[Int(mesh.indices[triangle + 1])]
            let third = mesh.positions[Int(mesh.indices[triangle + 2])]
            let center = (first + second + third) / 3
            let east = -Double(center.z)
            let north = Double(center.x)
            #expect(!finePlans.contains { fine in
                let halfSize = fine.sizeMeters / 2
                return east > fine.centerEastMeters - halfSize
                    && east < fine.centerEastMeters + halfSize
                    && north > fine.centerNorthMeters - halfSize
                    && north < fine.centerNorthMeters + halfSize
            })
        }
    }

    @Test func transparentFineTilesDoNotRemoveParentTriangles() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let plans = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: field.spacingMeters
        ).focusedPlans(
            focusEastMeters: 2,
            focusNorthMeters: 2,
            altitudeMeters: 20
        )
        let parentPlan = try #require(plans.first {
            $0.sampleSpacingMeters == 0.5
        })
        let generated = try Apollo11TerrainResource.makeProgressiveTileMeshData(
            heightField: field,
            plan: parentPlan,
            activePlans: plans,
            geometryReplacementPlans: plans.filter {
                $0.sampleSpacingMeters >= parentPlan.sampleSpacingMeters
            }
        )
        let mesh = try #require(generated)
        let sampleCount = Int(parentPlan.sizeMeters / parentPlan.sampleSpacingMeters) + 1
        #expect(mesh.indices.count == (sampleCount - 1) * (sampleCount - 1) * 6)
    }

    @Test func presentationPreloadsFineGeometryThenBlendsToExactRenderedTouchdown() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: field.spacingMeters)
        let plans = planner.focusedPlans(
            focusEastMeters: 2,
            focusNorthMeters: 2,
            altitudeMeters: 20
        )
        let parentPlan = try #require(plans.first { $0.sampleSpacingMeters == 0.5 })
        let finePlan = try #require(plans.first { $0.sampleSpacingMeters == 0.125 })
        let sampler = LMProgressiveTerrainSurfaceSampler(
            heightField: field,
            planner: planner
        )
        let east = finePlan.centerEastMeters
        let north = finePlan.centerNorthMeters
        let parent = try #require(sampler.renderedElevation(
            eastMeters: east,
            northMeters: north,
            plan: parentPlan,
            activePlans: plans
        ))
        let fine = try #require(sampler.renderedElevation(
            eastMeters: east,
            northMeters: north,
            plan: finePlan,
            activePlans: plans
        ))
        let preloaded = try #require(sampler.sample(
            eastMeters: east,
            northMeters: north,
            altitudeMeters: 50,
            activePlans: plans
        ))
        let halfway = try #require(sampler.sample(
            eastMeters: east,
            northMeters: north,
            altitudeMeters: 32.5,
            activePlans: plans
        ))
        let touchdown = try #require(sampler.sample(
            eastMeters: east,
            northMeters: north,
            altitudeMeters: 0,
            activePlans: plans
        ))

        #expect(preloaded.sampleSpacingMeters == 0.125)
        #expect(preloaded.presentationBlend == 0)
        #expect(abs(preloaded.presentationElevationMeters - parent) < 1e-6)
        #expect(abs(halfway.presentationBlend - 0.5) < 1e-9)
        #expect(abs(
            halfway.presentationElevationMeters - (parent + (fine - parent) * 0.5)
        ) < 1e-6)
        #expect(touchdown.presentationBlend == 1)
        #expect(abs(touchdown.presentationElevationMeters - fine) < 1e-6)
        #expect(abs(touchdown.renderedElevationMeters - fine) < 1e-6)
    }

    @Test func terminalVelocityPrefetchesBeyondTheCurrentSafetyFootprint() {
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: 2)
        let stationary = planner.prefetchedPlans(
            focusEastMeters: 12,
            focusNorthMeters: 2,
            velocityEastMetersPerSecond: 0,
            velocityNorthMetersPerSecond: 0,
            altitudeMeters: 20
        )
        let moving = planner.prefetchedPlans(
            focusEastMeters: 12,
            focusNorthMeters: 2,
            velocityEastMetersPerSecond: 4,
            velocityNorthMetersPerSecond: 0,
            altitudeMeters: 20
        )
        let stationaryFine = stationary.filter { $0.sampleSpacingMeters == 0.125 }
        let movingFine = moving.filter { $0.sampleSpacingMeters == 0.125 }

        #expect(stationaryFine.count == 9)
        #expect(movingFine.count == 15)
        #expect(Set(moving.map(\.id)).count == moving.count)
        #expect(movingFine.first?.id.eastIndex == -1)
        #expect(movingFine.last?.id.eastIndex == 3)

        let movingByID = Dictionary(
            uniqueKeysWithValues: movingFine.map { ($0.id, $0) }
        )
        for plan in movingFine {
            let eastNeighborID = LMTerrainTileID(
                level: plan.id.level,
                eastIndex: plan.id.eastIndex + 1,
                northIndex: plan.id.northIndex
            )
            if let eastNeighbor = movingByID[eastNeighborID] {
                #expect(!plan.transitionEdges.contains(.east))
                #expect(!eastNeighbor.transitionEdges.contains(.west))
            } else {
                #expect(plan.transitionEdges.contains(.east))
            }
        }
    }

    @Test func explorerViewProjectionKeepsAContiguousLandingViewCorridor() {
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: 2)
        let forward = planner.prefetchedPlans(
            focusEastMeters: -4.336,
            focusNorthMeters: 19.619,
            velocityEastMetersPerSecond: 48.0 / 6.0,
            velocityNorthMetersPerSecond: 0,
            altitudeMeters: 2
        )
        let rear = planner.focusedPlans(
            focusEastMeters: -4.336 - 32,
            focusNorthMeters: 19.619,
            altitudeMeters: 2
        )
        let plans = planner.mergedPlans(forward + rear)
        let landing = plans.filter { $0.sampleSpacingMeters == 0.125 }

        #expect(landing.count == 24)
        #expect(Set(landing.map(\.id.eastIndex)) == Set(-4...3))
        #expect(Set(landing.map(\.id.northIndex)) == Set(0...2))
        let byID = Dictionary(uniqueKeysWithValues: landing.map { ($0.id, $0) })
        for plan in landing where plan.id.eastIndex < 3 {
            let east = LMTerrainTileID(
                level: plan.id.level,
                eastIndex: plan.id.eastIndex + 1,
                northIndex: plan.id.northIndex
            )
            #expect(!plan.transitionEdges.contains(.east))
            #expect(!byID[east]!.transitionEdges.contains(.west))
        }
    }

    @Test func coarserResidencyEnclosesFinerFootprintByItsOwnMorphCollar() {
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: 2)
        // The terminal level's outer morph collar hands off to the measured
        // source over this width; the landing footprint must never reach it.
        let terminalCollarMeters = min(64.0 / 4, 2.0 * 8)
        // Foci deliberately include positions right at and just across 64 m
        // tile boundaries, where equal per-level radii used to leave the two
        // footprints ending on the same line.
        let foci: [(east: Double, north: Double)] = [
            (-4.336, 19.619),
            (0.5, 63.5),
            (-64.0, 128.0),
            (31.9, -0.1),
            (-547, 732),
        ]
        for focus in foci {
            let plans = planner.prefetchedPlans(
                focusEastMeters: focus.east,
                focusNorthMeters: focus.north,
                velocityEastMetersPerSecond: 48.0 / 6.0,
                velocityNorthMetersPerSecond: 0,
                altitudeMeters: 2
            )
            let terminal = plans.filter { $0.sampleSpacingMeters == 0.5 }
            func terminalCovers(east: Double, north: Double) -> Bool {
                terminal.contains { plan in
                    abs(east - plan.centerEastMeters) <= plan.sizeMeters / 2
                        && abs(north - plan.centerNorthMeters) <= plan.sizeMeters / 2
                }
            }
            for plan in plans where plan.sampleSpacingMeters == 0.125 {
                let reach = plan.sizeMeters / 2 + terminalCollarMeters
                for (east, north) in [
                    (plan.centerEastMeters - reach, plan.centerNorthMeters - reach),
                    (plan.centerEastMeters - reach, plan.centerNorthMeters + reach),
                    (plan.centerEastMeters + reach, plan.centerNorthMeters - reach),
                    (plan.centerEastMeters + reach, plan.centerNorthMeters + reach),
                    (plan.centerEastMeters - reach, plan.centerNorthMeters),
                    (plan.centerEastMeters + reach, plan.centerNorthMeters),
                    (plan.centerEastMeters, plan.centerNorthMeters - reach),
                    (plan.centerEastMeters, plan.centerNorthMeters + reach),
                ] {
                    #expect(
                        terminalCovers(east: east, north: north),
                        "landing tile \(plan.id) collar point (\(east), \(north)) has no terminal parent at focus \(focus)"
                    )
                }
            }
        }
    }

    @Test func focusedTilesMorphOnlyAtTheResidencyFootprintPerimeter() {
        let plans = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: 2
        ).focusedPlans(
            focusEastMeters: 12,
            focusNorthMeters: 2,
            altitudeMeters: 20
        )
        let byID = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })

        for plan in plans {
            let neighbors: [(LMTerrainTileEdges, LMTerrainTileID)] = [
                (.west, .init(
                    level: plan.id.level,
                    eastIndex: plan.id.eastIndex - 1,
                    northIndex: plan.id.northIndex
                )),
                (.east, .init(
                    level: plan.id.level,
                    eastIndex: plan.id.eastIndex + 1,
                    northIndex: plan.id.northIndex
                )),
                (.south, .init(
                    level: plan.id.level,
                    eastIndex: plan.id.eastIndex,
                    northIndex: plan.id.northIndex - 1
                )),
                (.north, .init(
                    level: plan.id.level,
                    eastIndex: plan.id.eastIndex,
                    northIndex: plan.id.northIndex + 1
                )),
            ]
            for (edge, neighborID) in neighbors {
                #expect(plan.transitionEdges.contains(edge) == (byID[neighborID] == nil))
            }
        }
    }

    @Test func focusedFootprintChangesOnlyWhenItsSafetyBoundaryIsCrossed() {
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: 2)
        let first = planner.focusedPlans(
            focusEastMeters: 31,
            focusNorthMeters: 31,
            altitudeMeters: 100
        )
        let same = planner.focusedPlans(
            focusEastMeters: 40,
            focusNorthMeters: 40,
            altitudeMeters: 100
        )
        let crossed = planner.focusedPlans(
            focusEastMeters: 49,
            focusNorthMeters: 49,
            altitudeMeters: 100
        )

        #expect(first.count == 1)
        #expect(first.map(\.id) == same.map(\.id))
        #expect(crossed.count == 4)
        #expect(Set(first.map(\.id)) != Set(crossed.map(\.id)))
    }

    @Test func eagleLandingFootprintStaysInsideResidentFineTiles() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let frame = try LMTerrainFrameAlignment(manifest: LMTerrainManifest.load())
        let eagle = frame.terrainReferenceTouchdown
        let plans = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: field.spacingMeters
        ).focusedPlans(
            focusEastMeters: eagle.y,
            focusNorthMeters: eagle.x,
            altitudeMeters: 20
        )
        let terminal = plans.filter { $0.sampleSpacingMeters == 0.5 }
        let landing = plans.filter { $0.sampleSpacingMeters == 0.125 }

        // Four terminal tiles: the parent level now encloses the landing
        // footprint by its own 16 m morph collar instead of ending on
        // whatever 64 m line quantization happened to pick. The landing
        // level keeps the same bounded 3x3 safety set as every other
        // off-center 16 m focus.
        #expect(terminal.count == 4)
        #expect(landing.count == 9)
        for northOffset in [-7.0, 0, 7.0] {
            for eastOffset in [-7.0, 0, 7.0] {
                #expect(landing.contains {
                    let half = $0.sizeMeters / 2
                    return eagle.y + eastOffset >= $0.centerEastMeters - half
                        && eagle.y + eastOffset <= $0.centerEastMeters + half
                        && eagle.x + northOffset >= $0.centerNorthMeters - half
                        && eagle.x + northOffset <= $0.centerNorthMeters + half
                })
            }
        }
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

@Suite("Terrain-relative landing")
struct TerrainRelativeLandingTests {
    private func heightField() throws -> Apollo11TerrainHeightField {
        try Apollo11TerrainResource.loadSourceBackedHeightField()
    }

    private func alignment() throws -> LMTerrainFrameAlignment {
        try LMTerrainFrameAlignment(manifest: LMTerrainManifest.load())
    }

    private func contactSurface(
        activePlans: [LMTerrainTilePlan] = [],
        altitudeMeters: Double = 20
    ) throws -> LMTerrainContactSurface {
        let field = try heightField()
        let frame = try alignment()
        return try LMTerrainContactSurfaceBuilder.build(
            heightField: field,
            alignment: frame,
            activePlans: activePlans,
            altitudeMeters: altitudeMeters,
            centerTerrainEastMeters: frame.terrainReferenceTouchdown.y,
            centerTerrainNorthMeters: frame.terrainReferenceTouchdown.x
        )
    }

    @Test func contactSurfaceIsZeroAtTheNominalTouchdownPoint() throws {
        let frame = try alignment()
        let surface = try contactSurface()
        let nominal = LMTerrainFrameAlignment.nominalP66GuidanceTouchdown
        let height = surface.surfaceHeightMeters(
            northMeters: nominal.x,
            eastMeters: nominal.y
        )
        // Referencing heights to the terrain under Eagle is what keeps the
        // bundled trajectories landing at guidance altitude zero.
        #expect(abs(height) < 0.02)
        #expect(surface.referenceElevationMeters != 0)
        _ = frame
    }

    @Test func contactSurfaceReproducesMeasuredReliefAwayFromTheDatum() throws {
        let field = try heightField()
        let frame = try alignment()
        let surface = try contactSurface()
        let nominal = LMTerrainFrameAlignment.nominalP66GuidanceTouchdown

        // Sample a few meters away and compare against the measured height
        // field read directly, in terrain coordinates.
        for offset in [-12.0, -5.0, 5.0, 12.0] {
            let north = nominal.x + offset
            let terrain = frame.terrainPosition(
                from: LMVector3D(x: north, y: nominal.y, z: 0)
            )
            let measured = try #require(field.relativeElevation(
                eastMeters: terrain.y,
                northMeters: terrain.x
            ))
            let expected = Double(measured - surface.referenceElevationMeters)
            let actual = surface.surfaceHeightMeters(
                northMeters: north,
                eastMeters: nominal.y
            )
            // With no procedural plans active the patch is pure measured relief.
            #expect(abs(actual - expected) < 0.02)
        }
    }

    @Test func proceduralCraterReliefReachesTheContactSurface() throws {
        let field = try heightField()
        let frame = try alignment()
        let eagle = frame.terrainReferenceTouchdown
        let landingPlan = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: field.spacingMeters
        ).focusedPlans(
            focusEastMeters: eagle.y,
            focusNorthMeters: eagle.x,
            altitudeMeters: 20
        )
        #expect(!landingPlan.isEmpty)

        let measuredOnly = try contactSurface()
        let withProcedural = try contactSurface(activePlans: landingPlan)
        let nominal = LMTerrainFrameAlignment.nominalP66GuidanceTouchdown

        var maximumDifference = 0.0
        for northOffset in stride(from: -6.0, through: 6.0, by: 0.25) {
            for eastOffset in stride(from: -6.0, through: 6.0, by: 0.25) {
                let north = nominal.x + northOffset
                let east = nominal.y + eastOffset
                let difference = abs(
                    withProcedural.surfaceHeightMeters(northMeters: north, eastMeters: east)
                        - measuredOnly.surfaceHeightMeters(northMeters: north, eastMeters: east)
                )
                maximumDifference = max(maximumDifference, difference)
            }
        }
        // Sub-resolution morphology is visible to the gear but stays inside the
        // bounded residual the geology model is allowed to add.
        #expect(maximumDifference > 0.01)
        #expect(maximumDifference < 0.30)
    }

    @Test func contactSurfaceSlopeIsRealisticForTheMareSite() throws {
        let surface = try contactSurface()
        let nominal = LMTerrainFrameAlignment.nominalP66GuidanceTouchdown
        let normal = surface.surfaceNormal(
            northMeters: nominal.x,
            eastMeters: nominal.y
        )
        let slopeDegrees = acos(min(max(normal.z, -1), 1)) * 180 / .pi
        #expect(slopeDegrees >= 0)
        #expect(slopeDegrees < LMLandingGearGeometry.criticalTiltRadians * 180 / .pi)
    }

    @Test func gearSettlesOnRealTerrainWithoutFloatingOrSinking() throws {
        let surface = try contactSurface()
        let nominal = LMTerrainFrameAlignment.nominalP66GuidanceTouchdown
        let mass = LMLandingGearGeometry.designTouchdownMassKilograms
        let gravity = LMVehicleConfiguration.sourceBackedDefault
            .lunarGravityMetersPerSecondSquared.value
        let inertia = LMInertiaMap.diagonalInertiaKilogramMetersSquared(massKilograms: mass)

        // The reference point is the uncompressed footpad plane, so this is a
        // vehicle a few centimeters above the ground at a nominal descent rate.
        var position = LMVector3D(x: nominal.x, y: nominal.y, z: 0.05)
        var velocity = LMVector3D(z: -0.5)
        var attitude = LMQuaternion.identity
        var angularVelocity = LMVector3D.zero
        var gear = LMLandingGearState()
        var settled = false

        for _ in 0..<1_800 {
            let result = LMLandingGearDynamics.integrate(
                positionMeters: position,
                velocityMetersPerSecond: velocity,
                attitude: attitude,
                angularVelocityRadiansPerSecond: angularVelocity,
                massKilograms: mass,
                inertiaKilogramMetersSquared: inertia,
                accelerationMetersPerSecondSquared: LMVector3D(z: -gravity),
                angularAccelerationRadiansPerSecondSquared: .zero,
                gear: gear,
                surface: surface,
                deltaTime: 1.0 / 60.0
            )
            position = result.positionMeters
            velocity = result.velocityMetersPerSecond
            attitude = result.attitude
            angularVelocity = result.angularVelocityRadiansPerSecond
            gear = result.gear
            if result.isSettled { settled = true; break }
        }

        #expect(settled)
        #expect(gear.failure == nil)

        // Real LROC relief across the 9.4 m gear span means the vehicle does not
        // arrive on a plane. Some pads carry it, others end up clear of the
        // ground, and none of them passes through the surface.
        var loaded = 0
        var clear = 0
        for leg in LMLandingGearLeg.allCases {
            let snapshot = try #require(gear.snapshot(leg))
            let pad = LMLandingGearGeometry.footpadBody(
                leg,
                strokeMeters: snapshot.strokeMeters
            )
            let world = position + attitude.rotated(pad)
            let ground = surface.surfaceHeightMeters(
                northMeters: world.x,
                eastMeters: world.y
            )
            let clearance = world.z - ground
            if snapshot.isInContact {
                loaded += 1
                // A loaded pad is sitting in the print it pushed into the soil.
                #expect(clearance < 0)
                #expect(
                    clearance
                        >= -(snapshot.regolithPenetrationMeters
                            + LMLandingGearDynamics.regolithBearingLoadNewtons
                            / LMLandingGearDynamics.padStiffnessNewtonsPerMeter
                            + 0.01)
                )
            } else {
                clear += 1
            }
            // Nothing hangs implausibly far off the ground it landed on.
            #expect(clearance < 0.5)
        }
        #expect(loaded >= 2)
        #expect(loaded + clear == LMLandingGearLeg.allCases.count)

        // Resting attitude follows the terrain instead of staying artificially
        // level, but the mare under Eagle is nowhere near the tip-over limit.
        let localUp = surface.surfaceNormal(
            northMeters: position.x,
            eastMeters: position.y
        )
        let tilt = LMLandingGearDynamics.tiltRadians(attitude: attitude, localUp: localUp)
        #expect(tilt < LMLandingGearGeometry.criticalTiltRadians / 2)

        let levelTilt = LMLandingGearDynamics.tiltRadians(
            attitude: .identity,
            localUp: LMVector3D(z: 1)
        )
        let settledTilt = LMLandingGearDynamics.tiltRadians(
            attitude: attitude,
            localUp: LMVector3D(z: 1)
        )
        #expect(settledTilt > levelTilt)
    }
}

@Suite("Terrain detail textures")
struct TerrainDetailTextureTests {
    @Test func jointMicrotextureSamplingMatchesIndependentChannels() {
        let microtexture = LMRegolithMicrotextureModel()
        let craterlets = microtexture.craterletField(
            eastMetersRange: -2...3,
            northMetersRange: -3...2
        )
        let samples = [
            SIMD2<Double>(-1.75, -2.25),
            SIMD2<Double>(-0.13, 0.27),
            SIMD2<Double>(0, 0),
            SIMD2<Double>(1.43, -1.17),
            SIMD2<Double>(2.81, 1.64),
        ]

        for sampleSpacing in [0, 0.03125, 0.125, 0.5] {
            for sample in samples {
                let combined = microtexture.appearanceSample(
                    eastMeters: sample.x,
                    northMeters: sample.y,
                    sampleSpacingMeters: sampleSpacing,
                    craterlets: craterlets
                )
                let relief = microtexture.reliefMeters(
                    eastMeters: sample.x,
                    northMeters: sample.y,
                    sampleSpacingMeters: sampleSpacing,
                    craterlets: craterlets
                )
                let reflectance = microtexture.reflectanceModulation(
                    eastMeters: sample.x,
                    northMeters: sample.y,
                    sampleSpacingMeters: sampleSpacing,
                    craterlets: craterlets
                )
                #expect(combined.reliefMeters == relief)
                #expect(combined.reflectanceModulation == reflectance)
            }
        }
    }

    @Test func microtextureSuppressesFeaturesBelowTheTexelFootprint() {
        let microtexture = LMRegolithMicrotextureModel()
        var fineReliefEnergy = 0.0
        var coarseReliefEnergy = 0.0
        var fineReflectanceEnergy = 0.0
        var coarseReflectanceEnergy = 0.0

        for northIndex in 0..<24 {
            for eastIndex in 0..<24 {
                let east = 1.25 + Double(eastIndex) * 0.037
                let north = -2.5 + Double(northIndex) * 0.041
                let fine = microtexture.appearanceSample(
                    eastMeters: east,
                    northMeters: north,
                    sampleSpacingMeters: 0.03125
                )
                let coarse = microtexture.appearanceSample(
                    eastMeters: east,
                    northMeters: north,
                    sampleSpacingMeters: 0.5
                )
                fineReliefEnergy += fine.reliefMeters * fine.reliefMeters
                coarseReliefEnergy += coarse.reliefMeters * coarse.reliefMeters
                let fineReflectance = fine.reflectanceModulation - 1
                let coarseReflectance = coarse.reflectanceModulation - 1
                fineReflectanceEnergy += fineReflectance * fineReflectance
                coarseReflectanceEnergy += coarseReflectance * coarseReflectance
            }
        }

        #expect(fineReliefEnergy > 0)
        #expect(fineReflectanceEnergy > 0)
        #expect(coarseReliefEnergy < fineReliefEnergy * 0.01)
        #expect(coarseReflectanceEnergy < fineReflectanceEnergy * 0.01)
    }

    private func landingPlan() throws -> LMTerrainTilePlan {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let frame = try LMTerrainFrameAlignment(manifest: LMTerrainManifest.load())
        let eagle = frame.terrainReferenceTouchdown
        let plans = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: field.spacingMeters
        ).focusedPlans(
            focusEastMeters: eagle.y,
            focusNorthMeters: eagle.x,
            altitudeMeters: 20
        )
        return try #require(plans.min { $0.sampleSpacingMeters < $1.sampleSpacingMeters })
    }

    @Test func measuredAlbedoIsLoadedAtHalfMeterResolution() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let albedo = try LMMeasuredAlbedoField.load(tile: field.tile)
        #expect(albedo.width == 4_097)
        #expect(albedo.height == 4_097)
        let reflectance = try #require(albedo.reflectance(eastMeters: 0, northMeters: 0))
        #expect(reflectance > 0)
        #expect(reflectance < 1)
        #expect(albedo.reflectance(eastMeters: 5_000, northMeters: 0) == nil)
    }

    @Test func bakedDetailIsFinerThanBothTheMeshAndTheSourceTexture() throws {
        let plan = try landingPlan()
        let texelSpacing = plan.sizeMeters
            / Double(LMTerrainTileDetailBaker.resolution - 1)
        // Finer than the 0.125 m triangles and far finer than 0.5 m NAC texels.
        #expect(texelSpacing < plan.sampleSpacingMeters)
        #expect(texelSpacing < 0.5)
    }

    @Test func appearanceHandoffTargetsTheRenderedParentFrequency() {
        let landing = LMTerrainTilePlan(
            id: .init(level: 1, eastIndex: 0, northIndex: 0),
            centerEastMeters: 8,
            centerNorthMeters: 8,
            sizeMeters: 16,
            sampleSpacingMeters: 0.125,
            containsProceduralSubresolution: true
        )
        let terminal = LMTerrainTilePlan(
            id: .init(level: 0, eastIndex: 0, northIndex: 0),
            centerEastMeters: 32,
            centerNorthMeters: 32,
            sizeMeters: 64,
            sampleSpacingMeters: 0.5,
            containsProceduralSubresolution: true
        )
        let landingTexelSpacing = landing.sizeMeters
            / Double(LMTerrainTileDetailBaker.resolution - 1)
        let terminalTexelSpacing = terminal.sizeMeters
            / Double(LMTerrainTileDetailBaker.resolution - 1)

        #expect(abs(
            LMTerrainTileDetailBaker.parentAppearanceSampleSpacingMeters(
                plan: landing,
                texelSpacingMeters: landingTexelSpacing
            )! - terminalTexelSpacing
        ) < 1e-12)
        #expect(LMTerrainTileDetailBaker.parentAppearanceSampleSpacingMeters(
            plan: terminal,
            texelSpacingMeters: terminalTexelSpacing
        ) == nil)
    }

    @Test func bakedNormalDistributionCanBeReusedForAnySunDirection() throws {
        let detail = try LMTerrainTileDetailBaker.bake(
            plan: landingPlan(),
            albedoField: nil,
            resolution: 64
        )
        let distribution = detail.normalDistribution
        let overhead = distribution.meanLambertianResponse(
            sunDirectionTangentSpace: SIMD3<Float>(0, 0, 1)
        )
        let grazingEast = distribution.meanLambertianResponse(
            sunDirectionTangentSpace: simd_normalize(SIMD3<Float>(1, 0, 0.2))
        )

        #expect(distribution.sampleCount == 64 * 64)
        #expect(distribution.counts.reduce(0) { $0 + Int($1) } == 64 * 64)
        #expect(overhead > 0.9)
        #expect(grazingEast > 0)
        #expect(grazingEast < overhead)
    }

    @Test func touchdownReliefStatisticsDoNotRequireAnLODGain() throws {
        let plan = try landingPlan()
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let mesh = try #require(
            try Apollo11TerrainResource.makeProgressiveTileMeshData(
                heightField: field,
                plan: plan,
                activePlans: [plan]
            )
        )
        let detail = try LMTerrainTileDetailBaker.bake(
            plan: plan,
            albedoField: nil,
            resolution: LMTerrainTileDetailBaker.resolution
        )
        let manifest = try LMTerrainManifest.load()
        let elevation = Float(manifest.sun.elevationDegrees * .pi / 180)
        let azimuth = Float(
            manifest.sun.azimuthDegreesClockwiseFromNorth * .pi / 180
        )
        let horizontal = cos(elevation)
        let tangentSun = simd_normalize(SIMD3<Float>(
            horizontal * sin(azimuth),
            -horizontal * cos(azimuth),
            sin(elevation)
        ))
        let flatResponse = tangentSun.z
        let detailResponse = detail.normalDistribution
            .meanLambertianResponse(sunDirectionTangentSpace: tangentSun)
        let meshResponse = mesh.addedReliefNormalDistribution
            .meanLambertianResponse(sunDirectionTangentSpace: tangentSun)
        let combinedRatio = (detailResponse / flatResponse)
            * (meshResponse / flatResponse)

        // The old B1 hypothesis predicted a 5-6% mean loss. The current,
        // hierarchy-corrected tile is neutral to 0.03%, so a material gain
        // would manufacture a new LOD step instead of removing one.
        #expect(abs(combinedRatio - 1) < 0.005)
    }

    @Test func renderingGutterKeepsSamplingInsideRepeatedBoundaryTexels() {
        let resolution = LMTerrainTileDetailBaker.resolution
        var albedo = [UInt8](repeating: 0, count: resolution * resolution * 4)
        var normal = [UInt8](repeating: 0, count: resolution * resolution * 4)

        func setPixel(
            _ bytes: inout [UInt8],
            column: Int,
            row: Int,
            value: (UInt8, UInt8, UInt8, UInt8)
        ) {
            let offset = (row * resolution + column) * 4
            bytes[offset] = value.0
            bytes[offset + 1] = value.1
            bytes[offset + 2] = value.2
            bytes[offset + 3] = value.3
        }

        setPixel(&albedo, column: 0, row: 0, value: (11, 12, 13, 14))
        setPixel(
            &albedo,
            column: resolution - 1,
            row: resolution - 1,
            value: (21, 22, 23, 24)
        )
        setPixel(&normal, column: 0, row: 0, value: (31, 32, 33, 34))
        setPixel(
            &normal,
            column: resolution - 1,
            row: resolution - 1,
            value: (41, 42, 43, 44)
        )

        let padded = LMTerrainTileDetailBaker.addingSamplingGutter(
            to: LMTerrainTileDetailTextures(
                resolution: resolution,
                albedo: albedo,
                normal: normal
            )
        )
        let gutter = LMTerrainTileDetailBaker.samplingGutterTexels
        let renderingResolution = LMTerrainTileDetailBaker.renderingResolution

        func pixel(_ bytes: [UInt8], column: Int, row: Int) -> [UInt8] {
            let offset = (row * renderingResolution + column) * 4
            return Array(bytes[offset..<(offset + 4)])
        }

        #expect(padded.resolution == renderingResolution)
        #expect(padded.normalDistribution == .flat)
        #expect(pixel(padded.albedo, column: 0, row: 0) == [11, 12, 13, 14])
        #expect(pixel(padded.albedo, column: gutter, row: gutter) == [11, 12, 13, 14])
        #expect(pixel(padded.normal, column: 0, row: 0) == [31, 32, 33, 34])
        #expect(pixel(padded.normal, column: gutter, row: gutter) == [31, 32, 33, 34])
        #expect(pixel(
            padded.albedo,
            column: renderingResolution - 1,
            row: renderingResolution - 1
        ) == [21, 22, 23, 24])
        #expect(pixel(
            padded.normal,
            column: renderingResolution - 1,
            row: renderingResolution - 1
        ) == [41, 42, 43, 44])

        let minimumUV = LMTerrainTileDetailBaker.renderingTextureCoordinate(
            contentFraction: 0
        )
        let maximumUV = LMTerrainTileDetailBaker.renderingTextureCoordinate(
            contentFraction: 1
        )
        #expect(minimumUV > 0)
        #expect(maximumUV < 1)
        #expect(abs(
            minimumUV * Float(renderingResolution - 1) - Float(gutter)
        ) < 0.0001)
        #expect(abs(
            maximumUV * Float(renderingResolution - 1)
                - Float(gutter + resolution - 1)
        ) < 0.0001)
    }

    @Test func bakedNormalsAreUnitLengthAndFadeFlatAtTheTileEdge() throws {
        let plan = try landingPlan()
        // Bake near the shipping density: at 0.25 m texels the centimetre-scale
        // microtexture aliases away and the test would measure nothing.
        let resolution = 256
        let detail = try LMTerrainTileDetailBaker.bake(
            plan: plan,
            albedoField: nil,
            resolution: resolution
        )
        #expect(detail.resolution == resolution)
        #expect(detail.normal.count == resolution * resolution * 4)

        func normal(column: Int, row: Int) -> SIMD3<Float> {
            let offset = (row * resolution + column) * 4
            return SIMD3(
                Float(detail.normal[offset]) / 255 * 2 - 1,
                Float(detail.normal[offset + 1]) / 255 * 2 - 1,
                Float(detail.normal[offset + 2]) / 255 * 2 - 1
            )
        }

        for row in stride(from: 0, to: resolution, by: 7) {
            for column in stride(from: 0, to: resolution, by: 7) {
                let length = simd_length(normal(column: column, row: row))
                #expect(abs(length - 1) < 0.02)
            }
        }

        // The outer collar hands off to the coarser parent surface, so the
        // baked detail has to vanish there rather than end on a hard seam.
        let corner = normal(column: 0, row: 0)
        #expect(abs(corner.x) < 0.01)
        #expect(abs(corner.y) < 0.01)
        #expect(corner.z > 0.99)

        let interior = (0..<resolution).flatMap { row in
            (0..<resolution).map { column in
                simd_length(SIMD2(normal(column: column, row: row).x,
                                  normal(column: column, row: row).y))
            }
        }.max() ?? 0
        #expect(interior > 0.05)
    }

    @Test func adjacentProceduralTexturesMatchExactlyAtTheirSharedWorldEdge() throws {
        let resolution = 64
        let west = LMTerrainTilePlan(
            id: .init(level: 1, eastIndex: 0, northIndex: 0),
            centerEastMeters: 8,
            centerNorthMeters: 8,
            sizeMeters: 16,
            sampleSpacingMeters: 0.125,
            containsProceduralSubresolution: true,
            transitionEdges: [.west, .south, .north]
        )
        let east = LMTerrainTilePlan(
            id: .init(level: 1, eastIndex: 1, northIndex: 0),
            centerEastMeters: 24,
            centerNorthMeters: 8,
            sizeMeters: 16,
            sampleSpacingMeters: 0.125,
            containsProceduralSubresolution: true,
            transitionEdges: [.east, .south, .north]
        )
        let westDetail = try LMTerrainTileDetailBaker.bake(
            plan: west,
            albedoField: nil,
            resolution: resolution
        )
        let eastDetail = try LMTerrainTileDetailBaker.bake(
            plan: east,
            albedoField: nil,
            resolution: resolution
        )

        for row in 0..<resolution {
            let westOffset = (row * resolution + resolution - 1) * 4
            let eastOffset = row * resolution * 4
            #expect(westDetail.albedo[westOffset..<(westOffset + 4)]
                .elementsEqual(eastDetail.albedo[eastOffset..<(eastOffset + 4)]))
            #expect(westDetail.normal[westOffset..<(westOffset + 4)]
                .elementsEqual(eastDetail.normal[eastOffset..<(eastOffset + 4)]))
        }
    }

    @Test func bakedAlbedoTracksMeasuredReflectanceWithBoundedContrast() throws {
        let plan = try landingPlan()
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let albedoField = try LMMeasuredAlbedoField.load(tile: field.tile)
        let detail = try LMTerrainTileDetailBaker.bake(
            plan: plan,
            albedoField: albedoField,
            resolution: 64
        )

        let measured = try #require(albedoField.reflectance(
            eastMeters: plan.centerEastMeters,
            northMeters: plan.centerNorthMeters
        ))
        var minimum = 1.0
        var maximum = 0.0
        for index in stride(from: 0, to: detail.albedo.count, by: 4) {
            let value = Double(detail.albedo[index]) / 255
            minimum = min(minimum, value)
            maximum = max(maximum, value)
        }
        // Procedural contrast modulates the measured reflectance; it never
        // replaces it, so the baked range brackets the source value.
        #expect(minimum < Double(measured))
        #expect(maximum > Double(measured))
        #expect(minimum > Double(measured) * 0.7)
        // Byte quantization plus sampling the exact tile boundary can exceed
        // the nominal 1.35 modulation by one output step.
        #expect(maximum < Double(measured) * 1.4)
    }

    @Test func microtextureNeverReachesTheGeometryOrContactSurface() throws {
        let microtexture = LMRegolithMicrotextureModel()
        var maximumRelief = 0.0
        for north in stride(from: 0.0, through: 4.0, by: 0.03) {
            for east in stride(from: 0.0, through: 4.0, by: 0.03) {
                maximumRelief = max(
                    maximumRelief,
                    abs(microtexture.reliefMeters(eastMeters: east, northMeters: north))
                )
            }
        }
        #expect(maximumRelief > 0.001)
        #expect(maximumRelief <= LMRegolithMicrotextureModel.maximumReliefMeters + 1e-9)

        // The height field the gear touches is built from the geology model
        // alone, so appearance micro-relief can never move a footpad.
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let sampler = LMProgressiveTerrainSurfaceSampler(heightField: field)
        let sample = try #require(sampler.sample(
            eastMeters: 3,
            northMeters: 3,
            altitudeMeters: 20,
            activePlans: []
        ))
        #expect(sample.renderedElevationMeters == sample.measuredElevationMeters)
    }

    @Test func craterFieldMemoizationDoesNotChangeTheSurface() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let plan = try landingPlan()
        let plain = LMProgressiveTerrainSurfaceSampler(heightField: field)
        let prepared = plain.prepared(for: plan)
        let step = plan.sizeMeters / 32

        for row in 0...32 {
            let north = plan.centerNorthMeters - plan.sizeMeters / 2 + Double(row) * step
            for column in 0...32 {
                let east = plan.centerEastMeters - plan.sizeMeters / 2 + Double(column) * step
                let a = plain.renderedElevation(
                    eastMeters: east,
                    northMeters: north,
                    plan: plan
                )
                let b = prepared.renderedElevation(
                    eastMeters: east,
                    northMeters: north,
                    plan: plan
                )
                #expect(a == b)
            }
        }
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
