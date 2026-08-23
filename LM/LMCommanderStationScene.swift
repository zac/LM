import LMCore
import RealityKit
import SwiftUI
import UIKit
import simd

/// A focused, life-size approximation of the commander's powered-descent station.
///
/// This milestone intentionally models only the load-bearing sight picture:
/// forward triangular windows, the commander's instrument shelf, side structure,
/// overhead structure, and the lunar exterior. Geometry is procedural so layout
/// can be iterated on-device before committing to a heavyweight cabin asset.
@MainActor
final class LMCommanderStationScene {
    let root = Entity()
    let lunarWorld = Entity()
    let acaHandle = ModelEntity()
    let rodSwitch = ModelEntity()
    let attitudeModeSwitch = ModelEntity()

    private let instrumentMount = Entity()
    private let provisionalTerrain = Entity()
    private let mapper = LMCockpitWorldMapper.fullScale
    private let controlMapper = LMSpatialControlMapper()
    private let acaNeutralPosition = SIMD3<Float>(-0.49, 0.50, -0.37)
    private let rodNeutralPosition = SIMD3<Float>(0.43, 0.58, -0.49)
    private let attitudeModeAutomaticPosition = SIMD3<Float>(0.48, 0.78, -0.675)

    init() {
        root.name = "LM Commander Station"
        lunarWorld.name = "Lunar World"
        instrumentMount.name = "Commander Instruments"
        provisionalTerrain.name = "Provisional terrain"

        buildCabin()
        buildPhysicalControls()
        buildProvisionalSurface()

        root.addChild(lunarWorld)
        root.addChild(instrumentMount)
    }

    func mountInstruments(_ entity: Entity) {
        guard entity.parent == nil else { return }
        entity.name = "FDAI and DSKY"
        entity.position = SIMD3(-0.16, 0.82, -0.69)
        entity.orientation = simd_quatf(angle: -.pi / 10, axis: SIMD3(1, 0, 0))
        entity.scale = SIMD3(repeating: 0.00058)
        instrumentMount.addChild(entity)
    }

    func apply(_ state: LMVehicleStateSnapshot?) {
        guard let state else { return }
        lunarWorld.transform = Transform(matrix: mapper.lunarWorldMatrix(from: state))
    }

    func loadApollo11Terrain() async throws {
        let terrain = try await Apollo11TerrainResource.makeEntity()
        provisionalTerrain.removeFromParent()
        lunarWorld.addChild(terrain)
    }

    func setACAVisual(_ input: LMACANormalizedInput) {
        acaHandle.position = acaNeutralPosition + controlMapper.visualACATranslation(for: input)
        acaHandle.orientation = simd_quatf(
            angle: Float(input.roll) * -0.18,
            axis: SIMD3(0, 0, 1)
        ) * simd_quatf(
            angle: Float(input.pitch) * 0.18,
            axis: SIMD3(1, 0, 0)
        )
    }

    func setRODVisual(_ position: PoweredDescentSession.RODSwitchPosition) {
        rodSwitch.position = rodNeutralPosition
            + SIMD3(0, controlMapper.visualRODTranslation(for: position), 0)
    }

    func setAttitudeHoldVisual(_ isAttitudeHold: Bool) {
        attitudeModeSwitch.position = attitudeModeAutomaticPosition
            + SIMD3(0, isAttitudeHold ? 0.028 : 0, 0)
        attitudeModeSwitch.orientation = simd_quatf(
            angle: isAttitudeHold ? -.pi / 7 : .pi / 7,
            axis: SIMD3(1, 0, 0)
        )
    }

