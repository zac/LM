import LunarMap
import Foundation
import OSLog

/// Opt-in Simulator integration sequence. Uses the same session actions as
/// the buttons; it does not certify physical gesture or UI hit-target comfort.
@MainActor enum LunarExplorerExperienceProbe {
    static func run(_ session: LunarExplorerSession, scene: LunarExplorerScene) async {
        if LunarMapLaunchOptions.current.arguments.contains("--lunar-explorer-profile"),
           LunarMapLaunchOptions.current.arguments.contains("--lunar-explorer-profile-reentry") {
            await runReentry(session)
            return
        }
        let logger = Logger(subsystem: LunarMapLog.subsystem, category: "MoonExperience")
        let originalLibrary = session.library
        defer { session.library = originalLibrary }
        let arguments = LunarMapLaunchOptions.current.arguments
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
            if arguments.contains("--lunar-explorer-profile-highland-dive") {
                try await runHighlandDive(session, scene: scene, stage: stage)
                logger.info("Moon experience stage=passed highlandDive=true")
                if let stageURL { try Data("passed".utf8).write(to: stageURL, options: .atomic) }
                return
            }
            if arguments.contains("--lunar-explorer-profile-one-zoom") {
                guard let place = session.catalogPlaces.first(where: { $0.id == "apollo-11" }) else {
                    throw CocoaError(.fileReadUnknown)
                }
                session.previewPlace(place)
                if !arguments.contains("--lunar-explorer-profile-gestures-only") {
                try await stage("disk")
                if arguments.contains("--lunar-explorer-profile-portal-switch") {
                    var low = 3_000_000.0, high = 5_000_000.0
                    for _ in 0..<32 {
                        let middle = (low + high) / 2
                        session.exploreZoom(by: session.metersAcross / middle, from: session.metersAcross)
                        if session.portalEnabled { low = middle } else { high = middle }
                    }
                    let threshold = (low + high) / 2
                    session.exploreZoom(by: session.metersAcross / (threshold * 1.001), from: session.metersAcross)
                    guard !session.portalEnabled else { throw CocoaError(.validationMissingMandatoryProperty) }
                    logger.info("Portal switch before width=\(session.metersAcross, privacy: .public)m")
                    try await stage("switch-before")
                    session.exploreZoom(by: session.metersAcross / (threshold * 0.999), from: session.metersAcross)
                    guard session.portalEnabled else { throw CocoaError(.validationMissingMandatoryProperty) }
                    logger.info("Portal switch after width=\(session.metersAcross, privacy: .public)m")
                    try await stage("switch-after")
                }
                session.exploreZoom(by: session.metersAcross / 1_000_000, from: session.metersAcross)
                try await stage("clipped")
                session.exploreZoom(by: session.metersAcross / 210_000, from: session.metersAcross)
                for _ in 0..<600 where !session.diagnostics.loadMessage.hasSuffix("terrain ready") {
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard session.diagnostics.loadMessage.hasSuffix("terrain ready") else { throw CocoaError(.fileReadUnknown) }
                try await stage("crossfade")
                session.exploreZoom(by: session.metersAcross / 180_000, from: session.metersAcross)
                try await stage("handoff")
                session.exploreZoom(by: session.metersAcross / 24_000, from: session.metersAcross)
                try await stage("terrain")
                session.enterImmersion()
                guard session.isImmersed else { throw CocoaError(.validationMissingMandatoryProperty) }
                try await stage("immersion")
                session.leaveImmersion()
                guard session.portalEnabled else { throw CocoaError(.validationMissingMandatoryProperty) }
                try await stage("return")
                } else {
                    session.exploreZoom(by: session.metersAcross / 700, from: session.metersAcross)
                    for _ in 0..<600 where !session.diagnostics.loadMessage.hasSuffix("terrain ready") {
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    guard session.diagnostics.loadMessage.hasSuffix("terrain ready") else { throw CocoaError(.fileReadUnknown) }
                }
                if arguments.contains("--lunar-explorer-profile-gestures") {
                    session.select(.terminal)
                    session.pan(northMeters: 0, eastMeters: 0)
                    try await stage("pinch-start")
                    try await scene.probeAnchoredPinch(session)
                    try await stage("pinch-end")
                    session.select(.terminal)
                    session.pan(northMeters: 0, eastMeters: 0)
                    try await stage("pan-before")
                    for step in 1...80 {
                        session.pan(northMeters: 0, eastMeters: Double(step) / 2)
                        try await Task.sleep(for: .milliseconds(33))
                    }
                    try await stage("pan-after")
                }
                logger.info("Moon experience stage=passed oneZoom=true")
                if let stageURL { try Data("passed".utf8).write(to: stageURL, options: .atomic) }
                return
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

    /// The same driver is compiled into the frozen control and candidate.
    /// No pause at 600 km: the prefetch margin is earned during the dive.
    private static func runHighlandDive(_ session: LunarExplorerSession, scene: LunarExplorerScene,
        stage: @MainActor (String) async throws -> Void) async throws {
        let logger = Logger(subsystem: LunarMapLog.subsystem, category: "MoonExperience")
        session.returnToGlobe()
        session.selectedPlaceID = nil
        session.automaticallyRotatesGlobe = false
        session.browseCoordinate = .init(latitudeDegrees: -42, longitudeDegrees: 120)
        session.sunAnchorDate = LunarExplorerSession.apollo11TouchdownUTC
        session.sunOffsetHours = 0
        session.showDaylight()
        try await stage("highland-disk")
        session.logarithmicMetersAcross = log10(1_000_000)
        let start = ContinuousClock.now
        var crossed600 = false, crossed240 = false
        for step in 0...180 {
            let width = exp(log(1_000_000.0) + Double(step) / 180 * log(0.21))
            session.logarithmicMetersAcross = log10(width)
            try await Task.sleep(for: .milliseconds(33))
            let state = scene.regionalProbeState
            if !crossed600 && session.metersAcross < 600_000 {
                crossed600 = true
                logger.info("Highland dive threshold=600000 actual=\(session.metersAcross)m tiles=\(state.tiles)")
                LMLunarTerrainTiming.memory("highland-600km")
            }
            if !crossed240 && session.metersAcross < 240_000 {
                crossed240 = true
                logger.info("Highland dive threshold=240000 actual=\(session.metersAcross)m tiles=\(state.tiles) spacing=\(state.spacing ?? 0)m globe=\(state.globe) site=\(state.site)")
                LMLunarTerrainTiming.memory("highland-240km")
            }
            if state.tiles == 0 && (state.globe != 1 || state.site != 0) {
                throw CocoaError(.validationMissingMandatoryProperty)
            }
        }
        logger.info("Highland dive elapsed=\(String(describing: start.duration(to: .now)))")
        try await stage("highland-arrival")
        for _ in 0..<1_200 where scene.regionalProbeState.tiles == 0 {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard scene.regionalProbeState.tiles > 0 else { throw CocoaError(.fileReadUnknown) }
        try await stage("highland-overlap")
        let regionalStart = ContinuousClock.now
        session.logarithmicMetersAcross = log10(24_000)
        for _ in 0..<1_200 {
            let state = scene.regionalProbeState
            if state.spacing == 8 && !state.morphing && session.diagnostics.loadMessage == "Lunar terrain ready" { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let final = scene.regionalProbeState
        guard final.spacing == 8 && !final.morphing else { throw CocoaError(.fileReadUnknown) }
        logger.info("Highland regional ready tiles=\(final.tiles) elapsed=\(String(describing: regionalStart.duration(to: .now)))")
        LMLunarTerrainTiming.memory("highland-regional")
        try await stage("highland-regional")
        // Final image has a 90-second settled observation in every run.
        try await Task.sleep(for: .seconds(90))
        try await stage("highland-settled")
    }

    /// Repeat the owner's default-location device check using production actions.
    /// Both profile flags are required; ordinary launches never navigate themselves.
    private static func runReentry(_ session: LunarExplorerSession) async {
        let logger = Logger(subsystem: LunarMapLog.subsystem, category: "MoonExperience")
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
