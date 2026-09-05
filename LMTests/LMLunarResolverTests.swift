import Foundation
import Testing
import simd
@testable import LM

@Suite("Global lunar source resolver")
struct LMLunarResolverTests {
    private func base() throws -> LMLunarElevationGrid {
        let source = try #require(LMTerrainManifest.load().sources.first { $0.productId == "LDEM_16" })
        let url = try #require(Bundle.main.url(forResource: source.bundledFile, withExtension: nil))
        return try .init(data: Data(contentsOf: url, options: .mappedIfSafe), source: source)
    }

    private func strip(first: Int, last: Int, cap: Double = 0.12) throws -> LMLunarElevationGrid {
        var data = Data(count: (last - first + 1) * 92_160)
        data.withUnsafeMutableBytes { bytes in
            for row in first...last {
                for column in 0..<46_080 {
                    let value = Int16((row % 80) * 10 + column % 100).littleEndian
                    bytes.storeBytes(of: value, toByteOffset: ((row - first) * 46_080 + column) * 2, as: Int16.self)
                }
            }
        }
        let json: [String: Any] = [
            "id": "fixture-\(first)-\(last)", "role": "global-elevation",
            "coverage": ["minimumLatitudeDegrees": 90 - Double(last + 1) / 128,
                         "maximumLatitudeDegrees": 90 - Double(first) / 128,
                         "westernmostLongitudeDegrees": 0, "easternmostLongitudeDegrees": 360],
            "postSpacingMeters": 236.9011751886625, "residualCapRatio": cap,
            "url": "https://example.invalid/fixture", "sha256": LMLunarElevationGrid.digest(data),
            "bytes": data.count, "sourceRowStart": first, "sourceRowEnd": last, "sourceRowBytes": 92_160,
            "mapResolutionPixelsPerDegree": 128, "productId": "LDEM_128", "productVersion": "V3.0",
            "labelURL": "https://example.invalid/fixture.lbl", "detail": "Generated test posts"
        ]
        let source = try JSONDecoder().decode(LMTerrainManifest.Source.self, from: JSONSerialization.data(withJSONObject: json))
        return try .init(data: data, source: source)
    }

    @Test func catalogCoversEveryRowWithBoundedOverlappingVerifiedRanges() throws {
        let catalog = try LMLunarElevationCatalog.load()
        var prior: LMTerrainManifest.Source?
        for index in catalog.sha256.indices {
            let source = catalog.source(at: index)
            #expect(source.bytes! <= 34 * 92_160)
            #expect(source.byteRangeEnd! - source.byteRangeStart! + 1 == source.bytes)
            #expect(source.byteRangeStart! >= 0 && source.byteRangeEnd! < catalog.sourceBytes)
            #expect(source.sha256.count == 64)
            if let prior { #expect(source.sourceRowStart! == prior.sourceRowEnd! - 1) }
            prior = source
        }
        #expect(catalog.source(at: 0).sourceRowStart == 0)
        #expect(catalog.source(at: 719).sourceRowEnd == 23_039)
        for latitude in [-90.0, -42, 0, 89.99, 90] {
            let sources = catalog.sources(around: .init(latitudeDegrees: latitude, longitudeDegrees: 179.999), radiusMeters: 25_000)
            #expect(!sources.isEmpty)
            #expect(sources.reduce(0) { $0 + $1.bytes! } < 32 * 1_024 * 1_024)
        }
    }

    @Test func nativePostsRemainExactAtEveryProceduralSpacingAndCapIsPerSource() throws {
        let grid = try strip(first: 11_519, last: 11_552, cap: 0.03)
        let terrain = LMLunarResolvedTerrain(base: try base(), refinements: [grid])
        for spacing in [512.0, 128, 32, 8, 2, 0.5, 0.125] {
            for row in [0, 1, 16, 33] {
                for column in [0, 1, 23_040, 46_079] {
                    let sample = try #require(terrain.sample(at: grid.coordinate(row: row, column: column), spacingMeters: spacing))
                    #expect(sample.measuredMeters == grid.elevation(row: row, column: column))
                    #expect(sample.residualMeters == 0)
                    #expect(sample.capMeters == grid.spacingMeters * 0.03)
                }
            }
        }
        for index in 0..<60 {
            let coordinate = LMSelenographicCoordinate(latitudeDegrees: -0.1 + Double(index) * 0.00001,
                                                        longitudeDegrees: 179.99 + Double(index) * 0.00002)
            let a = try #require(terrain.sample(at: coordinate, spacingMeters: 0.125))
            let b = try #require(terrain.sample(at: coordinate, spacingMeters: 0.125))
            #expect(a.elevationMeters == b.elevationMeters)
            #expect(abs(a.residualMeters) <= a.capMeters)
        }
    }

    @Test func overlappingStripsAgreeAtSeamAndOutsideCoverageDoesNotClamp() throws {
        let a = try strip(first: 11_519, last: 11_552)
        let b = try strip(first: 11_551, last: 11_584)
        let base = try base()
        let left = LMLunarResolvedTerrain(base: base, refinements: [a])
        let right = LMLunarResolvedTerrain(base: base, refinements: [b])
        for spacing in [32.0, 2, 0.125] {
            for index in 0..<21 {
                let coordinate = LMSelenographicCoordinate(latitudeDegrees: a.southernPostLatitude + Double(index) / 2560,
                                                            longitudeDegrees: 179.99999)
                #expect(left.sample(at: coordinate, spacingMeters: spacing)?.elevationMeters
                        == right.sample(at: coordinate, spacingMeters: spacing)?.elevationMeters)
            }
        }
        #expect(a.elevation(at: .init(latitudeDegrees: 30, longitudeDegrees: 0)) == nil)
    }

