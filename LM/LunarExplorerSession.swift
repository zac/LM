import Foundation
import SwiftUI

/// User-controlled inspection state for the production lunar terrain pipeline.
///
/// Virtual altitude selects the same progressive detail the landing scene would
/// request. Meters-across controls only the inspection scale, which lets us
/// deliberately zoom into a particular LOD without silently requesting a finer
/// one and hiding a transition defect.
@MainActor
@Observable
final class LunarExplorerSession {
    enum CapturePresentation: String {
        case globe
        case site
    }

    enum NavigationMode: String, CaseIterable, Identifiable {
        case orbit
        case pan

        var id: Self { self }

        var title: String {
            switch self {
            case .orbit: "Orbit"
            case .pan: "Pan"
            }
        }
    }

    enum Preset: String, CaseIterable, Identifiable {
        case globe
        case orbit
        case regional
        case approach
        case terminal
        case landing
        case surface

        var id: Self { self }

        var title: String {
            switch self {
            case .globe: "Globe"
            case .orbit: "Orbit"
            case .regional: "Regional"
            case .approach: "Approach"
            case .terminal: "Terminal"
            case .landing: "Landing"
            case .surface: "Surface"
            }
        }

        var altitudeMeters: Double {
            switch self {
            case .globe: 1_000_000
            case .orbit: 30_000
            case .regional: 7_500
            case .approach: 1_200
            case .terminal: 180
            case .landing: 40
            case .surface: 2
            }
        }

        var metersAcross: Double {
            switch self {
            case .globe: 4_400_000
            case .orbit: 120_000
            case .regional: 24_000
            case .approach: 4_000
            case .terminal: 700
            case .landing: 180
            case .surface: 20
            }
        }

        var tiltDegrees: Double {
            switch self {
            case .globe: 0
            case .orbit, .regional: 72
            case .approach: 66
            case .terminal: 58
            case .landing: 50
            case .surface: 38
            }
        }
    }

    enum Focus: String, CaseIterable, Identifiable {
        case eagle
        case northBoulderField

        var id: Self { self }

        var title: String {
            switch self {
            case .eagle: "Eagle"
            case .northBoulderField: "North rocks"
            }
        }

        var offsetNorthMeters: Double {
            switch self {
            case .eagle: 0
            case .northBoulderField: 135
            }
        }

        var offsetEastMeters: Double { 0 }
    }

    struct Diagnostics: Equatable {
        var loadMessage = "Loading measured terrain"
        var sourceDescription = "Waiting for manifest"
        var measuredFloorMeters: Double?
        var requestedTileCount = 0
        var activeTileCount = 0
        var finestSpacingMeters: Double?
        /// Live mission-sun geometry for the current instant, so the panel can
        /// show what the ephemeris resolved rather than a pinned constant.
        var sunAzimuthDegrees: Double?
        var sunElevationDegrees: Double?
        var earthIlluminatedFraction: Double?
        var latestGenerationMilliseconds: Int?
        var latestGenerationMetrics: Apollo11TerrainResource
            .ProgressiveTileGenerationMetrics?
        var globeTierState = "pending"
    }

    static let minimumAltitudeMeters = 1.5
    static let maximumAltitudeMeters = 1_500_000.0
    static let minimumMetersAcross = 8.0
    static let maximumMetersAcross = 5_000_000.0
    static let minimumTiltDegrees = 18.0
    static let minimumGlobeCaptureTiltDegrees = -82.0
    static let maximumTiltDegrees = 82.0
    /// Keep the globe outside the viewer while the site presentation grows
    /// out of its Apollo 11 surface point during the measured handoff.
    /// Keep the nearest globe surface at the accepted whole-Moon depth while
    /// zooming the sphere itself. Once its limb leaves the view, the local
    /// spherical patch and the registered site share the same screen scale.
    static let globeSurfaceDepthMeters: Float = 2.17
    static let globeHandoffRampStartMetersAcross = 330_000.0
    static let globeHandoffOverscan = 1.4
    /// Matched 210 km layer-isolation captures with the bundled 64 ppd JXL
    /// measured the globe at 0.02351 and the site at 0.13449 mean linear
    /// luminance. The exact measured ratio was 5.72; the bounded 5.70x match
    /// remains within the acceptance tolerance. Raise only the
    /// cartographic globe presentation before the crossfade; site materials
    /// remain the calibrated production terrain.
    static let globeSiteLinearRadianceMultiplier = 5.70
    /// RealityKit composites subtree opacity through its transparent path,
    /// which measured 4.9% low in linear luminance at the 210 km overlap even
    /// after the two opaque endpoints matched. This bounded sinusoid is zero
    /// at both endpoints and compensates only that mid-dissolve loss.
    static let globeCrossfadeCompositingCompensation = 0.10
    static let siteCoverageOverscanEndMetersAcross = Preset.regional.metersAcross
    static let lunarGlobeRadiusMeters = 1_737_400.0
    /// The 262.144 km regional source cannot cover a wider view at matching
    /// scale. Begin the representation blend only after it fills the frame.
    static let globeSiteBlendStartMetersAcross = 240_000.0
    static let globeSiteBlendEndMetersAcross = Preset.orbit.metersAcross
    /// Eagle's touchdown. Named instants are just dates: the pinned mission
    /// sun is this one evaluated through the ephemeris.
    static let apollo11TouchdownUTC: Date = {
        var components = DateComponents()
        components.year = 1969
        components.month = 7
        components.day = 20
        components.hour = 20
        components.minute = 17
        components.second = 40
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }()
    /// A full lunation either way, so the terminator can be swept across the
    /// site and back without touching the date picker.
    static let sunScrubRangeHours = 360.0

