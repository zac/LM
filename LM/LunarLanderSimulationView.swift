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
    private let module = LunarModuleModel()
    
    var telemetry = LMTelemetry()
    var rootEntity: Entity { module.rootEntity }
    
    @ObservationIgnored
    private var updateTimer: Timer?
    
    init() {
        startTelemetryUpdates()
        updateTelemetry()
    }
    
    private func startTelemetryUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateTelemetry()
        }
    }
    
    func updateTelemetry() {
        guard let snapshot = module.currentTelemetry() else { return }
        DispatchQueue.main.async {
            self.telemetry = snapshot
        }
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    func resetSimulation() {
        module.reset()
        updateTelemetry()
    }
    
    private func fireThruster(_ thruster: RCSThruster) {
        module.fireThruster(thruster)
        updateTelemetry()
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
