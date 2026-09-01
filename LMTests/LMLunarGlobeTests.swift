import Foundation
import ImageIO
import Testing
@testable import LM

@Suite("Pinned lunar globe")
struct LMLunarGlobeTests {
    @Test func manifestPinsTheGlobalMorphologicBase() throws {
        let manifest = try LMTerrainManifest.load()
        let tier = try #require(manifest.globe.textureTiers.first)
        let source = try #require(
            manifest.sources.first { $0.id == tier.sourceID }
        )

        #expect(manifest.schemaVersion == LMTerrainManifest.schemaVersion)
        #expect(manifest.globe.coordinateSystemName == "IAU_ME")
        #expect(manifest.globe.materialMode == "unlit-morphologic-map")
        #expect(manifest.globe.radiusMeters == manifest.projection.sphereRadiusMeters)
        #expect(tier.width == 5_760)
        #expect(tier.height == 2_880)
        #expect(tier.mapResolutionPixelsPerDegree == 16)
        #expect(tier.sha256 == "b799eab2d43f7a27799972d4ec4bc25cff06776ba14774e03e322cb7a7ea460e")
        #expect(source.sha256 == "c75a49b48df0d1d8afad8f25e58332599e8383e4967424ffbb0ba38b0808b2b6")
        #expect(source.bytes == 66_378_240)
        #expect(source.productId == "WAC_GLOBAL_E000N0000_016P")
        #expect(source.productVersion == "v1.3")
        #expect(
            source.url
                == "https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/BDR/WAC_GLOBAL/WAC_GLOBAL_E000N0000_016P.IMG"
        )
        #expect(source.labelURL == source.url)
    }

    @Test func bundledTextureMatchesTheManifestDimensions() throws {
        let manifest = try LMTerrainManifest.load()
        let tier = try #require(manifest.globe.textureTiers.first)
        let name = (tier.file as NSString).deletingPathExtension
        let ext = (tier.file as NSString).pathExtension
        let url = try #require(
            Bundle.main.url(
                forResource: name,
                withExtension: ext,
                subdirectory: "Terrain"
            ) ?? Bundle.main.url(forResource: name, withExtension: ext)
        )
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == tier.width)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == tier.height)
    }

    @Test func displayBasisUsesApollo11AsDiskCenter() throws {
        let manifest = try LMTerrainManifest.load()
        let front = manifest.landingOriginCoordinate
        let radius = manifest.globe.radiusMeters
        let center = LMLunarGlobeResource.displayPosition(
            coordinate: front,
            frontCoordinate: front,
            radiusMeters: radius
        )
        let north = LMLunarGlobeResource.displayPosition(
            coordinate: LMSelenographicCoordinate(
                latitudeDegrees: front.latitudeDegrees + 1,
                longitudeDegrees: front.longitudeDegrees
            ),
            frontCoordinate: front,
            radiusMeters: radius
        )
        let east = LMLunarGlobeResource.displayPosition(
            coordinate: LMSelenographicCoordinate(
                latitudeDegrees: front.latitudeDegrees,
                longitudeDegrees: front.longitudeDegrees + 1
            ),
            frontCoordinate: front,
            radiusMeters: radius
        )

        #expect(abs(center.x) < 0.1)
        #expect(abs(center.y) < 0.1)
        #expect(abs(Double(center.z) - (radius + front.heightMeters)) < 0.1)
        #expect(north.y > 0)
        #expect(east.x > 0)
    }

    @Test func apollo11CoordinateMapsToPinnedWACPixel() throws {
        let manifest = try LMTerrainManifest.load()
        let tier = try #require(manifest.globe.textureTiers.first)
        let uv = LMLunarGlobeResource.textureCoordinate(
            for: manifest.landingOriginCoordinate
        )

        #expect(abs(uv.x - 0.5652030916666667) < 0.000000001)
        #expect(abs(uv.y - 0.4962587055555555) < 0.000000001)
        #expect(abs(uv.x * Double(tier.width) - 3_255.569808) < 0.001)
        #expect(abs(uv.y * Double(tier.height) - 1_429.225072) < 0.001)
    }

    @Test func namedNearSideLandmarksHaveTheExpectedApolloCenteredOrientation() throws {
        let manifest = try LMTerrainManifest.load()
        let front = manifest.landingOriginCoordinate
        let radius = manifest.globe.radiusMeters
        let mareCrisium = LMLunarGlobeResource.displayPosition(
            coordinate: LMSelenographicCoordinate(
                latitudeDegrees: 17.0,
                longitudeDegrees: 59.1
            ),
            frontCoordinate: front,
            radiusMeters: radius
        )
        let tycho = LMLunarGlobeResource.displayPosition(
            coordinate: LMSelenographicCoordinate(
                latitudeDegrees: -43.31,
                longitudeDegrees: -11.36
            ),
            frontCoordinate: front,
            radiusMeters: radius
        )

        // In the default ME view, east is screen-right and north is up.
        // Both landmarks remain on the visible hemisphere; Crisium is in the
        // northeast quadrant and Tycho's ray system is in the southwest.
        #expect(mareCrisium.x > 0)
        #expect(mareCrisium.y > 0)
        #expect(mareCrisium.z > 0)
        #expect(tycho.x < 0)
        #expect(tycho.y < 0)
        #expect(tycho.z > 0)
    }

    @Test func terminatorIsAMultiplierRatherThanASecondLightingPass() {
        let sun = SIMD3<Double>(1, 0, 0)
        let day = LMLunarGlobeResource.terminatorMultiplier(
            surfaceNormal: sun,
            subsolarDirection: sun
        )
        let night = LMLunarGlobeResource.terminatorMultiplier(
            surfaceNormal: -sun,
            subsolarDirection: sun
        )
        let limb = LMLunarGlobeResource.terminatorMultiplier(
            surfaceNormal: SIMD3(0, 1, 0),
            subsolarDirection: sun
        )

        #expect(day == 1)
        #expect(night == LMLunarGlobeResource.terminatorNightMultiplier)
        #expect(abs(limb - (1 + night) / 2) < 0.000_001)
    }

    @Test func terminatorMaskMovesWithTheSessionSunDate() {
        let landing = LunarExplorerSession.apollo11TouchdownUTC
        let later = landing.addingTimeInterval(7 * 24 * 3_600)
        let landingSamples = LMLunarGlobeResource.terminatorOpacitySamples(
            date: landing,
            width: 180,
            height: 90
        )
        let laterSamples = LMLunarGlobeResource.terminatorOpacitySamples(
            date: later,
            width: 180,
            height: 90
        )

        #expect(landingSamples != laterSamples)
        #expect(landingSamples.contains(0))
        #expect(landingSamples.max() == UInt8(
            ((1 - LMLunarGlobeResource.terminatorNightMultiplier) * 255).rounded()
        ))
    }
}
