import Foundation
import OSLog

/// Opt-in Simulator integration sequence. Uses the same session actions as
/// the buttons; it does not certify physical gesture or UI hit-target comfort.
@MainActor enum LunarExplorerExperienceProbe {
    static func run(_ session: LunarExplorerSession) async {
        if ProcessInfo.processInfo.arguments.contains("--lunar-explorer-profile"),
           ProcessInfo.processInfo.arguments.contains("--lunar-explorer-profile-reentry") {
            await runReentry(session)
            return
        }
        let logger = Logger(subsystem: "io.positron.LM", category: "MoonExperience")
        let originalLibrary = session.library
        defer { session.library = originalLibrary }
        let arguments = ProcessInfo.processInfo.arguments
        let tokenPrefix = "--lunar-explorer-profile-capture-token="
        let token = arguments.first(where: { $0.hasPrefix(tokenPrefix) })
            .flatMap { UUID(uuidString: String($0.dropFirst(tokenPrefix.count))) }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stageURL = token.map { documents.appendingPathComponent("MoonExplorerJourney-\($0.uuidString)-stage.txt") }
        let ackURL = token.map { documents.appendingPathComponent("MoonExplorerJourney-\($0.uuidString)-ack.txt") }
        do {
            for _ in 0..<240 where session.diagnostics.globeTierState == "pending" {
                try await Task.sleep(for: .milliseconds(500))
            }
            func stage(_ value: String) async throws {
                logger.info("Moon experience stage=\(value, privacy: .public)")
                async let minimumHold: Void = Task.sleep(for: .seconds(25))
                if let stageURL, let ackURL {
                    try Data(value.utf8).write(to: stageURL, options: .atomic)
                    var acknowledged = false
                    for _ in 0..<1_200 {
                        if (try? String(contentsOf: ackURL, encoding: .utf8)) == value {
                            acknowledged = true
                            break
                        }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    guard acknowledged else { throw CocoaError(.fileReadUnknown) }
                }
                try await minimumHold
            }
            try await stage("globe")
            let place = try LMLunarPOICatalog.load().features.first { $0.id == "apollo-11" }
            guard let place else { throw CocoaError(.fileReadCorruptFile) }
            session.previewPlace(place)
            try await stage("selected")
            session.exploreSelectedPlace(altitude: 180)
            try await waitForArrival(session)
            session.headingDegrees = 27
            session.pan(northMeters: 130, eastMeters: -45)
            session.sunOffsetHours = 12
            try await stage("immersive")
            let suite = "MoonExplorerProbe-" + UUID().uuidString
            guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.fileWriteUnknown) }
            defer { defaults.removePersistentDomain(forName: suite) }
            let saved = session.savedView(named: "Explorer validation")
            session.library = LunarExplorerLibrary(defaults: defaults)
            session.library.save(saved)
            let reloaded = LunarExplorerLibrary(defaults: defaults)
            guard reloaded.views == [saved] else { throw CocoaError(.fileReadCorruptFile) }
            session.library = reloaded
            session.returnToGlobeGently()
            try await stage("returned")
            session.restore(saved)
            try await waitForArrival(session)
            var restored = session.savedView(named: saved.name)
            restored.id = saved.id
            guard restored == saved else { throw CocoaError(.validationMissingMandatoryProperty) }
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try JSONEncoder().encode([saved, restored]).write(to: directory.appendingPathComponent("MoonExplorerJourney.json"))
            try await stage("restored")
            session.returnToGlobeGently()
            for _ in 0..<120 where session.navigationInProgress {
                try await Task.sleep(for: .milliseconds(20))
            }
            guard session.isBrowsingGlobe, session.transitionOpacity == 1 else {
                throw CocoaError(.fileReadUnknown)
            }
            let prefix = "--lunar-explorer-profile-soak-cycles="
            if arguments.contains("--lunar-explorer-profile"),
               let argument = arguments.first(where: { $0.hasPrefix(prefix) }),
               let cycles = Int(argument.dropFirst(prefix.count)), (1...20).contains(cycles) {
                for cycle in 1...cycles {
                    session.restore(saved)
                    try await waitForArrival(session)
                    LMLunarTerrainTiming.memory("soak-\(cycle)-surface")
                    // Exercise the same sunlight state as the Lighting control.
                    let originalOffset = session.sunOffsetHours
                    session.sunOffsetHours += 6
                    try await Task.sleep(for: .seconds(5))
                    session.sunOffsetHours = originalOffset
                    try await Task.sleep(for: .seconds(5))
                    var replay = session.savedView(named: saved.name)
                    replay.id = saved.id
                    guard replay == saved else { throw CocoaError(.validationMissingMandatoryProperty) }
                    session.returnToGlobeGently()
                    for _ in 0..<120 where session.navigationInProgress {
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    guard session.isBrowsingGlobe, session.transitionOpacity == 1 else {
                        throw CocoaError(.fileReadUnknown)
                    }
                    try await Task.sleep(for: .seconds(25))
                    LMLunarTerrainTiming.memory("soak-\(cycle)-returned")
                    logger.info("Moon experience cycle=\(cycle) cameraAndSunlightExact=true")
                }
            }
            logger.info("Moon experience stage=passed cameraAndSunlightExact=true persistenceReload=true")
            if let stageURL { try Data("passed".utf8).write(to: stageURL, options: .atomic) }
        } catch {
            logger.error("Moon experience stage=failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    /// Repeat the owner's default-location device check using production actions.
    /// Both profile flags are required; ordinary launches never navigate themselves.
    private static func runReentry(_ session: LunarExplorerSession) async {
        let logger = Logger(subsystem: "io.positron.LM", category: "MoonExperience")
        do {
            for _ in 0..<240 where session.diagnostics.globeTierState == "pending" {
                try await Task.sleep(for: .milliseconds(500))
            }
            session.selectedPlaceID = nil
            session.browseCoordinate = .init(latitudeDegrees: 0, longitudeDegrees: 0)
            try await Task.sleep(for: .seconds(5))
            session.exploreSelectedPlace()
            try await waitForArrival(session)
            let first = session.diagnostics.latestGenerationMilliseconds ?? -1
            let source = session.diagnostics.sourceDescription
            let floor = session.diagnostics.measuredFloorMeters
            let count = session.diagnostics.activeTileCount
            LMLunarTerrainTiming.memory("reentry-first")
            session.returnToGlobeGently()
            for _ in 0..<200 where session.navigationInProgress {
                try await Task.sleep(for: .milliseconds(20))
            }
            guard session.isBrowsingGlobe, !session.navigationInProgress else { throw CocoaError(.fileReadUnknown) }
            try await Task.sleep(for: .seconds(5))
            session.exploreSelectedPlace()
            try await waitForArrival(session)
            guard session.diagnostics.latestGenerationMilliseconds == 0,
                  session.diagnostics.activeTileCount == count,
                  session.diagnostics.sourceDescription == source,
                  session.diagnostics.measuredFloorMeters == floor else { throw CocoaError(.validationMissingMandatoryProperty) }
            LMLunarTerrainTiming.memory("reentry-second")
            logger.info("Moon reentry passed first=\(first)ms second=0ms tiles=\(count) sourceExact=true")
            session.returnToGlobeGently()
        } catch {
            logger.error("Moon reentry failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private static func waitForArrival(_ session: LunarExplorerSession) async throws {
        for _ in 0..<600 {
            if !session.navigationInProgress {
                try await Task.sleep(for: .seconds(20))
                guard session.diagnostics.activeTileCount > 0, session.flightCoordinate == nil,
                      session.presentsSite else { throw CocoaError(.fileReadUnknown) }
                return
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw CocoaError(.fileReadUnknown)
    }
}
