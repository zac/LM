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
    let spokenText: String?
}

struct LMCockpitExperienceDirector: Equatable, Sendable {
    enum Event: String, CaseIterable, Sendable {
        case p64
        case p65
        case p66
        case threeHundredFeet
        case twoHundredTwentyFeet
        case twoHundredFeet
        case oneHundredSixtyFeet
        case oneHundredTwentyFeet
        case oneHundredFeet
        case seventyFiveFeet
        case fortyFeet
        case thirtyFeet
        case contact
        case softLanding
        case hardLanding
        case crashed
    }

    /// Apollo 11 LMP landing callout altitudes from the raw NASA air-to-ground
    /// transcript, tape 66/11, page 316. The values are presentation gates;
    /// the rates paired with them always come from the live simulation.
    private static let terminalAltitudeCallouts: [(event: Event, feet: Int)] = [
        (.threeHundredFeet, 300),
        (.twoHundredTwentyFeet, 220),
        (.twoHundredFeet, 200),
        (.oneHundredSixtyFeet, 160),
        (.oneHundredTwentyFeet, 120),
        (.oneHundredFeet, 100),
        (.seventyFiveFeet, 75),
        (.fortyFeet, 40),
        (.thirtyFeet, 30),
    ]

    private(set) var emitted = Set<Event>()
    private var previousInFlightAltitudeFeet: Double?

    mutating func reset() {
        emitted.removeAll(keepingCapacity: true)
        previousInFlightAltitudeFeet = nil
    }

    mutating func consume(
        program: Int?,
        landingPointDisplayActive: Bool = false,
        altitudeMeters: Double?,
        verticalSpeedMetersPerSecond: Double? = nil,
        downrangeSpeedMetersPerSecond: Double? = nil,
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
                spokenText: "Program sixty-four. Landing approach.",
                into: &cues
            )
        }
        if program == 65 {
            emit(
                .p65,
                title: "P65 · TERMINAL DESCENT",
                detail: "Automatic guidance. ATT HOLD plus a ROD pulse selects P66.",
                kind: .phase,
                spokenText: "Program sixty-five. Terminal descent.",
                into: &cues
            )
        }
        if program == 66 {
            emit(
                .p66,
                title: "P66 · RATE OF DESCENT",
                detail: "ACA controls attitude. ROD changes commanded descent rate.",
                kind: .phase,
                spokenText: "Program sixty-six. Rate of descent.",
                into: &cues
            )
        }
        if let altitudeMeters, outcome == .inFlight {
            let altitudeFeet = max(altitudeMeters / 0.3048, 0)
            if let previousInFlightAltitudeFeet, altitudeFeet <= previousInFlightAltitudeFeet {
                for callout in Self.terminalAltitudeCallouts where
                    previousInFlightAltitudeFeet > Double(callout.feet)
                        && altitudeFeet <= Double(callout.feet)
                {
                    emitTelemetryCallout(
                        callout,
                        verticalSpeedMetersPerSecond: verticalSpeedMetersPerSecond,
                        downrangeSpeedMetersPerSecond: downrangeSpeedMetersPerSecond,
                        into: &cues
                    )
                }
            }
            previousInFlightAltitudeFeet = altitudeFeet
        }
        if hasSurfaceContact {
            emit(
                .contact,
                title: "CONTACT LIGHT",
                detail: "Landing-gear probe contact. Execute ENGINE STOP and settle the vehicle.",
                kind: .contact,
                spokenText: "Contact light.",
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
                spokenText: "Touchdown. Soft landing.",
                into: &cues
            )
        case .hardLanding:
            emit(
                .hardLanding,
                title: "HARD LANDING",
                detail: "The vehicle is intact, but touchdown exceeded soft-landing limits.",
                kind: .warning,
                spokenText: "Touchdown. Hard landing.",
                into: &cues
            )
        case .crashed:
            emit(
                .crashed,
                title: "VEHICLE LOST",
                detail: "Touchdown exceeded the modeled landing-gear envelope.",
                kind: .failure,
                spokenText: "Vehicle lost.",
                into: &cues
            )
        case .inFlight, .none:
            break
        }

        return cues
    }

    private mutating func emitTelemetryCallout(
        _ callout: (event: Event, feet: Int),
        verticalSpeedMetersPerSecond: Double?,
        downrangeSpeedMetersPerSecond: Double?,
        into cues: inout [LMCockpitCue]
    ) {
        let verticalFeetPerSecond = verticalSpeedMetersPerSecond.map { $0 / 0.3048 }
        let downrangeFeetPerSecond = downrangeSpeedMetersPerSecond.map { $0 / 0.3048 }
        let vertical = verticalFeetPerSecond.map(Self.verticalRatePresentation)
        let horizontal = downrangeFeetPerSecond.flatMap(Self.horizontalRatePresentation)

        let title = (["\(callout.feet) FT", vertical?.title, horizontal?.title] as [String?])
            .compactMap { $0 }
            .joined(separator: " · ")
        let spokenText = (["\(callout.feet) feet", vertical?.spoken, horizontal?.spoken] as [String?])
            .compactMap { $0 }
            .joined(separator: ". ") + "."

        emit(
            callout.event,
            title: title,
            detail: "Live altitude and velocity in the Apollo 11 LMP landing-callout cadence.",
            kind: .altitude,
            spokenText: spokenText,
            into: &cues
        )
    }

    private static func verticalRatePresentation(_ feetPerSecond: Double) -> (title: String, spoken: String) {
        let direction = feetPerSecond <= 0 ? ("DOWN", "Down") : ("UP", "Up")
        let rate = halfFootRate(abs(feetPerSecond))
        return ("\(direction.0) \(rate)", "\(direction.1) \(rate)")
    }

    private static func horizontalRatePresentation(_ feetPerSecond: Double) -> (title: String, spoken: String)? {
        let rate = Int(abs(feetPerSecond).rounded())
        guard rate > 0 else { return nil }
        return feetPerSecond >= 0
            ? ("FWD \(rate)", "\(rate) forward")
            : ("BACK \(rate)", "\(rate) back")
    }

    private static func halfFootRate(_ rate: Double) -> String {
        let rounded = (rate * 2).rounded() / 2
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    private mutating func emit(
        _ event: Event,
        title: String,
        detail: String,
        kind: LMCockpitCue.Kind,
        spokenText: String? = nil,
        into cues: inout [LMCockpitCue]
    ) {
        guard emitted.insert(event).inserted else { return }
        cues.append(LMCockpitCue(
            id: event,
            title: title,
            detail: detail,
            kind: kind,
            spokenText: spokenText
        ))
    }
}
