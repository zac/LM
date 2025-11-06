//
//  LunarLanderSimulationView.swift
//  LM
//
//  Created by Zac White on 1/31/25.
//


import SwiftUI
import RealityKit
import RealityKitContent
import simd

// Add an enum to define RCS thruster control directions.
enum RCSDirection {
    case pitchUp, pitchDown, yawLeft, yawRight, rollLeft, rollRight, translateForward, translateBackward, translateLeft, translateRight, translateUp, translateDown
}

// Add an enum to define the specific RCS thrusters
enum RCSThruster: String {
    // Quad 1 (front right)
    case A1U, A1F, B1L, B1D
    // Quad 2 (front left) 
    case A2A, A2D, B2U, B2L
    // Quad 3 (rear left)
    case A3U, A3R, B3A, B3D
    // Quad 4 (rear right)
    case A4R, A4D, B4U, B4F
}

// Add a new struct for telemetry data
struct LMTelemetry {
    var position: SIMD3<Float> = .zero
    var quaternion: simd_quatf = simd_quatf()
    var angularVelocity: SIMD3<Float> = .zero
}

// After RCSThruster enum, add the following new struct

struct RCSThrusterData {
    let thruster: RCSThruster
    let entity: Entity
    let localPosition: SIMD3<Float>
    let localDirection: SIMD3<Float>
    let debugConeName: String
}

// MARK: - Main Simulation View

struct LunarLanderSimulationView: View {
    @State private var simulation = LunarLanderSimulation()
    @State private var hasAttachedRoot = false

    var body: some View {
        VStack {
            RealityView { content in
                if hasAttachedRoot == false {
                    content.add(simulation.rootEntity)
                    hasAttachedRoot = true
                    print("Attached simulation root to RealityView")
                }
            } update: { _ in
                simulation.updateTelemetry()
            }
            .frame(width: 800, height: 800)
            .ornament(attachmentAnchor: .scene(.bottom)) {
                controlPanel
            }
        }
    }
    
