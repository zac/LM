import Foundation
import RealityKit
import Testing
@testable import LMKit

private struct HandControllerInterface: Decodable {
    struct Part: Decodable {
        let name: String
        let parent: String
        let neutral_origin_m: [Float]
        let motion: String
        let axis: String
    }
    let entities: [Part]
}

@Test @MainActor func packagedHandControllersPreserveNeutralNestedMechanisms() throws {
    let data = try Data(contentsOf: LMKitAssets.handControllerInterfacesURL)
    let metadata = try JSONDecoder().decode(HandControllerInterface.self, from: data)
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let source = repository.appendingPathComponent("Assets/Cockpit/Components/HandControllers")
    #expect(data == (try Data(contentsOf: source.appendingPathComponent("interface.json"))))
    #expect(metadata.entities.count == 9)
    for controller in LMKitAssets.HandController.allCases {
        let id = controller.rawValue
        let url = LMKitAssets.handControllerURL(controller)
        #expect(try Data(contentsOf: url) == Data(contentsOf: source.appendingPathComponent(id + ".usdz")))
        let scene = try Entity.load(contentsOf: url)
        let root = try #require(scene.findEntity(named: id + "_Mount"))
        #expect(simd_length(root.position) < 1e-5)
        #expect(simd_length(root.scale - SIMD3<Float>(repeating: 1)) < 1e-5)
        #expect(abs(root.orientation.real) > 0.99999)
        let fixed = try #require(root.findEntity(named: id + "_Fixed"))
        let fixedTransform = fixed.transformMatrix(relativeTo: root)
        for part in metadata.entities where part.name.hasPrefix(id + "_") {
            let node = try #require(root.findEntity(named: part.name))
            let parent = try #require(root.findEntity(named: part.parent))
            #expect(node.parent === parent)
            try #require(part.neutral_origin_m.count == 3)
            let xyz = part.neutral_origin_m
            #expect(simd_length(node.position - SIMD3(xyz[0], xyz[1], xyz[2])) < 1e-5)
            #expect(simd_length(node.scale - SIMD3<Float>(repeating: 1)) < 1e-5)
            #expect(abs(node.orientation.real) > 0.99999)
            let neutral = node.transform
            let axis: SIMD3<Float>
            switch part.axis {
            case "X": axis = [1, 0, 0]
            case "Y": axis = [0, 1, 0]
            case "Z": axis = [0, 0, 1]
            default: Issue.record("Unsupported motion axis"); continue
            }
            for sign: Float in [-1, 1] {
                node.transform = neutral
                if part.motion == "rotation" {
                    node.orientation = simd_quatf(angle: sign * 0.1, axis: axis)
                } else {
                    #expect(part.motion == "translation")
                    node.position += axis * sign * 0.005
                }
                #expect(node.transform != neutral)
                #expect(fixed.transformMatrix(relativeTo: root) == fixedTransform)
            }
            node.transform = neutral
        }
    }
}
