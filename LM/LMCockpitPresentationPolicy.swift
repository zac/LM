import Foundation

/// App teaching aids are separate from flight hardware and DSKY output.
/// Recenter and mission restart deliberately do not replace this view-owned state.
struct LMCockpitPresentationPolicy: Equatable {
    private(set) var trainingEnabled = false
    private(set) var eyeAlignmentEnabled = false

    var showsCueOverlay: Bool { trainingEnabled }
    var showsCalledAngle: Bool { trainingEnabled }
    var showsEyeAlignment: Bool { trainingEnabled && eyeAlignmentEnabled }
    var usesDiagnosticPaneColors: Bool { showsEyeAlignment }

    mutating func toggleTraining() {
        trainingEnabled.toggle()
        if !trainingEnabled { eyeAlignmentEnabled = false }
    }

    mutating func toggleEyeAlignment() {
        guard trainingEnabled else { return }
        eyeAlignmentEnabled.toggle()
    }

    func landingPointHint(angleDegrees: Int?, windowClosed: Bool, redesignationEnabled: Bool) -> String {
        let subject = showsCalledAngle
            ? angleDegrees.map { "Training LPD \($0)°" } ?? "Training N64 LPD"
            : "DSKY N64"
        if windowClosed { return "\(subject) · redesignation window closed" }
        if redesignationEnabled { return "\(subject) · ACA redesignation enabled" }
        return "\(subject) · press PRO to enable ACA redesignation"
    }

    #if DEBUG
    static func validation(arguments: [String]) -> Self {
        var policy = Self()
        if arguments.contains("--cockpit-training-overlays") { policy.toggleTraining() }
        if arguments.contains("--cockpit-eye-alignment") { policy.toggleEyeAlignment() }
        return policy
    }
    #endif
}
