import Foundation
import OSLog

/// Opt-in Simulator integration sequence. Uses the same session actions as
/// the buttons; it does not certify physical gesture or UI hit-target comfort.
@MainActor enum LunarExplorerExperienceProbe {
    static func run(_ session: LunarExplorerSession) async {
        let logger = Logger(subsystem: "io.positron.LM", category: "MoonExperience")
        let originalLibrary = session.library
        defer { session.library = originalLibrary }
        do {
            for _ in 0..<240 where session.diagnostics.globeTierState == "pending" {
                try await Task.sleep(for: .milliseconds(500))
            }
            func stage(_ value: String) async throws {
                logger.info("Moon experience stage=\(value, privacy: .public)")
                try await Task.sleep(for: .seconds(25))
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
            session.returnToGlobe()
            try await stage("returned")
            session.restore(saved)
            try await waitForArrival(session)
            var restored = session.savedView(named: saved.name)
            restored.id = saved.id
            guard restored == saved else { throw CocoaError(.validationMissingMandatoryProperty) }
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try JSONEncoder().encode([saved, restored]).write(to: directory.appendingPathComponent("MoonExplorerJourney.json"))
            try await stage("restored")
            session.returnToGlobe()
            logger.info("Moon experience stage=passed cameraAndSunlightExact=true persistenceReload=true")
        } catch {
            logger.error("Moon experience stage=failed error=\(error.localizedDescription, privacy: .public)")
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
