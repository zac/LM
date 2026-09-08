import Foundation
import RealityKit
import Testing
@testable import LMKit

private struct PanelManifest: Decodable {
    struct Pose: Decodable {
        let position: [Float]
        let rotation_x_degrees: Float
    }
    struct Interface: Decodable {
        let panel_path: String
        let interface_path: String
        let interface_cabin_relative: Pose
    }
    let units: String
    let root: String
    let interfaces: [String: Interface]
}

@MainActor private func nodes(_ entity: Entity) -> [Entity] {
    [entity] + entity.children.flatMap { nodes($0) }
}

@MainActor private func unique(_ name: String, in root: Entity) throws -> Entity {
    let matches = nodes(root).filter { $0.name == name }
    try #require(matches.count == 1)
    return try #require(matches.first)
}

@Test @MainActor func packagedCommanderPanelsPreserveInterfacesAndIndependentBacking() throws {
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Assets/Cockpit/Components/CommanderPanels")
    for url in [LMKitAssets.commanderPanelsURL, LMKitAssets.commanderPanelMountsURL] {
        #expect(try Data(contentsOf: url) == Data(contentsOf: source.appendingPathComponent(url.lastPathComponent)))
    }
    let metadata = try JSONDecoder().decode(PanelManifest.self,
        from: Data(contentsOf: LMKitAssets.commanderPanelMountsURL))
    #expect(metadata.units == "meters")
    #expect(metadata.root == "/CommanderPanels")
    #expect(Set(metadata.interfaces.keys) == ["DSKY", "FDAI"])
    let scene = try Entity.load(contentsOf: LMKitAssets.commanderPanelsURL)
    let root = try unique("CommanderPanels", in: scene)
    let identity = matrix_identity_float4x4
    for i in 0..<4 {
        #expect(simd_length(root.transformMatrix(relativeTo: nil)[i] - identity[i]) < 1e-5)
    }
    let cabinScene = try Entity.load(contentsOf: LMKitAssets.cabinSkeletonURL)
    let cabin = try unique("Cabin", in: cabinScene)
    for (name, row) in metadata.interfaces {
        let node = try unique(name + "_Interface", in: root)
        let panel = try unique(String(row.panel_path.split(separator: "/").last!), in: root)
        #expect(node.parent === panel)
        #expect(metadata.root + "/" + panel.name + "/" + node.name == row.interface_path)
        #expect(node.children.isEmpty)
        #expect(node.components[ModelComponent.self] == nil)
        try #require(row.interface_cabin_relative.position.count == 3)
        let p = row.interface_cabin_relative.position
        let expected = SIMD3<Float>(p[0], p[1], p[2])
        #expect(simd_distance(node.position(relativeTo: root), expected) < 1e-5)
        let rotation = simd_quatf(angle: row.interface_cabin_relative.rotation_x_degrees * .pi / 180, axis: [1, 0, 0])
        #expect(abs(simd_dot(node.orientation(relativeTo: root).vector, rotation.vector)) > 0.99999)
        let reservation = try unique("Mount_" + name, in: cabin)
        for i in 0..<4 {
            #expect(simd_length(node.transformMatrix(relativeTo: root)[i] - reservation.transformMatrix(relativeTo: cabin)[i]) < 1e-5)
        }
        let shell = try unique(panel.name + "_Shell", in: panel)
        let backing = try unique(panel.name + "_RemovableBacking", in: panel)
        let before = shell.transformMatrix(relativeTo: root)
        let interfaceBefore = node.transformMatrix(relativeTo: root)
        backing.position.z += 0.01
        #expect(shell.transformMatrix(relativeTo: root) == before)
        #expect(node.transformMatrix(relativeTo: root) == interfaceBefore)
    }
    #expect(!nodes(root).contains { $0.name == "DSKY_Key_PRO" || $0.name == "FDAI_Ball_Pivot" })
    #expect(nodes(root).allSatisfy { $0.components[InputTargetComponent.self] == nil })
}
