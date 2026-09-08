import Foundation
import Testing
import simd
@testable import LM

@Suite("Lunar navigation")
struct LMLunarNavigationTests {
    @Test func coordinatesRejectInvalidInputAndPreserveEastPositiveConvention() {
        for text in ["NaN, 0", "0, inf", "91, 0", "0,181", "1", "1,2,3", ","] {
            #expect(LMLunarNavigation.parse(text) == nil)
        }
        #expect(LMLunarNavigation.parse(" -90, 180 ") == .init(latitudeDegrees: -90, longitudeDegrees: 180))
    }
    @Test func greatCircleTakesShortDatelinePathAndHandlesPolesAndAntipodes() {
        let a = LMSelenographicCoordinate(latitudeDegrees: 0, longitudeDegrees: 179)
        let b = LMSelenographicCoordinate(latitudeDegrees: 0, longitudeDegrees: -179)
        let middle = LMLunarNavigation.interpolate(from: a, to: b, fraction: 0.5)
        #expect(abs(abs(middle.longitudeDegrees) - 180) < 1e-9)
        for target in [LMSelenographicCoordinate(latitudeDegrees: 90, longitudeDegrees: 0),
                       .init(latitudeDegrees: 0, longitudeDegrees: -1)] {
            for i in 0...100 {
                let p = LMLunarNavigation.interpolate(from: a, to: target, fraction: Double(i) / 100)
                #expect(p.latitudeDegrees.isFinite && p.longitudeDegrees.isFinite)
            }
            #expect(LMLunarNavigation.interpolate(from: a, to: target, fraction: 1) == target)
        }
    }
    @Test func globeRotationKeepsDestinationAtDiskCenter() {
        let a = LMSelenographicCoordinate(latitudeDegrees: 0.67416, longitudeDegrees: 23.47314)
        for b in [LMSelenographicCoordinate(latitudeDegrees: -89.67, longitudeDegrees: 129.78),
                  .init(latitudeDegrees: 20.1911, longitudeDegrees: 30.7723),
                  .init(latitudeDegrees: 0, longitudeDegrees: -179.99)] {
            let original = LMLunarGlobeResource.displayPosition(coordinate: b, frontCoordinate: a, radiusMeters: 1)
            let rotated = LMLunarNavigation.displayRotation(from: a, to: b).act(original)
            #expect(simd_length(rotated - SIMD3(0, 0, 1)) < 1e-6)
        }
    }
    @Test func catalogHasVerifiedNaturalFeaturesAndApolloSites() throws {
        let catalog = try LMLunarPOICatalog.load()
        #expect(catalog.version == 1)
        #expect(Set(catalog.features.map(\.id)).count == catalog.features.count)
        #expect(catalog.features.count == 18)
        for p in catalog.features {
            #expect(!p.category.isEmpty && !p.blurb.isEmpty)
            #expect(p.suggestedAltitudeMeters > 0 && p.suggestedHeadingDegrees.isFinite)
            #expect(abs(p.latitude) <= 90 && abs(p.longitude) <= 180)
            #expect(["planetarynames.wr.usgs.gov", "www.lroc.asu.edu", "ssd.jpl.nasa.gov"].contains(p.sourceURL.host()))
        }
        let apollo = try #require(catalog.features.first { $0.id == "apollo-11" })
        #expect(apollo.coordinate == (try LMTerrainManifest.load()).landingOriginCoordinate)
    }
    @Test @MainActor func globalPanHasFiniteSourceWindowAndApolloBoundsStayUnchanged() throws {
        let manifest = try LMTerrainManifest.load()
        let landmark = try #require(manifest.landmark(id: LMTerrainManifest.eagleLandmarkID))
        let focusOrigin = manifest.localPosition(of: landmark)
        let pack = try LunarExplorerSitePack(manifest: manifest, focusOrigin: focusOrigin)
        let nearField = try #require(manifest.tile(id: "near-field"))
        let halfExtent = nearField.extentMeters / 2 - 128
        #expect(pack.panBounds.north == (-halfExtent - focusOrigin.x)...(halfExtent - focusOrigin.x))
        #expect(pack.panBounds.east == (-halfExtent - focusOrigin.y)...(halfExtent - focusOrigin.y))

        let session = LunarExplorerSession()
        session.residentPanBounds = pack.panBounds
        session.pan(northMeters: 100_000, eastMeters: -100_000)
        #expect(session.focusNorthOffsetMeters == pack.panBounds.north.upperBound)
        #expect(session.focusEastOffsetMeters == pack.panBounds.east.lowerBound)
        session.pan(northMeters: -100_000, eastMeters: 100_000)
        #expect(session.focusNorthOffsetMeters == pack.panBounds.north.lowerBound)
        #expect(session.focusEastOffsetMeters == pack.panBounds.east.upperBound)
        session.destinationCoordinate = .init(latitudeDegrees: 0, longitudeDegrees: 0)
        session.usesBundledSite = false
        session.residentPanBounds = .regional
        session.pan(northMeters: 100_000, eastMeters: -100_000)
        #expect(session.focusNorthOffsetMeters == 20_000)
        #expect(session.focusEastOffsetMeters == -20_000)
    }
}
