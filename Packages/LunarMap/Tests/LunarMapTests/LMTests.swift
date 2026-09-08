@testable import LunarMapExplorer
@testable import LunarMap
import Foundation
import CryptoKit
import CoreGraphics
import ImageIO
import RealityKit
import Testing
import simd
import LMCore

struct LMTests {
    @Test func frameStatisticsReportTailLatencyAndMissedFrames() throws {
        let statistics = try #require(
            LunarExplorerFrameStatistics.summarize(
                durationsMilliseconds: [10, 10, 10, 20, 40],
                nominalMilliseconds: 10
            )
        )

        #expect(statistics.sampleCount == 5)
        #expect(statistics.meanMilliseconds == 18)
        #expect(statistics.p95Milliseconds == 40)
        #expect(statistics.p99Milliseconds == 40)
        #expect(statistics.maximumMilliseconds == 40)
        #expect(statistics.nominalMilliseconds == 10)
        #expect(statistics.missedFrameCount == 2)
    }

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

    @Test func worldMapperKeepsUprangeOverThePadAndShowsNearFieldHorizontal() {
        let mapper = LMWorldMapper.tabletop
        let pdi = LMVector3D(
            x: Luminary99LandingPadLoad.rignXMeters,
            y: Luminary99LandingPadLoad.rignZMeters,
            z: 48_814.0 * 0.3048
        )
        let braking = mapper.position(from: pdi, program: 64)
        #expect(abs(braking.x) < 1e-5)
        #expect(abs(braking.z) < 1e-5)
        #expect(braking.y > 0.5)
        #expect(!mapper.showsSiteRelativeHorizontal(rangeMeters: mapper.pdiRangeMeters))

        let near = LMVector3D(x: 0, y: -500, z: 200)
        let approach = mapper.position(from: near, rangeMeters: 500)
        #expect(mapper.showsSiteRelativeHorizontal(rangeMeters: 500))
        #expect(approach.z > 0)
        #expect(abs(approach.x) < 1e-4)
    }

    @Test func worldMapperPoseKeepsPDIAboveThePad() {
        let state = LMPoweredDescentScenario.apollo11SourceBacked.initialState
        let pose = LMWorldMapper.tabletop.pose(from: state, program: 63)
        #expect(pose.position.y > 0.5)
        #expect(abs(pose.position.x) < 1e-5)
        #expect(abs(pose.position.z) < 1e-5)
    }

    @Test func worldMapperPlacesPDIBeadAtTheFarEndOfTheRangeStrip() {
        let mapper = LMWorldMapper.tabletop
        let pdi = mapper.stripBeadOffset(rangeMeters: mapper.pdiRangeMeters)
        let site = mapper.stripBeadOffset(rangeMeters: 0)
        #expect(abs(pdi.z + Float(mapper.stripLengthMeters)) < 1e-5)
        #expect(abs(site.z) < 1e-5)
    }

    @Test func worldMapperBeadContinuesPastTheSiteOnOvershoot() {
        let mapper = LMWorldMapper.tabletop
        let past = mapper.stripBeadOffset(downrangeMeters: 80_000)
        let uprange = mapper.stripBeadOffset(downrangeMeters: -mapper.pdiRangeMeters)
        #expect(past.z > 0)
        #expect(uprange.z < 0)
    }
}
