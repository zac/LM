import Testing
import simd
@testable import LM

struct LMCockpitShadowFitTests {
    private let down = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
    private var corners: [SIMD3<Float>] {
        [-1.0, 1.0].flatMap { x in [2.0, 4.0].flatMap { y in [-1.0, 1.0].map { SIMD3(Float(x), Float(y), Float($0)) } } }
    }
    @Test func overheadFitIncludesGroundWithoutWideningCasterFootprint() throws {
        let fit = try #require(LMCockpitShadowFit.fit(corners: corners, orientation: down,
            ground: .init(point: .zero, normal: SIMD3(0, 1, 0)), xyMargin: 0.25, depthMargin: 0.1))
        #expect(abs(fit.span - 2.5) < 0.0001)
        #expect(simd_distance(fit.origin, SIMD3(0, 4.1, 0)) < 0.0001)
        #expect(abs(fit.far - 4.2) < 0.0001)
        for p in corners + corners.map({ SIMD3($0.x, 0, $0.z) }) {
            let light = down.inverse.act(p - fit.origin)
            #expect(abs(light.x) <= fit.span / 2 && abs(light.y) <= fit.span / 2)
            #expect(-light.z >= fit.near && -light.z <= fit.far)
        }
    }
    @Test func distantGroundUsesBoundedLocalDepthAndLargePeerExpandsFit() throws {
        let fit = try #require(LMCockpitShadowFit.fit(corners: corners, orientation: down, ground: nil))
        #expect(abs(fit.far - 48) < 0.0001)
        let enlarged = try #require(LMCockpitShadowFit.fit(corners: corners + [SIMD3(10, 3, 0)], orientation: down, ground: nil))
        #expect(enlarged.span >= 12)
    }
    @Test func obliqueGroundProjectionSharesLightXY() throws {
        let q = simd_quatf(angle: -.pi / 4, axis: SIMD3<Float>(1, 0, 0))
        let p = SIMD3<Float>(0, 2, 0), receiver = SIMD3<Float>(0, 0, -2)
        let fit = try #require(LMCockpitShadowFit.fit(corners: [p], orientation: q,
            ground: .init(point: .zero, normal: SIMD3(0, 1, 0)), xyMargin: 0.25, depthMargin: 0.1))
        #expect(abs(fit.far - (2 * sqrt(2) + 0.2)) < 0.0001)
        #expect(simd_length(SIMD2(q.inverse.act(p).x - q.inverse.act(receiver).x, q.inverse.act(p).y - q.inverse.act(receiver).y)) < 0.0001)
    }
    @Test func rigidTransformAndQuaternionSignPreserveFit() throws {
        let plane = LMCockpitShadowFit.GroundPlane(point: .zero, normal: SIMD3(0, 1, 0))
        let original = try #require(LMCockpitShadowFit.fit(corners: corners, orientation: down, ground: plane))
        let rotation = simd_quatf(angle: 0.61, axis: SIMD3<Float>(0, 0, 1)) * simd_quatf(angle: 0.35, axis: SIMD3<Float>(0, 1, 0))
        let translation = SIMD3<Float>(123, -45, 67)
        let rotated = try #require(LMCockpitShadowFit.fit(corners: corners.map { rotation.act($0) + translation },
            orientation: rotation * down, ground: .init(point: translation, normal: rotation.act(plane.normal))))
        #expect(abs(rotated.span - original.span) < 0.0001)
        #expect(abs(rotated.far - original.far) < 0.0001)
        #expect(simd_distance(rotated.origin, rotation.act(original.origin) + translation) < 0.0001)
        let opposite = try #require(LMCockpitShadowFit.fit(corners: corners,
            orientation: simd_quatf(vector: -down.vector), ground: plane))
        #expect(simd_distance(opposite.origin, original.origin) < 0.0001)
    }

    @Test func invalidHorizonAndOversizedReceiverFallBack() {
        let plane = LMCockpitShadowFit.GroundPlane(point: .zero, normal: SIMD3(0, 1, 0))
        #expect(LMCockpitShadowFit.fit(corners: [], orientation: down, ground: nil) == nil)
        #expect(LMCockpitShadowFit.fit(corners: [SIMD3(.nan, 0, 0)], orientation: down, ground: nil) == nil)
        #expect(LMCockpitShadowFit.fit(corners: corners, orientation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), ground: plane) == nil)
        #expect(LMCockpitShadowFit.fit(corners: corners.map { $0 + SIMD3(0, 1_000, 0) }, orientation: down, ground: plane) == nil)
    }
}
