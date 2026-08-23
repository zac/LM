import Foundation
import RealityKit
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

@Suite("Apollo 11 terrain assets")
struct Apollo11TerrainAssetTests {
    @Test func manifestPinsTheOfficialLROCProductAndApollo11Site() throws {
        let manifest = try Apollo11TerrainResource.loadManifest()

        #expect(manifest.productID == "NAC_DTM_APOLLO11")
        #expect(manifest.sourceDTMSHA256 == "920da622e3d7c3f047c67a970b5429aaadf00f886804e3fc6c72f6e5298043e9")
        #expect(manifest.sourceHillshadeSHA256 == "a47fbe33a371fb0a5a823f1af6729888fa8bc9e0614a9acb3bd4784b29a974e3")
        #expect(abs(manifest.landingLatitudeDegrees - 0.67409) < 1e-8)
        #expect(abs(manifest.landingLongitudeDegrees - 23.47298) < 1e-8)
        #expect(manifest.schemaVersion == 2)
        #expect(manifest.cropWidthPixels == 1_025)
        #expect(manifest.cropHeightPixels == 2_049)
    }

    @Test func heightmapMatchesManifestAndIsCenteredOnTheLandingPost() throws {
        let manifest = try Apollo11TerrainResource.loadManifest()
        let heights = try Apollo11TerrainResource.loadHeights(manifest: manifest)

        #expect(heights.count == manifest.meshWidth * manifest.meshHeight)
        #expect(manifest.meshWidth == 257)
        #expect(manifest.meshHeight == 513)
        #expect(abs(manifest.meshSpacingMeters - 8) < 1e-6)
        let center = heights[(manifest.meshHeight / 2) * manifest.meshWidth + manifest.meshWidth / 2]
        #expect(abs(center) < 1e-6)
        let allFinite = heights.allSatisfy { $0.isFinite }
        #expect(allFinite)

        let field = Apollo11TerrainHeightField(manifest: manifest, heights: heights)
        #expect(abs(try #require(field.relativeElevation(eastMeters: 0, northMeters: 0))) < 1e-6)
        #expect(field.relativeElevation(eastMeters: -547, northMeters: 732) != nil)
    }
}

@Suite("Progressive lunar terrain")
struct ProgressiveLunarTerrainTests {
    @Test func measuredPostsRemainExactAndProceduralDetailIsBounded() throws {
        let field = try Apollo11TerrainResource.loadHeightField()
        let sampler = LMProgressiveTerrainSampler(heightField: field)

        let measuredPost = try #require(sampler.sample(
            eastMeters: 0,
            northMeters: 0,
            requestedSpacingMeters: 0.5
        ))
        #expect(abs(measuredPost.proceduralResidualMeters) < 1e-7)
        #expect(measuredPost.elevationMeters == measuredPost.measuredElevationMeters)
        #expect(measuredPost.provenance == .measuredWithProceduralSubresolution)

        let subPost = try #require(sampler.sample(
            eastMeters: 3.25,
            northMeters: 2.75,
            requestedSpacingMeters: 0.5
        ))
        #expect(abs(subPost.proceduralResidualMeters) <= sampler.maximumResidualMeters)
        #expect(abs(subPost.proceduralResidualMeters) > 1e-7)
        #expect(abs(
            subPost.elevationMeters
                - subPost.measuredElevationMeters
                - subPost.proceduralResidualMeters
        ) < 1e-6)
    }

    @Test func proceduralResidualIsDeterministicAndNeverFillsUnknownCoverage() throws {
        let field = try Apollo11TerrainResource.loadHeightField()
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
        let field = try Apollo11TerrainResource.loadHeightField()
        let sample = try #require(LMProgressiveTerrainSampler(heightField: field).sample(
            eastMeters: 11,
            northMeters: 17,
            requestedSpacingMeters: field.manifest.meshSpacingMeters
        ))

        #expect(sample.provenance == .measuredInterpolated)
        #expect(sample.proceduralResidualMeters == 0)
    }

    @Test func tileIDsStayStableUntilTheFocusCrossesATileBoundary() throws {
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: 8)
        let first = planner.plan(focusEastMeters: -547, focusNorthMeters: 732)
        let sameTile = planner.plan(focusEastMeters: -546.5, focusNorthMeters: 732.5)
        let crossed = planner.plan(focusEastMeters: -511.5, focusNorthMeters: 732.5)

        #expect(first.map(\.id) == sameTile.map(\.id))
        #expect(first.map(\.id) != crossed.map(\.id))
        #expect(first.contains { $0.containsProceduralSubresolution })
        #expect(first.contains { !$0.containsProceduralSubresolution })
        #expect(Set(first.map(\.id)).count == first.count)
    }
}

@Suite("Landing Point Designator")
struct LandingPointDesignatorTests {
    let lpd = LMLandingPointDesignator()

    @Test func dualPaneMarksCollimateAtTheCommanderEye() {
        for angle in [0.0, 10, 30, 47, 60] {
            #expect(lpd.alignmentErrorRadians(
                eyeMeters: lpd.commanderEyeMeters,
                elevationDegrees: angle
            ) < 0.0005)
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
        #expect(LMLandingPointDesignator.elevationDegrees == Array(0...60))
        #expect(LMLandingPointDesignator.azimuthDegrees == Array(-10...10))
        #expect(LMLandingPointDesignator.horizontalScaleElevations == [0, 50])
        #expect(LMLandingPointDesignator.apollo11InPlaneRedesignationDegrees == 0.5)
        #expect(LMLandingPointDesignator.apollo11CrossRangeRedesignationDegrees == 2)
    }
}

@Suite("Artist cockpit asset contract")
struct ArtistCockpitAssetContractTests {
    @Test @MainActor func completeIdentityScaledAssetPassesValidation() {
        let root = Entity()
        for node in LMCockpitAssetContract.Node.allCases {
            let entity = Entity()
            entity.name = node.rawValue
            root.addChild(entity)
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

@Suite("Cockpit experience events")
struct CockpitExperienceEventTests {
    @Test func phaseAndAltitudeCalloutsFireOnlyAtTheirRealGates() {
        var director = LMCockpitExperienceDirector()

        let p65 = director.consume(
            program: 65,
            altitudeMeters: 43.8,
            outcome: .inFlight,
            hasSurfaceContact: false
        )
        #expect(p65.map(\.id) == [.p65])

        let oneHundred = director.consume(
            program: 65,
            altitudeMeters: 30,
            outcome: .inFlight,
            hasSurfaceContact: false
        )
        #expect(oneHundred.map(\.id) == [.oneHundredFeet])

        let fifty = director.consume(
            program: 66,
            altitudeMeters: 15,
            outcome: .inFlight,
            hasSurfaceContact: false
        )
        #expect(fifty.map(\.id) == [.p66, .fiftyFeet])

        let duplicates = director.consume(
            program: 66,
            altitudeMeters: 10,
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
    @Test func directControlsAndFlightEventsCompleteEveryGate() {
        var recorder = LMCockpitValidationRecorder()

        recorder.observeTerrainLoaded()
        recorder.observe(events: [.p65])
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
            .fiftyFeet,
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