    var controlPanel: some View {
        HStack(spacing: 24) {
            // Telemetry Display
            telemetryReadout
            
            Divider()
            
            // Rotation Controls
            VStack(alignment: .leading) {
                Text("Rotation").font(.subheadline)
                
                HStack(spacing: 16) {
                    // Pitch Controls
                    VStack {
                        Button { simulation.fireRCSThruster(.pitchUp) } label: {
                            Image(systemName: "arrow.up")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        
                        Button { simulation.fireRCSThruster(.pitchDown) } label: {
                            Image(systemName: "arrow.down")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    // Yaw Controls
                    VStack {
                        Button { simulation.fireRCSThruster(.yawLeft) } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        
                        Button { simulation.fireRCSThruster(.yawRight) } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    // Roll Controls
                    VStack {
                        Button { simulation.fireRCSThruster(.rollLeft) } label: {
                            Image(systemName: "rotate.left")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        
                        Button { simulation.fireRCSThruster(.rollRight) } label: {
                            Image(systemName: "rotate.right")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            
            Divider()
            
            // Translation Controls
            VStack(alignment: .leading) {
                Text("Translation").font(.subheadline)
                
                HStack(spacing: 16) {
                    // Left/Right Controls
                    VStack {
                        Button { simulation.fireRCSThruster(.translateLeft) } label: {
                            Image(systemName: "arrow.left.square")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        
                        Button { simulation.fireRCSThruster(.translateRight) } label: {
                            Image(systemName: "arrow.right.square")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    // Forward/Backward Controls
                    VStack {
                        Button { simulation.fireRCSThruster(.translateForward) } label: {
                            Image(systemName: "arrow.up.square")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        
                        Button { simulation.fireRCSThruster(.translateBackward) } label: {
                            Image(systemName: "arrow.down.square")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    // Up/Down Controls
                    VStack {
                        Button { simulation.fireRCSThruster(.translateUp) } label: {
                            Image(systemName: "arrow.up.circle")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        
                        Button { simulation.fireRCSThruster(.translateDown) } label: {
                            Image(systemName: "arrow.down.circle")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            
            Divider()
            
            resetButton
        }
        .padding()
        .glassBackgroundEffect()
    }
    
    var telemetryReadout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Telemetry").font(.headline)
            
            Group {
                HStack {
                    Text("Position:")
                    Text(formatVector(simulation.telemetry.position))
                }
                HStack {
                    Text("Rotation:")
                    Text(formatQuaternion(simulation.telemetry.quaternion))
                }
                HStack {
                    Text("Angular Vel:")
                    Text(formatVector(simulation.telemetry.angularVelocity))
                }
            }
            .font(.system(.body, design: .monospaced))
        }
    }
    
    private var resetButton: some View {
        VStack {
            Button {
                simulation.resetSimulation()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .labelStyle(.titleAndIcon)
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private func formatVector(_ vector: SIMD3<Float>) -> String {
        String(format: "%.1f, %.1f, %.1f", vector.x, vector.y, vector.z)
    }
    
    private func formatQuaternion(_ quat: simd_quatf) -> String {
        // Format as axis-angle for more intuitive reading
        let normalized = simd_normalize(quat)
        let realPart = max(-1.0, min(1.0, normalized.real))
        let angle = 2 * acos(realPart)
        let halfAngle = angle * 0.5
        let divisor = sin(halfAngle)
        let axis: SIMD3<Float>

        if divisor.magnitude > 1e-4 {
            axis = normalized.imag / divisor
        } else {
            axis = SIMD3<Float>(0, 1, 0)  // Default up vector when rotation is tiny
        }

        return String(
            format: "%.1f° [%.1f,%.1f,%.1f]",
            angle * (180 / .pi),
            axis.x, axis.y, axis.z
        )
    }
}

// MARK: - Simulation Controller

/// This class loads the lunar module model from the realityKitContentBundle
/// and places it at the center of a transparent simulation volume. It provides
/// methods to apply thruster impulses for realistic RCS control.
@Observable
class LunarLanderSimulation {
    var sceneEntity: Entity?
    var displayModel: Entity?
    private var physicsRoot: ModelEntity?
    let rootEntity = Entity()

    var thrusters: [RCSThruster: RCSThrusterData] = [:]
    
    private let thrusterForceMagnitude: Float = 445.0  // Approximate 100 lbf in Newtons
    private let minimumPulseDuration: Float = 0.05     // Seconds, minimum DAP pulse
    private var moduleMass: Float = 120.0
    private var collisionExtents: SIMD3<Float> = SIMD3<Float>(repeating: 0.5)
    private var inertiaTensor: SIMD3<Float> = SIMD3<Float>(repeating: 1.0)

    // Define thruster force directions
    private let thrusterDirections: [RCSThruster: SIMD3<Float>] = [
        // Quad 1
        .A1U: SIMD3<Float>(0, 1, 0),   // Up
        .A1F: SIMD3<Float>(0, 0, -1),  // Forward
        .B1L: SIMD3<Float>(-1, 0, 0),  // Left
        .B1D: SIMD3<Float>(0, -1, 0),  // Down

        // Quad 2
        .A2A: SIMD3<Float>(0, 0, 1),  // Aft
        .A2D: SIMD3<Float>(0, -1, 0),  // Down
        .B2U: SIMD3<Float>(0, 1, 0),   // Up
        .B2L: SIMD3<Float>(-1, 0, 0),  // Left

        // Quad 3
        .A3U: SIMD3<Float>(0, 1, 0),   // Up
        .A3R: SIMD3<Float>(1, 0, 0),   // Right
        .B3A: SIMD3<Float>(0, 0, 1),  // Aft
        .B3D: SIMD3<Float>(0, -1, 0),  // Down

        // Quad 4
        .A4R: SIMD3<Float>(1, 0, 0),   // Right
        .A4D: SIMD3<Float>(0, -1, 0),  // Down
        .B4U: SIMD3<Float>(0, 1, 0),   // Up
        .B4F: SIMD3<Float>(0, 0, -1)    // Forward
    ]

    var telemetry = LMTelemetry()
    @ObservationIgnored
    private var updateTimer: Timer?

    init() {
        loadLunarModule()
        startTelemetryUpdates()
    }

    private func startTelemetryUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateTelemetry()
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

    func updateTelemetry() {
        guard let moduleEntity = physicsRoot else { return }

        let position = moduleEntity.position(relativeTo: nil)
        let orientation = moduleEntity.orientation(relativeTo: nil)
        let angularVelocity = moduleEntity.components[PhysicsMotionComponent.self]?.angularVelocity ?? .zero

        DispatchQueue.main.async {
            self.telemetry.position = position
            self.telemetry.quaternion = orientation
            self.telemetry.angularVelocity = angularVelocity
        }
    }

    deinit {
        updateTimer?.invalidate()
    }

    /// Loads the "lm" scene from the realityKitContentBundle
    func loadLunarModule() {
        do {
            sceneEntity = try Entity.load(named: "lm", in: realityKitContentBundle)

            guard let landerGeometry = sceneEntity?.findEntity(named: "lunarlander") else {
                print("Unable to locate lunar lander entity in loaded scene")
                return
            }

            // Clone and scale the lander mesh so we can attach physics without mutating the source asset.
            let landerVisual = landerGeometry.clone(recursive: true)
            landerVisual.name = "LunarModuleMesh"
            landerVisual.transform = Transform(
                scale: SIMD3<Float>(repeating: 0.05),
                rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
                translation: .zero
            )

            let physicsWrapper = ModelEntity()
            physicsWrapper.name = "LunarModuleRoot"
            physicsWrapper.addChild(landerVisual)  // Keep wrapper at origin so the model renders in the window

            physicsRoot = physicsWrapper
            displayModel = physicsWrapper

            rootEntity.children.removeAll()
            rootEntity.addChild(physicsWrapper)

            // Generate collision shapes so RealityKit can compute realistic inertia tensors.
            landerVisual.generateCollisionShapes(recursive: true)

            let bounds = physicsWrapper.visualBounds(relativeTo: physicsWrapper)
            let extents = SIMD3<Float>(
                max(bounds.extents.x, 0.4),
                max(bounds.extents.y, 0.4),
                max(bounds.extents.z, 0.4)
            )
            let collisionShape = ShapeResource.generateBox(size: extents)
            physicsWrapper.components[CollisionComponent.self] = CollisionComponent(shapes: [collisionShape])

            var physicsBody = PhysicsBodyComponent()
            moduleMass = 120.0
            collisionExtents = extents
            let width = max(extents.x, 1e-3)
            let height = max(extents.y, 1e-3)
            let depth = max(extents.z, 1e-3)
            let oneTwelfthMass = moduleMass / 12.0
            inertiaTensor = SIMD3<Float>(
                oneTwelfthMass * (height * height + depth * depth),
                oneTwelfthMass * (width * width + depth * depth),
                oneTwelfthMass * (width * width + height * height)
            )
            
            physicsBody.massProperties = .init(shape: collisionShape, mass: moduleMass)
            physicsBody.material = .generate(friction: 0.0, restitution: 0.0)
            physicsBody.mode = .dynamic
            physicsBody.isAffectedByGravity = false
            physicsBody.linearDamping = 0.0
            physicsBody.angularDamping = 0.0
            physicsWrapper.components[PhysicsBodyComponent.self] = physicsBody
            physicsWrapper.components[PhysicsMotionComponent.self] = PhysicsMotionComponent()
            print("Configured physics wrapper with extents: \(extents)")

            // Define the thruster mapping (using the same group names as before)
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

            thrusters.removeAll()
            for (groupName, thruster) in thrusterMapping {
                guard
                    let thrusterEntity = physicsWrapper.findEntity(named: groupName),
                    let direction = thrusterDirections[thruster]
                else {
                    print("Missing thruster entity or direction for \(groupName)")
                    continue
                }

                let localPosition = thrusterEntity.position(relativeTo: physicsWrapper)
                let approximateDirection = simd_normalize(direction)
                let thrusterOrientation = thrusterEntity.orientation(relativeTo: physicsWrapper)
                let localDirection = resolvedThrusterDirection(approximate: approximateDirection, orientation: thrusterOrientation)

                let coneName = "thruster-debug-\(thruster.rawValue)"
                let coneDirection = simd_normalize(localDirection)
                let coneHeight: Float = 0.04
                let coneRadius: Float = 0.015
                if let existingCone = physicsWrapper.findEntity(named: coneName) as? ModelEntity {
                    existingCone.model?.materials = [UnlitMaterial(color: UIColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 0.8))]
                    existingCone.transform = Transform(
                        rotation: rotationAligningPositiveY(to: coneDirection),
                        translation: localPosition + coneDirection * (-coneHeight * 0.5)
                    )
                } else {
                    let coneMesh = MeshResource.generateCone(height: coneHeight, radius: coneRadius)
                    let marker = ModelEntity(
                        mesh: coneMesh,
                        materials: [UnlitMaterial(color: UIColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 0.8))]
                    )
                    marker.name = coneName
                    marker.transform = Transform(
                        rotation: rotationAligningPositiveY(to: coneDirection),
                        translation: localPosition + coneDirection * (-coneHeight * 0.5)
                    )
                    physicsWrapper.addChild(marker)
                }

                thrusters[thruster] = RCSThrusterData(
                    thruster: thruster,
                    entity: thrusterEntity,
                    localPosition: localPosition,
                    localDirection: localDirection,
                    debugConeName: coneName
                )
                print("Stored thruster \(thruster) at \(localPosition) dir \(localDirection)")
            }
        } catch {
            print("Failed to load lunar-module scene: \(error)")
        }
    }

    func resetSimulation() {
        guard let moduleEntity = physicsRoot else { return }

        var transform = moduleEntity.transform
        transform.translation = .zero
        transform.rotation = simd_quatf()
        moduleEntity.transform = transform

        if var motion = moduleEntity.components[PhysicsMotionComponent.self] {
            motion.linearVelocity = .zero
            motion.angularVelocity = .zero
            moduleEntity.components[PhysicsMotionComponent.self] = motion
        }

        print("Simulation reset to origin with zeroed velocities")
        updateTelemetry()
    }

    // MARK: - Thruster Functions

    /// Fires a specific RCS thruster
    private func fireThruster(_ thruster: RCSThruster) {
        guard
            let thrusterData = thrusters[thruster],
            let module = physicsRoot,
            var motion = module.components[PhysicsMotionComponent.self]
        else {
            print("Missing thruster data or physics root for \(thruster)")
            return
        }

        print("Thruster \(thruster.rawValue) fired at position \(thrusterData.localPosition), direction \(thrusterData.localDirection)")

        let length = simd_length(thrusterData.localDirection)
        let normalizedDirection = length > 0 ? thrusterData.localDirection / length : SIMD3<Float>(0, 1, 0)
        let force = normalizedDirection * thrusterForceMagnitude
        let impulse = force * minimumPulseDuration

        // Linear impulse contribution
        let deltaLinearVelocity = impulse / moduleMass
        motion.linearVelocity += deltaLinearVelocity

        // Angular impulse contribution (torque = r x F)
        let torque = simd_cross(thrusterData.localPosition, force)
        let angularImpulse = torque * minimumPulseDuration
        let deltaAngularVelocity = SIMD3<Float>(
            inertiaTensor.x > 0 ? angularImpulse.x / inertiaTensor.x : 0,
            inertiaTensor.y > 0 ? angularImpulse.y / inertiaTensor.y : 0,
            inertiaTensor.z > 0 ? angularImpulse.z / inertiaTensor.z : 0
        )
        motion.angularVelocity += deltaAngularVelocity

        module.components[PhysicsMotionComponent.self] = motion

        // Highlight the thruster's debug cone in red while firing.
        let coneName = thrusterData.debugConeName
        if let debugCone = module.findEntity(named: coneName) as? ModelEntity {
            let onMaterial = UnlitMaterial(color: UIColor(red: 1.0, green: 0.15, blue: 0.1, alpha: 0.95))
            let offMaterial = UnlitMaterial(color: UIColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 0.8))
            debugCone.model?.materials = [onMaterial]
            let highlightDurationMilliseconds = max(1, Int(minimumPulseDuration * 6_000))
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(highlightDurationMilliseconds)) {
                debugCone.model?.materials = [offMaterial]
            }
        }

    }

    /// Updated RCS control function that fires appropriate thrusters
    func fireRCSThruster(_ direction: RCSDirection) {
        switch direction {
        // ---------- ROTATION ----------
        case .pitchUp:
            // front-left aft + rear-right forward
            fireThruster(.A2A)
            fireThruster(.B4F)

        case .pitchDown:
            // front-right forward + rear-left aft
            fireThruster(.A1F)
            fireThruster(.B3A)

        case .yawLeft:
            // front-right left + rear-left right
            fireThruster(.B1L)
            fireThruster(.A3R)

        case .yawRight:
            // front-left left + rear-right right
            fireThruster(.B2L)
            fireThruster(.A4R)

        case .rollLeft:
            // right side up + left side down
            fireThruster(.B4U)   // rear-right up
            fireThruster(.A2D)   // front-left down

        case .rollRight:
            // right side down + left side up
            fireThruster(.A4D)   // rear-right down
            fireThruster(.A3U)   // rear-left up

        // ---------- TRANSLATION ----------
        case .translateForward:   // +Z
            fireThruster(.A1F)
            fireThruster(.B4F)

        case .translateBackward:  // –Z
            fireThruster(.A2A)
            fireThruster(.B3A)

        case .translateLeft:      // –Y
            fireThruster(.B1L)
            fireThruster(.B2L)   // (both front; expect small pitch torque)

        case .translateRight:     // +Y
            fireThruster(.A3R)
            fireThruster(.A4R)   // (both rear; expect small pitch torque)

        case .translateUp:        // +X (clean)
            fireThruster(.A1U)
            fireThruster(.B2U)
            fireThruster(.A3U)
            fireThruster(.B4U)

        case .translateDown:      // –X (clean)
            fireThruster(.B1D)
            fireThruster(.A2D)
            fireThruster(.B3D)
            fireThruster(.A4D)
        }
    }
}

#Preview {
    LunarLanderSimulationView()
}
