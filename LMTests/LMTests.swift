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

    @Test @MainActor func rapidRestartReRestoresTheCheckpointWithoutABootCycle() async throws {        let session = PoweredDescentSession()
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

/// Full-immersion terrain pipeline: manifest provenance, height-map decode,
/// mesh grid conventions, and the 1:1 inverse-pose world mapping.
@Suite("Full descent terrain")
struct FullDescentTerrainTests {
    @Test func bundledManifestPinsApollo11Sources() throws {
        let manifest = try LMTerrainManifest.load()

        #expect(manifest.schemaVersion == LMTerrainManifest.schemaVersion)
        #expect(manifest.scenarioID == LMPoweredDescentScenario.apollo11SourceBacked.id)
        #expect(abs(manifest.landingOrigin.latitudeDegrees - 0.673433) < 1e-9)
        #expect(abs(manifest.landingOrigin.longitudeDegrees - 23.473113) < 1e-9)
        #expect(manifest.projection.mapProjectionType == "EQUIRECTANGULAR")
        #expect(abs(manifest.projection.sphereRadiusMeters - 1_737_400) < 1)

        let source = try #require(manifest.sources.first)
        #expect(source.productId == "NAC_DTM_APOLLO11")
        #expect(source.sha256.count == 64)
        #expect(source.url.contains("NAC_DTM/APOLLO11/NAC_DTM_APOLLO11.TIF"))

        let near = try #require(manifest.tile(id: "near-field"))
        #expect(near.postsPerSide == 1024)
        #expect(abs(near.postSpacingMeters - 2) < 1e-9)
        let horizon = try #require(manifest.tile(id: "horizon"))
        #expect(horizon.postsPerSide == 512)
        #expect(abs(horizon.postSpacingMeters - 32) < 1e-9)

        // Mission-appropriate low sun out of the west-southwest.
        #expect(manifest.sun.elevationDegrees > 5 && manifest.sun.elevationDegrees < 20)
        #expect(manifest.sun.azimuthDegreesClockwiseFromNorth > 240
            && manifest.sun.azimuthDegreesClockwiseFromNorth < 300)
        let sunENU = manifest.sunDirectionENU
        #expect(sunENU.z > 0)
        #expect(sunENU.y < 0, "sun azimuth west-southwest puts the sun west of the site")
    }

    @Test func heightMapsDecodeAtNativePrecision() throws {
        let manifest = try LMTerrainManifest.load()
        let near = try #require(manifest.tile(id: "near-field"))

        guard let heightURL = Bundle.main.url(
            forResource: "near-field-height",
            withExtension: "png",
            subdirectory: "Terrain"
        ) ?? Bundle.main.url(forResource: "near-field-height", withExtension: "png") else {
            Issue.record("near-field-height.png missing from the app bundle")
            return
        }
        let map = try LMTerrainHeightMap.load(contentsOf: heightURL)
        #expect(map.width == near.postsPerSide)
        #expect(map.height == near.postsPerSide)

        // With an even post count the landing origin falls between the four
        // middle posts; their average height must sit within a few meters of
        // the site elevation (the tile's zero point).
        let half = near.postsPerSide / 2
        let middleSum = Int(map.counts[(half - 1) * near.postsPerSide + half - 1])
            + Int(map.counts[(half - 1) * near.postsPerSide + half])
            + Int(map.counts[half * near.postsPerSide + half - 1])
            + Int(map.counts[half * near.postsPerSide + half])
        let middleMeters = Double(middleSum) / 4.0 / 100.0
        #expect(abs(middleMeters + near.zeroPointMeters) < 5,
                "middle posts \(middleMeters) m should be near the site zero \(near.zeroPointMeters) m")

        // The generator clamps counts at the tile minimum, so the minimum
        // count is zero and the tallest count reproduces the manifest envelope.
        #expect(map.counts.min() == 0)
        let maxHeight = near.zeroPointMeters + Double(map.counts.max()!) / 100.0
        #expect(abs(maxHeight - near.maximumHeightMeters) < 0.02)
    }

    @Test func meshGridFollowsNorthUpEastBackConventions() throws {
        let posts = 8
        let spacing = 2.0
        let tile = makeTile(posts: posts, spacing: spacing)
        var counts = [UInt16](repeating: 0, count: posts * posts)
        // Row 0 = north edge raised by 10 m; the rest stays at ground level.
        for column in 0..<posts { counts[column] = 1_000 }
        let map = LMTerrainHeightMap(width: posts, height: posts, counts: counts)

        let grid = try LMTerrainMeshBuilder.grid(tile: tile, heightMap: map)
        #expect(grid.positions.count == posts * posts)
        // Row 0, column posts-1: north edge, east edge -> +X, -Z.
        let halfSpan = Float(Double(posts - 1) / 2.0 * spacing)
        let northEast = grid.positions[posts - 1]
        #expect(abs(northEast.x - halfSpan) < 1e-4)
        #expect(abs(northEast.z + halfSpan) < 1e-4)
        #expect(abs(northEast.y - 10) < 0.02)
        // South-west corner at ground level.
        let southWest = grid.positions[(posts - 1) * posts]
        #expect(abs(southWest.x + halfSpan) < 1e-4)
        #expect(abs(southWest.y) < 0.02)
        // Normals on the flat south rows point up; on the raised north row
        // they tilt away from the raised edge.
        let flatNormal = grid.normals[(posts - 1) * posts + posts - 1]
        #expect(abs(flatNormal.y - 1) < 0.05)
        #expect(grid.triangles.count == (posts - 1) * (posts - 1) * 6)
    }

    @Test func meshHolePunchSkipsInteriorQuads() throws {
        let posts = 16
        let spacing = 4.0
        let tile = makeTile(posts: posts, spacing: spacing)
        let map = LMTerrainHeightMap(
            width: posts,
            height: posts,
            counts: [UInt16](repeating: 0, count: posts * posts)
        )
        // Hole wider than the middle half removes the central quads.
        let hole = Double(posts - 2) / 2.0 * spacing - spacing / 2
        let grid = try LMTerrainMeshBuilder.grid(
            tile: tile,
            heightMap: map,
            holeExtentMeters: hole
        )
        let fullCount = (posts - 1) * (posts - 1) * 6
        #expect(grid.triangles.count < fullCount)
        #expect(grid.triangles.count > 0)
    }

    @Test func fullDescentMapperKeepsGroundBelowTheUser() {
        let mapper = LMFullDescentMapper()

        // Level vehicle 100 m above the site: the landing origin must appear
        // exactly 100 m below the cockpit origin.
        let level = LMVehicleStateSnapshot(
            positionMeters: LMVector3D(x: 0, y: 0, z: 100),
            velocityMetersPerSecond: .zero,
            attitude: .identity,
            angularVelocityRadiansPerSecond: .zero,
            massKilograms: 15_000
        )
        let levelTransform = mapper.worldTransform(for: level)
        #expect(abs(levelTransform.translation.y + 100) < 1e-4)
        #expect(abs(levelTransform.translation.x) < 1e-4)
        #expect(abs(levelTransform.translation.z) < 1e-4)

        // 90-degree yaw about the up axis: a site feature 10 m north must
        // swing to the cockpit's -X (yaw carries world features around).
        let yaw = LMQuaternion.fromAxisAngle(axis: LMVector3D(z: 1), radians: .pi / 2)
        let yawed = LMVehicleStateSnapshot(
            positionMeters: LMVector3D(x: 0, y: 0, z: 100),
            velocityMetersPerSecond: .zero,
            attitude: yaw,
            angularVelocityRadiansPerSecond: .zero,
            massKilograms: 15_000
        )
        let yawedTransform = mapper.worldTransform(for: yawed)
        let featureNorthOfSite = SIMD4<Float>(10, 0, 0, 1)
        let cockpit = yawedTransform.matrix * featureNorthOfSite
        #expect(abs(cockpit.x) < 1e-3)
        #expect(abs(cockpit.y + 100) < 1e-3)
        #expect(abs(abs(cockpit.z) - 10) < 1e-3)

        // Altitude and horizontal offsets translate the world oppositely.
        let offset = LMVehicleStateSnapshot(
            positionMeters: LMVector3D(x: 30, y: -40, z: 50),
            velocityMetersPerSecond: .zero,
            attitude: .identity,
            angularVelocityRadiansPerSecond: .zero,
            massKilograms: 15_000
        )
        let offsetTransform = mapper.worldTransform(for: offset)
        let site = offsetTransform.matrix * SIMD4<Float>(0, 0, 0, 1)
        #expect(abs(site.x + 30) < 1e-4)
        #expect(abs(site.z + 40) < 1e-4, "vehicle 40 m west puts the site 40 m east, toward -Z")
        #expect(abs(site.y + 50) < 1e-4)
    }

    @Test func missionSunLightPointsAlongTheIlluminationAxis() throws {
        let manifest = try LMTerrainManifest.load()
        let sunRK = LMFullDescentMapper.sunDirection(from: manifest)
        let orientation = LMFullDescentMapper.sunLightOrientation(from: manifest)
        let lit = orientation.act(SIMD3(0, 0, -1))
        #expect(simd_distance(lit, -sunRK) < 1e-4)
        // RealityKit convention: +Y up, -Z east. A low western sun is mostly
        // +Z (west is -east), barely above the horizon.
        #expect(sunRK.z > 0.9)
        #expect(abs(sunRK.y - Float(sin(manifest.sun.elevationDegrees * .pi / 180))) < 1e-3)
        #expect(sunRK.z > sunRK.y * 3)
    }

    private func makeTile(posts: Int, spacing: Double) -> LMTerrainManifest.Tile {
        LMTerrainManifest.Tile(
            id: "test",
            postsPerSide: posts,
            postSpacingMeters: spacing,
            extentMeters: Double(posts - 1) * spacing,
            zeroPointMeters: 0,
            minimumHeightMeters: 0,
            maximumHeightMeters: 10,
            curvatureCorrected: false,
            edgeHandling: nil,
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
}
