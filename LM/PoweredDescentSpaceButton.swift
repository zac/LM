import SwiftUI

struct PoweredDescentSpaceButton: View {
    @Environment(MainMenuViewModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        Button {
            Task { @MainActor in
                switch appModel.descentSpaceState {
                case .open:
                    appModel.descentSpaceState = .inTransition
                    await dismissImmersiveSpace()
                case .closed:
                    appModel.descentSpaceState = .inTransition
                    switch await openImmersiveSpace(id: appModel.descentSpaceID) {
                    case .opened:
                        break
                    case .userCancelled, .error:
                        fallthrough
                    @unknown default:
                        appModel.descentSpaceState = .closed
                    }
                case .inTransition:
                    break
                }
            }
        } label: {
            Text(appModel.descentSpaceState == .open ? "Leave table" : "Tabletop descent")
        }
        .disabled(appModel.descentSpaceState == .inTransition)
        .fontWeight(.semibold)
    }
}
