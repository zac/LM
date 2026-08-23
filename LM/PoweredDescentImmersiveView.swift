import SwiftUI
import RealityKit
import LMCore

struct PoweredDescentImmersiveView: View {
    @Environment(MainMenuViewModel.self) private var appModel
    @State private var module = LunarModuleModel(mode: .kinematicGuidance)
    @State private var pad = LunarPadEntity()
    @State private var rangeStrip = DescentRangeStrip()

    var body: some View {
        RealityView { content in
            let padEntity = pad.root
            padEntity.position = SIMD3(0, 0.75, -1.2)
            padEntity.addChild(module.rootEntity)
            padEntity.addChild(rangeStrip.root)
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
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button("Auto-land") { appModel.session.start() }
                        .disabled(!appModel.session.canStart)
                    Button("Stop") { appModel.session.stop() }
                        .disabled(!appModel.session.canStop)
                    Button("Replay") { appModel.session.replay() }
                        .disabled(!appModel.session.canReplay)
                    Text(appModel.session.loadMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderedProminent)
                CrewControlPanel(session: appModel.session)
            }
        }
        .ornament(attachmentAnchor: .scene(.leading)) {
            HStack(alignment: .top, spacing: 12) {
                FDAIPanel(session: appModel.session)
                    .frame(width: 240)
                DSKYPanel(session: appModel.session)
                    .frame(width: 440)
            }
        }
    }

    private func applySnapshot() {
        let mapper = LMWorldMapper.tabletop
        let program = appModel.session.programNumber
        if let state = appModel.session.vehicleState {
            module.apply(siState: state, mapper: mapper, program: program)
            rangeStrip.apply(
                downrangeMeters: state.downrangeMeters,
                mapper: mapper,
                visible: true
            )
        }
        if let commands = appModel.session.vehicleCommands {
            module.setActiveJets(LMRCSJetMapping.thrusters(from: commands.rcsJets))
            let engineOn = commands.isMainEngineProducingThrust(
                outcome: appModel.session.vehicleState?.flightOutcome
            )
            module.setDPSThrust(newtons: commands.dps.commandedThrustNewtons, engineOn: engineOn)
        }
    }
}

#Preview(immersionStyle: .mixed) {
    PoweredDescentImmersiveView()
        .environment(MainMenuViewModel())
}
