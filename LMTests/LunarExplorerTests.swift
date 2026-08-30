import Testing
@testable import LM

@Suite("Lunar Explorer")
@MainActor
struct LunarExplorerTests {
    @Test func presetsCrossEveryProductionLODGate() {
        let session = LunarExplorerSession()
        let policy = LMTerrainDetailPolicy()

        session.select(.orbit)
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
        ])

        #expect(session.selectedPreset == .landing)
        #expect(session.altitudeMeters == LunarExplorerSession.Preset.landing.altitudeMeters)
        #expect(session.metersAcross == LunarExplorerSession.Preset.landing.metersAcross)
        #expect(session.selectedFocus == .northBoulderField)
        #expect(session.focusNorthOffsetMeters == 135)
        #expect(session.navigationMode == .pan)
    }
}
