import Foundation
import LMCore
import Testing
@testable import LM

@Suite("Cockpit terrain streaming")
struct LMLunarCockpitStreamingTests {
    func plan(_ east: Double, _ north: Double = 0, size: Double = 16, spacing: Double = 2,
              level: Int = 1, edges: LMTerrainTileEdges = .all) -> LMTerrainTilePlan {
        .init(id: .init(level: level, eastIndex: Int(east), northIndex: Int(north)),
              centerEastMeters: east, centerNorthMeters: north, sizeMeters: size,
              sampleSpacingMeters: spacing, containsProceduralSubresolution: true, transitionEdges: edges)
    }

    @Test func coverageRejectsInternalHolesAndUncoveredSweptFootpads() {
        let left = plan(-12), right = plan(12)
        #expect(!LMLunarCockpitStreamingPolicy.covers([left, right], east: 0, north: 0, radius: 6))
        let a = plan(-8, size: 16, edges: [.west, .north, .south])
        let b = plan(8, size: 16, edges: [.east, .north, .south])
        #expect(LMLunarCockpitStreamingPolicy.covers([a, b], east: 0, north: 0, radius: 4, interior: true))
        #expect(!LMLunarCockpitStreamingPolicy.covers([a, b], east: 0, north: 0, radius: 7, interior: true))
        let fixture = LMLunarTerrainArrivalTests().tile(level: 0, spacing: 2, fine: false)
        let state = LMVehicleStateSnapshot(positionMeters: .init(x: 2, y: 2, z: 10))
        #expect(fixture.sample(east: 2, north: 2) != nil)
        #expect(!LMLunarCockpitStreamingPolicy.permitsStep(state, snapshot: .init(tiles: [fixture])))
        #expect(!LMLunarCockpitStreamingPolicy.covers([a], east: .nan, north: 0, radius: 4))
    }

