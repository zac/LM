import LMCore
import RealityKit
import RealityKitContent
import SwiftUI
import UIKit
import simd

enum FDAIOrientation {
    /// RealityKit's sphere faces longitude 270° at its authored orientation.
    /// Rotate the texture frame 90° so zero pitch is under the fixed wing.
    static let textureAlignment = simd_quatf(
        angle: .pi / 2,
        axis: SIMD3<Float>(0, 1, 0)
    )

    /// The FDAI ball is an inertial reference inside the spacecraft, so it moves
    /// opposite the vehicle attitude while the bezel and wing remain fixed.
    static func ballOrientation(for attitude: LMQuaternion) -> simd_quatf {
        let vehicleOrientation = LMWorldMapper.tabletop.orientation(from: attitude)
        return simd_normalize(vehicleOrientation.inverse * textureAlignment)
    }

    /// NASA P/Q/R gimbal degrees (CDUX/CDUY/CDUZ). PDI 95° about sim X is Q,
    /// not 3-2-1 Euler roll.
    static func nasaGimbalDegrees(for attitude: LMQuaternion) -> (p: Double, q: Double, r: Double) {
        let radians = LMIMUGimbalMap.cduRadians(from: attitude)
        func degrees(_ value: Double) -> Double { value * 180 / .pi }
        return (p: degrees(radians.x), q: degrees(radians.y), r: degrees(radians.z))
    }
}

struct FDAIPanel: View {
    @Bindable var session: PoweredDescentSession

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("FDAI")
                    .font(.caption.weight(.semibold))
                Spacer()
                Circle()
                    .fill(vehicleAttitude == nil ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                Text(vehicleAttitude == nil ? "NO ATT" : "ATT")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            FDAIInstrument(ballOrientation: ballRotation)
                .frame(width: 205, height: 205)

            Text(attitudeSummary)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Flight director attitude indicator")
        .accessibilityValue(attitudeSummary)
    }

    private var vehicleAttitude: LMQuaternion? {
        session.snapshot?.vehicleState.attitude
    }

    private var ballRotation: simd_quatf {
        FDAIOrientation.ballOrientation(for: vehicleAttitude ?? .identity)
    }

    private var attitudeSummary: String {
        guard let attitude = vehicleAttitude else { return "attitude unavailable" }
        let gimbals = FDAIOrientation.nasaGimbalDegrees(for: attitude)
        return String(
            format: "P %+.0f°  Q %+.0f°  R %+.0f°",
            gimbals.p,
            gimbals.q,
            gimbals.r
        )
    }
}

private struct FDAIInstrument: View {
    let ballOrientation: simd_quatf

    var body: some View {
        RealityView { content in
            if let ball = try? await Entity(named: "FDAI", in: realityKitContentBundle) {
                ball.name = "FDAIBall"
                ball.scale = SIMD3(repeating: 0.55)
                ball.position.x = 0.06
                ball.orientation = ballOrientation
                content.add(ball)
            }
            let fixedDisplay = Self.makeFixedDisplay()
            fixedDisplay.scale = SIMD3(repeating: 0.55)
            fixedDisplay.position.x = 0.06
            content.add(fixedDisplay)
        } update: { content in
            content.entities.first(where: { $0.name == "FDAIBall" })?.orientation = ballOrientation
        }
        .background(Color.black, in: Circle())
    }

    private static func makeFixedDisplay() -> Entity {
        let root = Entity()
        root.name = "FDAIFixedDisplay"
        let white = UnlitMaterial(color: UIColor.white)

        for index in 0..<72 {
            let isMajor = index.isMultiple(of: 6)
            let length: Float = isMajor ? 0.012 : (index.isMultiple(of: 2) ? 0.008 : 0.005)
            let angle = Float(index) * 5 * .pi / 180
            let radius: Float = 0.098
            let tick = ModelEntity(
                mesh: .generateBox(size: SIMD3(isMajor ? 0.0015 : 0.001, length, 0.001)),
                materials: [white]
            )
            tick.position = SIMD3(
                sin(angle) * (radius - length / 2),
                cos(angle) * (radius - length / 2),
                0.092
            )
            tick.orientation = simd_quatf(angle: -angle, axis: SIMD3(0, 0, 1))
            root.addChild(tick)
        }

        addBar(to: root, size: SIMD3(0.049, 0.002, 0.001), position: SIMD3(-0.0545, 0, 0.094), material: white)
        addBar(to: root, size: SIMD3(0.049, 0.002, 0.001), position: SIMD3(0.0545, 0, 0.094), material: white)
        addBar(to: root, size: SIMD3(0.002, 0.018, 0.001), position: SIMD3(0, 0.073, 0.094), material: white)
        addBar(to: root, size: SIMD3(0.002, 0.018, 0.001), position: SIMD3(0, -0.073, 0.094), material: white)
        return root
    }

    private static func addBar(
        to root: Entity,
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        material: UnlitMaterial
    ) {
        let bar = ModelEntity(mesh: .generateBox(size: size), materials: [material])
        bar.position = position
        root.addChild(bar)
    }
}