    private func buildCabin() {
        let dark = SimpleMaterial(
            color: UIColor(red: 0.105, green: 0.115, blue: 0.105, alpha: 1),
            roughness: 0.78,
            isMetallic: false
        )
        let panel = SimpleMaterial(
            color: UIColor(red: 0.19, green: 0.205, blue: 0.18, alpha: 1),
            roughness: 0.68,
            isMetallic: false
        )
        let aluminum = SimpleMaterial(
            color: UIColor(red: 0.49, green: 0.50, blue: 0.46, alpha: 1),
            roughness: 0.48,
            isMetallic: true
        )

        addBox(size: SIMD3(1.36, 0.44, 0.09), position: SIMD3(0, 0.83, -0.72), material: panel, name: "Panel 1")
        addBox(size: SIMD3(1.62, 0.08, 0.32), position: SIMD3(0, 0.59, -0.51), material: dark, name: "Glare shield")
        addBox(size: SIMD3(1.75, 0.08, 1.50), position: SIMD3(0, 0.10, -0.05), material: dark, name: "Cabin floor")
        addBox(size: SIMD3(0.12, 1.80, 1.35), position: SIMD3(-0.92, 1.02, -0.12), material: dark, name: "Commander sidewall")
        addBox(size: SIMD3(0.12, 1.80, 1.35), position: SIMD3(0.92, 1.02, -0.12), material: dark, name: "LMP sidewall")
        addBox(size: SIMD3(1.75, 0.12, 1.30), position: SIMD3(0, 1.98, -0.12), material: dark, name: "Overhead")

        // Window frames leave the forward view physically open. Their splayed
        // lower rails capture the LM's characteristic triangular sight picture.
        addBox(size: SIMD3(0.09, 0.88, 0.09), position: SIMD3(-0.72, 1.46, -0.79), material: aluminum, name: "Left window post")
        addBox(size: SIMD3(0.09, 0.88, 0.09), position: SIMD3(0.72, 1.46, -0.79), material: aluminum, name: "Right window post")
        addBox(size: SIMD3(1.52, 0.08, 0.09), position: SIMD3(0, 1.88, -0.79), material: aluminum, name: "Window header")
        addBox(
            size: SIMD3(0.74, 0.08, 0.09),
            position: SIMD3(-0.37, 1.13, -0.79),
            orientation: simd_quatf(angle: -.pi / 9, axis: SIMD3(0, 0, 1)),
            material: aluminum,
            name: "Commander window sill"
        )
        addBox(
            size: SIMD3(0.74, 0.08, 0.09),
            position: SIMD3(0.37, 1.13, -0.79),
            orientation: simd_quatf(angle: .pi / 9, axis: SIMD3(0, 0, 1)),
            material: aluminum,
            name: "LMP window sill"
        )
        addBox(size: SIMD3(0.10, 0.78, 0.12), position: SIMD3(0, 1.48, -0.76), material: aluminum, name: "Center window post")

        // Landing-point designator reticle: fixed to the commander's window.
        let reticleMaterial = SimpleMaterial(color: UIColor(red: 0.92, green: 0.78, blue: 0.28, alpha: 0.72), isMetallic: false)
        addBox(size: SIMD3(0.30, 0.004, 0.004), position: SIMD3(-0.36, 1.48, -0.84), material: reticleMaterial, name: "LPD horizontal")
        addBox(size: SIMD3(0.004, 0.30, 0.004), position: SIMD3(-0.36, 1.48, -0.84), material: reticleMaterial, name: "LPD vertical")
    }

