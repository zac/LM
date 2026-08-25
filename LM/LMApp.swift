import SwiftUI

@main
struct LMApp: App {
    @State private var viewModel = MainMenuViewModel()

    var body: some Scene {
        WindowGroup(id: viewModel.descentConsoleWindowID) {
            if ProcessInfo.processInfo.arguments.contains("--mission-control-preview") {
                CockpitMissionControlWindow()
                    .environment(viewModel)
            } else if ProcessInfo.processInfo.arguments.contains("--fdai-preview") {
                FDAITexturePreviewView()
            } else {
                PoweredDescentView()
                    .environment(viewModel)
            }
        }
        .defaultSize(width: 980, height: 720)

        WindowGroup(id: viewModel.cockpitMissionControlWindowID) {
            CockpitMissionControlWindow()
                .environment(viewModel)
        }
        .defaultSize(width: 560, height: 300)
        .windowResizability(.contentSize)

        WindowGroup(id: "menu") {
            MainMenuView()
                .environment(viewModel)
        }
        .defaultSize(width: 400, height: 400)

        ImmersiveSpace(id: viewModel.moonSpaceID) {
            ImmersiveView()
                .environment(viewModel)
                .onAppear {
                    viewModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    viewModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.full), in: .full)

        ImmersiveSpace(id: viewModel.descentSpaceID) {
            PoweredDescentImmersiveView()
                .environment(viewModel)
                .onAppear {
                    viewModel.descentSpaceState = .open
                }
                .onDisappear {
                    viewModel.descentSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        ImmersiveSpace(id: viewModel.cockpitSpaceID) {
            TerminalDescentCockpitView()
                .environment(viewModel)
                .onAppear {
                    viewModel.cockpitSpaceState = .open
                }
                .onDisappear {
                    viewModel.cockpitSpaceState = .closed
                }
        }
        // The closed pressure cabin supplies visual occlusion while mixed
        // immersion allows native mission-control windows to coexist with the
        // physical cockpit controls.
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
