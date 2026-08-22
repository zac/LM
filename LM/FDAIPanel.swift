import LMCore
import RealityKit
import RealityKitContent
import SwiftUI
import simd

enum FDAIOrientation {
    /// RealityKit's sphere faces longitude 270° at its authored orientation.
    /// Rotate the texture frame 90° so zero pitch is under the fixed wing.
    static let textureAlignment = simd_quatf(
        angle: .pi / 2,
        axis: SIMD3<Float>(0, 1, 0)
    )

    /// This simulation begins at PDI with the LM already pitched 95° in its
    /// site-local world frame. The FDAI is referenced to the inertial platform,
    /// so that world-frame setup attitude must not be painted onto the ball.
    static let poweredDescentReferenceAttitude =
        LMPoweredDescentScenario.apollo11SourceBacked.initialState.attitude

    static func relativeAttitude(
        _ attitude: LMQuaternion,
        reference: LMQuaternion
    ) -> LMQuaternion {
        reference.conjugated.multiplied(by: attitude).normalized()
    }

    /// The FDAI ball is an inertial reference inside the spacecraft, so it moves
    /// opposite the reference-relative vehicle attitude while the bezel stays fixed.
    static func ballOrientation(
        for attitude: LMQuaternion,
        relativeTo reference: LMQuaternion = .identity
    ) -> simd_quatf {
        let relative = relativeAttitude(attitude, reference: reference)
        let vehicleOrientation = LMWorldMapper.tabletop.orientation(from: relative)
        return simd_normalize(vehicleOrientation.inverse * textureAlignment)
    }

    /// NASA P/Q/R gimbal degrees (CDUX/CDUY/CDUZ), expressed relative to the
    /// display's inertial reference rather than the simulation's site-local frame.
    static func nasaGimbalDegrees(
        for attitude: LMQuaternion,
        relativeTo reference: LMQuaternion = .identity
    ) -> (p: Double, q: Double, r: Double) {
        let relative = relativeAttitude(attitude, reference: reference)
        let radians = LMIMUGimbalMap.cduRadians(from: relative)
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
                .offset(x: 44, y: 4)
                .allowsHitTesting(false)

            Text(attitudeSummary)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Flight director attitude indicator")
        .accessibilityValue(attitudeSummary)
    }

    private var vehicleAttitude: LMQuaternion? {
        session.vehicleState?.attitude
    }

    private var ballRotation: simd_quatf {
        FDAIOrientation.ballOrientation(
            for: vehicleAttitude ?? FDAIOrientation.poweredDescentReferenceAttitude,
            relativeTo: FDAIOrientation.poweredDescentReferenceAttitude
        )
    }

    private var attitudeSummary: String {
        guard let attitude = vehicleAttitude else { return "attitude unavailable" }
        let gimbals = FDAIOrientation.nasaGimbalDegrees(
            for: attitude,
            relativeTo: FDAIOrientation.poweredDescentReferenceAttitude
        )
        return String(
            format: "ΔP %+.0f°  ΔQ %+.0f°  ΔR %+.0f°",
            gimbals.p,
            gimbals.q,
            gimbals.r
        )
    }
}

private struct FDAIInstrument: View {
    let ballOrientation: simd_quatf

    var body: some View {
        ZStack {
            Model3D(named: "FDAI", bundle: realityKitContentBundle) { model in
                model
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .rotation3DEffect(
                        rotation.angle,
                        axis: rotation.axis
                    )
            } placeholder: {
                ProgressView()
            }
            .frame(width: 178, height: 178)
            .offset(x: -20)

            FDAIFixedDisplay()
        }
    }

    private var rotation: (angle: Angle, axis: (x: CGFloat, y: CGFloat, z: CGFloat)) {
        let imaginary = ballOrientation.imag
        let magnitude = simd_length(imaginary)
        guard magnitude > 0.000_001 else {
            return (.zero, (x: 0, y: 0, z: 1))
        }
        let axis = imaginary / magnitude
        let angle = 2 * atan2(magnitude, ballOrientation.real)
        return (
            .radians(Double(angle)),
            (x: CGFloat(axis.x), y: CGFloat(axis.y), z: CGFloat(axis.z))
        )
    }
}

private struct FDAIFixedDisplay: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(white: 0.78), lineWidth: 1.25)
                .frame(width: 178, height: 178)

            ForEach(0..<72, id: \.self) { index in
                let isMajor = index.isMultiple(of: 6)
                let length: CGFloat = isMajor ? 12 : (index.isMultiple(of: 2) ? 8 : 5)
                let angle = CGFloat(index) * 5 * .pi / 180
                Rectangle()
                    .fill(.white)
                    .frame(width: isMajor ? 1.5 : 1, height: length)
                    .rotationEffect(.radians(Double(angle)))
                    .position(
                        x: 102.5 + sin(angle) * (98 - length / 2),
                        y: 102.5 - cos(angle) * (98 - length / 2)
                    )
            }

            Rectangle()
                .fill(.white)
                .frame(width: 49, height: 2)
                .position(x: 48, y: 102.5)
            Rectangle()
                .fill(.white)
                .frame(width: 49, height: 2)
                .position(x: 157, y: 102.5)
            Rectangle()
                .fill(.white)
                .frame(width: 2, height: 18)
                .position(x: 102.5, y: 29.5)
            Rectangle()
                .fill(.white)
                .frame(width: 2, height: 18)
                .position(x: 102.5, y: 175.5)
        }
        .frame(width: 205, height: 205)
    }
}
