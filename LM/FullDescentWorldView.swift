import RealityKit
import SwiftUI

/// Full-immersion exterior scene for the commander-station cockpit. The user
/// stays fixed at the cockpit origin; the terrain world moves by the inverse
/// vehicle pose every frame the session publishes a snapshot.
struct FullDescentWorldView: View {
    @Environment(MainMenuViewModel.self) private var appModel
    @State private var worldRoot: Entity?
    @State private var loadError: String?

    var body: some View {
        RealityView { content in
            do {
                let assembly = try await LMTerrainWorld.load()
                content.add(assembly.worldRoot)
                worldRoot = assembly.worldRoot
            } catch {
                loadError = "Terrain unavailable: \(error.localizedDescription)"
            }
        } update: { _ in
            guard let worldRoot else { return }
            worldRoot.transform = LMTerrainWorld.worldTransform(
                for: appModel.session.snapshot?.vehicleState
            )
        }
        .overlay {
            if let loadError {
                Text(loadError)
                    .font(.callout)
                    .padding()
                    .glassBackgroundEffect()
            }
        }
    }
}
