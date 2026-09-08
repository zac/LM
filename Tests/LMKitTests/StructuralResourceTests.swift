import Foundation
import RealityKit
import Testing
@testable import LMKit

private struct Controls: Decodable {
    struct Component: Decodable { let id: String; let mount: String; let moving: [String] }
    let components: [Component]
}

private struct CabinInterface: Decodable {
    struct Mount: Decodable {
        let position: [Float]
        let rotation_x_degrees: Float
        let path: String
    }
    struct Optical: Decodable { let position: [Float]; let normal: [Float]; let right: [Float] }
    let coordinate_space: String
    let mounts: [String: Mount]
    let optical: [String: Optical]
}

private func vector(_ values: [Float]) throws -> SIMD3<Float> {
    try #require(values.count == 3)
    return SIMD3(values[0], values[1], values[2])
}

private func authoringURL(_ component: String, _ file: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Assets/Cockpit/Components/\(component)/\(file)")
}

@Test @MainActor func packagedControlFamiliesPreserveIndependentMechanisms() throws {
    let metadata = try JSONDecoder().decode(Controls.self, from: Data(contentsOf: LMKitAssets.controlInterfacesURL))
    #expect(Set(metadata.components.map(\.id)) == Set(LMKitAssets.ControlFamily.allCases.map(\.rawValue)))
    for item in metadata.components {
        let family = try #require(LMKitAssets.ControlFamily(rawValue: item.id))
        let url = LMKitAssets.controlURL(family)
        #expect(try Data(contentsOf: url) == Data(contentsOf: authoringURL("ControlLibrary", item.id + ".usdz")))
        let scene = try Entity.load(contentsOf: url)
        let root = try #require(scene.findEntity(named: item.mount))
        #expect(simd_length(root.position) < 1e-5)
        #expect(simd_length(root.scale - SIMD3<Float>(repeating: 1)) < 1e-5)
        #expect(abs(root.orientation.real) > 0.99999)
        let housing = try #require(root.findEntity(named: item.id + "__Housing"))
        let originalHousing = housing.transformMatrix(relativeTo: root)
        for name in item.moving {
            let part = try #require(root.findEntity(named: name))
            #expect(part.parent === root)
            let neutral = part.transform
            part.position.z += 0.005
            #expect(housing.transformMatrix(relativeTo: root) == originalHousing)
            part.transform = neutral
        }
        let bounds = root.visualBounds(relativeTo: root)
        #expect(bounds.min.z < 0 && bounds.max.z > 0)
    }
}

@Test @MainActor func packagedCabinPreservesRootSpaceMountsAndOpticalBasis() throws {
    #expect(try Data(contentsOf: LMKitAssets.cabinSkeletonURL) == Data(contentsOf: authoringURL("Cabin", "Cabin.usdz")))
    let metadata = try JSONDecoder().decode(CabinInterface.self, from: Data(contentsOf: LMKitAssets.cabinMountsURL))
    #expect(metadata.coordinate_space.contains("NOT parent-local"))
    let scene = try Entity.load(contentsOf: LMKitAssets.cabinSkeletonURL)
    let root = try #require(scene.findEntity(named: "Cabin"))
    #expect(simd_length(root.position) < 1e-5)
    #expect(simd_length(root.scale - SIMD3<Float>(repeating: 1)) < 1e-5)
    #expect(abs(root.orientation.real) > 0.99999)
    for (name, row) in metadata.mounts {
        let node = try #require(root.findEntity(named: name))
        #expect(simd_length(node.position(relativeTo: root) - (try vector(row.position))) < 1e-5)
        let expected = simd_quatf(angle: row.rotation_x_degrees * .pi / 180, axis: SIMD3<Float>(1, 0, 0))
        #expect(abs(simd_dot(node.orientation(relativeTo: root).vector, expected.vector)) > 0.99999)
        var names = [String]()
        var ancestor: Entity? = node
        while let entity = ancestor {
            names.insert(entity.name, at: 0)
            if entity === root { break }
            ancestor = entity.parent
        }
        #expect("/" + names.joined(separator: "/") == row.path)
    }
    for (name, row) in metadata.optical {
        let pane = try #require(root.findEntity(named: name))
        #expect(simd_length(pane.position(relativeTo: root) - (try vector(row.position))) < 1e-5)
        let rotation = pane.orientation(relativeTo: root)
        let right = try vector(row.right)
        let normal = try vector(row.normal)
        #expect(simd_length(rotation.act(SIMD3<Float>(1, 0, 0)) - right) < 1e-5)
        #expect(simd_length(rotation.act(SIMD3<Float>(0, 0, 1)) - normal) < 1e-5)
        #expect(simd_length(rotation.act(SIMD3<Float>(0, 1, 0)) - simd_cross(normal, right)) < 1e-5)
    }
    let eye = try #require(root.findEntity(named: "CDR_Eye"))
    #expect(simd_length(eye.position(relativeTo: root) - SIMD3<Float>(-0.5588, 1.78, -0.38)) < 1e-5)
    // Optical metadata survives migration; visible panes/marks are exclusively WindowsLPD.
    let optical = try #require(root.findEntity(named: "Optical"))
    func descendants(_ node: Entity) -> [Entity] { [node] + node.children.flatMap(descendants) }
    #expect(descendants(optical).allSatisfy { $0.components[ModelComponent.self] == nil })
    let migration = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: LMKitAssets.cabinMigrationURL)) as? [String: Any])
    let removed = try #require(migration["removed_visual_nodes"] as? [[String: String]])
    for item in removed {
        let name = try #require(item["name"])
        #expect(root.findEntity(named: name) == nil)
    }
    let cutaways = try #require(migration["new_cutaways"] as? [String: String])
    #expect(cutaways.count == 6)
    for name in cutaways.keys {
        let part = try #require(root.findEntity(named: name))
        #expect(part.isEnabled)
    }
}
