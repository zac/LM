import Foundation
import Testing
import simd
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

    @Test func fdaiBallCounterRotatesAgainstVehicleAttitude() {
        let angle = Float(30.0 * .pi / 180.0)
        let attitude = LMQuaternion.fromAxisAngle(
            axis: LMVector3D(x: 1),
            radians: Double(angle)
        )
        let neutral = FDAIOrientation.ballOrientation(for: .identity)
        let rotated = FDAIOrientation.ballOrientation(for: attitude)
        let relative = simd_normalize(rotated * neutral.inverse)
        let movedUp = relative.act(SIMD3<Float>(0, 1, 0))

        #expect(abs(movedUp.x) < 1e-5)
        #expect(abs(movedUp.y - cos(angle)) < 1e-5)
        #expect(abs(movedUp.z + sin(angle)) < 1e-5)
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

    @Test func fdaiStartsAtItsPoweredDescentInertialReference() {
        let pdi = FDAIOrientation.poweredDescentReferenceAttitude
        let orientation = FDAIOrientation.ballOrientation(for: pdi, relativeTo: pdi)
        let redPole = orientation.act(SIMD3<Float>(0, 1, 0))
        let gimbals = FDAIOrientation.nasaGimbalDegrees(for: pdi, relativeTo: pdi)

        #expect(abs(redPole.x) < 1e-5)
        #expect(abs(redPole.y - 1) < 1e-5)
        #expect(abs(redPole.z) < 1e-5)
        #expect(abs(gimbals.p) < 1e-5)
        #expect(abs(gimbals.q) < 1e-5)
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
}

extension Int {
    /// ±57-count ACA mechanical stops.
    fileprivate var clampedToMechanicalStops: Int {
        Swift.min(Swift.max(self, -LMACAInputMapper.mechanicalClampCounts), LMACAInputMapper.mechanicalClampCounts)
    }
}

/// Live checkpoint-resumed flight against the bundled P65 fixture.
@Suite("P65 checkpoint session", .serialized)
struct P65CheckpointSessionTests {
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
}

@Suite("Apollo 11 terrain assets")
struct Apollo11TerrainAssetTests {
    @Test func manifestPinsTheOfficialLROCProductAndApollo11Site() throws {
        let manifest = try Apollo11TerrainResource.loadManifest()

        #expect(manifest.productID == "NAC_DTM_APOLLO11")
        #expect(manifest.sourceDTMSHA256 == "920da622e3d7c3f047c67a970b5429aaadf00f886804e3fc6c72f6e5298043e9")
        #expect(manifest.sourceHillshadeSHA256 == "a47fbe33a371fb0a5a823f1af6729888fa8bc9e0614a9acb3bd4784b29a974e3")
        #expect(abs(manifest.landingLatitudeDegrees - 0.67409) < 1e-8)
        #expect(abs(manifest.landingLongitudeDegrees - 23.47298) < 1e-8)
        #expect(manifest.cropSizePixels == 1_025)
    }

    @Test func heightmapMatchesManifestAndIsCenteredOnTheLandingPost() throws {
        let manifest = try Apollo11TerrainResource.loadManifest()
        let heights = try Apollo11TerrainResource.loadHeights(manifest: manifest)

        #expect(heights.count == manifest.meshWidth * manifest.meshHeight)
        #expect(manifest.meshWidth == 257)
        #expect(manifest.meshHeight == 257)
        #expect(abs(manifest.meshSpacingMeters - 8) < 1e-6)
        let center = heights[(manifest.meshHeight / 2) * manifest.meshWidth + manifest.meshWidth / 2]
        #expect(abs(center) < 1e-6)
        let allFinite = heights.allSatisfy { $0.isFinite }
        #expect(allFinite)
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
        let visual = mapper.visualACATranslation(for: input)
        #expect(abs(visual.x - mapper.acaTravelMeters) < 1e-6)
        #expect(abs(visual.y + mapper.acaTravelMeters * 0.5) < 1e-6)
        #expect(abs(visual.z + mapper.acaTravelMeters * 0.75) < 1e-6)
    }

    @Test func rodUsesSpringLoadedDetentsAroundNeutral() {
        #expect(mapper.rodPosition(for: 0) == .neutral)
        #expect(mapper.rodPosition(for: mapper.rodTravelMeters * 0.2) == .neutral)
        #expect(mapper.rodPosition(for: mapper.rodTravelMeters * 0.5) == .descendPlus)
        #expect(mapper.rodPosition(for: mapper.rodTravelMeters * -0.5) == .descendMinus)
        #expect(mapper.visualRODTranslation(for: .neutral) == 0)
    }
}
