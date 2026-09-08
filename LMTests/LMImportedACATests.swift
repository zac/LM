import Foundation
import LMKit
import RealityKit
import Testing
import simd
@testable import LM

@MainActor
@Suite(.serialized)
struct LMImportedACATests {
    @Test func realResourcePreservesPivotsHousingAndLimits() throws {
        let aca = try LMImportedACA.load()
        let fixed = aca.fixed.transformMatrix(relativeTo: aca.root)
        let origins = [aca.roll.position, aca.yaw.position, aca.pitch.position]
        for sign in [-1.0, 1.0] {
            aca.apply(.init(pitch: sign * 2, yaw: sign * 2, roll: sign * 2))
            let angle = LMCommanderStationGeometry.acaProportionalTravelDegrees * .pi / 180
            #expect(simd_distance(aca.pitch.orientation.act([0, 1, 0]), [0, cos(angle), Float(sign) * sin(angle)]) < 0.00001)
            #expect(simd_distance(aca.yaw.orientation.act([0, 0, 1]), [Float(sign) * sin(angle), 0, cos(angle)]) < 0.00001)
            #expect(simd_distance(aca.roll.orientation.act([0, 1, 0]), [Float(sign) * sin(angle), cos(angle), 0]) < 0.00001)
            #expect(LMCommanderStationAssembly.near(fixed, aca.fixed.transformMatrix(relativeTo: aca.root)))
            #expect(origins == [aca.roll.position, aca.yaw.position, aca.pitch.position])
        }
        aca.apply(.neutral)
        for node in [aca.roll, aca.yaw, aca.pitch] {
            #expect(abs(node.orientation.real - 1) < 0.00001)
            #expect(simd_length(node.scale - SIMD3(repeating: 1)) < 0.00001)
        }
        let trigger = try LMImportedDSKY.unique("ACA_PTT_Trigger", in: aca.root)
        #expect(abs(trigger.orientation.real - 1) < 0.00001)
    }

    @Test func installationIsAtomicAndHasOneTargetIncludingChildren() throws {
        let station = LMCommanderStationScene(loadACA: false)
        let original = Array(station.acaHandle.children)
        #expect(!station.installImportedACA { throw LMImportedDSKY.ContractError.invalidParent("injected") })
        #expect(Array(station.acaHandle.children) == original)
        #expect(station.acaHandle.components[CollisionComponent.self] != nil)
        #expect(station.installImportedACA())
        let aca = try #require(station.importedACA)
        let child = Entity(); aca.interactionTarget.addChild(child)
        #expect(station.isACAEntity(child))
        #expect(!station.isACAEntity(station.rodSwitch))
        #expect(station.installImportedACA { throw LMImportedDSKY.ContractError.invalidParent("must not reload") })
        #expect(station.importedACA === aca)
        #expect(station.acaHandle.components[CollisionComponent.self] == nil)
        let colliders = LMCommanderStationAssembly.descendants(station.acaHandle).filter { $0.components[CollisionComponent.self] != nil }
        #expect(colliders.count == 1 && colliders.first === aca.interactionTarget)
        #expect(original.allSatisfy { $0.parent == nil })
        #expect(simd_distance(aca.root.position, LMImportedACA.registration) < 0.00001)
        station.setACAVisual(.init(pitch: 1, yaw: 1, roll: 1))
        #expect(abs(station.acaHandle.orientation.real - 1) < 0.00001)
        let before = aca.root.transformMatrix(relativeTo: station.root)
        #expect(station.installCommanderAssembly())
        #expect(LMCommanderStationAssembly.near(before, aca.root.transformMatrix(relativeTo: station.root)))
    }

    @Test func badInterfaceRejectsLoadAndNonfiniteInputNeutralizes() throws {
        let data = try Data(contentsOf: LMKitAssets.handControllerInterfacesURL)
        let bad = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"axis\": \"Z\"", with: "\"axis\": \"X\"").utf8)
        #expect(throws: (any Error).self) {
            try LMImportedACA(asset: Entity.load(contentsOf: LMKitAssets.handControllerURL(.aca)), interfaceData: bad)
        }
        let session = PoweredDescentSession()
        session.setACA(pitch: .nan, yaw: .infinity, roll: -.infinity)
        #expect(session.aca == .neutral)
        #expect(session.effectiveRHCPitch == 0)
    }

    @Test func releasedStoppedAndDeactivatedGenerationsCannotReapply() throws {
        let session = PoweredDescentSession()
        session.start(from: .p65TerminalDescent)
        defer { session.stop() }
        let input = LMACANormalizedInput(pitch: 1, yaw: -1, roll: 0.5)
        let first = try #require(session.beginACAInteraction())
        #expect(session.updateACAInteraction(input, generation: first))
        #expect(session.effectiveRHCPitch == 42)
        #expect(session.effectiveRHCYaw == -42)
        #expect(session.effectiveRHCRoll == 21)
        session.releaseACA()
        #expect(!session.updateACAInteraction(input, generation: first))
        #expect(session.aca == .neutral)
        let second = try #require(session.beginACAInteraction())
        session.setSceneActive(false)
        session.setSceneActive(true)
        #expect(!session.updateACAInteraction(input, generation: second))
        let third = try #require(session.beginACAInteraction())
        session.stop()
        session.start(from: .p65TerminalDescent)
        #expect(!session.updateACAInteraction(input, generation: third))
        #expect(session.aca == .neutral)
        let station = LMCommanderStationScene()
        station.setACAVisual(input)
        station.setACAVisual(session.aca)
        #expect(abs(try #require(station.importedACA).pitch.orientation.real - 1) < 0.00001)
    }
}
