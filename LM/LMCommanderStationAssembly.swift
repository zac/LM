import Foundation
import LMKit
import RealityKit
import UIKit
import simd

/// Optional visual assembly. Never owns spacecraft state or instrument bindings.
@MainActor
final class LMCommanderStationAssembly {
    enum AssemblyError: Error { case invalidContract(String) }
    struct Manifest: Decodable {
        struct Mount: Decodable {
            let position: [Float]
            let rotation_x_degrees: Float
            let path: String
        }
        let units: String
        let coordinate_space: String
        let mounts: [String: Mount]
    }
    let root: Entity
    let cabin: Entity
    let manifest: Manifest

    static func load() throws -> LMCommanderStationAssembly {
        try LMCommanderStationAssembly(
            asset: Entity.load(contentsOf: LMKitAssets.cabinSkeletonURL),
            manifestData: Data(contentsOf: LMKitAssets.cabinMountsURL),
            loadControl: { try Entity.load(contentsOf: LMKitAssets.controlURL($0)) }
        )
    }

    init(asset: Entity, manifestData: Data,
         loadControl: (LMKitAssets.ControlFamily) throws -> Entity) throws {
        manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard manifest.units == "meters", manifest.coordinate_space.contains("NOT parent-local") else {
            throw AssemblyError.invalidContract("Mount coordinate space")
        }
        root = asset
        cabin = try Self.unique("Cabin", in: asset)
        guard Self.near(cabin.transformMatrix(relativeTo: asset.parent), matrix_identity_float4x4) else {
            throw AssemblyError.invalidContract("Non-neutral cabin root")
        }
        // Verify authored world transforms BEFORE reconciling parent mounts.
        for (name, mount) in manifest.mounts {
            let entity = try Self.path(mount.path, in: cabin)
            guard entity.name == name, mount.position.count == 3 else {
                throw AssemblyError.invalidContract(name)
            }
            let expected = Transform(rotation: simd_quatf(angle: mount.rotation_x_degrees * .pi / 180,
                                                         axis: [1, 0, 0]),
                                     translation: SIMD3(mount.position[0], mount.position[1], mount.position[2]))
            guard Self.near(entity.transformMatrix(relativeTo: cabin), expected.matrix) else {
                throw AssemblyError.invalidContract("Root-relative mount mismatch: \(name)")
            }
        }
        let lpd = LMLandingPointDesignator()
        let eye = try Self.unique("CDR_Eye", in: cabin)
        guard simd_distance(eye.position(relativeTo: cabin), lpd.commanderEyeMeters) < 0.00001 else {
            throw AssemblyError.invalidContract("CDR eye")
        }
        for pane in LMLPDPane.allCases {
            let node = try Self.unique(pane == .inner ? "CDR_Window_Inner" : "CDR_Window_Outer", in: cabin)
            guard simd_distance(node.position(relativeTo: cabin), lpd.windowCorners(on: pane)[0]) < 0.00001,
                  simd_distance(node.orientation(relativeTo: cabin).act([0, 0, 1]),
                                lpd.paneOrientation(pane).act([0, 0, 1])) < 0.00001 else {
                throw AssemblyError.invalidContract("CDR pane basis")
            }
        }
        // Preserve the app's reviewed reach/face registration. USD mount origins
        // are face centers, whereas app surface origins are box centers.
        for (index, surface) in LMCommanderStationGeometry.panelSurfaces.enumerated() {
            let panel = try Self.unique("Mount_Panel_\(index + 1)", in: cabin)
            panel.setTransformMatrix(Transform(rotation: surface.orientation,
                translation: surface.scenePoint(local: [0, 0, surface.sizeMeters.z / 2])).matrix,
                relativeTo: cabin)
        }
        for (name, position, orientation) in [
            ("Mount_DSKY", LMCommanderStationGeometry.dskyMountPositionMeters, LMCommanderStationGeometry.dskyMountOrientation),
            ("Mount_FDAI", LMCommanderStationGeometry.fdaiMountPositionMeters, LMCommanderStationGeometry.fdaiMountOrientation)
        ] {
            let mount = try Self.unique(name, in: cabin)
            mount.setTransformMatrix(Transform(rotation: orientation, translation: position).matrix, relativeTo: cabin)
            // Reservation outlines are not additional instrument renderers.
            for child in mount.children { child.isEnabled = false }
        }
        // No invented mechanical cutout. Entire backing remains absent pending fit.
        for name in ["Panel_1_Reservation", "Panel_4_Reservation", "CDR_Glareshield", "LMP_Glareshield"] {
            try Self.unique(name, in: cabin).isEnabled = false
        }
        // Two generic shape specimens on an otherwise unused reservation, well
        // away from the functional Panel 5 controls. No semantic assignment.
        let tier = try Self.unique("Mount_CDR_MiddleTier", in: cabin)
        for (family, x) in [(LMKitAssets.ControlFamily.maintainedToggle, Float(-0.05)), (.rotarySelector, Float(0.05))] {
            let control = try loadControl(family)
            let neutral = try Self.unique("\(family.rawValue)_Mount", in: control)
            guard Self.near(neutral.transformMatrix(relativeTo: control.parent), matrix_identity_float4x4) else {
                throw AssemblyError.invalidContract("Non-neutral specimen")
            }
            let mount = Entity()
            mount.name = "VisualOnly_\(family.rawValue)"
            mount.position = [x, 0, 0.006]
            mount.addChild(control)
            Self.removeInput(in: control)
            tier.addChild(mount)
        }
        let label = ModelEntity(mesh: .generateText("GENERIC SPECIMENS\nVISUAL ONLY", extrusionDepth: 0.0001,
            font: .systemFont(ofSize: 0.009), containerFrame: CGRect(x: 0, y: 0, width: 0.18, height: 0.03),
            alignment: .center), materials: [UnlitMaterial(color: .white)])
        label.name = "Visual-only specimen status"
        label.position = [-0.09, 0.045, 0.007]
        tier.addChild(label)
        Self.noShadows(in: root)
    }

    static func path(_ path: String, in cabin: Entity) throws -> Entity {
        let names = path.split(separator: "/").map(String.init)
        guard names.first == "Cabin" else { throw AssemblyError.invalidContract(path) }
        return try names.dropFirst().reduce(cabin) { parent, name in
            let matches = parent.children.filter { $0.name == name }
            guard matches.count == 1, let node = matches.first else { throw AssemblyError.invalidContract(path) }
            return node
        }
    }
    static func unique(_ name: String, in root: Entity) throws -> Entity {
        let matches = descendants(root).filter { $0.name == name }
        guard matches.count == 1, let entity = matches.first else { throw AssemblyError.invalidContract(name) }
        return entity
    }
    static func descendants(_ root: Entity) -> [Entity] {
        [root] + root.children.flatMap { descendants($0) }
    }
    static func near(_ lhs: simd_float4x4, _ rhs: simd_float4x4) -> Bool {
        (0..<4).allSatisfy { simd_length(lhs[$0] - rhs[$0]) < 0.00001 }
    }
    private static func removeInput(in root: Entity) {
        for entity in descendants(root) {
            entity.components.remove(InputTargetComponent.self)
            entity.components.remove(CollisionComponent.self)
            entity.components.remove(HoverEffectComponent.self)
        }
    }
    private static func noShadows(in root: Entity) {
        for entity in descendants(root) where entity.components[ModelComponent.self] != nil {
            entity.components.set(DynamicLightShadowComponent(castsShadow: false))
        }
    }
}
