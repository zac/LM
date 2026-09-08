import Foundation
import RealityKit
import Testing
@testable import LMKit

private struct WindowManifest: Decodable {
    struct Pane: Decodable {
        let position: [Float]
        let right: [Float]
        let up: [Float]
        let normal: [Float]
    }
    let pane_transforms: [String: Pane]
}

@MainActor private func windowNodes(_ root: Entity) -> [Entity] {
    [root] + root.children.flatMap { windowNodes($0) }
}

@MainActor private func windowNode(_ name: String, in root: Entity) throws -> Entity {
    let matches = windowNodes(root).filter { $0.name == name }
    try #require(matches.count == 1)
    return try #require(matches.first)
}

private func windowVector(_ values: [Float]) throws -> SIMD3<Float> {
    try #require(values.count == 3)
    return SIMD3(values[0], values[1], values[2])
}

@Test @MainActor func packagedWindowsPreserveIndependentPaneBasesAndMarkOwnership() throws {
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Assets/Cockpit/Components/WindowsLPD")
    for url in [LMKitAssets.windowsURL, LMKitAssets.windowInterfacesURL, LMKitAssets.windowManifestURL] {
        #expect(try Data(contentsOf: url) == Data(contentsOf: source.appendingPathComponent(url.lastPathComponent)))
    }
    let manifest = try JSONDecoder().decode(WindowManifest.self, from: Data(contentsOf: LMKitAssets.windowManifestURL))
    #expect(manifest.pane_transforms.count == 4)
    let scene = try Entity.load(contentsOf: LMKitAssets.windowsURL)
    let root = try windowNode("WindowsLPD", in: scene)
    let identity = matrix_identity_float4x4
    for i in 0..<4 { #expect(simd_length(root.transformMatrix(relativeTo: nil)[i] - identity[i]) < 1e-5) }
    for (name, pane) in manifest.pane_transforms {
        let node = try windowNode(name, in: root)
        let rotation = node.orientation(relativeTo: root)
        #expect(simd_distance(node.position(relativeTo: root), try windowVector(pane.position)) < 1e-5)
        let right = try windowVector(pane.right), up = try windowVector(pane.up), normal = try windowVector(pane.normal)
        #expect(simd_distance(rotation.act([1, 0, 0]), right) < 1e-5)
        #expect(simd_distance(rotation.act([0, 1, 0]), up) < 1e-5)
        #expect(simd_distance(rotation.act([0, 0, 1]), normal) < 1e-5)
        #expect(simd_dot(simd_cross(right, up), normal) > 0.99999)
    }
    let outer = try windowNode("CDR_Window_Outer", in: root)
    let outerBefore = outer.transformMatrix(relativeTo: root)
    for layer in ["Inner", "Outer"] {
        let pane = try windowNode("CDR_Window_" + layer, in: root)
        let marks = try windowNode("LPD_" + layer, in: root)
        #expect(marks.parent === pane)
        let pilot = try windowNode("LMP_Window_" + layer, in: root)
        #expect(!windowNodes(pilot).contains { $0.name.hasPrefix("LPD_") })
    }
    let inner = try windowNode("CDR_Window_Inner", in: root)
    inner.position.z += 0.01
    #expect(outer.transformMatrix(relativeTo: root) == outerBefore)
    _ = try windowNode("DockingWindow", in: root)
    let data = try Data(contentsOf: LMKitAssets.windowInterfacesURL)
    let contract = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let layout = try #require(contract["marking_layout"] as? [String: Any])
    #expect(layout["angular_targeting_qualified"] as? Bool == false)
    #expect(layout["baseline_angular_targeting_qualified"] as? Bool == false)
}
