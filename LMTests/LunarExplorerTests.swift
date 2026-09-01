import Testing
import simd
@testable import LM

@Suite("Lunar Explorer")
@MainActor
struct LunarExplorerTests {
    @Test func presetsCrossEveryProductionLODGate() {
        let session = LunarExplorerSession()
        let policy = LMTerrainDetailPolicy()

        session.select(.globe)
        #expect(session.presentsGlobe)
        #expect(!session.presentsSite)
        #expect(policy.finestSpacingMeters(altitudeMeters: session.altitudeMeters) == nil)

        session.select(.orbit)
        #expect(!session.presentsGlobe)
        #expect(session.presentsSite)
        #expect(policy.finestSpacingMeters(altitudeMeters: session.altitudeMeters) == nil)

        session.select(.approach)
        #expect(policy.finestSpacingMeters(altitudeMeters: session.altitudeMeters) == 2)

        session.select(.terminal)
        #expect(policy.finestSpacingMeters(altitudeMeters: session.altitudeMeters) == 0.5)

        session.select(.landing)
        #expect(policy.finestSpacingMeters(altitudeMeters: session.altitudeMeters) == 0.125)

        session.select(.surface)
        #expect(policy.finestSpacingMeters(altitudeMeters: session.altitudeMeters) == 0.125)
    }

