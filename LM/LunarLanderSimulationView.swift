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
    var quaternion: simd_quatf = .init(angle: 0, axis: .zero)  // Store raw quaternion
    var angularVelocity: SIMD3<Float> = .zero
}

// After RCSThruster enum, add the following new struct

struct RCSThrusterData {
    let thruster: RCSThruster
    let entity: Entity
    let relativePosition: SIMD3<Float>
}

// MARK: - Main Simulation View

struct LunarLanderSimulationView: View {
    @State private var simulation = LunarLanderSimulation()

    var body: some View {
        VStack {
            RealityView { content in
                if let displayModel = simulation.displayModel {
                    content.add(displayModel)
                    print("Added display model to RealityView")
                }
            } update: { content in
                if let physics = simulation.modulePhysicsBody,
                   let display = simulation.displayModel {
                    // Update the display model's position and orientation based on physics
                    display.transform.rotation = physics.transform.rotation
                    display.transform.translation = physics.transform.translation
                    
                    // Update telemetry
                    simulation.updateTelemetry()
                }
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
    
    private func formatVector(_ vector: SIMD3<Float>) -> String {
        String(format: "%.1f, %.1f, %.1f", vector.x, vector.y, vector.z)
    }
    
    private func formatQuaternion(_ quat: simd_quatf) -> String {
        // Format as axis-angle for more intuitive reading
        let angle = 2 * acos(quat.real)
        let axis: SIMD3<Float>
        if angle == 0 {
            axis = .init(0, 1, 0)  // Default up vector when no rotation
        } else {
            axis = quat.imag / sin(angle/2)
        }
        return String(format: "%.1f° [%.1f,%.1f,%.1f]", 
                     angle * (180 / .pi),  // Convert to degrees
                     axis.x, axis.y, axis.z)
    }
}

// MARK: - Simulation Controller

/// This class loads the lunar module model from the realityKitContentBundle
/// and places it at the center of a transparent simulation volume. It provides
/// methods to apply thruster impulses for realistic RCS control.
@Observable
class LunarLanderSimulation {
    var sceneEntity: Entity?

    var modulePhysicsBody: HasPhysicsBody?
    var displayModel: Entity?
    
    // In class LunarLanderSimulation, remove the old thrusterEntities dictionary and add a new one:
    var thrusters: [RCSThruster: RCSThrusterData] = [:]
    
    // Define thruster positions relative to center (in meters)
    private let thrusterPositions: [RCSThruster: SIMD3<Float>] = [
        // Quad 1 (front right, +Z)
        .A1U: SIMD3<Float>(0.5, 0.5, 1.0),
        .A1F: SIMD3<Float>(0.5, -0.5, 1.0),
        .B1L: SIMD3<Float>(0.5, 0.5, 1.0),
        .B1D: SIMD3<Float>(0.5, -0.5, 1.0),
        
        // Quad 2 (front left, +X)
        .A2A: SIMD3<Float>(1.0, 0.5, 0.5),
        .A2D: SIMD3<Float>(1.0, -0.5, 0.5),
        .B2U: SIMD3<Float>(1.0, 0.5, 0.5),
        .B2L: SIMD3<Float>(1.0, -0.5, 0.5),
        
        // Quad 3 (rear left, -Z)
        .A3U: SIMD3<Float>(-0.5, 0.5, -1.0),
        .A3R: SIMD3<Float>(-0.5, -0.5, -1.0),
        .B3A: SIMD3<Float>(-0.5, 0.5, -1.0),
        .B3D: SIMD3<Float>(-0.5, -0.5, -1.0),
        
        // Quad 4 (rear right, -X)
        .A4R: SIMD3<Float>(-1.0, 0.5, -0.5),
        .A4D: SIMD3<Float>(-1.0, -0.5, -0.5),
        .B4U: SIMD3<Float>(-1.0, 0.5, -0.5),
        .B4F: SIMD3<Float>(-1.0, -0.5, -0.5)
    ]
    
    // Define thruster force directions
    private let thrusterDirections: [RCSThruster: SIMD3<Float>] = [
        // Quad 1
        .A1U: SIMD3<Float>(0, 1, 0),   // Up
        .A1F: SIMD3<Float>(0, 0, -1),  // Forward
        .B1L: SIMD3<Float>(-1, 0, 0),  // Left
        .B1D: SIMD3<Float>(0, -1, 0),  // Down
        
        // Quad 2
        .A2A: SIMD3<Float>(0, 0, -1),  // Aft
        .A2D: SIMD3<Float>(0, -1, 0),  // Down
        .B2U: SIMD3<Float>(0, 1, 0),   // Up
        .B2L: SIMD3<Float>(-1, 0, 0),  // Left
        
        // Quad 3
        .A3U: SIMD3<Float>(0, 1, 0),   // Up
        .A3R: SIMD3<Float>(1, 0, 0),   // Right
        .B3A: SIMD3<Float>(0, 0, -1),  // Aft
        .B3D: SIMD3<Float>(0, -1, 0),  // Down
        
        // Quad 4
        .A4R: SIMD3<Float>(1, 0, 0),   // Right
        .A4D: SIMD3<Float>(0, -1, 0),  // Down
        .B4U: SIMD3<Float>(0, 1, 0),   // Up
        .B4F: SIMD3<Float>(0, 0, 1)    // Forward
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
    
    func updateTelemetry() {
        guard let physics = modulePhysicsBody else { return }
        DispatchQueue.main.async {
            // Update telemetry from physics calculations
            self.telemetry.position = physics.transform.translation
            self.telemetry.quaternion = physics.transform.rotation
        }
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    /// Loads the "lm" scene from the realityKitContentBundle
    func loadLunarModule() {
        do {
            sceneEntity = try Entity.load(named: "lm", in: realityKitContentBundle)

            // Get the lander geometry and its bounds
            if let landerGeometry = sceneEntity?.findEntity(named: "lunarlander") {
                // Clone and set up the display model with proper scaling and zero translation
                displayModel = landerGeometry.clone(recursive: true)
                displayModel?.scale = SIMD3<Float>(repeating: 0.05)
                
                // Add physics component directly to the display model if it doesn't exist
                if let displayEntity = displayModel, displayEntity.components[PhysicsBodyComponent.self] == nil {
                    print("Adding physics body to display model")
                    var physicsBody = PhysicsBodyComponent()
                    
                    // Configure with more appropriate mass and inertia for a lunar lander
                    physicsBody.massProperties = .init(mass: 100.0)  // Increased mass for better stability
                    physicsBody.material = .generate(friction: 0.5, restitution: 0.2)
                    physicsBody.mode = .dynamic
                    physicsBody.isAffectedByGravity = true  // Make sure gravity affects the lander
                    physicsBody.linearDamping = 0.1  // Add some damping to prevent excessive movement
                    physicsBody.angularDamping = 0.2  // Add some angular damping
                    
                    displayEntity.components[PhysicsBodyComponent.self] = physicsBody
                    modulePhysicsBody = displayEntity as? HasPhysicsBody
                    
                    print("Configured physics body with mass: \(physicsBody.massProperties.mass)")
                }
            }

            // Define the thruster mapping (using the same group names as before)
            let thrusterMapping: [String: RCSThruster] = [
                "group13_10": .A1U,
                "group13_11": .A1F,
                "group13_12": .B1L,
                "group13_13": .B1D,
                "group13_14": .A2A,
                "group13_g1": .A2D,
                "group13_g2": .B2U,
                "group13_g3": .B2L,
                "group13_g4": .A3U,
                "group13_g5": .A3R,
                "group13_g6": .B3A,
                "group13_g7": .B3D,
                "group13_g8": .A4R,
                "group13_g9": .A4D,
                "group13_gr": .B4U,
                "group13_p1": .B4F
            ]

            // First try to find the physics entity
            if let physicsEntity = sceneEntity?.findEntity(named: "Physics") as? Entity {
                if let hasPhysics = physicsEntity as? HasPhysicsBody {
                    modulePhysicsBody = hasPhysics
                } else {
                    // If the physics entity doesn't have a physics body, add one
                    print("Physics entity found but no physics body component, adding one")
                    var physicsBody = PhysicsBodyComponent()
                    physicsBody.massProperties = .init(mass: 10.0)
                    physicsBody.material = .generate(friction: 0.5, restitution: 0.2)
                    physicsBody.mode = .dynamic
                    physicsEntity.components[PhysicsBodyComponent.self] = physicsBody
                    modulePhysicsBody = physicsEntity as? HasPhysicsBody
                }
            } else if modulePhysicsBody == nil, let displayEntity = displayModel as? HasPhysicsBody {
                // If no physics entity was found and we haven't set modulePhysicsBody yet,
                // use the display model as the physics body
                print("No Physics entity found, using display model for physics")
                modulePhysicsBody = displayEntity
            }
            
            // Print physics body status
            if let physicsBody = modulePhysicsBody {
                print("Physics body configured: \(physicsBody)")
            } else {
                print("WARNING: No physics body found or created!")
            }

            // Now set up thrusters
            for (groupName, thruster) in thrusterMapping {
                if let thrusterEntity = displayModel?.findEntity(named: groupName) {
                    // Get world transform of thruster
                    let worldTransform = thrusterEntity.transform
                    
                    // Convert to physics entity's local space
                    let physicsTransform = (modulePhysicsBody as? Entity)?.transform ?? .identity
                    let relativePosition = worldTransform.translation - physicsTransform.translation
                    
                    // Create a simple visual marker
                    let marker = ModelEntity(mesh: .generateSphere(radius: 0.05), materials: [UnlitMaterial(color: .red)])
                    thrusterEntity.addChild(marker)
                    
                    // Store the thruster data
                    thrusters[thruster] = RCSThrusterData(thruster: thruster, entity: thrusterEntity, relativePosition: relativePosition)
                    print("Stored thruster \(thruster) with relative position \(relativePosition)")
                }
            }
        } catch {
            print("Failed to load lunar-module scene: \(error)")
        }
    }
    
    // MARK: - Thruster Functions
    
    /// Fires a specific RCS thruster
    private func fireThruster(_ thruster: RCSThruster) {
        guard let module = modulePhysicsBody else { 
            print("No physics body available")
            return 
        }
        
        let thrusterForce: Float = 10000.0  // Significantly increased force for more noticeable effect
        
        guard let thrusterData = thrusters[thruster], 
              let direction = thrusterDirections[thruster] else {
            print("Missing thruster data or direction for \(thruster)")
            return
        }
        
        // Create a visual effect for the thruster
        let thrusterEffect = ModelEntity(
            mesh: .generateBox(size: 0.1),
            materials: [UnlitMaterial(color: .orange.withAlphaComponent(0.7))]
        )
        thrusterData.entity.addChild(thrusterEffect)
        
        thrusterEffect.scale = .zero
        withAnimation(.easeOut(duration: 0.2)) {
            thrusterEffect.scale = .init(repeating: 1.0)
            thrusterEffect.model?.materials = [UnlitMaterial(color: .orange.withAlphaComponent(0))]
        } completion: {
            thrusterEffect.removeFromParent()
        }

        // Convert force direction from world space to physics body's local space
        let rotation = module.transform.rotation
        let localForce = rotation.act(direction) * thrusterForce
        
        // Apply the force using the HasPhysicsBody protocol
        module.addForce(localForce, at: thrusterData.relativePosition, relativeTo: sceneEntity)
        
        // Also apply a direct impulse for immediate effect
        let impulseForce = localForce * 0.1
        module.addForce(impulseForce, at: thrusterData.relativePosition, relativeTo: sceneEntity)
        
        print("Applied force \(localForce) and impulse \(impulseForce) for thruster \(thruster)")
    }
    
    /// Updated RCS control function that fires appropriate thrusters
    func fireRCSThruster(_ direction: RCSDirection) {
        switch direction {
        case .pitchUp:
            fireThruster(.A2D)
            fireThruster(.B4U)
        case .pitchDown:
            fireThruster(.A2A)
            fireThruster(.B4F)
        case .yawLeft:
            fireThruster(.B2U)
            fireThruster(.A4D)
        case .yawRight:
            fireThruster(.B2L)
            fireThruster(.A4R)
        case .rollLeft:
            fireThruster(.A1F)
            fireThruster(.B3A)
        case .rollRight:
            fireThruster(.A1U)
            fireThruster(.B3D)
        case .translateForward:
            fireThruster(.A1F)
            fireThruster(.B4F)
        case .translateBackward:
            fireThruster(.A1U)
            fireThruster(.B4U)
        case .translateLeft:
            fireThruster(.A2A)
            fireThruster(.B3A)
        case .translateRight:
            fireThruster(.A2D)
            fireThruster(.B3D)
        case .translateUp:
            fireThruster(.B1D)
            fireThruster(.A3U)
        case .translateDown:
            fireThruster(.B1L)
            fireThruster(.A3R)
        }
    }
}