    @Test func polarOwnershipConvergesAndLongitudeWrapIsContinuous() throws {
        let north = try strip(first: 0, last: 32)
        let south = try strip(first: 23_007, last: 23_039)
        let terrain = LMLunarResolvedTerrain(base: try base(), refinements: [north, south])
        for latitude in [-90.0, 90] {
            let a = try #require(terrain.sample(at: .init(latitudeDegrees: latitude, longitudeDegrees: 0), spacingMeters: 0.125))
            let b = try #require(terrain.sample(at: .init(latitudeDegrees: latitude, longitudeDegrees: 137), spacingMeters: 0.125))
            #expect(a.elevationMeters == b.elevationMeters)
            #expect(a.residualMeters == 0)
            #expect(a.sourceSpacingMeters == north.spacingMeters)
        }
        for latitude in [89.9, 30.0, -42] {
            let a = try #require(terrain.sample(at: .init(latitudeDegrees: latitude, longitudeDegrees: 180 - 1e-9), spacingMeters: 0.125))
            let b = try #require(terrain.sample(at: .init(latitudeDegrees: latitude, longitudeDegrees: -180 + 1e-9), spacingMeters: 0.125))
            #expect(abs(a.elevationMeters - b.elevationMeters) < 0.001)
        }
    }

    @Test func sphericalGraphRetainsCurvatureAndMeasuresKernelCost() throws {
        let base = try base()
        let terrain = LMLunarResolvedTerrain(base: base, refinements: [])
        let origin = LMSelenographicCoordinate(latitudeDegrees: -42, longitudeDegrees: 179.99,
                                               heightMeters: base.elevation(at: .init(latitudeDegrees: -42, longitudeDegrees: 179.99))!)
        let field = LMLunarTerrainHeightField(terrain: terrain, frame: LMSelenographicCoordinateSystem().localFrame(at: origin))
        var maximumError = 0.0
        let start = ContinuousClock.now
        for index in 0..<100 {
            let east = Double(index - 50) * 250
            let north = Double(index % 7 - 3) * 250
            let sample = try #require(field.resolvedSample(eastMeters: east, northMeters: north, requestedSpacingMeters: 0.125))
            let coordinate = field.frame.coordinate(for: .init(northMeters: north, eastMeters: east, upMeters: Double(sample.elevationMeters)))
            let expected = try #require(terrain.sample(at: coordinate, spacingMeters: 0.125))
            maximumError = max(maximumError, abs(coordinate.heightMeters - expected.elevationMeters))
        }
        print("LUNAR_RESOLVER kernel100=\(start.duration(to: .now)) radialError=\(maximumError)m")
        #expect(maximumError < 0.002)
    }

    @Test func childPerimeterMatchesActualParentTrianglesAndNormals() throws {
        let terrain = LMLunarResolvedTerrain(base: try base(), refinements: [])
        let frame = LMSelenographicCoordinateSystem().localFrame(at: .init(latitudeDegrees: -42, longitudeDegrees: 120))
        var field = LMLunarTerrainHeightField(terrain: terrain, frame: frame)
        let parent = LMTerrainTilePlan(id: .init(level: 3, eastIndex: 0, northIndex: 0),
                                      centerEastMeters: 32, centerNorthMeters: 32, sizeMeters: 64,
                                      sampleSpacingMeters: 8, containsProceduralSubresolution: true)
        let child = LMTerrainTilePlan(id: .init(level: 2, eastIndex: 0, northIndex: 0),
                                     centerEastMeters: 24, centerNorthMeters: 24, sizeMeters: 16,
                                     sampleSpacingMeters: 2, containsProceduralSubresolution: true).withTransitionEdges(.all)
        let parentMesh = try #require(try Apollo11TerrainResource.makeProgressiveTileMeshData(heightField: field,
                                           plan: parent, activePlans: [parent, child]))
        let parentTile = LMLunarTerrainMeshTile(plan: parent, mesh: parentMesh)
        field.parents = .init(tiles: [parentTile])
        let childMesh = try #require(try Apollo11TerrainResource.makeProgressiveTileMeshData(heightField: field,
                                          plan: child, activePlans: [parent, child]))
        var maximumHeightError = Float.zero
        var maximumNormalError = Float.zero
        for row in 0..<9 {
            for column in 0..<9 where row == 0 || row == 8 || column == 0 || column == 8 {
                let east = 16 + Double(column) * 2, north = 32 - Double(row) * 2
                let sample = try #require(parentTile.sample(east: east, north: north))
                let index = row * 9 + column
                maximumHeightError = max(maximumHeightError, abs(sample.elevation - childMesh.positions[index].y))
                maximumNormalError = max(maximumNormalError, simd_length(sample.normal - childMesh.normals[index]))
                #expect(childMesh.positions[index].x == Float(north - 24))
                #expect(childMesh.positions[index].z == Float(24 - east))
            }
        }
        print("LUNAR_RESOLVER parentTriangleHeightError=\(maximumHeightError)m normalError=\(maximumNormalError)")
        #expect(maximumHeightError == 0)
        #expect(maximumNormalError < 1e-6)
    }
}