    /// The instant mission lighting is evaluated for.
    var sunDate: Date {
        sunAnchorDate.addingTimeInterval(sunOffsetHours * 3_600)
    }

    static func presentsControls(arguments: [String]) -> Bool {
        !arguments.contains("--lunar-explorer-capture")
    }

    // Capture sessions retain the original full-space inspection path.
    var reduceMotion = false
    var automaticallyRotatesGlobe = false
    var isManipulatingGlobe = false
    let catalogPlaces = (try? LMLunarPOICatalog.load().features) ?? []
    var transitionOpacity: Float = 1
    var globePosition = SIMD3<Float>(1.05, 0, -2.0)
    var globePlacementRevision = 0
    var isExplorerExperience = false
    var isBrowsingGlobe = false
    var immersionStyle: any ImmersionStyle = .full
    /// Container configuration, independent of the camera and terrain pipeline.
    /// Fixed reference captures render without the room-facing frame.
    var usesWindowContainer = false
    var isImmersed = false
    var portalEnabled: Bool {
        usesWindowContainer && !isImmersed
            && (portalProjection?.frameOverflow ?? .infinity) >= 0
    }
    var portalProjection: LunarExplorerPortalGeometry.Projection? {
        let offset = globePosition - SIMD3<Float>(0, 0, -2)
        let radius = Float(Self.lunarGlobeRadiusMeters) * globePresentationScale
        return LunarExplorerPortalGeometry.project(
            center: offset + SIMD3(0, 1.45, -(Self.globeSurfaceDepthMeters + radius)),
            radius: radius, eye: LunarExplorerPortalGeometry.simulatorEyePosition,
            planeCenter: offset + SIMD3(0, 1.45, -Self.globeSurfaceDepthMeters))
    }
    var canImmerse: Bool {
        usesWindowContainer && !isImmersed && !navigationInProgress
            && !landingRunning && metersAcross <= Self.globeSiteBlendEndMetersAcross
            && diagnostics.loadMessage.hasSuffix("terrain ready")
    }
    var maximumZoomWidth: Double {
        isImmersed ? Self.globeSiteBlendEndMetersAcross : Self.maximumMetersAcross
    }

    func enterImmersion() {
        guard canImmerse else { return }
        isImmersed = true
        immersionStyle = .full
    }

    func leaveImmersion() {
        isImmersed = false
        immersionStyle = .mixed
    }

    /// Product zoom crosses the handoff without changing immersion. Keep the
    /// globe visible while the existing terrain load catches up.
    func synchronizeZoomDestination() {
        guard usesWindowContainer else { return }
        if metersAcross < Self.globeSiteBlendStartMetersAcross {
            guard isBrowsingGlobe else { return }
            let coordinate = browseCoordinate
            let apollo = try? LMTerrainManifest.load().landingOriginCoordinate
            let next: LMSelenographicCoordinate? = coordinate == apollo ? nil : coordinate
            isBrowsingGlobe = false
            if destinationCoordinate != next || diagnostics.activeTileCount == 0 {
                destinationCoordinate = next
                currentCoordinate = nil
                focusNorthOffsetMeters = 0
                focusEastOffsetMeters = 0
                navigationRevision += 1
            }
        } else if !isImmersed {
            if !isBrowsingGlobe {
                browseCoordinate = currentCoordinate ?? destinationCoordinate ?? browseCoordinate
            }
            isBrowsingGlobe = true
        }
    }
    var browseCoordinate = LMSelenographicCoordinate(latitudeDegrees: 0, longitudeDegrees: 0)
    var selectedPlaceID: String?
    var pendingSavedView: LunarExplorerSavedView?
    var library = LunarExplorerLibrary()

