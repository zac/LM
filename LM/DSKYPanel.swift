import SwiftUI
import AGC

struct DSKYKeyItem: Identifiable {
    let code: DSKYKeyCode
    let accent: Bool

    var id: String { code.label }
    var label: String { code.label }
}

enum DSKYIndicatorLabel {
    static let labels: [Int: String] = [
        11: "UPLINK ACTY",
        12: "NO ATT",
        13: "STBY",
        14: "KEY REL",
        15: "OPER ERR",
        21: "TEMP",
        22: "GIMBAL LOCK",
        23: "PROG",
        24: "RESTART",
        25: "TRACKER",
        26: "ALT",
        27: "VEL"
    ]
}

struct DSKYKeyButtonStyle: ButtonStyle {
    let accent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(accent ? Color.yellow : Color.white.opacity(0.9))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent ? Color.yellow.opacity(configuration.isPressed ? 0.35 : 0.18)
                          : Color.white.opacity(configuration.isPressed ? 0.16 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
    }
}

struct DSKYPanel: View {
    @Bindable var session: PoweredDescentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            display
            scripts
            keypad
        }
        .padding(16)
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var display: some View {
        if let dsky = session.dsky {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(dsky.lampTest ? "LAMP TEST" : "DSKY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(dsky.lampTest ? .yellow : .green)
                    Spacer()
                    Text("MCT \(session.snapshot?.agc.cycle ?? 0)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 16) {
                    indicatorGrid(state: dsky)
                    registerDisplay(state: dsky)
                }
            }
        } else {
            Text(session.loadMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var scripts: some View {
        HStack(spacing: 8) {
            ForEach([DSKYScript.v35e, .v37e63e, .v37e64e, .v37e65e, .v37e66e, .reset]) { script in
                Button(script.id) {
                    session.sendDSKYScript(script)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(session.snapshot == nil)
            }
        }
    }

    private var keypad: some View {
        VStack(spacing: 8) {
            ForEach(Array(keypadRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { key in
                        Button {
                            session.sendDSKYKey(key.code)
                        } label: {
                            Text(key.label)
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(DSKYKeyButtonStyle(accent: key.accent))
                        .disabled(session.snapshot == nil)
                    }
                }
            }
        }
    }

    private func indicatorGrid(state: DSKYSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(indicatorRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    indicatorCell(for: row.left, state: state)
                    indicatorCell(for: row.right, state: state)
                }
            }
        }
    }

    private func registerDisplay(state dsky: DSKYSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                readout("PROG", dsky.mode, flashing: false)
                readout("VERB", dsky.verb, flashing: dsky.verbNounFlash)
                readout("NOUN", dsky.noun, flashing: dsky.verbNounFlash)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(dsky.r1)
                Text(dsky.r2)
                Text(dsky.r3)
            }
            .font(.system(.title2, design: .monospaced))
            .foregroundStyle(.green)
            HStack(spacing: 12) {
                Text(dsky.compActy ? "COMP ACTY" : "COMP")
                    .foregroundStyle(dsky.compActy ? .green : .secondary)
                Text("PRO")
                    .foregroundStyle(dsky.proKeyPressed ? .green : .secondary)
            }
            .font(.caption)
        }
    }

    private func readout(_ label: String, _ value: String, flashing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(flashing ? .yellow : .green)
        }
    }

    @ViewBuilder
    private func indicatorCell(for id: Int?, state: DSKYSnapshot) -> some View {
        if let id {
            let isOn = state.indicatorIsOn(id) || state.lampTest
            let label = DSKYIndicatorLabel.labels[id] ?? " "
            HStack(spacing: 6) {
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundStyle(isOn ? Color.yellow : Color.white.opacity(0.2))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(isOn ? Color.yellow : Color.white.opacity(0.45))
            }
            .frame(width: 110, alignment: .leading)
        }
    }

    private var keypadRows: [[DSKYKeyItem]] {
        [
            [
                DSKYKeyItem(code: .verb, accent: true),
                DSKYKeyItem(code: .noun, accent: true),
                DSKYKeyItem(code: .pro, accent: true),
                DSKYKeyItem(code: .keyRelease, accent: true)
            ],
            [
                DSKYKeyItem(code: .digit7, accent: false),
                DSKYKeyItem(code: .digit8, accent: false),
                DSKYKeyItem(code: .digit9, accent: false),
                DSKYKeyItem(code: .plus, accent: true)
            ],
            [
                DSKYKeyItem(code: .digit4, accent: false),
                DSKYKeyItem(code: .digit5, accent: false),
                DSKYKeyItem(code: .digit6, accent: false),
                DSKYKeyItem(code: .minus, accent: true)
            ],
            [
                DSKYKeyItem(code: .digit1, accent: false),
                DSKYKeyItem(code: .digit2, accent: false),
                DSKYKeyItem(code: .digit3, accent: false),
                DSKYKeyItem(code: .enter, accent: true)
            ],
            [
                DSKYKeyItem(code: .clear, accent: true),
                DSKYKeyItem(code: .digit0, accent: false),
                DSKYKeyItem(code: .reset, accent: true)
            ]
        ]
    }

    private var indicatorRows: [(left: Int?, right: Int?)] {
        [
            (11, 21),
            (12, 22),
            (13, 23),
            (14, 24),
            (15, 25),
            (16, 26),
            (17, 27)
        ]
    }
}
