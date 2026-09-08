import AGC
import LMCore
import simd
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
        imported.apply(DSKYSnapshot(r1: "+82345", verb: "16", noun: "36", mode: "63", lampTest: true))
        let segment = try LMImportedDSKY.unique("DSKY_Digit_R1_0_A", in: imported.root)
        func model(in node: Entity) -> ModelComponent? {
            if let model = node.components[ModelComponent.self] { return model }
            return node.children.lazy.compactMap { model(in: $0) }.first
        }
        #expect(model(in: segment)?.materials.first is UnlitMaterial)
        imported.apply(nil)
        #expect(!(model(in: segment)?.materials.first is UnlitMaterial))
        let keys = Array(imported.keys.values)
        for a in keys.indices {
            for b in keys.indices where b > a {
                let delta = abs(keys[a].position - keys[b].position)
                #expect(delta.x >= 0.01778 || delta.y >= 0.015748)
            }
        }
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
    @Test func importedFDAIKnownAxesAndCapApproaches() {
        let zero = LMImportedFDAIOrientation.ballOrientation(for: .identity)
        #expect(simd_length(zero.act(SIMD3<Float>(0, 0, 1)) - SIMD3(0, 0, 1)) < 1e-5)
        for degrees in [-85.0, -30, 30, 85] {
            let angle = degrees * .pi / 180
            // Simulation X is NASA pitch/inner, Y is yaw/middle, Z is roll/outer.
            let pitch = LMQuaternion.fromAxisAngle(axis: LMVector3D(x: 1), radians: angle)
            let yaw = LMQuaternion.fromAxisAngle(axis: LMVector3D(y: 1), radians: angle)
            let roll = LMQuaternion.fromAxisAngle(axis: LMVector3D(z: 1), radians: angle)
            let p = LMImportedFDAIOrientation.ballOrientation(for: pitch)
            let y = LMImportedFDAIOrientation.ballOrientation(for: yaw)
            let r = LMImportedFDAIOrientation.ballOrientation(for: roll)
            // Explicit authored UV points, independent of the adapter formula:
            // pitch label at longitude +angle moves to the front index.
            let pitchLabel = SIMD3<Float>(0, -Float(sin(angle)), Float(cos(angle)))
            #expect(simd_length(p.act(pitchLabel) - SIMD3(0, 0, 1)) < 1e-5)
            #expect(simd_length(p.act(SIMD3(1, 0, 0)) - SIMD3(1, 0, 0)) < 1e-5)
            // Positive yaw brings the negative-latitude cap toward the crew.
            let yawLabel = SIMD3<Float>(-Float(sin(angle)), 0, Float(cos(angle)))
            #expect(simd_length(y.act(yawLabel) - SIMD3(0, 0, 1)) < 1e-5)
            let rollIndex = SIMD3<Float>(-Float(sin(angle)), Float(cos(angle)), 0)
            #expect(simd_length(r.act(rollIndex) - SIMD3(0, 1, 0)) < 1e-5)
        }
    }

    @Test func importedFDAICompositionAndReference() {
        let attitude = LMQuaternion.fromAxisAngle(axis: LMVector3D(z: 1), radians: 0.3)
            .multiplied(by: .fromAxisAngle(axis: LMVector3D(y: 1), radians: -0.6))
            .multiplied(by: .fromAxisAngle(axis: LMVector3D(x: 1), radians: 0.9))
        let q = LMImportedFDAIOrientation.ballOrientation(for: attitude)
        // Change of basis from legacy GASTA axes, with legacy texture alignment removed.
        let basis = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(0, 0, 1))
        let oldMotion = FDAIOrientation.ballOrientation(for: attitude) * FDAIOrientation.textureAlignment.inverse
        let expected = basis * oldMotion * basis.inverse
        #expect(abs(simd_dot(q.vector, expected.vector)) > 0.99999)
        let referenced = LMImportedFDAIOrientation.ballOrientation(for: attitude, relativeTo: attitude)
        #expect(abs(referenced.real) > 0.99999)
    }

    @Test @MainActor func importedFDAINativeHierarchyKeepsFixedStructureStill() throws {
        let binding = try LMImportedFDAI(asset: Entity.load(contentsOf: LMKitAssets.fdaiURL))
        let fixed = binding.fixed.transform
        let ballPosition = binding.ball.position
        binding.apply(.fromAxisAngle(axis: LMVector3D(x: 1), radians: 0.5))
        #expect(binding.fixed.transform == fixed)
        #expect(binding.ball.position == ballPosition)
        #expect(abs(binding.ball.orientation.real - 1) > 0.01)
        for name in LMImportedFDAI.unboundNames {
            #expect(try !LMImportedDSKY.unique(name, in: binding.root).isEnabled)
        }
    }

}
