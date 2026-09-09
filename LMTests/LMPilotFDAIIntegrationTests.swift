import Foundation
import LMCore
import LMKit
import RealityKit
import Testing
import simd
@testable import LM

@MainActor
@Suite(.serialized)
struct LMPilotFDAIIntegrationTests {
    private func sameRotation(_ a: simd_quatf, _ b: simd_quatf) -> Bool {
        abs(simd_dot(a.vector, b.vector)) > 0.99999
    }

    @Test func pilotTracksCommanderWithIndependentEntitiesAtItsOwnSlot() throws {
        let station = LMCommanderStationScene()
        let commander = try #require(station.importedFDAI?.root)
        let commanderBall = try LMCommanderStationAssembly.unique("FDAI_Ball_Pivot", in: commander)
        let commanderFixed = try LMCommanderStationAssembly.unique("FDAI_Fixed", in: commander)
        #expect(station.installCommanderAssembly())
        let assembly = try #require(station.commanderAssembly)
        let commanderPose = commander.transformMatrix(relativeTo: station.root)
        let firstState = LMVehicleStateSnapshot(attitude: .init(w: cos(0.25), x: sin(0.25)))
        station.apply(firstState)
        #expect(station.installPilotFDAI())
        let pilot = try #require(station.importedPilotFDAI)
        #expect(pilot.root !== commander && pilot.ball !== commanderBall && pilot.fixed !== commanderFixed)
        #expect(sameRotation(pilot.ball.orientation, commanderBall.orientation))
        #expect(LMCommanderStationAssembly.near(commanderPose, commander.transformMatrix(relativeTo: station.root)))
        let slot = try #require(assembly.inventory.panels.flatMap(\.slots).first { $0.id == "Panel2__FDAI" })
        let mount = try LMCommanderStationAssembly.path(slot.node, in: assembly.panelInventory)
        let blank = try LMCommanderStationAssembly.path(slot.default_placeholder_node, in: assembly.panelInventory)
        #expect(pilot.root.parent === mount && !blank.isEnabled)
        #expect(LMCommanderStationAssembly.near(pilot.root.transform.matrix, matrix_identity_float4x4))
        let fixedPose = pilot.fixed.transform
        let commanderRotation = commanderBall.orientation
        pilot.apply(.init(w: cos(0.4), y: sin(0.4)))
        #expect(sameRotation(commanderBall.orientation, commanderRotation))
        #expect(!sameRotation(pilot.ball.orientation, commanderBall.orientation))
        let secondState = LMVehicleStateSnapshot(attitude: .init(w: cos(0.35), z: -sin(0.35)))
        station.apply(secondState)
        #expect(sameRotation(pilot.ball.orientation, LMImportedFDAIOrientation.ballOrientation(for: secondState.attitude)))
        #expect(sameRotation(pilot.ball.orientation, commanderBall.orientation))
        #expect(pilot.fixed.transform == fixedPose)
        for binding in [pilot.root, commander] {
            for name in LMImportedFDAI.unboundNames {
                #expect(try !LMCommanderStationAssembly.unique(name, in: binding).isEnabled)
            }
        }
        #expect(LMCommanderStationAssembly.descendants(pilot.root).allSatisfy {
            $0.components[InputTargetComponent.self] == nil && $0.components[CollisionComponent.self] == nil
        })
        #expect(station.installPilotFDAI { throw LMCommanderStationAssembly.AssemblyError.invalidContract("must not reload") })
        #expect(station.importedPilotFDAI === pilot)
    }

    @Test func failedPilotLoadRetainsOnlyItsBlankAndAllowsRetry() throws {
        let station = LMCommanderStationScene()
        var attempted = false
        #expect(!station.installPilotFDAI {
            attempted = true
            throw LMCommanderStationAssembly.AssemblyError.invalidContract("no foundation")
        })
        #expect(!attempted)
        #expect(station.installCommanderAssembly())
        let assembly = try #require(station.commanderAssembly)
        let pilotSlot = try #require(assembly.inventory.panels.flatMap(\.slots).first { $0.id == "Panel2__FDAI" })
        let blank = try LMCommanderStationAssembly.path(pilotSlot.default_placeholder_node, in: assembly.panelInventory)
        let peer = try #require(assembly.inventory.panels.flatMap(\.slots).first { $0.id == "Panel2__CrossPointer" })
        let peerBlank = try LMCommanderStationAssembly.path(peer.default_placeholder_node, in: assembly.panelInventory)
        let commander = try #require(station.importedFDAI?.root)
        #expect(!station.installPilotFDAI { throw CocoaError(.fileNoSuchFile) })
        #expect(blank.isEnabled && peerBlank.isEnabled && station.importedPilotFDAI == nil)
        #expect(!station.installPilotFDAI { try LMImportedFDAI(asset: Entity()) })
        #expect(blank.isEnabled && peerBlank.isEnabled && station.importedPilotFDAI == nil)
        #expect(!station.installPilotFDAI {
            let invalid = try LMImportedFDAI(asset: Entity.load(contentsOf: LMKitAssets.fdaiURL))
            invalid.root.scale = SIMD3(repeating: 2)
            return invalid
        })
        #expect(blank.isEnabled && peerBlank.isEnabled && commander.parent != nil)
        #expect(station.installPilotFDAI())
        #expect(!blank.isEnabled && peerBlank.isEnabled)
    }

    @Test func normalStartupIncludesPilotButProceduralFallbackDoesNot() async throws {
        let station = LMCommanderStationScene()
        #expect(try await !station.loadArtistCabinIfAvailable(arguments: ["--procedural-cockpit"]))
        #expect(station.importedPilotFDAI == nil)
        #expect(try await station.loadArtistCabinIfAvailable(arguments: ["--no-interior-details"]))
        #expect(station.importedPilotFDAI != nil)
        #expect(LMCommanderStationAssembly.descendants(station.root).filter { $0.name == "FDAI_Ball_Pivot" }.count == 2)
    }
}
