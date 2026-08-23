import SwiftUI

@main
struct LMApp: App {
    @State private var viewModel = MainMenuViewModel()

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--fdai-preview") {
                FDAITexturePreviewView()
            } else {
                PoweredDescentView()
                    .environment(viewModel)
            }
        }
        .defaultSize(width: 980, height: 720)

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

        ImmersiveSpace(id: viewModel.fullDescentSpaceID) {
            FullDescentWorldView()
                .environment(viewModel)
                .onAppear {
                    viewModel.fullDescentSpaceState = .open
                }
                .onDisappear {
                    viewModel.fullDescentSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
