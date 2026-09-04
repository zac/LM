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
    static let maximumFocusOffsetMeters = 900.0
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

    var selectedPreset: Preset = .regional
    var selectedFocus: Focus = .eagle
    var navigationMode: NavigationMode = .orbit
    var detailMode: LMTerrainDetailMode = .automatic
    var altitudeMeters = Preset.regional.altitudeMeters
    var metersAcross = Preset.regional.metersAcross
    var headingDegrees = 0.0
    var tiltDegrees = Preset.regional.tiltDegrees
    var focusNorthOffsetMeters = 0.0
    var focusEastOffsetMeters = 0.0
    var missionShadowsEnabled = true
    /// Mission lighting is time-driven. The ephemeris evaluates the Sun for
    /// this instant, so any date shows its own real illumination rather than a
    /// single baked-in direction. The anchor is a named instant and the offset
    /// is the scrub around it, which keeps "return to the landing" one tap
    /// away no matter how far the terminator has been swept.
    var sunAnchorDate = LunarExplorerSession.apollo11TouchdownUTC
    var sunOffsetHours = 0.0
    /// Tonal presentation. Changing this rebuilds resident tiles, because the
    /// exposure floor is baked into each tile's material.
    var presentationGrade: LMTerrainPresentationGrade = .calibrated
    var diagnosticsVisible = true
    var diagnostics = Diagnostics()
    /// Capture-only layer isolation for measuring the globe/site handoff at
    /// identical camera scale. Normal launches always leave this nil.
    private(set) var capturePresentation: CapturePresentation?
    /// Capture-only radiance bypass used to retain a before frame after the
    /// shipping globe match is active.
    private(set) var captureUnmatchedGlobeRadiance = false
    private(set) var captureReanchorProbe = false

    var logarithmicAltitude: Double {
        get { log10(altitudeMeters) }
        set {
            altitudeMeters = min(
                max(pow(10, newValue), Self.minimumAltitudeMeters),
                Self.maximumAltitudeMeters
            )
            selectedPreset = closestPreset(to: altitudeMeters)
        }
    }

    var logarithmicMetersAcross: Double {
        get { log10(metersAcross) }
        set {
            metersAcross = min(
                max(pow(10, newValue), Self.minimumMetersAcross),
                Self.maximumMetersAcross
            )
        }
    }

    /// Three scene meters span the selected inspection width.
    var presentationScale: Float {
        Float(3 / metersAcross)
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
        let matched = 1 + (Self.globeSiteLinearRadianceMultiplier - 1)
            * globeHandoffRampProgress
        guard capturePresentation == nil else { return matched }
        let siteOpacity = automaticGlobeSiteBlend.siteOpacity
        let compositingCompensation = 1
            + Self.globeCrossfadeCompositingCompensation
                * sin(.pi * siteOpacity)
        return matched * compositingCompensation
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
        metersAcross = preset.metersAcross
        tiltDegrees = preset.tiltDegrees
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
        captureReanchorProbe = isCapture && arguments.contains("--lunar-explorer-reanchor-probe")
        var altitudeOverride: Double?
        var metersAcrossOverride: Double?
        var headingOverride: Double?
        var tiltOverride: Double?
        for argument in arguments {
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
        metersAcross = min(
            max(initialMetersAcross / magnification, Self.minimumMetersAcross),
            Self.maximumMetersAcross
        )
    }

    func pan(northMeters: Double, eastMeters: Double) {
        focusNorthOffsetMeters = min(
            max(northMeters, -Self.maximumFocusOffsetMeters),
            Self.maximumFocusOffsetMeters
        )
        focusEastOffsetMeters = min(
            max(eastMeters, -Self.maximumFocusOffsetMeters),
            Self.maximumFocusOffsetMeters
        )
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
