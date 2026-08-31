import Testing
@testable import LM

@Suite("Selenographic coordinate authority")
struct LMSelenographicCoordinateTests {
    private let system = LMSelenographicCoordinateSystem()

    @Test func meanEarthPolarDatumAndCardinalAxesAreExplicit() {
        #expect(system.datumRadiusMeters == 1_737_400)

        let primeMeridian = system.moonCenteredPosition(
            for: LMSelenographicCoordinate(latitudeDegrees: 0, longitudeDegrees: 0)
        )
        let east = system.moonCenteredPosition(
            for: LMSelenographicCoordinate(latitudeDegrees: 0, longitudeDegrees: 90)
        )
        let northPole = system.moonCenteredPosition(
            for: LMSelenographicCoordinate(latitudeDegrees: 90, longitudeDegrees: 0)
        )

        #expect(distance(primeMeridian.vector, [1_737_400, 0, 0]) < 1e-9)
        #expect(distance(east.vector, [0, 1_737_400, 0]) < 1e-9)
        #expect(distance(northPole.vector, [0, 0, 1_737_400]) < 1e-9)
    }

    @Test(arguments: [
        LMSelenographicCoordinate(
            latitudeDegrees: 0.673433,
            longitudeDegrees: 23.473113,
            heightMeters: -1_928.037353515625
        ),
        LMSelenographicCoordinate(
            latitudeDegrees: -42.125,
            longitudeDegrees: 179.75,
            heightMeters: 8_912.25
        ),
        LMSelenographicCoordinate(
            latitudeDegrees: 89.999,
            longitudeDegrees: -135,
            heightMeters: -2_500
        ),
    ])
    func moonCenteredRoundTripIsSubMillimeter(
        coordinate: LMSelenographicCoordinate
    ) {
        let position = system.moonCenteredPosition(for: coordinate)
        let roundTrip = system.coordinate(for: position)
        let reconstructed = system.moonCenteredPosition(for: roundTrip)

        #expect(distance(position.vector, reconstructed.vector) < 0.001)
        #expect(abs(roundTrip.heightMeters - coordinate.heightMeters) < 0.001)
    }

    @Test func siteFrameRoundTripIsSubMillimeterAtApollo11() throws {
        let manifest = try LMTerrainManifest.load()
        let frame = manifest.landingLocalFrame
        let coordinate = LMSelenographicCoordinate(
            latitudeDegrees: manifest.landingOrigin.latitudeDegrees + 0.0017,
            longitudeDegrees: manifest.landingOrigin.longitudeDegrees - 0.0021,
            heightMeters: manifest.landingOriginElevationMeters + 37.25
        )

        let local = frame.position(for: coordinate)
        let roundTrip = frame.coordinate(for: local)
        let expectedPosition = manifest.selenographicCoordinateSystem
            .moonCenteredPosition(for: coordinate)
        let actualPosition = manifest.selenographicCoordinateSystem
            .moonCenteredPosition(for: roundTrip)

        #expect(distance(expectedPosition.vector, actualPosition.vector) < 0.001)
    }

    @Test func productionSiteProjectionRoundTripIsSubMillimeter() throws {
        let manifest = try LMTerrainManifest.load()
        let coordinate = LMSelenographicCoordinate(
            latitudeDegrees: manifest.landingOrigin.latitudeDegrees - 0.42,
            longitudeDegrees: manifest.landingOrigin.longitudeDegrees + 0.38,
            heightMeters: manifest.landingOriginElevationMeters + 2_345.67
        )
        let local = manifest.selenographicCoordinateSystem.sitePosition(
            for: coordinate,
            relativeTo: manifest.landingOriginCoordinate
        )
        let roundTrip = manifest.selenographicCoordinateSystem.coordinate(
            forSitePosition: local,
            relativeTo: manifest.landingOriginCoordinate
        )
        let expectedPosition = manifest.selenographicCoordinateSystem
            .moonCenteredPosition(for: coordinate)
        let actualPosition = manifest.selenographicCoordinateSystem
            .moonCenteredPosition(for: roundTrip)

        #expect(distance(expectedPosition.vector, actualPosition.vector) < 0.001)
    }

    @Test func manifestAnchorAndTerrainAlignmentUseTheSameFrame() throws {
        let manifest = try LMTerrainManifest.load()
        let frame = manifest.landingLocalFrame
        let anchor = frame.position(for: manifest.landingOriginCoordinate)

        #expect(abs(anchor.northMeters) < 1e-9)
        #expect(abs(anchor.eastMeters) < 1e-9)
        #expect(abs(anchor.upMeters) < 1e-9)

        let eagle = try #require(
            manifest.landmark(id: LMTerrainManifest.eagleLandmarkID)
        )
        let eagleENU = manifest.selenographicCoordinateSystem.sitePosition(
            for: LMSelenographicCoordinate(
                latitudeDegrees: eagle.latitudeDegrees,
                longitudeDegrees: eagle.longitudeDegrees,
                heightMeters: manifest.landingOriginElevationMeters
            ),
            relativeTo: manifest.landingOriginCoordinate
        )
        let terrainPosition = manifest.localPosition(of: eagle)
        let alignment = try LMTerrainFrameAlignment(manifest: manifest)

        #expect(abs(terrainPosition.x - eagleENU.northMeters) < 1e-9)
        #expect(abs(terrainPosition.y - eagleENU.eastMeters) < 1e-9)
        #expect(terrainPosition.z == 0)
        #expect(alignment.terrainReferenceTouchdown == terrainPosition)
    }

    @Test func longitudeIsCanonicalAcrossTheAntimeridian() {
        #expect(
            LMSelenographicCoordinate(
                latitudeDegrees: 0,
                longitudeDegrees: 540
            ).longitudeDegrees == -180
        )
        #expect(
            LMSelenographicCoordinate(
                latitudeDegrees: 0,
                longitudeDegrees: -181
            ).longitudeDegrees == 179
        )
    }

    private func distance(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
        let delta = lhs - rhs
        return (delta.x * delta.x + delta.y * delta.y + delta.z * delta.z).squareRoot()
    }
}
