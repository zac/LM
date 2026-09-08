import SwiftUI
import LunarMapExplorer

struct LunarExplorerControlsWindow: View {
    @Environment(MainMenuViewModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var didRestoreAutomatedSpace = false
    @State private var leavingForCockpit = false

    var body: some View {
        LunarExplorerControls(session: appModel.lunarExplorerSession) {
            Task { @MainActor in
                await dismissImmersiveSpace()
                if appModel.lunarExplorerSession.isExplorerExperience {
                    appModel.lunarExplorerSession.prepareForPresentation()
                }
                dismissWindow(id: appModel.lunarExplorerControlsWindowID)
            }
        } landInCockpit: {
            leavingForCockpit = true
            appModel.cockpitCoordinate = appModel.lunarExplorerSession.usesBundledSite ? nil
                : appModel.lunarExplorerSession.currentCoordinate
            appModel.session.stop()
            if appModel.cockpitCoordinate == nil { appModel.session.selectLandingSite(nil) }
            Task { @MainActor in
                await dismissImmersiveSpace()
                let result = await openImmersiveSpace(id: appModel.cockpitSpaceID)
                if case .opened = result { dismissWindow(id: appModel.lunarExplorerControlsWindowID) }
            }
        }
        .onDisappear {
            guard appModel.lunarExplorerSession.isExplorerExperience,
                  !leavingForCockpit, appModel.lunarExplorerSpaceState == .open else { return }
            appModel.lunarExplorerSession.prepareForPresentation()
            Task { @MainActor in await dismissImmersiveSpace() }
        }
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("--lunar-explorer"),
                  !didRestoreAutomatedSpace,
                  appModel.lunarExplorerSpaceState == .closed else { return }
            didRestoreAutomatedSpace = true
            appModel.lunarExplorerSpaceState = .inTransition
            switch await openImmersiveSpace(id: appModel.lunarExplorerSpaceID) {
            case .opened:
                if !LunarExplorerSession.presentsControls(arguments: arguments) {
                    dismissWindow(id: appModel.lunarExplorerControlsWindowID)
                }
            case .userCancelled, .error:
                fallthrough
            @unknown default:
                appModel.lunarExplorerSpaceState = .closed
            }
        }
    }
}


#Preview(immersionStyle: .full) {
    let model = MainMenuViewModel()
    LunarExplorerView(session: model.lunarExplorerSession)
        .environment(model)
}