    @Test func globeAndSiteCrossfadeOverTheMeasuredBand() {
        let session = LunarExplorerSession()

        session.metersAcross = 400_000
        #expect(session.globeSiteBlend == .init(
            progress: 0,
            morphProgress: 0,
            globeOpacity: 1,
            siteOpacity: 0
        ))
        #expect(session.presentsGlobe)
        #expect(!session.presentsSite)

        session.metersAcross = 260_000
        #expect(abs(session.globeSiteBlend.progress - 0.5) < 1e-12)
        #expect(session.globeSiteBlend.morphProgress == 0)
        #expect(session.globeSiteBlend.globeOpacity == 0)
        #expect(session.globeSiteBlend.siteOpacity == 1)
        #expect(!session.presentsGlobe)
        #expect(session.presentsSite)

        session.metersAcross = 120_000
        #expect(session.globeSiteBlend == .init(
            progress: 1,
            morphProgress: 1,
            globeOpacity: 0,
            siteOpacity: 1
        ))
        #expect(!session.presentsGlobe)
        #expect(session.presentsSite)
    }

    @Test func registeredSiteCenterPreservesTheApolloViewRay() {
        let eye = SIMD3<Float>(0, 1.45, 0)
        let apollo = SIMD3<Float>(0.7, 0.2, -2.9)
        let registered = LunarExplorerScene.registeredSitePresentationPosition(
            apolloSurfacePosition: apollo,
            eyePosition: eye,
            depthMeters: 1.45
        )
        let globeRay = simd_normalize(apollo - eye)
        let siteRay = simd_normalize(registered - eye)

        #expect(simd_length(globeRay - siteRay) < 1e-6)
        #expect(abs(simd_length(registered - eye) - 1.45) < 1e-6)
    }

    @Test func zoomDoesNotSilentlyChangeVirtualAltitude() {
        let session = LunarExplorerSession()
        session.select(.terminal)
        let altitude = session.altitudeMeters
        let initialWidth = session.metersAcross

        session.zoom(by: 4, from: initialWidth)

        #expect(session.metersAcross == initialWidth / 4)
        #expect(session.altitudeMeters == altitude)
    }

    @Test func orbitAndPanStayInsideInspectionBounds() {
        let session = LunarExplorerSession()

        session.setOrbit(headingDegrees: 725, tiltDegrees: -20)
        session.pan(northMeters: 5_000, eastMeters: -5_000)

        #expect(session.headingDegrees == 5)
        #expect(session.tiltDegrees == LunarExplorerSession.minimumTiltDegrees)
        #expect(
            session.focusNorthOffsetMeters
                == LunarExplorerSession.maximumFocusOffsetMeters
        )
        #expect(
            session.focusEastOffsetMeters
                == -LunarExplorerSession.maximumFocusOffsetMeters
        )
    }

    @Test func launchArgumentsSelectARepeatableInspectionView() {
        let session = LunarExplorerSession()

        session.configure(arguments: [
            "LM",
            "--lunar-explorer",
            "--lunar-explorer-preset=landing",
            "--lunar-explorer-focus=northBoulderField",
            "--lunar-explorer-navigation=pan",
            "--lunar-explorer-detail=procedural",
        ])

        #expect(session.selectedPreset == .landing)
        #expect(session.altitudeMeters == LunarExplorerSession.Preset.landing.altitudeMeters)
        #expect(session.metersAcross == LunarExplorerSession.Preset.landing.metersAcross)
        #expect(session.selectedFocus == .northBoulderField)
        #expect(session.focusNorthOffsetMeters == 135)
        #expect(session.navigationMode == .pan)
        #expect(session.detailMode == .procedural)
    }

    @Test func appModelConfiguresExplorerBeforeRestoredWindowsAppear() {
        let model = MainMenuViewModel(arguments: [
            "LM",
            "--lunar-explorer",
            "--lunar-explorer-preset=surface",
            "--lunar-explorer-focus=northBoulderField",
        ])

        #expect(model.lunarExplorerSession.selectedPreset == .surface)
        #expect(model.lunarExplorerSession.altitudeMeters == 2)
        #expect(model.lunarExplorerSession.selectedFocus == .northBoulderField)
    }

    @Test func captureLaunchHidesControlsWithoutChangingNormalLaunches() {
        #expect(!LunarExplorerSession.presentsControls(arguments: [
            "LM",
            "--lunar-explorer",
            "--lunar-explorer-capture",
        ]))
        #expect(LunarExplorerSession.presentsControls(arguments: [
            "LM",
            "--lunar-explorer",
        ]))
    }

    @Test func launchArgumentsPinExactLODGateAltitudeAndFraming() {
        let session = LunarExplorerSession()

        session.configure(arguments: [
            "LM",
            "--lunar-explorer-altitude=249.5",
            "--lunar-explorer-meters-across=700",
            "--lunar-explorer-preset=orbit",
            "--lunar-explorer-shadows=off",
        ])

        #expect(session.altitudeMeters == 249.5)
        #expect(session.metersAcross == 700)
        #expect(session.missionShadowsEnabled == false)
        #expect(session.selectedPreset == .terminal)
        #expect(
            LMTerrainDetailPolicy().finestSpacingMeters(
                altitudeMeters: session.altitudeMeters
            ) == 0.5
        )
    }

    @Test func captureArgumentsCanInspectGlobeOrientationAndNearGateScale() {
        let session = LunarExplorerSession()
        session.configure(arguments: [
            "LM",
            "--lunar-explorer-preset=globe",
            "--lunar-explorer-meters-across=375000",
            "--lunar-explorer-heading=180",
            "--lunar-explorer-tilt=82",
        ])

        #expect(session.headingDegrees == 180)
        #expect(session.tiltDegrees == 82)
        #expect(session.presentsGlobe)
        #expect(session.presentsSite)
        #expect(
            session.globePresentationScale
                == LunarExplorerSession.maximumGlobeDisplayRadiusMeters
                    / Float(LunarExplorerSession.lunarGlobeRadiusMeters)
        )
    }

    @Test func captureCanInspectBothGlobePolesWithoutChangingSiteTiltBounds() {
        let globe = LunarExplorerSession()
        globe.configure(arguments: [
            "LM",
            "--lunar-explorer-preset=globe",
            "--lunar-explorer-tilt=-82",
            "--lunar-explorer-capture",
        ])
        let site = LunarExplorerSession()
        site.configure(arguments: [
            "LM",
            "--lunar-explorer-preset=orbit",
            "--lunar-explorer-tilt=-82",
            "--lunar-explorer-capture",
        ])

        #expect(globe.tiltDegrees == -82)
        #expect(site.tiltDegrees == LunarExplorerSession.minimumTiltDegrees)
    }

    @Test func invalidAndOutOfRangeCaptureOverridesAreSafe() {
        let invalid = LunarExplorerSession()
        invalid.configure(arguments: [
            "LM",
            "--lunar-explorer-altitude=not-a-number",
            "--lunar-explorer-meters-across=nan",
        ])
        #expect(invalid.altitudeMeters == LunarExplorerSession.Preset.regional.altitudeMeters)
        #expect(invalid.metersAcross == LunarExplorerSession.Preset.regional.metersAcross)

        let clamped = LunarExplorerSession()
        clamped.configure(arguments: [
            "LM",
            "--lunar-explorer-altitude=0",
            "--lunar-explorer-meters-across=9999999",
        ])
        #expect(clamped.altitudeMeters == LunarExplorerSession.minimumAltitudeMeters)
        #expect(clamped.metersAcross == LunarExplorerSession.maximumMetersAcross)
    }

    @Test func launchArgumentsSelectComparableAppearanceImplementations() {
        let procedural = LunarExplorerSession()
        procedural.configure(arguments: [
            "LM",
            "--lunar-explorer-detail=procedural",
        ])
        let neural = LunarExplorerSession()
        neural.configure(arguments: [
            "LM",
            "--lunar-explorer-detail=neural",
        ])
        let invalid = LunarExplorerSession()
        invalid.configure(arguments: [
            "LM",
            "--lunar-explorer-detail=unknown",
        ])

        #expect(procedural.detailMode == .procedural)
        #expect(neural.detailMode == .neural)
        #expect(invalid.detailMode == .automatic)
        #expect(
            LMTerrainDetailMode.procedural.makePipeline().modelID
                == LMTerrainTileDetailBaker.modelID
        )
    }
}
