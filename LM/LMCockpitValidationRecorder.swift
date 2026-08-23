import Foundation

struct LMCockpitValidationRecorder: Equatable, Sendable {
    enum Requirement: String, CaseIterable, Identifiable, Sendable {
        case terrainLoaded
        case p65
        case acaPitch
        case acaYaw
        case acaRoll
        case acaNeutral
        case rodDescendPlus
        case rodDescendMinus
        case rodNeutral
        case attitudeHold
        case p66
        case oneHundredFeet
        case fiftyFeet
        case contact
        case softLanding
        case comfortConfirmed

        var id: Self { self }

        var title: String {
            switch self {
            case .terrainLoaded: "LROC terrain"
            case .p65: "P65 live"
            case .acaPitch: "ACA pitch"
            case .acaYaw: "ACA yaw"
            case .acaRoll: "ACA roll"
            case .acaNeutral: "ACA neutral"
            case .rodDescendPlus: "ROD +"
            case .rodDescendMinus: "ROD −"
            case .rodNeutral: "ROD neutral"
            case .attitudeHold: "ATT HOLD"
            case .p66: "P66 live"
            case .oneHundredFeet: "100 feet"
            case .fiftyFeet: "50 feet"
            case .contact: "Contact"
            case .softLanding: "Soft landing"
            case .comfortConfirmed: "Comfort confirmed"
            }
        }
    }

    private(set) var completed = Set<Requirement>()
    private(set) var terminalResult: LMCockpitExperienceDirector.Event?
    private var acaWasDeflected = false
    private var rodWasDeflected = false

    var completedCount: Int { completed.count }
    var totalCount: Int { Requirement.allCases.count }
    var isComplete: Bool { completed.count == Requirement.allCases.count }

    mutating func resetForRun() {
        let terrainWasLoaded = completed.contains(.terrainLoaded)
        completed.removeAll(keepingCapacity: true)
        if terrainWasLoaded {
            completed.insert(.terrainLoaded)
        }
        terminalResult = nil
        acaWasDeflected = false
        rodWasDeflected = false
    }

    mutating func observeTerrainLoaded() {
        completed.insert(.terrainLoaded)
    }

    mutating func observe(events: some Sequence<LMCockpitExperienceDirector.Event>) {
        for event in events {
            switch event {
            case .p65:
                completed.insert(.p65)
            case .p66:
                completed.insert(.p66)
            case .oneHundredFeet:
                completed.insert(.oneHundredFeet)
            case .fiftyFeet:
                completed.insert(.fiftyFeet)
            case .contact:
                completed.insert(.contact)
            case .softLanding:
                completed.insert(.softLanding)
                terminalResult = event
            case .hardLanding, .crashed:
                terminalResult = event
            }
        }
    }

    mutating func observeDirectACA(_ input: LMACANormalizedInput) {
        let threshold = 0.2
        if abs(input.pitch) >= threshold {
            completed.insert(.acaPitch)
            acaWasDeflected = true
        }
        if abs(input.yaw) >= threshold {
            completed.insert(.acaYaw)
            acaWasDeflected = true
        }
        if abs(input.roll) >= threshold {
            completed.insert(.acaRoll)
            acaWasDeflected = true
        }
    }

    mutating func observeDirectACARelease() {
        guard acaWasDeflected else { return }
        completed.insert(.acaNeutral)
    }

    mutating func observeDirectROD(_ position: PoweredDescentSession.RODSwitchPosition) {
        switch position {
        case .descendPlus:
            completed.insert(.rodDescendPlus)
            rodWasDeflected = true
        case .descendMinus:
            completed.insert(.rodDescendMinus)
            rodWasDeflected = true
        case .neutral:
            guard rodWasDeflected else { return }
            completed.insert(.rodNeutral)
        }
    }

    mutating func observeDirectAttitudeHold() {
        completed.insert(.attitudeHold)
    }

    mutating func confirmComfort() {
        completed.insert(.comfortConfirmed)
    }

    func summary() -> String {
        let missing = Requirement.allCases
            .filter { !completed.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
        let result = terminalResult?.rawValue ?? "inFlight"
        return "completed=\(completedCount)/\(totalCount) result=\(result) missing=[\(missing)]"
    }
}
