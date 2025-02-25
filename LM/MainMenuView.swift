//
//  MainMenuView.swift
//  LM
//
//  Created by Zac White on 1/25/25.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct MainMenuView: View {
    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Model3D(named: "lunar-module", bundle: realityKitContentBundle) { model in
                        // Customize the model if needed
                        model
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100)
                    } placeholder: {
                        ProgressView()
                            .frame(width: 100)
                    }

                    Text("LM")
                        .font(.largeTitle)

                    Spacer()
                }
                .padding(.bottom)

                NewGameButton()
                
                // New button to open the LM Thruster Simulation
                NavigationLink(destination: LunarLanderSimulationView()) {
                    Text("LM Thruster Sim")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding(.vertical)

                Spacer()
            }
            .padding()
            .navigationTitle("Main Menu")
        }
    }
}

#Preview(windowStyle: .automatic) {
    MainMenuView()
        .environment(MainMenuViewModel())
        .frame(width: 200, height: 200)
}
