//
//  LunarModuleModel.swift
//  LM
//
//  Created by Zac White on 11/6/25.
//

import UIKit
import RealityKitContent
import RealityKit
import LMCore

enum LunarModuleFlightMode {
    case impulseSandbox
    case kinematicGuidance
}

final class LunarModuleModel {
    let rootEntity = Entity()
    let mode: LunarModuleFlightMode
    
    private(set) var physicsEntity: ModelEntity?
    private var thrusters: [RCSThruster: RCSThrusterData] = [:]
    private var plumeEntity: ModelEntity?
    private let thrusterForceMagnitude: Float = 445.0  // ≈100 lbf
    private let minimumPulseDuration: Float = 0.05     // 50 ms pulse
    private let idleConeMaterial = UnlitMaterial(color: UIColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 0.8))
    private let activeConeMaterial = UnlitMaterial(color: UIColor(red: 1.0, green: 0.15, blue: 0.1, alpha: 0.95))
    
    private var moduleMass: Float = 2150.0
    private var inertiaTensor: SIMD3<Float> = SIMD3<Float>(repeating: 1.0)
    private var centerOfMassOffset: SIMD3<Float> = .zero
    
    private let thrusterDirections: [RCSThruster: SIMD3<Float>] = [
        // Quad 1
        .A1U: SIMD3<Float>(0, 1, 0),   // Up
        .A1F: SIMD3<Float>(0, 0, -1),  // Forward
        .B1L: SIMD3<Float>(-1, 0, 0),  // Left
        .B1D: SIMD3<Float>(0, -1, 0),  // Down
        
        // Quad 2
        .A2A: SIMD3<Float>(0, 0, 1),   // Aft
        .A2D: SIMD3<Float>(0, -1, 0),  // Down
        .B2U: SIMD3<Float>(0, 1, 0),   // Up
        .B2L: SIMD3<Float>(-1, 0, 0),  // Left
        
        // Quad 3
        .A3U: SIMD3<Float>(0, 1, 0),   // Up
        .A3R: SIMD3<Float>(1, 0, 0),   // Right
        .B3A: SIMD3<Float>(0, 0, 1),   // Aft
        .B3D: SIMD3<Float>(0, -1, 0),  // Down
        
        // Quad 4
        .A4R: SIMD3<Float>(1, 0, 0),   // Right
        .A4D: SIMD3<Float>(0, -1, 0),  // Down
        .B4U: SIMD3<Float>(0, 1, 0),   // Up
        .B4F: SIMD3<Float>(0, 0, -1)   // Forward
    ]
    
    init(mode: LunarModuleFlightMode = .impulseSandbox) {
        self.mode = mode
        loadModel()
    }

    func apply(siState: LMVehicleStateSnapshot, mapper: LMWorldMapper, program: Int? = nil) {
        guard let physicsEntity else { return }
        let pose = mapper.pose(from: siState, program: program)
        physicsEntity.position = pose.position
        physicsEntity.orientation = pose.orientation
    }

    func setActiveJets(_ jets: Set<RCSThruster>) {
        guard let module = physicsEntity else { return }
        for (thruster, data) in thrusters {
            guard let cone = module.findEntity(named: data.debugConeName) as? ModelEntity else { continue }
            cone.model?.materials = [jets.contains(thruster) ? activeConeMaterial : idleConeMaterial]
        }
    }

    func setDPSThrust(newtons: Double?, engineOn: Bool) {
        guard let plumeEntity else { return }
        let thrust = newtons ?? 0
        let lit = engineOn && thrust > 1
        plumeEntity.isEnabled = lit
        guard lit else { return }
        let fraction = max(0.25, min(1.6, thrust / LMDPSThrottleMap.ratedMaxThrustNewtons))
        plumeEntity.scale = SIMD3(repeating: Float(fraction))
    }
    
    func currentTelemetry() -> LMTelemetry? {
        guard let physicsEntity else { return nil }
        var snapshot = LMTelemetry()
        snapshot.position = physicsEntity.position(relativeTo: nil)
        snapshot.quaternion = physicsEntity.orientation(relativeTo: nil)
        snapshot.angularVelocity = physicsEntity.components[PhysicsMotionComponent.self]?.angularVelocity ?? .zero
        return snapshot
    }
    
    func reset() {
        guard let physicsEntity else { return }
        
        var transform = physicsEntity.transform
        transform.translation = .zero
        transform.rotation = simd_quatf()
        physicsEntity.transform = transform
        
        if var motion = physicsEntity.components[PhysicsMotionComponent.self] {
            motion.linearVelocity = .zero
            motion.angularVelocity = .zero
            physicsEntity.components[PhysicsMotionComponent.self] = motion
        }
    }
    
    func fireThruster(_ thruster: RCSThruster) {
        guard
            let thrusterData = thrusters[thruster],
            let module = physicsEntity,
            var motion = module.components[PhysicsMotionComponent.self]
        else {
            print("Missing thruster data or physics entity for \(thruster)")
            return
        }
        
        print("Thruster \(thruster.rawValue) fired at position \(thrusterData.localPosition), direction \(thrusterData.localDirection)")
        
        let length = simd_length(thrusterData.localDirection)
        let normalizedDirection = length > 0 ? thrusterData.localDirection / length : SIMD3<Float>(0, 1, 0)
        let force = normalizedDirection * thrusterForceMagnitude
        let impulse = force * minimumPulseDuration
        
        motion.linearVelocity += impulse / moduleMass
        
        let torque = simd_cross(thrusterData.localPosition, force)
        let angularImpulse = torque * minimumPulseDuration
        let deltaAngularVelocity = SIMD3<Float>(
            inertiaTensor.x > 0 ? angularImpulse.x / inertiaTensor.x : 0,
            inertiaTensor.y > 0 ? angularImpulse.y / inertiaTensor.y : 0,
            inertiaTensor.z > 0 ? angularImpulse.z / inertiaTensor.z : 0
        )
        motion.angularVelocity += deltaAngularVelocity
        
        module.components[PhysicsMotionComponent.self] = motion
        
        highlightCone(for: thrusterData)
    }
    
    // MARK: - Private helpers
    
    private func loadModel() {
        do {
            let scene = try Entity.load(named: "lm", in: realityKitContentBundle)
            rootEntity.children.removeAll()
            thrusters.removeAll()
            
            guard let landerGeometry = scene.findEntity(named: "lunarlander") else {
                print("Unable to locate lunar lander entity in loaded scene")
                return
            }
            
            let scaleFactor: Float = 0.05
            let physicsGeometry = scene.findEntity(named: "Physics")
            
            let physicsBounds: BoundingBox
            if let physicsGeometry {
                physicsBounds = physicsGeometry.visualBounds(relativeTo: scene)
            } else {
                print("WARNING: Physics geometry not found; using lunarlander bounds for COM estimate")
                physicsBounds = landerGeometry.visualBounds(relativeTo: scene)
            }
            
            let centerOfMass = physicsBounds.center
            centerOfMassOffset = centerOfMass * scaleFactor
            
            let landerClone = landerGeometry.clone(recursive: true)
            landerClone.name = "LunarModuleMesh"
            let landerMatrix = landerGeometry.transformMatrix(relativeTo: scene)
            var landerTransform = Transform(matrix: landerMatrix)
            landerTransform.translation -= centerOfMass
            landerTransform.translation *= scaleFactor
            landerTransform.scale *= SIMD3<Float>(repeating: scaleFactor)
            landerClone.transform = landerTransform
            
            let physicsRootEntity = ModelEntity()
            physicsRootEntity.name = "LunarModuleRoot"
            physicsRootEntity.addChild(landerClone)
            
            rootEntity.addChild(physicsRootEntity)
            physicsEntity = physicsRootEntity
            
            let scaledExtents = physicsBounds.extents * scaleFactor
            let collisionExtents = SIMD3<Float>(
                max(scaledExtents.x, 0.1),
                max(scaledExtents.y, 0.1),
                max(scaledExtents.z, 0.1)
            )
            let collisionShape = ShapeResource.generateBox(size: collisionExtents)
            physicsRootEntity.components[CollisionComponent.self] = CollisionComponent(shapes: [collisionShape])
            
            moduleMass = 2150.0
            let width = max(collisionExtents.x, 1e-3)
            let height = max(collisionExtents.y, 1e-3)
            let depth = max(collisionExtents.z, 1e-3)
            let oneTwelfthMass = moduleMass / 12.0
            inertiaTensor = SIMD3<Float>(
                oneTwelfthMass * (height * height + depth * depth),
                oneTwelfthMass * (width * width + depth * depth),
                oneTwelfthMass * (width * width + height * height)
            )
            
            var physicsBody = PhysicsBodyComponent()
            physicsBody.massProperties = .init(shape: collisionShape, mass: moduleMass)
            physicsBody.material = .generate(friction: 0.0, restitution: 0.0)
            physicsBody.mode = mode == .kinematicGuidance ? .kinematic : .dynamic
            physicsBody.isAffectedByGravity = false
            physicsBody.linearDamping = 0.0
            physicsBody.angularDamping = 0.0
            physicsRootEntity.components[PhysicsBodyComponent.self] = physicsBody
            physicsRootEntity.components[PhysicsMotionComponent.self] = PhysicsMotionComponent()
            print("Configured physics root with COM offset \(centerOfMassOffset) and extents: \(collisionExtents)")
            
            configureThrusters(on: physicsRootEntity)
            configureDPSPlume(on: physicsRootEntity)
        } catch {
            print("Failed to load lunar-module scene: \(error)")
        }
    }
    
    private func configureThrusters(on physicsRootEntity: ModelEntity) {
        let thrusterMapping: [String: RCSThruster] = [
            "group13_g5": .A1U,
            "group13_g7": .A1F,
            "group13_g6": .B1L,
            "group13_g4": .B1D,
            
            "group13_10": .A2A,
            "group13_g8": .A2D,
            "group13_g9": .B2U,
            "group13_11": .B2L,
            
            "group13_12": .A3U,
            "group13_13": .A3R,
            "group13_14": .B3A,
            "group13_p1": .B3D,
            
            "group13_g2": .A4R,
            "group13_g1": .A4D,
            "group13_gr": .B4U,
            "group13_g3": .B4F
        ]
        
        for (groupName, thruster) in thrusterMapping {
            guard
                let thrusterEntity = physicsRootEntity.findEntity(named: groupName),
                let direction = thrusterDirections[thruster]
            else {
                print("Missing thruster entity or direction for \(groupName)")
                continue
            }
            
            let localPosition = thrusterEntity.position(relativeTo: physicsRootEntity)
            let approximateDirection = simd_normalize(direction)
            let thrusterOrientation = thrusterEntity.orientation(relativeTo: physicsRootEntity)
            let localDirection = resolvedThrusterDirection(approximate: approximateDirection,
                                                           orientation: thrusterOrientation)
            
            let coneName = "thruster-debug-\(thruster.rawValue)"
            let coneDirection = simd_normalize(localDirection)
            let coneHeight: Float = 0.02
            let coneRadius: Float = 0.0075
            
            if let existingCone = thrusterEntity.findEntity(named: coneName) as? ModelEntity {
                existingCone.model?.materials = [idleConeMaterial]
                existingCone.transform = Transform(
                    rotation: rotationAligningPositiveY(to: coneDirection),
                    translation: coneDirection * (-coneHeight * 0.5)
                )
            } else {
                let coneMesh = MeshResource.generateCone(height: coneHeight, radius: coneRadius)
                let marker = ModelEntity(
                    mesh: coneMesh,
                    materials: [idleConeMaterial]
                )
                marker.name = coneName
                marker.transform = Transform(
                    rotation: rotationAligningPositiveY(to: coneDirection),
                    translation: coneDirection * (-coneHeight * 0.5)
                )
                thrusterEntity.addChild(marker)
            }
            
            thrusters[thruster] = RCSThrusterData(
                thruster: thruster,
                entity: thrusterEntity,
                localPosition: localPosition,
                localDirection: localDirection,
                debugConeName: coneName
            )
        }
    }
    
    private func highlightCone(for thrusterData: RCSThrusterData) {
        guard
            let module = physicsEntity,
            let debugCone = module.findEntity(named: thrusterData.debugConeName) as? ModelEntity
        else { return }
        
        debugCone.model?.materials = [activeConeMaterial]
        let highlightDurationMilliseconds = max(1, Int(minimumPulseDuration * 6_000))
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(highlightDurationMilliseconds)) {
            debugCone.model?.materials = [self.idleConeMaterial]
        }
    }

    private func configureDPSPlume(on physicsRootEntity: ModelEntity) {
        let mesh = MeshResource.generateCone(height: 0.12, radius: 0.035)
        let plume = ModelEntity(
            mesh: mesh,
            materials: [UnlitMaterial(color: UIColor(red: 1.0, green: 0.55, blue: 0.15, alpha: 0.85))]
        )
        plume.name = "DPSPlume"
        plume.orientation = simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0))
        plume.position = SIMD3(0, -0.07, 0)
        plume.isEnabled = false
        physicsRootEntity.addChild(plume)
        plumeEntity = plume
    }
    
    private func rotationAligningReferenceAxis(_ reference: SIMD3<Float>, to direction: SIMD3<Float>) -> simd_quatf {
        let epsilon: Float = 1e-4
        let target = simd_normalize(direction)
        if simd_length(target) < epsilon {
            return simd_quatf()
        }
        
        let base = simd_normalize(reference)
        let dot = simd_dot(base, target)
        
        if dot > 1 - epsilon {
            return simd_quatf()
        }
        
        if dot < -1 + epsilon {
            let orthogonal = abs(base.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 0, 1)
            let axis = simd_normalize(simd_cross(base, orthogonal))
            return simd_quatf(angle: .pi, axis: axis)
        }
        
        let axis = simd_normalize(simd_cross(base, target))
        let angle = acos(dot)
        return simd_quatf(angle: angle, axis: axis)
    }
    
    private func rotationAligningPositiveY(to direction: SIMD3<Float>) -> simd_quatf {
        rotationAligningReferenceAxis(SIMD3<Float>(0, 1, 0), to: direction)
    }
    
    private func resolvedThrusterDirection(approximate: SIMD3<Float>, orientation: simd_quatf) -> SIMD3<Float> {
        let approx = simd_length(approximate) > 0 ? simd_normalize(approximate) : SIMD3<Float>(0, 1, 0)
        let candidateAxes: [SIMD3<Float>] = [
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(-1, 0, 0),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(0, -1, 0),
            SIMD3<Float>(0, 0, 1),
            SIMD3<Float>(0, 0, -1)
        ]
        
        var bestDirection = approx
        var bestDot: Float = -Float.greatestFiniteMagnitude
        
        for axis in candidateAxes {
            let rotated = orientation.act(axis)
            let normalized = simd_length(rotated) > 0 ? simd_normalize(rotated) : rotated
            let dot = simd_dot(normalized, approx)
            if dot > bestDot {
                bestDot = dot
                bestDirection = normalized
            }
        }
        
        if bestDot < 0 {
            return -bestDirection
        }
        
        return simd_normalize(bestDirection)
    }
}