    private func buildPhysicalControls() {
        let housing = SimpleMaterial(
            color: UIColor(red: 0.12, green: 0.13, blue: 0.115, alpha: 1),
            roughness: 0.72,
            isMetallic: false
        )
        let handleMaterial = SimpleMaterial(
            color: UIColor(red: 0.29, green: 0.27, blue: 0.20, alpha: 1),
            roughness: 0.58,
            isMetallic: false
        )
        let switchMaterial = SimpleMaterial(
            color: UIColor(red: 0.72, green: 0.69, blue: 0.54, alpha: 1),
            roughness: 0.45,
            isMetallic: true
        )

        addBox(
            size: SIMD3(0.24, 0.08, 0.28),
            position: SIMD3(acaNeutralPosition.x, 0.365, acaNeutralPosition.z),
            material: housing,
            name: "ACA pedestal"
        )
        acaHandle.name = "Attitude Controller Assembly"
        acaHandle.model = ModelComponent(
            mesh: .generateCylinder(height: 0.25, radius: 0.028),
            materials: [handleMaterial]
        )
        acaHandle.position = acaNeutralPosition
        acaHandle.components.set(InputTargetComponent())
        acaHandle.components.set(HoverEffectComponent())
        acaHandle.components.set(CollisionComponent(shapes: [
            .generateBox(size: SIMD3(0.14, 0.30, 0.14))
        ]))
        root.addChild(acaHandle)

        addBox(
            size: SIMD3(0.18, 0.07, 0.18),
            position: SIMD3(rodNeutralPosition.x, 0.49, rodNeutralPosition.z),
            material: housing,
            name: "ROD switch pedestal"
        )
        rodSwitch.name = "Rate of Descent switch"
        rodSwitch.model = ModelComponent(
            mesh: .generateBox(size: SIMD3(0.10, 0.10, 0.08)),
            materials: [switchMaterial]
        )
        rodSwitch.position = rodNeutralPosition
        rodSwitch.components.set(InputTargetComponent())
        rodSwitch.components.set(HoverEffectComponent())
        rodSwitch.components.set(CollisionComponent(shapes: [
            .generateBox(size: SIMD3(0.16, 0.18, 0.14))
        ]))
        root.addChild(rodSwitch)

        attitudeModeSwitch.name = "Mode Control attitude hold"
        attitudeModeSwitch.model = ModelComponent(
            mesh: .generateBox(size: SIMD3(0.08, 0.13, 0.055)),
            materials: [switchMaterial]
        )
        attitudeModeSwitch.position = attitudeModeAutomaticPosition
        attitudeModeSwitch.components.set(InputTargetComponent())
        attitudeModeSwitch.components.set(HoverEffectComponent())
        attitudeModeSwitch.components.set(CollisionComponent(shapes: [
            .generateBox(size: SIMD3(0.16, 0.20, 0.12))
        ]))
        setAttitudeHoldVisual(false)
        root.addChild(attitudeModeSwitch)
    }

    private func buildProvisionalSurface() {
        let surfaceMaterial = SimpleMaterial(
            color: UIColor(red: 0.37, green: 0.36, blue: 0.33, alpha: 1),
            roughness: 1,
            isMetallic: false
        )
        let surface = ModelEntity(
            mesh: .generatePlane(width: 1_200, depth: 1_200),
            materials: [surfaceMaterial]
        )
        surface.name = "Provisional lunar surface"
        provisionalTerrain.addChild(surface)

        let markerMaterial = SimpleMaterial(
            color: UIColor(red: 0.66, green: 0.64, blue: 0.57, alpha: 1),
            roughness: 1,
            isMetallic: false
        )
        for index in 0..<24 {
            let angle = Float(index) * 2 * .pi / 24
            let radius = Float(14 + (index % 6) * 13)
            let rock = ModelEntity(
                mesh: .generateBox(size: SIMD3(1.4 + Float(index % 4), 0.35, 0.9 + Float(index % 3))),
                materials: [markerMaterial]
            )
            rock.position = SIMD3(cos(angle) * radius, 0.17, sin(angle) * radius)
            rock.orientation = simd_quatf(angle: angle * 0.37, axis: SIMD3(0, 1, 0))
            provisionalTerrain.addChild(rock)
        }
        lunarWorld.addChild(provisionalTerrain)

        let sun = Entity()
        sun.components.set(DirectionalLightComponent(color: .white, intensity: 42_000))
        sun.orientation = simd_quatf(angle: -.pi / 3, axis: SIMD3(1, 0.25, 0))
        lunarWorld.addChild(sun)
    }

    private func addBox(
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        orientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
        material: SimpleMaterial,
        name: String
    ) {
        let entity = ModelEntity(mesh: .generateBox(size: size), materials: [material])
        entity.name = name
        entity.position = position
        entity.orientation = orientation
        root.addChild(entity)
    }
}
