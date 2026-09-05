import Foundation
import LMCore
import Testing
@testable import LM

@Suite("Custom cockpit restart")
struct LMLunarCockpitRestartTests {
    @Test @MainActor func ignitionRestartRestoresFreshSiteState() async throws {
        let session = PoweredDescentSession()
        let site = try LMLunarLandingSite(latitudeDegrees: -42, longitudeDegrees: 120, radiusMeters: 1_739_000)
        session.selectLandingSite(site)
        session.setSceneActive(false)
        defer { session.stop() }
        session.start(from: .ignition)
        try await wait { session.snapshot?.agc.dsky.programNumber == 63 }
        let initial = try #require(session.snapshot)
        session.setSceneActive(true)
        try await wait { (session.snapshot?.timeSeconds ?? 0) > initial.timeSeconds + 20 }
        session.setSceneActive(false)
        session.restart()
        try await wait { session.snapshot?.timeSeconds == initial.timeSeconds }
        let restarted = try #require(session.snapshot)
        #expect(restarted.agc.dsky.programNumber == 63)
        #expect(restarted.agc.cycle == initial.agc.cycle)
        #expect(restarted.vehicleState == initial.vehicleState)
        #expect(restarted.vehicleState.landingSite == site)
    }

    @Test @MainActor func cancelledTerrainLoadCannotSelectASite() async throws {
        let session = PoweredDescentSession()
        defer { session.stop() }
        let station = LMCommanderStationScene()
        let task = Task { @MainActor in
            try await station.loadGlobalTerrain(at: .init(latitudeDegrees: -42, longitudeDegrees: 120),
                session: session, date: LunarExplorerSession.apollo11TouchdownUTC)
        }
        task.cancel()
        do {
            try await task.value
            Issue.record("Cancelled cockpit source load completed")
        } catch is CancellationError { }
        #expect(session.scenario.initialState.landingSite == nil)
    }

    @MainActor private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition())
    }
}
