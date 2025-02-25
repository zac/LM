//
//  ImmersiveView.swift
//  LM
//
//  Created by Zac White on 1/25/25.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    @Environment(MainMenuViewModel.self) var appModel

    var body: some View {
        RealityView { content in
            // Add the initial RealityKit content
            content.add(MoonScene())
        }
    }
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(MainMenuViewModel())
}
