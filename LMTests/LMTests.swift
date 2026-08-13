import Testing
import simd
import LMCore
@testable import LM

struct LMTests {
    @Test func worldMapperSendsSimUpToRealityKitUp() {
        let mapper = LMWorldMapper.tabletop
        let up = mapper.direction(from: LMVector3D(z: 1))
        #expect(abs(up.x) < 1e-5)
        #expect(abs(up.y - 1) < 1e-5)
        #expect(abs(up.z) < 1e-5)

        let forward = mapper.direction(from: LMVector3D(y: 1))
        #expect(abs(forward.x) < 1e-5)
        #expect(abs(forward.y) < 1e-5)
        #expect(abs(forward.z + 1) < 1e-5)

        let right = mapper.direction(from: LMVector3D(x: 1))
        #expect(abs(right.x - 1) < 1e-5)
        #expect(abs(right.y) < 1e-5)
        #expect(abs(right.z) < 1e-5)
    }

    @Test func worldMapperCompressesHighAltitudeAndExpandsNearField() {
        let mapper = LMWorldMapper.tabletop
        let high = mapper.visualAltitude(mapper.highAltitudeMeters)
        let near = mapper.visualAltitude(mapper.nearAltitudeMeters)
        let landed = mapper.visualAltitude(0)
        #expect(abs(high - mapper.highVisualMeters - mapper.nearVisualMeters) < 1e-6)
        #expect(abs(near - mapper.nearVisualMeters) < 1e-6)
        #expect(landed == 0)
        #expect(mapper.position(from: LMVector3D(z: 0)).y == 0)
    }

    @Test func worldMapperKeepsP63OverThePadAndShowsP64Horizontal() {
        let mapper = LMWorldMapper.tabletop
        let pdi = LMVector3D(
            x: Luminary99LandingPadLoad.rignXMeters,
            y: Luminary99LandingPadLoad.rignZMeters,
            z: 48_814.0 * 0.3048
        )
        let braking = mapper.position(from: pdi, program: 63)
        #expect(abs(braking.x) < 1e-5)
        #expect(abs(braking.z) < 1e-5)
        #expect(braking.y > 0.5)

        let approach = mapper.position(from: pdi, program: 64)
        #expect(abs(approach.x + Float(mapper.padRadiusMeters)) < 1e-5)
        #expect(abs(approach.z - Float(mapper.padRadiusMeters)) < 1e-5)
        #expect(!mapper.showsSiteRelativeHorizontal(program: 63))
        #expect(mapper.showsSiteRelativeHorizontal(program: 64))
    }

    @Test func worldMapperPlacesPDIBeadAtTheFarEndOfTheRangeStrip() {
        let mapper = LMWorldMapper.tabletop
        let pdi = mapper.stripBeadOffset(rangeMeters: mapper.pdiRangeMeters)
        let site = mapper.stripBeadOffset(rangeMeters: 0)
        #expect(abs(pdi.z + Float(mapper.stripLengthMeters)) < 1e-5)
        #expect(abs(site.z) < 1e-5)
    }

    @Test func rcsJetMapCoversEveryLuminaryJetUniquely() {
        #expect(LMRCSJetMapping.table.count == LMRCSJet.allCases.count)
        #expect(Set(LMRCSJetMapping.table.values).count == LMRCSJet.allCases.count)
        #expect(Set(LMRCSJetMapping.table.keys) == Set(LMRCSJet.allCases))
    }
}
