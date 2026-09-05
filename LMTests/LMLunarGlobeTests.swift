import CryptoKit
import Foundation
import ImageIO
import simd
import Testing
@testable import LM

@Suite("Pinned lunar globe")
struct LMLunarGlobeTests {
    @Test func manifestPinsTheGlobalMorphologicBase() throws {
        let manifest = try LMTerrainManifest.load()
        let tier = try #require(manifest.globe.textureTiers.first)
        let normalMap = manifest.globe.normalMap
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
        let elevationSource = try #require(
            manifest.sources.first { $0.id == normalMap.sourceID }
        )
        #expect(normalMap.width == 5_760)
        #expect(normalMap.height == 2_880)
        #expect(normalMap.coordinateFrame == "IAU_ME")
        #expect(normalMap.sha256 == "bd70494eb4194aca023e4f4f724cc7a6d11a4b23148f4519192715694dd34696")
        #expect(elevationSource.bytes == 33_177_600)
        #expect(elevationSource.sha256 == "a511e40d7a3ea3275945b4da2a1df377133264fab0be94b7434b1cf8907254cb")
        #expect(elevationSource.labelBytes == 5_121)
        #expect(elevationSource.labelSHA256 == "9aef29463ccc6ed3a3fbe0df3ecd830a99c69e16b564f455507dee2697096579")
        #expect(elevationSource.productId == "LDEM_16")
        #expect(elevationSource.productVersion == "V3.1")
        #expect(elevationSource.url == "https://imbrium.mit.edu/DATA/LOLA_GDR/CYLINDRICAL/IMG/LDEM_16.IMG")
    }

    @Test func bundledNormalMapMatchesManifestAndMEOrientation() throws {
        let manifest = try LMTerrainManifest.load()
        let map = manifest.globe.normalMap
        let name = (map.file as NSString).deletingPathExtension
        let ext = (map.file as NSString).pathExtension
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
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == map.width)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == map.height)

        let width = 360
        let height = 180
        let normals = try LMLunarGlobeResource.globeNormalSamples(
            manifest: manifest,
            bundle: .main,
            width: width,
            height: height
        )
        let north = normals[0..<width]
        let south = normals[((height - 1) * width)..<(height * width)]
        #expect(north.allSatisfy { $0.z > 0.95 })
        #expect(south.allSatisfy { $0.z < -0.95 })
        let seamWest = normals[(height / 2) * width]
        let seamEast = normals[(height / 2) * width + width - 1]
        #expect(simd_dot(seamWest, seamEast) > 0.98)
    }

    @Test func bundledTexturesMatchManifestDimensionsAndHashes() throws {
        let manifest = try LMTerrainManifest.load()
        for tier in manifest.globe.textureTiers {
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
            // Xcode losslessly rewrites PNG resources while copying them into
            // the product, so their installed file hash is not a provenance
            // hash. JPEG XL is copied verbatim and must retain its manifest
            // digest through the actual app-bundle path.
            if tier.codec == "JPEG XL" {
                let digest = SHA256.hash(
                    data: try Data(contentsOf: url, options: .mappedIfSafe)
                )
                    .map { String(format: "%02x", $0) }
                    .joined()
                #expect(digest == tier.sha256)
            }
        }
    }

    @Test func manifestPinsTheOffline64PPDJXLTier() throws {
        let manifest = try LMTerrainManifest.load()
        let tier = try #require(
            manifest.globe.textureTiers.first { $0.id == "wac-global-64ppd" }
        )
        let source = try #require(
            manifest.sources.first { $0.id == tier.sourceID }
        )
        #expect(tier.file == "WACGlobal64PPD-q95.jxl")
        #expect(tier.width == 23_040)
        #expect(tier.height == 11_520)
        #expect(tier.mapResolutionPixelsPerDegree == 64)
        #expect(tier.sha256 == "819ca84afedca9a5fe864a0a3a036bc6384a105f21135614c90808c184355841")
        #expect(tier.codec == "JPEG XL")
        #expect(tier.codecQuality == 95)
        #expect(tier.codecEffort == 7)
        #expect(tier.codecEncoder == "cjxl 0.12.0 effort 7")
        #expect(tier.losslessSourceSHA256 == "faead7d93e3ac1b16f30955419f4cbb2f1fbd1040dbc2913473ccd5f30df2420")
        #expect(tier.losslessSourceBytes == 128_461_405)
        #expect(source.productId == "WAC_GLOBAL_E000N0000_064P")
        #expect(source.productVersion == "v1.3")
        #expect(source.bytes == 1_061_775_360)
        #expect(source.sha256 == "bc1feab6e86ae2cf47798a4f00cdf7f5e73030fcbc2223fba7fab59a5a2a34ec")
    }

    @Test func interactiveExplorerPrefers64WhileCapturesRetain16() throws {
        let tiers = try LMTerrainManifest.load().globe.textureTiers
        #expect(LMLunarGlobeResource.textureTier(
            from: tiers,
            arguments: ["LM", "--lunar-explorer"]
        )?.id == "wac-global-64ppd")
        #expect(LMLunarGlobeResource.textureLoadTiers(
            from: tiers,
            arguments: ["LM", "--lunar-explorer"]
        ).map(\.id) == ["wac-global-64ppd", "wac-global-16ppd"])
        #expect(LMLunarGlobeResource.textureLoadTiers(
            from: tiers,
            arguments: ["LM", "--lunar-explorer-capture"]
        ).map(\.id) == ["wac-global-16ppd"])
        #expect(LMLunarGlobeResource.textureLoadTiers(
            from: tiers,
            arguments: [
                "LM",
                "--lunar-globe-texture-tier=wac-global-64ppd"
            ]
        ).map(\.id) == ["wac-global-64ppd"])
        #expect(LMLunarGlobeResource.textureTier(
            from: tiers,
            arguments: ["LM", "--lunar-explorer-capture"]
        )?.id == "wac-global-16ppd")
        #expect(LMLunarGlobeResource.textureTier(
            from: tiers,
            arguments: [
                "LM",
                "--lunar-explorer-capture",
                "--lunar-globe-texture-tier=wac-global-64ppd"
            ]
        )?.id == "wac-global-64ppd")
    }

    @Test func captureTextureOverrideIsExplicitAndDefaultsToTheManifest() {
        let bundled = "WACGlobal16PPD.png"
        #expect(LMLunarGlobeResource.textureFile(
            bundledFile: bundled,
            arguments: ["LM", "--lunar-explorer-capture"]
        ) == bundled)
        #expect(LMLunarGlobeResource.textureFile(
            bundledFile: bundled,
            arguments: [
                "LM",
                "--lunar-explorer-capture",
                "--lunar-globe-texture-override=WACGlobal64PPD-q68.heic"
            ]
        ) == "WACGlobal64PPD-q68.heic")
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

    @Test func backgroundPreparationPreservesTerminatorBytesAndGlobeVertices() async throws {
        let manifest = try LMTerrainManifest.load()
        let date = Date(timeIntervalSince1970: 0)
        let result = try await Task.detached {
            #expect(!Thread.isMainThread)
            return try LMLunarGlobeResource.prepareTerminator(manifest: manifest, date: date)
        }.value
        let expected = LMLunarGlobeResource.terminatorOpacitySamples(
            date: date, surfaceNormals: result.surfaceNormals)
        let bytes = try #require(result.image.dataProvider?.data)
        #expect((bytes as Data) == Data(expected))
        let coordinate = manifest.landingOriginCoordinate
        let mesh = await Task.detached {
            LMLunarGlobeResource.globeMeshData(radiusMeters: manifest.globe.radiusMeters,
                                               frontCoordinate: coordinate)
        }.value
        #expect(mesh.positions.count == 129 * 257)
        #expect(mesh.indices.count == 128 * 256 * 6)
        for row in stride(from: 0, through: 128, by: 16) {
            for column in stride(from: 0, through: 256, by: 16) {
                let expected = LMLunarGlobeResource.displayPosition(
                    coordinate: .init(latitudeDegrees: 90 - Double(row) * 180 / 128,
                                      longitudeDegrees: -180 + Double(column) * 360 / 256),
                    frontCoordinate: coordinate, radiusMeters: manifest.globe.radiusMeters)
                #expect(mesh.positions[row * 257 + column] == expected)
            }
        }
        #expect(mesh.textureCoordinates[256].x == 1)
    }

    @Test func cancelledTerminatorPreparationDoesNotReturnPublishableData() async throws {
        let manifest = try LMTerrainManifest.load()
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try LMLunarGlobeResource.prepareTerminator(manifest: manifest, date: .now)
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled preparation returned a resource")
        } catch is CancellationError { }
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