    @Test func forecastIsBoundedAndPrefetchesTheNextBand() throws {
        let site = try LMLunarLandingSite(latitudeDegrees: 8.35, longitudeDegrees: 30.83, radiusMeters: 1_736_431)
        let state = LMVehicleStateSnapshot(positionMeters: .init(x: -650, y: -400, z: 70),
            velocityMetersPerSecond: .init(x: 0, y: 8, z: -1.5), landingSite: site)
        let forecast = LMLunarCockpitStreamingPolicy.forecast(state)
        #expect(forecast.altitude < 60)
        #expect(abs(forecast.east - state.positionMeters.y - 64) < 1e-8)
        let plans = LMLunarCockpitStreamingPolicy.plans(state, sourceSpacing: 236.9)
        #expect(plans.map(\.sampleSpacingMeters).min() == 0.125)
        #expect(LMLunarCockpitStreamingPolicy.covers(plans, east: state.positionMeters.y,
                                                    north: state.positionMeters.x, radius: 12))
        // The horizon changes residency, never source resolution or contact.
        #expect(plans.count <= LMLunarCockpitStreamingPolicy.maximumPrefetchedTiles)
        let fast = LMVehicleStateSnapshot(positionMeters: .init(x: -650, y: -1000, z: 500),
            velocityMetersPerSecond: .init(x: 0, y: 50, z: -14), landingSite: site)
        #expect(LMLunarCockpitStreamingPolicy.forecast(fast).altitude > 250)
    }

    @Test @MainActor func pendingDetailDoesNotStopFlightOverPublishedGeometry() async throws {
        let region = try LMLunarContactTests().region(at: .init(latitudeDegrees: -42, longitudeDegrees: 120))
        let controller = try LMLunarCockpitTerrain(region: region, gate: .init(),
            date: LunarExplorerSession.apollo11TouchdownUTC)
        var published = false
        controller.presentation.update(plans: [plan(0, size: 64, spacing: 8, level: 3)],
            east: 0, north: 0) { _, _, _, _, milliseconds in published = milliseconds != nil }
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !published && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(published)
        controller.apply(.init(positionMeters: .init(x: 0, y: 0, z: 50), landingSite: controller.site))
        #expect(!controller.ready)
        #expect(controller.permitsPhysicsStep)
        #expect(controller.captureMetrics["missingContactSamples"] == 0)
        #expect(controller.captureMetrics["contactSamples"] == 4)
        controller.apply(.init(positionMeters: .init(x: 0, y: 0, z: 10),
            flightOutcome: .hardLanding, landingSite: controller.site))
        #expect(controller.captureMetrics["heldAtContact"] == 1)
        #expect(controller.permitsPhysicsStep)
        let held = controller.presentation.snapshot.tiles.map(\.plan)
        try await Task.sleep(for: .milliseconds(150))
        #expect(controller.presentation.snapshot.tiles.map(\.plan) == held)
        controller.apply(.init(positionMeters: .init(x: 0, y: 0, z: 1_000), landingSite: controller.site))
        #expect(controller.captureMetrics["heldAtContact"] == 0)
        controller.presentation.cancel()
    }

    @Test @MainActor func contactHoldFreezesMorphWithoutBlockingPhysicsAndCanResume() async throws {
        let region = try LMLunarContactTests().region(at: .init(latitudeDegrees: -42, longitudeDegrees: 120))
        let gate = LMTerrainSimulationGate()
        let presentation = LMLunarTerrainPresentation(region: region, mode: .procedural, simulationGate: gate)
        var allow = true, ready = false
        presentation.publicationAllowed = { allow }
        let fixture = LMLunarTerrainArrivalTests()
        func wait(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            #expect(condition())
        }
        presentation.update(plans: [fixture.tile(level: 0, spacing: 2, fine: false).plan],
                            east: 1, north: 1) { _, _, _, _, ms in ready = ms != nil }
        try await wait { ready }
        ready = false
        presentation.presentationChanged = { allow = false }
        presentation.update(plans: [fixture.tile(level: 1, spacing: 0.5, fine: true).plan],
                            east: 1, north: 1) { _, _, _, _, ms in ready = ms != nil }
        try await wait { presentation.isMorphing && !allow }
        let height = try #require(presentation.snapshot.sample(east: 1.3, north: 1.7)).elevation
        let accessible = await gate.withAccess { true }
        #expect(accessible)
        try await Task.sleep(for: .milliseconds(250))
        #expect(presentation.snapshot.sample(east: 1.3, north: 1.7)?.elevation == height)
        #expect(!ready)
        presentation.presentationChanged = nil
        allow = true
        try await wait { ready }
        #expect(!presentation.isMorphing)
        presentation.cancel()
    }

    @Test @MainActor func residentReentryRetainsEntitiesAndRejectsDifferentLOD() async throws {
        let region = try LMLunarContactTests().region(at: .init(latitudeDegrees: -42, longitudeDegrees: 120))
        let presentation = LMLunarTerrainPresentation(region: region, mode: .procedural)
        let plans = [plan(0)]
        #expect(!presentation.resumeIfReady(plans: plans))
        var ready = false
        presentation.update(plans: plans, east: 0, north: 0) { _, _, _, _, ms in
            if ms != nil { ready = true }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !ready && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(ready)
        let entities = presentation.root.children.map(\.id)
        let positions = try #require(presentation.snapshot.tiles.first).mesh.positions
        #expect(!presentation.resumeIfReady(plans: [plan(0, spacing: 1)]))
        #expect(!presentation.resumeIfReady(plans: []))
        for _ in 0..<3 {
            #expect(presentation.resumeIfReady(plans: plans))
            #expect(presentation.root.children.map(\.id) == entities)
            #expect(presentation.snapshot.tiles.first?.mesh.positions == positions)
            #expect(presentation.cacheStatistics.hits == 1)
            var callback = false
            presentation.update(plans: plans, east: 0, north: 0) { _, _, _, _, _ in callback = true }
            #expect(!callback)
        }
        presentation.cancel()
    }

    @Test func dependencySupportIncludesEdgeNormalsButExcludesDistantTiles() {
        let center = plan(0)
        let edge = plan(16), distant = plan(256, size: 64, spacing: 8, level: 2)
        let dependencies = LMLunarTerrainPresentation.samplingDependencies(for: center, in: [center, edge, distant])
        #expect(dependencies == [center, edge])
    }

    @Test @MainActor func cacheReuseMatchesColdBakesAcrossDistantAndAncestorChanges() async throws {
        let region = try LMLunarContactTests().region(at: .init(latitudeDegrees: -42, longitudeDegrees: 120))
        let warm = LMLunarTerrainPresentation(region: region, mode: .procedural)
        let grand = plan(0, size: 64, spacing: 8, level: 3)
        let parent = plan(0, size: 32, spacing: 4, level: 2)
        let child = plan(0)
        let far = plan(256, size: 64, spacing: 8, level: 3)
        func finish(_ presentation: LMLunarTerrainPresentation, _ plans: [LMTerrainTilePlan]) async throws {
            var done = false
            presentation.update(plans: plans, east: 0, north: 0) { message, _, _, _, milliseconds in
                if message.hasPrefix("Lunar terrain failed") { Issue.record(Comment(rawValue: message)); done = true }
                if milliseconds != nil { done = true }
            }
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while !done && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            #expect(done)
        }
        try await finish(warm, [grand, parent, child])
        for (index, plans) in [
            [grand, far, parent, child],
            [grand.withTransitionEdges([]), far, parent, child],
            [grand.withTransitionEdges([]), far, parent, child, plan(16)]
        ].enumerated() {
            try await finish(warm, plans)
            if index == 0 { #expect(warm.cacheStatistics.hits == 3) }
            if index == 2 { #expect(warm.cacheStatistics.remasked > 0) }
            let cold = LMLunarTerrainPresentation(region: region, mode: .procedural)
            try await finish(cold, plans)
            for actual in warm.snapshot.tiles {
                let expected = try #require(cold.snapshot.tiles.first { $0.plan.id == actual.plan.id })
                #expect(actual.mesh.positions == expected.mesh.positions)
                #expect(actual.mesh.normals == expected.mesh.normals)
                #expect(actual.mesh.indices == expected.mesh.indices)
            }
            cold.cancel()
        }
        warm.cancel()
    }
}
