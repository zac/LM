import SwiftUI

struct CrewControlPanel: View {
    @Bindable var session: PoweredDescentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Crew")
                .font(.headline)

            Toggle(
                "MODE CONTROL · ATT HOLD (P66)",
                isOn: Binding(
                    get: { session.attitudeMode == .attitudeHold },
                    set: { session.attitudeMode = $0 ? .attitudeHold : .automatic }
                )
            )
            .toggleStyle(.switch)

            HStack(alignment: .top, spacing: 20) {
                axisGroup("RHC pitch", plus: "arrow.up", minus: "arrow.down") { held, sign in
                    session.rhcPitch = held ? sign * PoweredDescentSession.rhcDeflection : 0
                }
                axisGroup("RHC yaw", plus: "arrow.clockwise", minus: "arrow.counterclockwise") { held, sign in
                    session.rhcYaw = held ? sign * PoweredDescentSession.rhcDeflection : 0
                }
                axisGroup("RHC roll", plus: "rotate.right", minus: "rotate.left") { held, sign in
                    session.rhcRoll = held ? sign * PoweredDescentSession.rhcDeflection : 0
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Rate")
                        .font(.subheadline)
                    holdButton("DESCENT+", systemImage: "minus.circle") {
                        session.setROD(.descendPlus, held: $0)
                    }
                    .help("Slow descent by 1 ft/s while held")
                    holdButton("DESCENT−", systemImage: "plus.circle") {
                        session.setROD(.descendMinus, held: $0)
                    }
                    .help("Increase descent by 1 ft/s while held")
                }
            }

            Text("ATT HOLD selects P66. ACA and ROD feed the live Luminary input channels.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .glassBackgroundEffect()
    }

    private func axisGroup(
        _ title: String,
        plus: String,
        minus: String,
        update: @escaping (Bool, Int) -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
            holdButton(nil, systemImage: plus) { update($0, 1) }
            holdButton(nil, systemImage: minus) { update($0, -1) }
        }
    }

    private func holdButton(_ title: String?, systemImage: String, setHeld: @escaping (Bool) -> Void) -> some View {
        Group {
            if let title {
                Label(title, systemImage: systemImage)
                    .frame(minWidth: 120, minHeight: 36)
            } else {
                Image(systemName: systemImage)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in setHeld(true) }
                .onEnded { _ in setHeld(false) }
        )
    }
}
