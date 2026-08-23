import Foundation
import LMCore

struct LMCockpitCue: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case phase
        case altitude
        case contact
        case success
        case warning
        case failure
    }

    let id: LMCockpitExperienceDirector.Event
    let title: String
    let detail: String
    let kind: Kind
}

struct LMCockpitExperienceDirector: Equatable, Sendable {
    enum Event: String, CaseIterable, Sendable {
        case p64
        case p65
        case p66
        case oneHundredFeet
        case fiftyFeet
        case contact
        case softLanding
        case hardLanding
        case crashed
    }

    private(set) var emitted = Set<Event>()

    mutating func reset() {
        emitted.removeAll(keepingCapacity: true)
    }

    mutating func consume(
        program: Int?,
        landingPointDisplayActive: Bool = false,
        altitudeMeters: Double?,
        outcome: LMFlightOutcome?,
        hasSurfaceContact: Bool
    ) -> [LMCockpitCue] {
        var cues = [LMCockpitCue]()

        if program == 64 && landingPointDisplayActive {
            emit(
                .p64,
                title: "P64 · LANDING APPROACH",
                detail: "Read the N64 LPD angle on the commander window. PRO enables ACA redesignation.",
                kind: .phase,
                into: &cues
            )
        }
        if program == 65 {
            emit(
                .p65,
                title: "P65 · TERMINAL DESCENT",
                detail: "Automatic guidance. ATT HOLD plus a ROD pulse selects P66.",
                kind: .phase,
                into: &cues
            )
        }
        if program == 66 {
            emit(
                .p66,
                title: "P66 · RATE OF DESCENT",
                detail: "ACA controls attitude. ROD changes commanded descent rate.",
                kind: .phase,
                into: &cues
            )
        }
        if let altitudeMeters, outcome == .inFlight {
            if altitudeMeters <= 100 * 0.3048 {
                emit(
                    .oneHundredFeet,
                    title: "100 FEET",
                    detail: "Check horizontal velocity, attitude, and landing area.",
                    kind: .altitude,
                    into: &cues
                )
            }
            if altitudeMeters <= 50 * 0.3048 {
                emit(
                    .fiftyFeet,
                    title: "50 FEET",
                    detail: "Hold a stable descent. Prepare for probe contact.",
                    kind: .altitude,
                    into: &cues
                )
            }
        }
        if hasSurfaceContact {
            emit(
                .contact,
                title: "CONTACT",
                detail: "Landing-gear contact is confirmed by the simulation.",
                kind: .contact,
                into: &cues
            )
        }

        switch outcome {
        case .softLanding:
            emit(
                .softLanding,
                title: "SOFT LANDING",
                detail: "Contact criteria passed. Eagle is intact.",
                kind: .success,
                into: &cues
            )
        case .hardLanding:
            emit(
                .hardLanding,
                title: "HARD LANDING",
                detail: "The vehicle is intact, but touchdown exceeded soft-landing limits.",
                kind: .warning,
                into: &cues
            )
        case .crashed:
            emit(
                .crashed,
                title: "VEHICLE LOST",
                detail: "Touchdown exceeded the modeled landing-gear envelope.",
                kind: .failure,
                into: &cues
            )
        case .inFlight, .none:
            break
        }

        return cues
    }

    private mutating func emit(
        _ event: Event,
        title: String,
        detail: String,
        kind: LMCockpitCue.Kind,
        into cues: inout [LMCockpitCue]
    ) {
        guard emitted.insert(event).inserted else { return }
        cues.append(LMCockpitCue(id: event, title: title, detail: detail, kind: kind))
    }
}
