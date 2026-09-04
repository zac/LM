import Testing
import RealityKit
import simd
@testable import LM

@Suite("Floating lunar ENU")
struct LMLunarFloatingOriginTests {
    private let system = LMSelenographicCoordinateSystem()

    @Test func thresholdComesFromFloatPrecisionRatherThanPlanarCurvature() {
        #expect(Float(4_096).ulp == 0.00048828125)
        #expect(Float(25_000).ulp == 0.001953125)
        #expect(Float(50_000).ulp == 0.00390625)
        let sag = system.datumRadiusMeters
            * (1 - cos(25_000 / system.datumRadiusMeters))
        #expect(sag > 179 && sag < 181)
        print("Anchor precision: ULP4096=0.48828125mm ULP25000=1.953125mm ULP50000=3.90625mm sag25000=\(sag)m")
    }

    @Test func anchorsWithinCentimetersOfEitherPoleKeepSubmillimeterAccuracy() {
        for latitude in [89.999999, 89.9999999, 90, -89.999999, -89.9999999, -90] {
            let point = system.moonCenteredPosition(for:
                .init(latitudeDegrees: latitude, longitudeDegrees: 137.25, heightMeters: 9123))
            let recovered = system.moonCenteredPosition(for: system.coordinate(for: point))
            #expect(simd_length(point.vector - recovered.vector) < 1e-8)
        }
    }

    @Test func sourceDatumIsNotReinterpretedByTheDestination() {
        let source = LMSelenographicCoordinateSystem(datumRadiusMeters: 1_738_400)
            .localFrame(at: .init(latitudeDegrees: 42, longitudeDegrees: -95, heightMeters: 13))
        let destination = system.localFrame(at: source.anchor)
        let transform = LMLunarFrameTransform(from: source, to: destination)
        #expect(simd_length(transform.translation - SIMD3(0, 0, 1_000)) < 1e-8)
    }

    @Test func thresholdIncludesAltitudeAndDoesNotThrashOnReturn() {
        let frame = system.localFrame(at: .init(latitudeDegrees: 0, longitudeDegrees: 0))
        var origin = LMLunarFloatingOrigin(frame: frame)
        let below = frame.moonCenteredPosition(for:
            .init(northMeters: 0, eastMeters: 0, upMeters: 4_095.99))
        #expect(!{ origin.update(focus: below) }())
        let boundary = frame.moonCenteredPosition(for:
            .init(northMeters: 0, eastMeters: 0, upMeters: 4_096))
        #expect({ origin.update(focus: boundary) }())
        #expect(!{ origin.update(focus: below) }())
        #expect(!{ origin.update(focus: boundary) }())
        #expect(origin.generation == 1)
        #expect(simd_length(origin.frame.position(for: boundary).vector) < 1e-8)
        let antipode = system.moonCenteredPosition(for:
            .init(latitudeDegrees: 0, longitudeDegrees: 180))
        #expect({ origin.update(focus: antipode) }())
    }

    @Test func rigidReanchoringPreservesPositionsDirectionsAndSharedEdgesGlobally() {
        let coordinates = [
            LMSelenographicCoordinate(latitudeDegrees: 0.673433, longitudeDegrees: 23.473113, heightMeters: -1928),
            .init(latitudeDegrees: -42, longitudeDegrees: 179.99, heightMeters: 6000),
            .init(latitudeDegrees: 89.999, longitudeDegrees: -120),
            .init(latitudeDegrees: -89.999, longitudeDegrees: 150),
            .init(latitudeDegrees: 0, longitudeDegrees: -179.99)
        ]
        var worst = 0.0
        for coordinate in coordinates {
            let source = system.localFrame(at: coordinate)
            var origin = LMLunarFloatingOrigin(frame: source)
            for step in 1...100 {
                let focus = source.moonCenteredPosition(for: .init(
                    northMeters: Double(step) * 3_001,
                    eastMeters: Double(step) * -4_001, upMeters: Double(step) * 13))
                #expect({ origin.update(focus: focus) }())
                let transform = LMLunarFrameTransform(from: source, to: origin.frame)
                let inverse = LMLunarFrameTransform(from: origin.frame, to: source)
                for delta in [SIMD3<Double>(0, 0, 0), SIMD3(16, 32, -7.125), SIMD3(-16, -32, 11.375)] {
                    let point = source.position(for: focus).vector + delta
                    let transformed = transform.position(point)
                    let returned = inverse.position(transformed)
                    worst = max(worst, simd_length(returned - point))
                    let moon = origin.frame.moonCenteredPosition(for: .init(
                        northMeters: transformed.x, eastMeters: transformed.y, upMeters: transformed.z))
                    let expected = source.moonCenteredPosition(for: .init(
                        northMeters: point.x, eastMeters: point.y, upMeters: point.z))
                    #expect(simd_length(moon.vector - expected.vector) < 1e-6)
                    // An independently authored adjacent source must agree at
                    // the same canonical edge, including after a basis rotation.
                    let neighbor = system.localFrame(at: source.coordinate(for:
                        .init(northMeters: point.x + 32, eastMeters: point.y, upMeters: point.z)))
                    let neighborPoint = neighbor.position(for: expected).vector
                    let neighborMap = LMLunarFrameTransform(from: neighbor, to: origin.frame)
                    #expect(simd_length(neighborMap.position(neighborPoint) - transformed) < 1e-6)
                }
                let normal = simd_normalize(SIMD3<Double>(0.1, -0.3, 1))
                #expect(simd_length(inverse.direction(transform.direction(normal)) - normal) < 1e-12)
                #expect(abs(simd_determinant(transform.rotation) - 1) < 1e-12)
            }
        }
        print("Anchor 500 transitions: worst Double roundtrip=\(worst)m")
        #expect(worst < 1e-6)
    }

