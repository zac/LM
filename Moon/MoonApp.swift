import LunarMap
import LunarMapExplorer
import SwiftUI

@main
struct MoonApp: App {
    @State private var model: MoonModel

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let options = LunarMapLaunchOptions(arguments: arguments)
        LunarMap.configure(options: options, logSubsystem: "io.positron.Moon")
        _model = State(wrappedValue: MoonModel(options: options, arguments: arguments))
    }

    var body: some Scene {
        WindowGroup(id: MoonModel.controlsID) {
            MoonControlsWindow(model: model)
        }
        .defaultSize(width: 420, height: 690)
        .windowResizability(.contentSize)

        ImmersiveSpace(id: MoonModel.spaceID) {
            LunarExplorerView(session: model.session)
                .onAppear { model.spaceState = .open }
                .onDisappear { model.spaceState = .closed }
        }
        .immersionStyle(selection: Bindable(model.session).immersionStyle,
                        in: .mixed, .progressive, .full)
    }
}

struct MoonControlsWindow: View {
    @Bindable var model: MoonModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        LunarExplorerControls(session: model.session, actions: .init(close: {
            Task { @MainActor in
                await dismissImmersiveSpace()
                if model.session.isExplorerExperience { model.session.prepareForPresentation() }
                dismissWindow(id: MoonModel.controlsID)
            }
        }))
        .toolbar {
            if model.spaceState == .closed {
                Button("Show Moon", systemImage: "moon.fill") {
                    Task { await presentMoon() }
                }
            }
        }
        .task { await presentMoon() }
        .onDisappear {
            guard model.session.isExplorerExperience, model.spaceState == .open else { return }
            model.session.prepareForPresentation()
            Task { @MainActor in await dismissImmersiveSpace() }
        }
    }

    @MainActor private func presentMoon() async {
        guard model.spaceState == .closed else { return }
        model.spaceState = .inTransition
        switch await openImmersiveSpace(id: MoonModel.spaceID) {
        case .opened:
            if !LunarExplorerSession.presentsControls(arguments: model.arguments) {
                dismissWindow(id: MoonModel.controlsID)
            }
        case .userCancelled, .error:
            fallthrough
        @unknown default:
            model.spaceState = .closed
        }
    }
}
