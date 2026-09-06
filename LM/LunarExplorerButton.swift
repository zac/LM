import SwiftUI

struct LunarExplorerButton: View {
    @Environment(MainMenuViewModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            Task { @MainActor in
                switch appModel.lunarExplorerSpaceState {
                case .open:
                    appModel.lunarExplorerSpaceState = .inTransition
                    await dismissImmersiveSpace()
                case .closed:
                    if appModel.lunarExplorerSession.isExplorerExperience {
                        appModel.lunarExplorerSession.prepareForPresentation()
                    }
                    appModel.lunarExplorerSpaceState = .inTransition
                    switch await openImmersiveSpace(id: appModel.lunarExplorerSpaceID) {
                    case .opened:
                        openWindow(id: appModel.lunarExplorerControlsWindowID)
                    case .userCancelled, .error:
                        fallthrough
                    @unknown default:
                        appModel.lunarExplorerSpaceState = .closed
                    }
                case .inTransition:
                    break
                }
            }
        } label: {
            Label(
                appModel.lunarExplorerSpaceState == .open
                    ? "Leave Lunar Explorer"
                    : "Explore the Moon",
                systemImage: "globe.americas.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(appModel.lunarExplorerSpaceState == .inTransition)
        .fontWeight(.semibold)
    }
}
