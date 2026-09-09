import Foundation
    enum StartPoint: Equatable {
        case ignition
        case p64Approach
        case twoMinuteApproach
        case p65TerminalDescent

        /// Apollo cockpit defaults to approximately two minutes before touchdown.
        /// The longer P64 approach remains available through an explicit launch option.
        static func cockpitLaunch(arguments: [String]) -> Self {
            if arguments.contains("--cockpit-start-p64") { return .p64Approach }
            if arguments.contains("--cockpit-start-p65") { return .p65TerminalDescent }
            return .twoMinuteApproach
        }

        var programLabel: String {
            switch self {
            case .ignition: "P63"
            case .p64Approach, .twoMinuteApproach: "P64"
            case .p65TerminalDescent: "P65"
            }
        }
    }

precondition(StartPoint.cockpitLaunch(arguments: []) == .twoMinuteApproach)
precondition(StartPoint.cockpitLaunch(arguments: ["--cockpit-start-p65"]) == .p65TerminalDescent)
precondition(StartPoint.cockpitLaunch(arguments: ["--cockpit-start-p64"]) == .p64Approach)
precondition(StartPoint.cockpitLaunch(arguments: ["--cockpit-start-p64", "--cockpit-start-p65"]) == .p64Approach)
precondition(StartPoint.twoMinuteApproach.programLabel == "P64")
print("Five launch-selection assertions passed against the extracted app enum")
