import Foundation
import LMKit
import RealityKit
import Testing
import simd
@testable import LM

@MainActor
@Suite(.serialized)
struct LMCommanderLandingInstrumentTests {
    @Test func altitudeRowsAndShuttersMoveAndNeverExposeStaleInvalidValues() throws {
        let instrument = try LMImportedAltitudeRate.load()
        let tape = try LMCommanderStationAssembly.unique("AltitudeTape", in: instrument.root)
        let invalid = try LMCommanderStationAssembly.unique("InvalidAltitude", in: instrument.root)
        let pointer = try LMCommanderStationAssembly.unique("AltitudePointer", in: instrument.root)
        let fixed = pointer.transform
        #expect(!tape.isEnabled && invalid.isEnabled)
        instrument.apply(.init(altitudeMeters: 304.8, radialRateMetersPerSecond: -3.048))
        let row = try LMCommanderStationAssembly.unique("AltitudeTick_01000", in: tape)
        #expect(row.isEnabled && abs(row.position.y) < 0.00001 && row.position.z == 0)
        #expect(tape.isEnabled && !invalid.isEnabled)
        #expect(tape.children.allSatisfy { !$0.isEnabled || abs($0.position.y) <= instrument.contract.motion.row_center_limit_m })
        #expect(LMCommanderStationAssembly.near(pointer.transform.matrix, fixed.matrix))
        instrument.apply(.init(altitudeMeters: .nan, radialRateMetersPerSecond: .infinity))
        #expect(!tape.isEnabled && invalid.isEnabled)
        #expect(tape.children.allSatisfy { !$0.isEnabled })
        #expect(invalid.position.z > 0)
    }
    @Test func crossPointerMovesIndependentNeedlesAndHidesInvalidSource() throws {
        let instrument = try LMImportedCrossPointer.load()
        #expect(!instrument.group.isEnabled)
        let initialLateral = instrument.lateral.position
        let initialForward = instrument.forward.position
        let value = try #require(LMCrossPointerReading(velocity: .init(x: 6.096, y: 3.048, z: -20),
            bodyForward: .init(y: 1), radialUp: .init(z: 1)))
        instrument.apply(value)
        #expect(instrument.group.isEnabled)
        #expect(abs(instrument.lateral.position.x - initialLateral.x + 0.016) < 0.00001)
        #expect(abs(instrument.forward.position.y - initialForward.y - 0.008) < 0.00001)
        #expect(instrument.lateral.position.z == initialLateral.z && instrument.forward.position.z == initialForward.z)
        instrument.apply(nil)
        #expect(!instrument.group.isEnabled)
    }
    @Test func controlsPreserveReferenceRotationsAndRejectUnsupportedOff() throws {
        let mode = try LMImportedDescentControl.load(.attitudeMode)
        let autoLabel = try LMCommanderStationAssembly.unique("AttitudeMode__AUTO", in: mode.root)
        let labelModels = LMCommanderStationAssembly.descendants(autoLabel).compactMap { $0.components[ModelComponent.self] }
        #expect(!labelModels.isEmpty && labelModels.flatMap(\.materials).allSatisfy { $0 is UnlitMaterial })
        #expect(!mode.backingMaterials.isEmpty && mode.backingMaterials.allSatisfy { $0 is UnlitMaterial })
        #expect(mode.apply(runtimeValue: "attitudeHold"))
        #expect(abs(mode.actuator.orientation.real) > 0.99999)
        let before = mode.actuator.transform
        #expect(!mode.apply(runtimeValue: "OFF"))
        #expect(LMCommanderStationAssembly.near(mode.actuator.transform.matrix, before.matrix))
        let rate = try LMImportedDescentControl.load(.descentRate)
        let position = rate.actuator.position
        for (value, degrees) in [("descendPlus", Float(-17)), ("descendMinus", Float(17)), ("center", Float(0))] {
            #expect(rate.apply(runtimeValue: value))
            let expected = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: degrees * .pi / 180, axis: SIMD3<Float>(1, 0, 0))
            #expect(abs(simd_dot(rate.actuator.orientation.vector, expected.vector)) > 0.99999)
            #expect(rate.actuator.position == position)
        }
        #expect(LMCommanderStationAssembly.descendants(rate.root).filter { $0.components[InputTargetComponent.self] != nil }.count == 1)
    }
    @Test func partialInstallationKeepsAllBlanksAndFailureRetainsFallbackControl() throws {
        let station = LMCommanderStationScene()
        #expect(station.installCommanderAssembly())
        let assembly = try #require(station.commanderAssembly)
        let slots = assembly.inventory.panels.flatMap(\.slots).filter { ["Panel1__RangeThrust", "Panel1__CrossPointer", "Panel3__Stability", "Panel5__Engine", "Panel5__Translation"].contains($0.id) }
        let blanks = try slots.map { try LMCommanderStationAssembly.path($0.default_placeholder_node, in: assembly.panelInventory) }
        #expect(!station.installDescentControl(.descentRate, loader: { throw LMCommanderStationAssembly.AssemblyError.invalidContract("injected") }))
        #expect(station.rodSwitch.isEnabled)
        #expect(station.installAltitudeRate())
        #expect(station.installCrossPointer())
        #expect(station.installDescentControl(.attitudeMode))
        #expect(station.installDescentControl(.descentRate))
        #expect(blanks.allSatisfy { $0.isEnabled })
        #expect(!station.rodSwitch.isEnabled && !station.attitudeModeSwitch.isEnabled)
        #expect(station.isRODEntity(try #require(station.importedDescentRate).target))
        #expect(!station.isRODEntity(station.rodSwitch))
        #expect(station.installAltitudeRate { throw LMCommanderStationAssembly.AssemblyError.invalidContract("must not reload") })
        #expect(!station.installStaticOverlay("Missing", assetURL: URL(fileURLWithPath: "/missing"),
            interfaceURL: URL(fileURLWithPath: "/missing"), schema: "missing"))
        #expect(station.importedAltitudeRate != nil && blanks.allSatisfy { $0.isEnabled })
    }
    @Test func optionalDetailsAreSeparateNoninteractiveAndFailureContained() async throws {
        let station = LMCommanderStationScene()
        #expect(station.installCommanderAssembly())
        let assembly = try #require(station.commanderAssembly)
        let slots = assembly.inventory.panels.flatMap(\.slots)
        let enabledBefore = try slots.map { try LMCommanderStationAssembly.path($0.default_placeholder_node, in: assembly.panelInventory).isEnabled }
        #expect(station.installStaticOverlay("InteriorDetails", assetURL: LMKitAssets.interiorDetailsURL,
            interfaceURL: LMKitAssets.interiorDetailsInterfaceURL, schema: "lmkit.interior-details.v1"))
        for corruptTransform in [true, false] {
            var contract = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: LMKitAssets.breakerBanksInterfaceURL)) as? [String: Any])
            var mappings = try #require(contract["slots"] as? [[String: Any]])
            if corruptTransform {
                var pose = try #require(mappings[0]["slot_pose"] as? [String: Any])
                pose["translation_m"] = [100, 0, 0]
                mappings[0]["slot_pose"] = pose
            } else { mappings[0]["default_placeholder_node"] = slots[0].default_placeholder_node }
            contract["slots"] = mappings
            let bad = try LMCockpitStaticOverlay(asset: Entity.load(contentsOf: LMKitAssets.breakerBanksURL),
                interfaceData: JSONSerialization.data(withJSONObject: contract), name: "BreakerBanks", schema: "lmkit.breaker-banks.interface.v1")
            #expect(throws: (any Error).self) { try assembly.installStaticOverlay(bad) }
            #expect(bad.root.parent == nil)
            let afterFailure = try slots.map { try LMCommanderStationAssembly.path($0.default_placeholder_node, in: assembly.panelInventory).isEnabled }
            #expect(afterFailure == enabledBefore)
        }
        #expect(station.installStaticOverlay("BreakerBanks", assetURL: LMKitAssets.breakerBanksURL,
            interfaceURL: LMKitAssets.breakerBanksInterfaceURL, schema: "lmkit.breaker-banks.interface.v1"))
        #expect(station.staticOverlays.count == 2)
        for root in station.staticOverlays.values {
            #expect(LMCommanderStationAssembly.near(root.transform.matrix, matrix_identity_float4x4))
            #expect(LMCommanderStationAssembly.descendants(root).allSatisfy {
                $0.components[InputTargetComponent.self] == nil && $0.components[CollisionComponent.self] == nil
            })
        }
        let enabledAfter = try slots.map { try LMCommanderStationAssembly.path($0.default_placeholder_node, in: assembly.panelInventory).isEnabled }
        #expect(zip(enabledBefore, enabledAfter).filter { $0 && !$1 }.count == 9)
        let withoutDetails = LMCommanderStationScene()
        #expect(try await withoutDetails.loadArtistCabinIfAvailable(arguments: ["--no-interior-details"]))
        #expect(withoutDetails.staticOverlays["InteriorDetails"] == nil)
        #expect(withoutDetails.staticOverlays["BreakerBanks"] == nil)
        #expect(withoutDetails.staticOverlays["CautionWarning"] != nil)
        let bare = try #require(withoutDetails.commanderAssembly)
        for slot in slots where slot.id.hasPrefix("Panel11__") || slot.id.hasPrefix("Panel16__") {
            #expect(try LMCommanderStationAssembly.path(slot.default_placeholder_node, in: bare.panelInventory).isEnabled)
        }
    }

}