    @Test(arguments: [0, 1, 2, 3])
    @MainActor func floatHierarchyPreservesCloseGeometryAcrossTheTrigger(site: Int) throws {
        let sources = [
            try LMTerrainManifest.load().landingLocalFrame,
            system.localFrame(at: .init(latitudeDegrees: -42, longitudeDegrees: 179.99, heightMeters: 6000)),
            system.localFrame(at: .init(latitudeDegrees: 89.999999, longitudeDegrees: -120)),
            system.localFrame(at: .init(latitudeDegrees: -89.999999, longitudeDegrees: 150))
        ]
        let source = sources[site]
        let focus = LMSiteENUPosition(northMeters: 127.3125, eastMeters: -74.625, upMeters: 3.125)
        let offset = source.coordinate(for: .init(
            northMeters: focus.northMeters + 4_200,
            eastMeters: focus.eastMeters, upMeters: focus.upMeters))
        var origin = LMLunarFloatingOrigin(frame: system.localFrame(at: offset))
        let before = LMLunarAnchoredPlacement(source: source, anchor: origin.frame, focus: focus)
        #expect({ origin.update(focus: source.moonCenteredPosition(for: focus)) }())
        let after = LMLunarAnchoredPlacement(source: source, anchor: origin.frame, focus: focus)
        let parent = Entity()
        let tile = Entity()
        parent.addChild(tile)
        func rendered(_ placement: LMLunarAnchoredPlacement, point: SIMD3<Float>) -> SIMD3<Float> {
            parent.transform = placement.viewTransform
            tile.transform = placement.sourceTransform
            return tile.convert(position: point, to: nil)
        }
        var worst = 0.0
        for index in 0...256 {
            let north = focus.northMeters - 16 + Double(index) * 0.125
            let point = SIMD3<Float>(Float(north), Float(focus.upMeters), Float(-focus.eastMeters))
            let expected = SIMD3<Float>(Float(north - focus.northMeters), 0, 0)
            let a = rendered(before, point: point)
            let b = rendered(after, point: point)
            worst = max(worst, Double(simd_length(a - b)))
            #expect(simd_length(a - expected) < 0.001)
            #expect(simd_length(b - expected) < 0.001)
        }
        print("Anchor Float RealityKit hierarchy: worst transition=\(worst)m")
        #expect(worst < 0.001)
    }

    @Test @MainActor func apolloIdentityPlacementAndCaptureGatingStayExact() throws {
        let source = try LMTerrainManifest.load().landingLocalFrame
        let focus = LMSiteENUPosition(northMeters: 123.456789, eastMeters: -76.54321, upMeters: 9.876543)
        let placement = LMLunarAnchoredPlacement(source: source, anchor: source, focus: focus)
        #expect(placement.sourceTransform.matrix == matrix_identity_float4x4)
        #expect(placement.viewTransform.translation == SIMD3(
            Float(-focus.northMeters), Float(-focus.upMeters), Float(focus.eastMeters)))
        let session = LunarExplorerSession()
        session.configure(arguments: ["--lunar-explorer-reanchor-probe"])
        #expect(!session.captureReanchorProbe)
        session.configure(arguments: ["--lunar-explorer-capture", "--lunar-explorer-reanchor-probe"])
        #expect(session.captureReanchorProbe)
    }
}