    var selectedPreset: Preset = .regional
    var selectedFocus: Focus = .eagle
    var navigationMode: NavigationMode = .orbit
    var detailMode: LMTerrainDetailMode = .automatic
    var camera = LunarExplorerCamera()
    var usesAltitudeCamera: Bool { camera.reference == nil }
    var altitudeMeters: Double {
        get { camera.altitude }
        set {
            guard newValue.isFinite else { return }
            camera.altitude = min(Self.maximumAltitudeMeters, max(Self.minimumAltitudeMeters, newValue))
            if isImmersed && camera.width > maximumZoomWidth { camera.setWidth(maximumZoomWidth) }
        }
    }
    var metersAcross: Double {
        get { camera.width }
        set {
            guard newValue.isFinite else { return }
            let width = min(maximumZoomWidth, max(Self.minimumMetersAcross, newValue))
            let gate = Self.globeSiteBlendEndMetersAcross
            camera.setWidth(abs(width - gate) <= gate.ulp ? gate : width)
        }
    }
    var headingDegrees = 0.0 {
        didSet { if !headingGestureActive { planningHeading.commit(headingDegrees) } }
    }
    private(set) var headingGestureActive = false
    private(set) var planningHeading = LunarExplorerPlanningHeading()
    var terrainPlanningHeadingDegrees: Double {
        // Reference captures can pin a deliberately unquantised corridor.
        usesAltitudeCamera ? planningHeading.degrees : headingDegrees
    }
    func beginHeadingGesture() { headingGestureActive = true }
    func endHeadingGesture() {
        headingGestureActive = false
        planningHeading.commit(headingDegrees)
    }
    var tiltDegrees: Double {
        get { camera.tilt }
        set { if newValue.isFinite { camera.reference?.tilt = newValue } }
    }
    var focusNorthOffsetMeters = 0.0
    var focusEastOffsetMeters = 0.0
    var missionShadowsEnabled = true
    /// Mission lighting is time-driven. The ephemeris evaluates the Sun for
    /// this instant, so any date shows its own real illumination rather than a
    /// single baked-in direction. The anchor is a named instant and the offset
    /// is the scrub around it, which keeps "return to the landing" one tap
    /// away no matter how far the terminator has been swept.
    var sunAnchorDate = LunarExplorerSession.apollo11TouchdownUTC {
        didSet { followsDaylightSelection = false }
    }
    var sunOffsetHours = 0.0 {
        didSet { followsDaylightSelection = false }
    }
    /// Reapply the selected daylight preset at a newly selected place. Manual
    /// date/offset edits and saved-view restoration leave the chosen instant fixed.
    var followsDaylightSelection = false
    /// Tonal presentation. Changing this rebuilds resident tiles, because the
    /// exposure floor is baked into each tile's material.
    var presentationGrade: LMTerrainPresentationGrade = .calibrated
    var diagnosticsVisible = true
    var diagnostics = Diagnostics()

    /// Called at the scene's frame publication boundary. Diagnostics are
    /// outputs and do not participate in the scene input snapshot.
    func publishDiagnostics(_ value: Diagnostics) {
        diagnostics = value
    }
    var destinationCoordinate: LMSelenographicCoordinate?
    var usesBundledSite = true
    var residentPanBounds = LunarExplorerPanBounds.regional
    var regionOffline = false
    var navigationRevision = 0
    enum NavigationPhase { case idle, departing, loading, arriving }
    var navigationPhase = NavigationPhase.idle
    var navigationInProgress: Bool { navigationPhase != .idle }
    var pendingArrival = false
    private var arrivalAltitude = Preset.regional.altitudeMeters
    private var arrivalHeading = 0.0
    var flightCoordinate: LMSelenographicCoordinate?
    var currentCoordinate: LMSelenographicCoordinate?
    var navigationMessage = ""
    var downloadMessage = ""
    var isDownloading = false
    var navigationHistory = [LMSelenographicCoordinate]()
    var landingRequest = 0
    var landingMessage = ""
    var landingRunning = false
    @ObservationIgnored private var flightTask: Task<Void, Never>?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?

