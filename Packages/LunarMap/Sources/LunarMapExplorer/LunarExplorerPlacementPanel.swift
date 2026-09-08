import SwiftUI

/// Native adjustable controls let people position the globe while resting
/// their hands, without requiring a drag or physical movement.
struct LunarExplorerPlacementPanel: View {
    @Bindable var session: LunarExplorerSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Position globe", systemImage: "move.3d").font(.title2.weight(.semibold))
                Text("Place the Moon where it is comfortable to view.")
                    .foregroundStyle(.secondary)
                Text("Left and right")
                Slider(value: $session.globePosition.x, in: -1.4...1.4)
                    .accessibilityLabel("Globe horizontal position")
                Text("Lower and higher")
                Slider(value: $session.globePosition.y, in: -0.65...0.65)
                    .accessibilityLabel("Globe vertical position")
                Text("Nearer and farther")
                Slider(value: $session.globePosition.z, in: -2.5 ... -1.2)
                    .accessibilityLabel("Globe distance")
                Button("Place beside me again") {
                    session.globePosition = SIMD3(1.05, 0, -2.0)
                    session.globePlacementRevision += 1
                }
                Text("Placement stays still when you turn your head. You can also use the Digital Crown to recenter the experience.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }.padding(24)
        }.frame(width: dynamicTypeSize.isAccessibilitySize ? 680 : 460, height: 560)
    }
}
