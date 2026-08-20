import RealityKit
import RealityKitContent
import SwiftUI

/// A launch-argument-only visual check for the equirectangular FDAI texture.
/// Run the app with `--fdai-preview` to inspect both yaw-pole disks, the grid, and field seam.
struct FDAITexturePreviewView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("FDAI 8-ball texture check")
                .font(.title2.weight(.semibold))

            HStack(spacing: 16) {
                ball(pitch: -70, turn: 0, label: "north pole")
                ball(pitch: -20, turn: 0, label: "scale grid")
                ball(pitch: -20, turn: -90, label: "field seam")
                ball(pitch: 70, turn: 0, label: "south pole")
            }
        }
        .padding(32)
        .background(Color(white: 0.045).ignoresSafeArea())
    }

    private func ball(pitch: Double, turn: Double, label: String) -> some View {
        VStack(spacing: 8) {
            Model3D(named: "FDAI", bundle: realityKitContentBundle) { model in
                model
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .rotation3DEffect(.degrees(pitch), axis: (x: 1, y: 0, z: 0))
                    .rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0))
            } placeholder: {
                ProgressView()
            }
            .frame(width: 210, height: 360)

            Text(label)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    FDAITexturePreviewView()
}