    func fly(to coordinate: LMSelenographicCoordinate, remember: Bool = true,
             altitude: Double = Preset.regional.altitudeMeters, heading targetHeading: Double = 0) {
        guard !landingRunning else { return }
        // Explicit inspection calibration retains the scripted flight used by
        // --lunar-explorer-fly-to captures; normal navigation uses the portal.
        if isExplorerExperience {
            navigateWithFade(to: coordinate, remember: remember, altitude: altitude, heading: targetHeading)
            return
        }
        flightTask?.cancel()
        pendingSavedView = nil
        arrivalAltitude = min(Self.maximumAltitudeMeters, max(Self.minimumAltitudeMeters, altitude))
        arrivalHeading = targetHeading
        let start = flightCoordinate ?? currentCoordinate ?? destinationCoordinate
            ?? (try? LMTerrainManifest.load().landingOriginCoordinate) ?? coordinate
        if remember { navigationHistory.append(start) }
        navigationPhase = .departing
        navigationMessage = "Flying"
        pendingArrival = false
        let width = metersAcross, altitude = altitudeMeters, tilt = tiltDegrees, heading = headingDegrees
        flightTask = Task { [weak self] in
            for index in 1...60 {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard let self else { return }
                let t = Double(index) / 60
                let eased = t * t * (3 - 2 * t)
                self.metersAcross = exp(log(width) * (1 - eased) + log(Preset.globe.metersAcross) * eased)
                self.altitudeMeters = exp(log(altitude) * (1 - eased) + log(Preset.globe.altitudeMeters) * eased)
                self.tiltDegrees = tilt * (1 - eased)
                self.headingDegrees = heading * (1 - eased)
            }
            self?.select(.globe)
            self?.flightCoordinate = start
            for index in 1...120 {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard let self else { return }
                let t = Double(index) / 120
                self.flightCoordinate = LMLunarNavigation.interpolate(from: start, to: coordinate,
                                                                       fraction: t * t * (3 - 2 * t))
            }
            guard let self else { return }
            let apollo = try? LMTerrainManifest.load().landingOriginCoordinate
            self.destinationCoordinate = coordinate.latitudeDegrees == apollo?.latitudeDegrees
                && coordinate.longitudeDegrees == apollo?.longitudeDegrees ? nil : coordinate
            self.focusNorthOffsetMeters = 0
            self.focusEastOffsetMeters = 0
            self.pendingArrival = true
            self.navigationRevision += 1
            // Hold the destination-facing globe until its replacement is ready.
            self.flightCoordinate = coordinate
            self.navigationPhase = .loading
            self.navigationMessage = "Loading destination"
        }
    }

    func beginArrival() {
        guard pendingArrival else { return }
        // Readiness belongs to the destination, even when its globe was reused.
        flightCoordinate = nil
        pendingArrival = false
        navigationPhase = .arriving
        navigationMessage = "Arriving"
        // Inspection configuration preserves independent width/tilt endpoints
        // for the pinned ladders. The product camera derives both from altitude.
        if isExplorerExperience {
            select(closestPreset(to: arrivalAltitude))
            altitudeMeters = arrivalAltitude
            if !usesAltitudeCamera {
                metersAcross = arrivalAltitude * 3.2
                tiltDegrees = Preset.regional.tiltDegrees
            }
            headingDegrees = arrivalHeading
            applyPendingSavedView()
            flightTask = Task { [weak self] in
                guard let self else { return }
                do { try await self.fadePresentation(to: 1) } catch { return }
                self.navigationPhase = .idle
                self.navigationMessage = ""
            }
            return
        }
        flightTask = Task { [weak self] in
            for index in 1...120 {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard let self else { return }
                let t = Double(index) / 120
                let eased = t * t * (3 - 2 * t)
                self.metersAcross = exp(log(Preset.globe.metersAcross) * (1 - eased) + log(self.arrivalAltitude * 3.2) * eased)
                self.altitudeMeters = exp(log(Preset.globe.altitudeMeters) * (1 - eased) + log(self.arrivalAltitude) * eased)
                self.tiltDegrees = Preset.regional.tiltDegrees * eased
                self.headingDegrees = self.arrivalHeading * eased
            }
            self?.selectedPreset = .regional
            self?.navigationPhase = .idle
            self?.navigationMessage = ""
            self?.applyPendingSavedView()
        }
    }

