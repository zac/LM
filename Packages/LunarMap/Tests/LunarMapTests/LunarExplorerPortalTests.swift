@testable import LunarMapExplorer
import Foundation
import Testing
import simd

@Suite("Moon Explorer portal silhouette") @MainActor
struct LunarExplorerPortalTests {
    @Test func diskIsFreeStandingAndSwitchReversesAtFirstFrameContact() throws {
        let session = LunarExplorerSession()
        session.configure(arguments: [])
        #expect(!session.portalEnabled)
        #expect(session.camera.windowWidthMeters == 1.6)
        var low = 3_000_000.0, high = 4_400_000.0
        for _ in 0..<32 {
            let width = (low + high) / 2
            session.exploreZoom(by: session.metersAcross / width, from: session.metersAcross)
            if session.portalEnabled { low = width } else { high = width }
        }
        let width = (low + high) / 2
        for factor in [1.001, 0.999, 1.001] {
            session.exploreZoom(by: session.metersAcross / (width * factor), from: session.metersAcross)
            #expect(session.portalEnabled == (factor < 1))
        }
        let projection = try #require(session.portalProjection)
        #expect(abs(projection.frameOverflow) < 0.002)
        #expect(projection.height < 1.1) // Off-axis limb reaches the upper edge first.
        session.globePosition.z = -1.5
        #expect(session.portalProjection?.height != projection.height)
    }

    @Test func apertureExcludesBlackCornersAtTheFirstClippedDisk() throws {
        let eye = SIMD3<Float>(0, 1.45, 0)
        let plane = SIMD3<Float>(1.05, 1.45, -2.17)
        let radius: Float = 0.707
        let center = plane - SIMD3(0, 0, radius)
        let projection = try #require(LunarExplorerPortalGeometry.project(
            center: center, radius: radius, eye: eye, planeCenter: plane))
        #expect(projection.height > Double(LunarExplorerPortalGeometry.height))
        #expect(!projection.contains(SIMD2(0.79, 0.54)))
        let outline = LunarExplorerPortalGeometry.aperture(projection)
        #expect(outline.count >= 3)
        for point in outline {
            #expect(abs(point.x) <= 0.80001 && abs(point.y) <= 0.55001)
            // A ray through each aperture vertex must intersect the sphere.
            // Allow Float boundary roundoff, not an uncovered rectangular corner.
            let ray = simd_normalize(plane + SIMD3(point.x, point.y, 0) - eye)
            let c = center - eye
            let closest = simd_length(simd_cross(c, ray))
            #expect(closest <= radius + 0.00001)
        }
    }

    @Test func largeSphereUsesFullFrameAndHeadMotionMovesSilhouette() throws {
        let plane = SIMD3<Float>(1.05, 1.45, -2.17)
        let center = plane - SIMD3<Float>(0, 0, 4)
        let projection = try #require(LunarExplorerPortalGeometry.project(
            center: center, radius: 4, eye: SIMD3(0, 1.45, 0), planeCenter: plane))
        #expect(LunarExplorerPortalGeometry.aperture(projection) == LunarExplorerPortalGeometry.frameOutline)
        let moved = try #require(LunarExplorerPortalGeometry.project(
            center: center, radius: 4, eye: SIMD3(0.2, 1.55, 0), planeCenter: plane))
        #expect(simd_distance(moved.center, projection.center) > 0.01)
    }
}
