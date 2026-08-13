import SwiftUI
import RealityKit
import LMCore

struct PoweredDescentImmersiveView: View {
    @Environment(MainMenuViewModel.self) private var appModel
    @State private var module = LunarModuleModel(mode: .kinematicGuidance)
    @State private var pad = LunarPadEntity()

    var body: some View {
        RealityView { content in
            let padEntity = pad.root
            padEntity.position = SIMD3(0, 0.75, -1.2)
            padEntity.addChild(module.rootEntity)
            content.add(padEntity)
            applySnapshot()
        } update: { _ in
            applySnapshot()
        }
        .gesture(
            DragGesture()
                .targetedToEntity(pad.root)
                .onChanged { value in
                    pad.root.position = value.convert(value.location3D, from: .local, to: .scene)
                }
        )
        .ornament(attachmentAnchor: .scene(.bottom)) {
            CrewControlPanel(session: appModel.session)
        }
        .ornament(attachmentAnchor: .scene(.leading)) {
            DSKYPanel(session: appModel.session)
                .frame(width: 440)
        }
    }

    private func applySnapshot() {
        let mapper = LMWorldMapper.tabletop
        if let state = appModel.session.vehicleState {
            module.apply(siState: state, mapper: mapper)
        }
        if let commands = appModel.session.vehicleCommands {
            module.setActiveJets(LMRCSJetMapping.thrusters(from: commands.rcsJets))
            let engineOn = commands.mainEngineOn && !commands.mainEngineOff
            module.setDPSThrust(newtons: commands.dps.commandedThrustNewtons, engineOn: engineOn)
        }
    }
}

#Preview(immersionStyle: .mixed) {
    PoweredDescentImmersiveView()
        .environment(MainMenuViewModel())
}
