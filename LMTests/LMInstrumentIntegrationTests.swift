import AGC
import LMKit
import RealityKit
import Testing
@testable import LM

struct LMInstrumentIntegrationTests {
    @Test func preservesBlankDigitsSignsAndRuntimeFlash() {
        let state = LMDSKYSegmentState(DSKYSnapshot(r1: "+12 45", r2: "-00000", mode: " 1", verbNounFlash: true))
        #expect(state.illuminated.contains("DSKY_Digit_PROG_1_B"))
        #expect(!state.illuminated.contains { $0.hasPrefix("DSKY_Digit_PROG_0") })
        #expect(!state.illuminated.contains { $0.hasPrefix("DSKY_Digit_R1_2") })
        #expect(state.illuminated.contains("DSKY_Sign_R1_Plus"))
        #expect(state.illuminated.contains("DSKY_Sign_R1_Minus"))
        #expect(!state.illuminated.contains("DSKY_Sign_R2_Plus"))
        #expect(LMDSKYSegmentState(nil).illuminated.isEmpty)
        let flash = LMDSKYSegmentState(DSKYSnapshot(verb: "88", noun: "88", mode: "88", verbNounFlash: true))
        #expect(!flash.illuminated.contains { $0.contains("Digit_VERB") || $0.contains("Digit_NOUN") })
        #expect(flash.illuminated.contains("DSKY_Digit_PROG_0_A"))
        let blank = LMDSKYSegmentState(DSKYSnapshot(channel163: 0o1000, r1: "+88888", mode: "88", compActy: true))
        #expect(blank.illuminated == ["DSKY_COMP_ACTY_Lens"])
    }

    @Test func lampsAreIndependentAndSparesStayUnbound() {
        for (name, id) in LMDSKYSegmentState.lamps {
            #expect(LMDSKYSegmentState(DSKYSnapshot(indicators: [id: true])).illuminated == ["DSKY_Lamp_\(name)_Lens"])
        }
        let test = LMDSKYSegmentState(DSKYSnapshot(lampTest: true))
        #expect(test.illuminated.count == 13)
        #expect(!test.illuminated.contains { $0.contains("SPARE") })
    }

    @Test @MainActor func nativeNeutralAssetBindsEveryKeyAndRejectsImpostors() throws {
        let imported = try LMImportedDSKY(asset: Entity.load(contentsOf: LMKitAssets.dskyURL))
        #expect(imported.keys.count == 19)
        for key in imported.keys.values {
            #expect(key.parent === imported.root)
            #expect(key.components[InputTargetComponent.self] != nil)
            #expect(key.components[CollisionComponent.self] != nil)
        }
        imported.apply(DSKYSnapshot(r1: "+12345", verb: "16", noun: "36", mode: "63", lampTest: true))
        imported.apply(nil)
        let station = LMCommanderStationScene()
        for key in station.dskyKeyEntities {
            #expect(station.dskyKeyCode(for: key) != nil)
            let impostor = Entity(); impostor.name = key.name
            #expect(station.dskyKeyCode(for: impostor) == nil)
        }
        let duplicate = Entity(); duplicate.name = "DSKY_Key_PRO"
        imported.root.addChild(duplicate)
        #expect(throws: (any Error).self) { try LMImportedDSKY(asset: imported.root) }
    }

    @Test @MainActor func proCancellationAlwaysReleasesAndRegularKeysDispatchOnce() async {
        var edges: [Bool] = []
        var keys: [DSKYKeyCode] = []
        let pulse = Task { @MainActor in
            await LMDSKYInputPulse.run(key: .pro, sendKey: { keys.append($0) }, sendPRO: { edges.append($0) })
        }
        while edges.isEmpty { await Task.yield() }
        pulse.cancel()
        await pulse.value
        #expect(edges == [true, false])
        #expect(keys.isEmpty)
        for key in DSKYKeyCode.allCases where key != .pro {
            await LMDSKYInputPulse.run(key: key, sendKey: { keys.append($0) }, sendPRO: { edges.append($0) })
        }
        #expect(keys.count == 18)
        #expect(Set(keys.map(\.rawValue)).count == 18)
        #expect(edges == [true, false])
    }
}
