@testable import LunarMap
import Foundation
import Testing
@testable import LM

@Suite("Photo-derived lunar crater catalog")
struct LMLunarCraterCatalogTests {
    private func catalog(
        id: String = "apollo11-nac-craters-test-v1",
        entries: [LMLunarCraterCatalog.Entry]
    ) throws -> LMLunarCraterCatalog {
        try LMLunarCraterCatalog(
            catalogID: id,
            generatorVersion: "crater-detector-test-v1",
            sourceIDs: [
                "nac-ortho-m150361817-50cm-slab",
                "nac-ortho-m150368601-50cm-slab",
            ],
            entries: entries
        )
    }

    @Test func productionCatalogIsLoadedIntoTheSharedTerrainSampler() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let productionCatalog = try #require(field.craterCatalog)
        let sampler = LMProgressiveTerrainSampler(heightField: field)

        #expect(productionCatalog.catalogID == "apollo11-near-field-nac-craters-v1")
        #expect(productionCatalog.generatorVersion == "nac-parametric-correlation-v1")
        #expect(productionCatalog.entries.count == 1_200)
        #expect(sampler.geology.craterCatalog == productionCatalog)
        #expect(
            sampler.geology.versionedModelID
                == "surveyor-degraded-microrelief-v3+apollo11-near-field-nac-craters-v1@nac-parametric-correlation-v1"
        )
    }

    @Test func catalogCanonicalizesEntriesAndRejectsInvalidMeasurements() throws {
        let second = LMLunarCraterCatalog.Entry(
            id: "crater-002",
            eastMeters: 7.5,
            northMeters: -3.25,
            diameterMeters: 1.8,
            sharpness: 0.7,
            confidence: 0.91
        )
        let first = LMLunarCraterCatalog.Entry(
            id: "crater-001",
            eastMeters: -2,
            northMeters: 4,
            diameterMeters: 0.9,
            sharpness: 0.45,
            confidence: 0.82
        )
        let valid = try catalog(entries: [second, first])

        #expect(valid.entries.map(\.id) == ["crater-001", "crater-002"])
        #expect(
            valid.versionedModelID
                == "apollo11-nac-craters-test-v1@crater-detector-test-v1"
        )

        #expect(throws: LMLunarCraterCatalog.CatalogError.self) {
            try catalog(entries: [
                .init(
                    id: "bad-diameter",
                    eastMeters: 0,
                    northMeters: 0,
                    diameterMeters: 0,
                    sharpness: 0.5,
                    confidence: 0.8
                ),
            ])
        }
        #expect(throws: LMLunarCraterCatalog.CatalogError.self) {
            try catalog(entries: [first, first])
        }
    }

    @Test func encodingAndDecodingPreserveTheVersionedCatalog() throws {
        let expected = try catalog(entries: [
            .init(
                id: "round-trip",
                eastMeters: 12.25,
                northMeters: -6.5,
                diameterMeters: 2.25,
                sharpness: 0.8,
                confidence: 0.94,
                aspectRatio: 0.83,
                rotationRadians: 1.2
            ),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(expected)
        let decoded = try JSONDecoder().decode(LMLunarCraterCatalog.self, from: data)

        #expect(decoded == expected)
    }

    @Test func emptyCatalogPreservesTheExistingGeologyExactly() throws {
        let emptyCatalog = try catalog(entries: [])
        let baseline = LMLunarGeologyModel(seed: 42)
        let catalogModel = LMLunarGeologyModel(seed: 42, craterCatalog: emptyCatalog)

        for spacing in [0.125, 0.25, 0.5, 1.0] {
            for point in [
                SIMD2<Double>(-8.75, 4.125),
                SIMD2<Double>(0, 0),
                SIMD2<Double>(13.375, -9.625),
            ] {
                #expect(baseline.visualReliefMeters(
                    eastMeters: point.x,
                    northMeters: point.y,
                    requestedSpacingMeters: spacing
                ) == catalogModel.visualReliefMeters(
                    eastMeters: point.x,
                    northMeters: point.y,
                    requestedSpacingMeters: spacing
                ))
            }
        }
    }

    @Test func catalogCraterAppearsAtItsObservedCoordinate() throws {
        let observed = LMLunarCraterCatalog.Entry(
            id: "observed-center",
            eastMeters: 101.25,
            northMeters: -73.5,
            diameterMeters: 2,
            sharpness: 1,
            confidence: 0.99
        )
        let baseline = LMLunarGeologyModel(seed: 7)
        let photoSeeded = LMLunarGeologyModel(
            seed: 7,
            craterCatalog: try catalog(entries: [observed])
        )
        let baselineCenter = baseline.visualReliefMeters(
            eastMeters: observed.eastMeters,
            northMeters: observed.northMeters,
            requestedSpacingMeters: 0.125
        )
        let photoSeededCenter = photoSeeded.visualReliefMeters(
            eastMeters: observed.eastMeters,
            northMeters: observed.northMeters,
            requestedSpacingMeters: 0.125
        )

        #expect(photoSeededCenter < baselineCenter - 0.08)
        #expect(photoSeeded.versionedModelID.contains("observed") == false)
        #expect(photoSeeded.versionedModelID.contains("apollo11-nac-craters-test-v1"))
    }

    @Test func catalogCraterSuppressesAnOverlappingHashCandidate() throws {
        let baseline = LMLunarGeologyModel(seed: 19)
        var found: (eastCell: Int64, northCell: Int64, candidate: Int,
                   crater: LMLunarGeologyModel.Crater)?
        search: for northCell in -8...8 {
            for eastCell in -8...8 {
                for candidate in 0..<baseline.candidatesPerCell {
                    if let crater = baseline.crater(
                        cellEast: Int64(eastCell),
                        cellNorth: Int64(northCell),
                        candidate: candidate
                    ) {
                        found = (Int64(eastCell), Int64(northCell), candidate, crater)
                        break search
                    }
                }
            }
        }
        let resolved = try #require(found)
        let replacement = LMLunarCraterCatalog.Entry(
            id: "photo-replacement",
            eastMeters: resolved.crater.eastMeters,
            northMeters: resolved.crater.northMeters,
            diameterMeters: resolved.crater.diameterMeters,
            sharpness: 0.9,
            confidence: 0.95
        )
        let photoSeeded = LMLunarGeologyModel(
            seed: baseline.seed,
            craterCatalog: try catalog(entries: [replacement])
        )

        #expect(photoSeeded.resolvedCrater(
            nil,
            cellEast: resolved.eastCell,
            cellNorth: resolved.northCell,
            candidate: resolved.candidate
        ) == nil)
    }

    @Test func preparedAndOnDemandCatalogSamplingAreIdentical() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let craterCatalog = try catalog(entries: [
            .init(
                id: "prepared-equivalence",
                eastMeters: 3.25,
                northMeters: -1.5,
                diameterMeters: 2.4,
                sharpness: 0.75,
                confidence: 0.9
            ),
        ])
        let sampler = LMProgressiveTerrainSampler(
            heightField: field,
            craterCatalog: craterCatalog
        )
        let prepared = sampler.prepared(
            eastMetersRange: -8...8,
            northMetersRange: -8...8
        )

        for point in [
            SIMD2<Double>(-7.875, 6.625),
            SIMD2<Double>(3.25, -1.5),
            SIMD2<Double>(7.375, -7.125),
        ] {
            #expect(sampler.sample(
                eastMeters: point.x,
                northMeters: point.y,
                requestedSpacingMeters: 0.125
            ) == prepared.sample(
                eastMeters: point.x,
                northMeters: point.y,
                requestedSpacingMeters: 0.125
            ))
        }
    }

    @Test func catalogReliefRemainsZeroAtEveryMeasuredPost() throws {
        let field = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let sampler = LMProgressiveTerrainSampler(
            heightField: field,
            craterCatalog: try catalog(entries: [
                .init(
                    id: "post-anchor",
                    eastMeters: 0,
                    northMeters: 0,
                    diameterMeters: 5,
                    sharpness: 0.95,
                    confidence: 0.99
                ),
            ])
        )

        for north in stride(from: -8.0, through: 8.0, by: field.spacingMeters) {
            for east in stride(from: -8.0, through: 8.0, by: field.spacingMeters) {
                let sample = try #require(sampler.sample(
                    eastMeters: east,
                    northMeters: north,
                    requestedSpacingMeters: 0.125
                ))
                #expect(abs(sample.proceduralResidualMeters) < 1e-7)
                #expect(sample.elevationMeters == sample.measuredElevationMeters)
            }
        }
    }
}