    /// Product navigation avoids simulated camera travel, including when the
    /// system requests Reduce Motion. Legacy inspection flights stay unchanged.
    private func navigateWithFade(to coordinate: LMSelenographicCoordinate, remember: Bool,
                                  altitude: Double, heading: Double) {
        flightTask?.cancel()
        pendingSavedView = nil
        arrivalAltitude = min(Self.maximumAltitudeMeters, max(Self.minimumAltitudeMeters, altitude))
        arrivalHeading = heading
        if remember { navigationHistory.append(displayedCoordinate) }
        pendingArrival = false
        navigationPhase = .departing
        navigationMessage = "Opening terrain"
        flightTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.fadePresentation(to: 0) } catch { return }
            self.isBrowsingGlobe = false
            if !self.usesWindowContainer { self.immersionStyle = .full }
            let apollo = try? LMTerrainManifest.load().landingOriginCoordinate
            self.destinationCoordinate = coordinate.latitudeDegrees == apollo?.latitudeDegrees
                && coordinate.longitudeDegrees == apollo?.longitudeDegrees ? nil : coordinate
            self.focusNorthOffsetMeters = 0
            self.focusEastOffsetMeters = 0
            self.pendingArrival = true
            self.flightCoordinate = coordinate
            self.navigationPhase = .loading
            self.navigationMessage = "Loading destination"
            self.navigationRevision += 1
        }
    }

    private func fadePresentation(to target: Float) async throws {
        let start = transitionOpacity
        let steps = reduceMotion ? 8 : 15
        for step in 1...steps {
            try await Task.sleep(for: .milliseconds(16))
            transitionOpacity = start + (target - start) * Float(step) / Float(steps)
        }
    }

    func returnToGlobeGently() {
        guard !landingRunning else { return }
        if isBrowsingGlobe { returnToGlobe(); return }
        cancelNavigation()
        navigationPhase = .departing
        navigationMessage = "Returning to globe"
        flightTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.fadePresentation(to: 0)
                self.setGlobePresentation()
                try await self.fadePresentation(to: 1)
                self.navigationPhase = .idle
                self.navigationMessage = ""
            } catch { return }
        }
    }

    func prepareForPresentation() {
        isManipulatingGlobe = false
        returnToGlobe()
        transitionOpacity = 1
    }

    func cancelNavigation() {
        flightTask?.cancel()
        flightTask = nil
        pendingArrival = false
        pendingSavedView = nil
        navigationPhase = .idle
        flightCoordinate = nil
        navigationMessage = ""
    }

    func back() {
        guard let coordinate = navigationHistory.popLast() else { return }
        fly(to: coordinate, remember: false)
    }

    func downloadRegion() {
        guard !isDownloading, let coordinate = currentCoordinate ?? destinationCoordinate else { return }
        isDownloading = true
        downloadMessage = "Checking region sources"
        downloadTask = Task { [weak self] in
            defer { self?.isDownloading = false }
            do {
                let manifest = try LMTerrainManifest.load()
                let catalog = try LMLunarElevationCatalog.load()
                let sources = LMLunarTerrainRegion.sources(at: coordinate, manifest: manifest, catalog: catalog)
                let total = sources.reduce(0) { $0 + ($1.bytes ?? 0) }
                let store = try LMLunarElevationStore(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("LunarElevation-v1", isDirectory: true))
                self?.downloadMessage = String(format: "Downloading %.1f MiB", Double(total) / 1_048_576)
                try await store.prefetch(sources)
                self?.downloadMessage = "Region cached for offline use; the 128 MiB cache may evict older regions."
            } catch is CancellationError { self?.downloadMessage = "Download paused; verified sources retained." }
            catch { self?.downloadMessage = "Download failed: " + error.localizedDescription }
        }
    }

    func cancelDownload() { downloadTask?.cancel() }

    func testLanding() {
        guard !usesBundledSite, !landingRunning else { return }
        select(.surface)
        metersAcross = 30
        landingMessage = "Preparing terrain"
        landingRequest += 1
    }

    /// Capture-only layer isolation for measuring the globe/site handoff at
    /// identical camera scale. Normal launches always leave this nil.
    private(set) var capturePresentation: CapturePresentation?
    /// Capture-only radiance bypass used to retain a before frame after the
    /// shipping globe match is active.
    private(set) var captureUnmatchedGlobeRadiance = false
    private(set) var captureReanchorProbe = false
    private(set) var captureElevationCoordinate: LMSelenographicCoordinate?
    private(set) var captureElevationOffline = false

    var logarithmicAltitude: Double {
        get { log10(altitudeMeters) }
        set {
            altitudeMeters = min(
                max(pow(10, newValue), Self.minimumAltitudeMeters),
                Self.maximumAltitudeMeters
            )
            selectedPreset = closestPreset(to: altitudeMeters)
            synchronizeZoomDestination()
        }
    }

    var logarithmicMetersAcross: Double {
        get { log10(metersAcross) }
        set {
            metersAcross = min(
                max(pow(10, newValue), Self.minimumMetersAcross),
                maximumZoomWidth
            )
            synchronizeZoomDestination()
        }
    }

    /// The product window spans 1.6 scene meters; reference inspection keeps
    /// its original three-metre calibration and all pinned capture transforms.
    var presentationScale: Float {
        Float((usesWindowContainer ? camera.windowWidthMeters : 3) / metersAcross)
    }

    var globePresentationScale: Float {
        presentationScale * Float(globeHandoffScaleMultiplier)
    }

    /// Ramp the matched globe/site overscan in before the site becomes
    /// visible. Both representations then retain identical screen scale while
    /// the finite regional patch covers the complete immersive view.
    var globeHandoffScaleMultiplier: Double {
        1 + (Self.globeHandoffOverscan - 1) * globeHandoffRampProgress
    }

    /// Smoothly match the globe's baked WAC radiance to the live site before
    /// both layers become visible. Keeping the actual crossfade endpoints at
    /// equal mean radiance prevents opacity itself from producing a flash.
    var globeHandoffLinearRadianceMultiplier: Double {
        if captureUnmatchedGlobeRadiance { return 1 }
        let matched = 1 + (sunMatchedGlobeRadiance - 1)
            * globeHandoffRampProgress
        guard capturePresentation == nil else { return matched }
        let siteOpacity = automaticGlobeSiteBlend.siteOpacity
        let compositingCompensation = 1
            + Self.globeCrossfadeCompositingCompensation
                * sin(.pi * siteOpacity)
        return matched * compositingCompensation
    }

    @ObservationIgnored private var radianceCache: (date: Date, coordinate: LMSelenographicCoordinate, value: Double)?

    private var sunMatchedGlobeRadiance: Double {
        // Before a source resolves there is no site radiance to match. Keep
        // the reference calibration, rather than metering a browse coordinate.
        guard let coordinate = currentCoordinate ?? destinationCoordinate else {
            return Self.globeSiteLinearRadianceMultiplier
        }
        if let cached = radianceCache, cached.date == sunDate, cached.coordinate == coordinate { return cached.value }
        let elevation = LMLunarEphemeris.sunAngles(at: sunDate, site: coordinate).elevationDegrees
        let value = Self.globeRadianceMatch(elevationDegrees: elevation)
        radianceCache = (sunDate, coordinate, value)
        return value
    }

    static func globeRadianceMatch(elevationDegrees: Double) -> Double {
        let reference = LMTerrainWorld.referenceSunElevationDegrees
        func groundIlluminance(_ elevation: Double) -> Double {
            Double(LMTerrainWorld.missionSunIlluminance(elevationDegrees: elevation))
                * max(0, sin(elevation * .pi / 180))
        }
        let ratio = groundIlluminance(elevationDegrees) / groundIlluminance(reference)
        // The exposure model holds sunlit flat ground constant. Remove Float
        // roundoff on that plateau to preserve the exact mission calibration.
        let exposure = abs(ratio - 1) < 1e-6 ? 1 : ratio
        // Central 80% overlap captures at the mission instant and 25 degrees
        // measure 0.134490 and 0.137054 site luminance. Flat-ground exposure
        // alone misses this measured relief response. Interpolate only inside
        // the calibrated band and retain its endpoints beyond it (calibration v1).
        // The exposure reference is rounded to 0.001 degree. Retain the exact
        // reference within that rounding cell, including the mission ephemeris.
        let reliefElevation = abs(elevationDegrees - reference) < 0.001 ? reference : elevationDegrees
        let reliefProgress = min(1, max(0, (reliefElevation - reference) / (25 - reference)))
        let reliefResponse = 1 + (0.137054 / 0.134490 - 1) * reliefProgress
        return globeSiteLinearRadianceMultiplier * exposure * reliefResponse
    }

    private var globeHandoffRampProgress: Double {
        let span = Self.globeHandoffRampStartMetersAcross
            - Self.globeSiteBlendStartMetersAcross
        let linear = min(max(
            (Self.globeHandoffRampStartMetersAcross - metersAcross) / span,
            0
        ), 1)
        return linear * linear * (3 - 2 * linear)
    }

    /// Keep the finite regional mesh outside the camera frustum at Orbit,
    /// then release the extra coverage once the ordinary site extent is more
    /// than large enough for the selected view.
    var siteCoverageScaleMultiplier: Double {
        let span = Self.globeSiteBlendEndMetersAcross
            - Self.siteCoverageOverscanEndMetersAcross
        let linear = min(max(
            (metersAcross - Self.siteCoverageOverscanEndMetersAcross) / span,
            0
        ), 1)
        let smooth = linear * linear * (3 - 2 * linear)
        return 1 + (Self.globeHandoffOverscan - 1) * smooth
    }

    struct GlobeSiteBlend: Equatable {
        let progress: Double
        let morphProgress: Double
        let globeOpacity: Double
        let siteOpacity: Double
    }

    /// Smooth globe-to-site presentation handoff. `metersAcross` remains a
    /// camera/presentation concern and never changes the production terrain
    /// LOD selected by virtual altitude.
    var globeSiteBlend: GlobeSiteBlend {
        let automatic = automaticGlobeSiteBlend
        return switch capturePresentation {
        case .globe:
            GlobeSiteBlend(
                progress: automatic.progress,
                morphProgress: automatic.morphProgress,
                globeOpacity: 1,
                siteOpacity: 0
            )
        case .site:
            GlobeSiteBlend(
                progress: automatic.progress,
                morphProgress: automatic.morphProgress,
                globeOpacity: 0,
                siteOpacity: 1
            )
        case nil:
            automatic
        }
    }

    private var automaticGlobeSiteBlend: GlobeSiteBlend {
        let span = Self.globeSiteBlendStartMetersAcross
            - Self.globeSiteBlendEndMetersAcross
        let linear = min(max(
            (Self.globeSiteBlendStartMetersAcross - metersAcross) / span,
            0
        ), 1)
        let smooth = linear * linear * (3 - 2 * linear)
        // Finish the representation crossfade before the planar patch leaves
        // its registered tangent pose. The second half of the band is a
        // site-only camera morph, so valid globe and site geometry cannot cut
        // through one another as the patch grows to inspection scale.
        let fadeLinear = min(smooth * 2, 1)
        let siteOpacity = fadeLinear * fadeLinear * (3 - 2 * fadeLinear)
        // Opacity components composite source-over; complementary alpha on
        // two layers therefore reveals black behind them at mid-fade. Keep
        // the globe opaque as the backplate while the registered site fades
        // over it, then remove it only after the site is fully opaque.
        let globeOpacity = siteOpacity >= 0.999 ? 0.0 : 1.0
        let morphLinear = min(max((smooth - 0.5) * 2, 0), 1)
        let morph = morphLinear * morphLinear * (3 - 2 * morphLinear)
        return GlobeSiteBlend(
            progress: smooth,
            morphProgress: morph,
            globeOpacity: globeOpacity,
            siteOpacity: siteOpacity
        )
    }

    var presentsGlobe: Bool {
        globeSiteBlend.globeOpacity > 0
    }

    var presentsSite: Bool {
        globeSiteBlend.siteOpacity > 0
    }

    func select(_ preset: Preset) {
        selectedPreset = preset
        altitudeMeters = preset.altitudeMeters
        // Explicit reference configuration preserves inspection-scale captures.
        // Interactive presets are named altitudes in the calibrated camera.
        if !usesAltitudeCamera {
            metersAcross = preset.metersAcross
            tiltDegrees = preset.tiltDegrees
        }
    }

    func focus(on focus: Focus) {
        selectedFocus = focus
        focusNorthOffsetMeters = focus.offsetNorthMeters
        focusEastOffsetMeters = focus.offsetEastMeters
    }

    func resetView() {
        headingDegrees = 0
        navigationMode = .orbit
        focus(on: .eagle)
        select(.regional)
    }

    /// Applies deterministic launch configuration used by Simulator captures
    /// and visual regression checks. Interactive navigation remains available
    /// after launch, but every named preset starts from the same terrain state.
    func configure(arguments: [String]) {
        let isCapture = arguments.contains("--lunar-explorer-capture")
        let inspectionOptions = arguments.contains {
            $0.hasPrefix("--lunar-explorer-") && !$0.hasPrefix("--lunar-explorer-profile")
        }
        isExplorerExperience = !isCapture && !inspectionOptions
        usesWindowContainer = isExplorerExperience
        if isExplorerExperience { camera.reference = nil }
        if isExplorerExperience { returnToGlobe(); showDaylight() }
        captureReanchorProbe = isCapture && arguments.contains("--lunar-explorer-reanchor-probe")
        captureElevationOffline = isCapture && arguments.contains("--lunar-explorer-elevation-offline")
        captureElevationCoordinate = nil
        if isCapture, let argument = arguments.first(where: { $0.hasPrefix("--lunar-explorer-elevation-preview=") }) {
            let values = argument.dropFirst("--lunar-explorer-elevation-preview=".count).split(separator: ",")
            if values.count == 2, let latitude = Double(values[0]), let longitude = Double(values[1]),
               latitude.isFinite, longitude.isFinite, abs(latitude) <= 90 {
                captureElevationCoordinate = .init(latitudeDegrees: latitude, longitudeDegrees: longitude)
            }
        }
        var altitudeOverride: Double?
        var metersAcrossOverride: Double?
        var headingOverride: Double?
        var tiltOverride: Double?
        for argument in arguments {
            if argument.hasPrefix("--lunar-explorer-coordinate=") {
                let values = argument.dropFirst("--lunar-explorer-coordinate=".count).split(separator: ",")
                if values.count == 2, let latitude = Double(values[0]), let longitude = Double(values[1]),
                   latitude.isFinite, longitude.isFinite, abs(latitude) <= 90 {
                    destinationCoordinate = .init(latitudeDegrees: latitude, longitudeDegrees: longitude)
                }
            }
            if argument == "--lunar-explorer-offline" { regionOffline = true }
            if let value = value(after: "--lunar-explorer-preset=", in: argument),
               let preset = Preset(rawValue: value) {
                select(preset)
            } else if let value = value(
                after: "--lunar-explorer-focus=",
                in: argument
            ), let focus = Focus(rawValue: value) {
                self.focus(on: focus)
            } else if let value = value(
                after: "--lunar-explorer-navigation=",
                in: argument
            ), let mode = NavigationMode(rawValue: value) {
                navigationMode = mode
            } else if let value = value(
                after: "--lunar-explorer-detail=",
                in: argument
            ), let mode = LMTerrainDetailMode(rawValue: value) {
                detailMode = mode
            } else if let value = value(
                after: "--lunar-explorer-grade=",
                in: argument
            ), let grade = LMTerrainPresentationGrade(rawValue: value) {
                presentationGrade = grade
            } else if let value = value(
                after: "--lunar-explorer-capture-presentation=",
                in: argument
            ), isCapture, let presentation = CapturePresentation(rawValue: value) {
                capturePresentation = presentation
            } else if argument == "--lunar-explorer-capture-globe-radiance=unmatched",
                      isCapture {
                captureUnmatchedGlobeRadiance = true
            } else if let value = value(
                after: "--lunar-explorer-sun-offset-hours=",
                in: argument
            ), let hours = Double(value), hours.isFinite {
                sunOffsetHours = min(
                    max(hours, -Self.sunScrubRangeHours),
                    Self.sunScrubRangeHours
                )
            } else if let value = value(
                after: "--lunar-explorer-shadows=",
                in: argument
            ) {
                missionShadowsEnabled = value != "off"
            } else if let value = value(
                after: "--lunar-explorer-altitude=",
                in: argument
            ), let altitude = Double(value), altitude.isFinite {
                altitudeOverride = altitude
            } else if let value = value(
                after: "--lunar-explorer-meters-across=",
                in: argument
            ), let metersAcross = Double(value), metersAcross.isFinite {
                metersAcrossOverride = metersAcross
            } else if let value = value(
                after: "--lunar-explorer-heading=",
                in: argument
            ), let heading = Double(value), heading.isFinite {
                headingOverride = heading
            } else if let value = value(
                after: "--lunar-explorer-tilt=",
                in: argument
            ), let tilt = Double(value), tilt.isFinite {
                tiltOverride = tilt
            }
        }

        // Opt-in lighting isolation uses the same daylight selector. Ordinary
        // inspection launches keep their pinned mission instant.
        if isCapture, arguments.contains("--lunar-explorer-capture-daylight"),
           let coordinate = captureElevationCoordinate ?? (try? LMTerrainManifest.load().landingOriginCoordinate) {
            sunAnchorDate = Self.daylightDate(near: Self.apollo11TouchdownUTC, coordinate: coordinate)
            sunOffsetHours = 0
        }

        // Apply numeric overrides after named presets so launch argument order
        // cannot accidentally replace an exact LOD-gate inspection altitude.
        if let altitudeOverride {
            altitudeMeters = min(
                max(altitudeOverride, Self.minimumAltitudeMeters),
                Self.maximumAltitudeMeters
            )
            selectedPreset = closestPreset(to: altitudeMeters)
        }
        if let metersAcrossOverride {
            metersAcross = min(
                max(metersAcrossOverride, Self.minimumMetersAcross),
                Self.maximumMetersAcross
            )
        }
        if let headingOverride {
            headingDegrees = headingOverride.truncatingRemainder(dividingBy: 360)
        }
        if let tiltOverride {
            let minimumTilt = selectedPreset == .globe
                && arguments.contains("--lunar-explorer-capture")
                ? Self.minimumGlobeCaptureTiltDegrees
                : Self.minimumTiltDegrees
            tiltDegrees = min(
                max(tiltOverride, minimumTilt),
                Self.maximumTiltDegrees
            )
        }
    }

    func setOrbit(
        headingDegrees: Double,
        tiltDegrees: Double
    ) {
        self.headingDegrees = headingDegrees.truncatingRemainder(dividingBy: 360)
        self.tiltDegrees = min(
            max(tiltDegrees, Self.minimumTiltDegrees),
            Self.maximumTiltDegrees
        )
    }

    func zoom(by magnification: Double, from initialMetersAcross: Double) {
        guard magnification.isFinite, magnification > 0 else { return }
        let width = min(
            max(initialMetersAcross / magnification, Self.minimumMetersAcross),
            maximumZoomWidth
        )
        // Division at the exact handoff can round one ULP above the gate.
        let gate = Self.globeSiteBlendEndMetersAcross
        metersAcross = abs(width - gate) <= gate.ulp ? gate : width
    }

    func pan(northMeters: Double, eastMeters: Double) {
        focusNorthOffsetMeters = min(max(northMeters, residentPanBounds.north.lowerBound),
                                     residentPanBounds.north.upperBound)
        focusEastOffsetMeters = min(max(eastMeters, residentPanBounds.east.lowerBound),
                                    residentPanBounds.east.upperBound)
        selectedFocus = .eagle
    }

    func fitViewToAltitude() {
        metersAcross = min(
            max(altitudeMeters * 3.2, Self.minimumMetersAcross),
            Self.maximumMetersAcross
        )
    }

    private func closestPreset(to altitude: Double) -> Preset {
        Preset.allCases.min {
            abs(log10($0.altitudeMeters) - log10(altitude))
                < abs(log10($1.altitudeMeters) - log10(altitude))
        } ?? .regional
    }

    private func value(after prefix: String, in argument: String) -> String? {
        guard argument.hasPrefix(prefix) else { return nil }
        return String(argument.dropFirst(prefix.count))
    }
}
