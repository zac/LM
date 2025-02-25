//
//  LMApp.swift
//  LM
//
//  Created by Zac White on 1/25/25.
//

import SwiftUI

@main
struct LMApp: App {
    @State private var viewModel = MainMenuViewModel()

    var body: some Scene {
        WindowGroup {
            LunarLanderSimulationView()
        }

        WindowGroup {
            MainMenuView()
                .environment(viewModel)
        }
        .defaultSize(width: 400, height: 400)


        ImmersiveSpace(id: viewModel.immersiveSpaceID) {
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
    }
}
