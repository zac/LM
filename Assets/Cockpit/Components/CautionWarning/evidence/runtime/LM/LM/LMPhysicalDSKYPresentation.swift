import AGC
import Foundation

/// A renderer-independent representation of the electroluminescent DSKY face.
/// It deliberately preserves one line per annunciator so the dim engraved
/// legends and their illuminated overlays share exact physical registration.
struct LMPhysicalDSKYPresentation: Equatable, Sendable {
    private static let annunciators: [(id: Int?, label: String)] = [
        (nil, "COMP ACTY"),
        (11, "UPLINK ACTY"),
        (12, "NO ATT"),
        (13, "STBY"),
        (14, "KEY REL"),
        (15, "OPR ERR"),
        (21, "TEMP"),
        (22, "GIMBAL LOCK"),
        (23, "PROG"),
        (24, "RESTART"),
        (25, "TRACKER"),
        (26, "ALT"),
        (27, "VEL"),
    ]

    static let annunciatorLegendText = annunciators.map(\.label).joined(separator: "\n")

    let header: String
    let registerText: String
    let activeAnnunciatorText: String

    init(snapshot: DSKYSnapshot?) {
        guard let snapshot else {
            header = "waiting for AGC"
            registerText = "PROG --\nVERB --  NOUN --\n\n------\n------\n------"
            activeAnnunciatorText = Self.annunciators.map { _ in " " }.joined(separator: "\n")
            return
        }

        let program = Self.displayField(snapshot.mode, blank: "--")
        let verb = Self.displayField(snapshot.verb, blank: "--")
        let noun = Self.displayField(snapshot.noun, blank: "--")
        header = "P\(program) V\(verb) N\(noun)"
        registerText = [
            "PROG \(program)",
            "VERB \(verb)  NOUN \(noun)",
            "",
            Self.displayRegister(snapshot.r1),
            Self.displayRegister(snapshot.r2),
            Self.displayRegister(snapshot.r3),
        ].joined(separator: "\n")

        activeAnnunciatorText = Self.annunciators.map { item in
            let isOn: Bool
            if snapshot.lampTest {
                isOn = true
            } else if item.id == nil {
                isOn = snapshot.compActy
            } else {
                isOn = snapshot.indicatorIsOn(item.id!)
            }
            return isOn ? item.label : " "
        }.joined(separator: "\n")
    }

    var signature: String {
        registerText + "\u{1F}" + activeAnnunciatorText
    }

    private static func displayField(_ value: String, blank: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? blank : trimmed
    }

    private static func displayRegister(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "------" : trimmed
    }
}
