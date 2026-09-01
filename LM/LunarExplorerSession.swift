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
    }

    static let minimumAltitudeMeters = 1.5
    static let maximumAltitudeMeters = 1_500_000.0
    static let minimumMetersAcross = 8.0
    static let maximumMetersAcross = 5_000_000.0
    static let minimumTiltDegrees = 18.0
    static let minimumGlobeCaptureTiltDegrees = -82.0
    static let maximumTiltDegrees = 82.0
    static let maximumFocusOffsetMeters = 900.0
    /// Keep the temporary discrete globe view outside the viewer even when a
    /// capture deliberately approaches the globe/site gate. The measured
    /// crossfade replaces this cap later in Stage 1.
    static let maximumGlobeDisplayRadiusMeters: Float = 1.35
    static let lunarGlobeRadiusMeters = 1_737_400.0
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
        min(
            presentationScale,
            Self.maximumGlobeDisplayRadiusMeters / Float(Self.lunarGlobeRadiusMeters)
        )
    }

    /// The first Stage 1 gate deliberately avoids pretending that globe/site
    /// curvature registration is complete. A later slice will replace this
    /// discrete switch with the plan's measured crossfade.
    var presentsGlobe: Bool {
        metersAcross >= 350_000
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
