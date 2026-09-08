import LunarMap
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
    private var plumeEntity: Entity?
    private var dpsBellEntity: Entity?
    private var dpsBellBaseOrientation = simd_quatf()
    private var dpsBellPivotPosition = SIMD3<Float>.zero
    private var dpsPlumeBaseOffset = SIMD3<Float>.zero
    private var modelGeometryBounds: BoundingBox?
    private var activeJets: Set<RCSThruster> = []
    private let thrusterForceMagnitude: Float = 445.0  // ≈100 lbf
    private let minimumPulseDuration: Float = 0.05     // 50 ms pulse
    
    private var moduleMass: Float = 2150.0
    private var inertiaTensor: SIMD3<Float> = SIMD3<Float>(repeating: 1.0)
    private var centerOfMassOffset: SIMD3<Float> = .zero
    
    static let thrusterDirections: [RCSThruster: SIMD3<Float>] = [
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

    static let thrusterEntityNames: [String: RCSThruster] = [
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
    
    init(mode: LunarModuleFlightMode = .impulseSandbox) {
        self.mode = mode
        loadModel()
    }

    func apply(
        siState: LMVehicleStateSnapshot,
        mapper: LMWorldMapper,
        program: Int? = nil,
        floorY: Float? = nil
    ) {
        guard let physicsEntity else { return }
        let pose = mapper.pose(from: siState, program: program)
        physicsEntity.orientation = pose.orientation
        if let floorY, let modelGeometryBounds {
            physicsEntity.position = Self.position(
                pose.position,
                keeping: modelGeometryBounds,
                orientation: pose.orientation,
                above: floorY
            )
        } else {
            physicsEntity.position = pose.position
        }
        applyDPSGimbal(
            pitchRadians: siState.dpsPitchGimbalRadians,
            rollRadians: siState.dpsRollGimbalRadians
        )
    }

    func setActiveJets(_ jets: Set<RCSThruster>) {
        guard jets != activeJets else { return }
        for thruster in activeJets.subtracting(jets) {
            if let plume = thrusters[thruster]?.plumeEntity {
                setExhaustFiring(plume, firing: false)
            }
        }
        for thruster in jets.subtracting(activeJets) {
            if let plume = thrusters[thruster]?.plumeEntity {
                setExhaustFiring(plume, firing: true)
            }
        }
        activeJets = jets
    }

    func setDPSThrust(newtons: Double?, engineOn: Bool) {
        guard let plumeEntity else { return }
        let thrust = newtons ?? 0
        let lit = engineOn && thrust > 1
        setExhaustFiring(plumeEntity, firing: lit)
        guard lit else { return }
        let fraction = max(0.35, min(1.8, thrust / LMDPSThrottleMap.ratedMaxThrustNewtons))
        plumeEntity.scale = SIMD3(1, Float(fraction), 1)
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
        
        setExhaustFiring(thrusterData.plumeEntity, firing: true)
        let highlightDurationMilliseconds = max(1, Int(minimumPulseDuration * 6_000))
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(highlightDurationMilliseconds)) {
            self.setExhaustFiring(thrusterData.plumeEntity, firing: false)
        }
    }
    
    // MARK: - Private helpers
    
    private func loadModel() {
        do {
            let scene = try Entity.load(named: "lm", in: realityKitContentBundle)
            rootEntity.children.removeAll()
            thrusters.removeAll()
            activeJets.removeAll()
            
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
            modelGeometryBounds = landerClone.visualBounds(relativeTo: physicsRootEntity)

            if let dpsBell = physicsRootEntity.findEntity(named: "group13_pC") {
                dpsBellEntity = dpsBell
                dpsBellBaseOrientation = dpsBell.orientation(relativeTo: physicsRootEntity)
                dpsBellPivotPosition = dpsBell.position(relativeTo: physicsRootEntity)
            } else {
                dpsBellEntity = nil
                print("WARNING: DPS engine bell entity group13_pC not found")
            }
            
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
        for (groupName, thruster) in Self.thrusterEntityNames {
            guard
                let thrusterEntity = physicsRootEntity.findEntity(named: groupName),
                let direction = Self.thrusterDirections[thruster]
            else {
                print("Missing thruster entity or direction for \(groupName)")
                continue
            }
            
            let localDirection = simd_normalize(direction)
            let exhaust = simd_normalize(-localDirection)
            let nozzleBounds = thrusterEntity.visualBounds(relativeTo: physicsRootEntity)
            let localPosition = Self.effectAnchor(in: nozzleBounds, direction: exhaust)
            let plume = makeExhaustPlume(
                name: "rcs-plume-\(thruster.rawValue)",
                length: 0.055,
                radius: 0.007,
                core: UIColor(red: 0.82, green: 0.95, blue: 1.0, alpha: 0.95),
                envelope: UIColor(red: 0.45, green: 0.78, blue: 1.0, alpha: 0.7),
                birthRate: 90,
                speed: 0.22,
                lifeSpan: 0.18,
                particleSize: 0.004
            )
            plume.position = localPosition
            plume.orientation = rotationAligningPositiveY(to: exhaust)
            physicsRootEntity.addChild(plume)

            thrusters[thruster] = RCSThrusterData(
                thruster: thruster,
                entity: thrusterEntity,
                localPosition: localPosition,
                localDirection: localDirection,
                plumeEntity: plume
            )
        }
    }

    private func configureDPSPlume(on physicsRootEntity: ModelEntity) {
        let plume = makeExhaustPlume(
            name: "DPSPlume",
            length: 0.18,
            radius: 0.038,
            core: UIColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 0.95),
            envelope: UIColor(red: 1.0, green: 0.45, blue: 0.12, alpha: 0.8),
            birthRate: 220,
            speed: 0.45,
            lifeSpan: 0.28,
            particleSize: 0.012
        )
        let baseExhaust = SIMD3<Float>(0, -1, 0)
        if let dpsBellEntity {
            let bellBounds = dpsBellEntity.visualBounds(relativeTo: physicsRootEntity)
            plume.position = Self.effectAnchor(in: bellBounds, direction: baseExhaust)
            dpsPlumeBaseOffset = plume.position - dpsBellPivotPosition
        } else {
            plume.position = SIMD3(0, -0.14, 0)
            dpsPlumeBaseOffset = plume.position
        }
        plume.orientation = rotationAligningPositiveY(to: baseExhaust)
        physicsRootEntity.addChild(plume)
        plumeEntity = plume
    }

    private func applyDPSGimbal(pitchRadians: Double, rollRadians: Double) {
        let thrustBody = LMDPSGimbalMap.thrustDirectionBody(
            pitchRadians: pitchRadians,
            rollRadians: rollRadians
        )
        let exhaustDirection = simd_normalize(SIMD3<Float>(
            -Float(thrustBody.x),
            -Float(thrustBody.z),
            Float(thrustBody.y)
        ))
        let gimbal = rotationAligningReferenceAxis(
            SIMD3<Float>(0, -1, 0),
            to: exhaustDirection
        )
        dpsBellEntity?.orientation = gimbal * dpsBellBaseOrientation
        plumeEntity?.position = dpsBellPivotPosition + gimbal.act(dpsPlumeBaseOffset)
        plumeEntity?.orientation = rotationAligningPositiveY(to: exhaustDirection)
    }

    private func makeExhaustPlume(
        name: String,
        length: Float,
        radius: Float,
        core: UIColor,
        envelope: UIColor,
        birthRate: Float,
        speed: Float,
        lifeSpan: Double,
        particleSize: Float
    ) -> Entity {
        let root = Entity()
        root.name = name

        let envelopeMesh = makeTaperedPlumeMesh(
            name: "\(name)-envelope-mesh",
            length: length,
            startRadius: radius * 0.08,
            endRadius: radius
        )
        let envelopeCone = ModelEntity(
            mesh: envelopeMesh,
            materials: [UnlitMaterial(color: envelope)]
        )
        envelopeCone.name = "\(name)-envelope"
        root.addChild(envelopeCone)

        let coreMesh = makeTaperedPlumeMesh(
            name: "\(name)-core-mesh",
            length: length * 0.72,
            startRadius: radius * 0.04,
            endRadius: radius * 0.38
        )
        let coreCone = ModelEntity(
            mesh: coreMesh,
            materials: [UnlitMaterial(color: core)]
        )
        coreCone.name = "\(name)-core"
        root.addChild(coreCone)

        var particles = ParticleEmitterComponent.Presets.sparks
        particles.emitterShape = .point
        particles.birthDirection = .local
        particles.speed = speed
        particles.isEmitting = false
        particles.mainEmitter.birthRate = birthRate
        particles.mainEmitter.lifeSpan = lifeSpan
        particles.mainEmitter.lifeSpanVariation = lifeSpan * 0.25
        particles.mainEmitter.size = particleSize
        particles.mainEmitter.sizeVariation = particleSize * 0.35
        particles.mainEmitter.spreadingAngle = 0.18
        particles.mainEmitter.stretchFactor = 6
        particles.mainEmitter.color = .evolving(
            start: .single(core),
            end: .single(envelope.withAlphaComponent(0))
        )
        root.components.set(particles)

        setExhaustFiring(root, firing: false)
        return root
    }

    private func makeTaperedPlumeMesh(
        name: String,
        length: Float,
        startRadius: Float,
        endRadius: Float,
        segments: Int = 20
    ) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(segments * 2)
        indices.reserveCapacity(segments * 6)

        for segment in 0..<segments {
            let angle = Float(segment) / Float(segments) * 2 * .pi
            let radial = SIMD2<Float>(cos(angle), sin(angle))
            positions.append(SIMD3(radial.x * startRadius, 0, radial.y * startRadius))
            positions.append(SIMD3(radial.x * endRadius, length, radial.y * endRadius))
        }

        for segment in 0..<segments {
            let next = (segment + 1) % segments
            let start = UInt32(segment * 2)
            let end = start + 1
            let nextStart = UInt32(next * 2)
            let nextEnd = nextStart + 1
            indices.append(contentsOf: [start, end, nextStart, end, nextEnd, nextStart])
        }

        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        if let mesh = try? MeshResource.generate(from: [descriptor]) {
            return mesh
        }
        return MeshResource.generateCone(height: length, radius: endRadius)
    }

    private func setExhaustFiring(_ plume: Entity, firing: Bool) {
        for child in plume.children {
            child.isEnabled = firing
        }
        if var particles = plume.components[ParticleEmitterComponent.self] {
            particles.isEmitting = firing
            plume.components.set(particles)
        }
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

    static func effectAnchor(in bounds: BoundingBox, direction: SIMD3<Float>) -> SIMD3<Float> {
        let normalized = simd_length(direction) > 0 ? simd_normalize(direction) : SIMD3<Float>(0, 1, 0)
        let halfExtents = bounds.extents * 0.5
        let epsilon: Float = 1e-5
        return bounds.center + SIMD3(
            abs(normalized.x) < epsilon ? 0 : (normalized.x > 0 ? halfExtents.x : -halfExtents.x),
            abs(normalized.y) < epsilon ? 0 : (normalized.y > 0 ? halfExtents.y : -halfExtents.y),
            abs(normalized.z) < epsilon ? 0 : (normalized.z > 0 ? halfExtents.z : -halfExtents.z)
        )
    }

    static func position(
        _ proposedPosition: SIMD3<Float>,
        keeping bounds: BoundingBox,
        orientation: simd_quatf,
        above floorY: Float
    ) -> SIMD3<Float> {
        let halfExtents = bounds.extents * 0.5
        var lowestOffset = Float.greatestFiniteMagnitude
        for x in [-halfExtents.x, halfExtents.x] {
            for y in [-halfExtents.y, halfExtents.y] {
                for z in [-halfExtents.z, halfExtents.z] {
                    let corner = bounds.center + SIMD3(x, y, z)
                    lowestOffset = min(lowestOffset, orientation.act(corner).y)
                }
            }
        }

        var constrained = proposedPosition
        constrained.y = max(constrained.y, floorY - lowestOffset)
        return constrained
    }
}
