import simd

/// Rigid coordinates only. No source samples, tile IDs, or generator seeds depend
/// on this frame. NEU vectors use north/east/up; renderer vectors use north/up/-east.
public struct LMLunarFrameTransform: Equatable, Sendable {
    let rotation: simd_double3x3
    let translation: SIMD3<Double>

    public init(from source: LMSelenographicLocalFrame, to destination: LMSelenographicLocalFrame) {
        func direction(_ axis: SIMD3<Double>) -> SIMD3<Double> {
            destination.localDirection(source.moonFixedDirection(axis))
        }
        if source == destination {
            rotation = matrix_identity_double3x3
            translation = .zero
        } else {
            rotation = simd_double3x3(columns: (
                direction(SIMD3(1, 0, 0)),
                direction(SIMD3(0, 1, 0)),
                direction(SIMD3(0, 0, 1))
            ))
            translation = destination.position(for: source.moonCenteredPosition(for:
                .init(northMeters: 0, eastMeters: 0, upMeters: 0)
            )).vector
        }
    }

    public func position(_ point: SIMD3<Double>) -> SIMD3<Double> {
        rotation * point + translation
    }

    func direction(_ vector: SIMD3<Double>) -> SIMD3<Double> {
        rotation * vector
    }

    public static func renderVector(_ neu: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(neu.x, neu.z, -neu.y)
    }

    public var renderRotation: simd_double3x3 {
        simd_double3x3(columns: (
            Self.renderVector(rotation.columns.0),
            Self.renderVector(rotation.columns.2),
            -Self.renderVector(rotation.columns.1)
        ))
    }

    var renderTranslation: SIMD3<Double> { Self.renderVector(translation) }
}

/// A floating spherical ENU frame. Recompute from canonical Moon coordinates on
/// each transition, never accumulate Float transforms. The trigger is a 3-D chord
/// distance, so vertical travel and antipodal jumps cannot evade it.
public struct LMLunarFloatingOrigin: Sendable {
    /// At 4096 m Float32 ULP is 0.48828125 mm. The former 25–50 km proposal
    /// allowed 1.953–3.906 mm steps. This bounds the focus, not a distant mesh:
    /// fine resident meshes must also retain their own source-local origins.
    static let reanchorDistanceMeters = 4_096.0

    public private(set) var frame: LMSelenographicLocalFrame
    public private(set) var generation = 0

    public init(frame: LMSelenographicLocalFrame) { self.frame = frame }

    @discardableResult
    public mutating func update(focus: LMMoonCenteredPosition) -> Bool {
        guard simd_length(frame.position(for: focus).vector)
                >= Self.reanchorDistanceMeters else { return false }
        reanchor(at: frame.coordinateSystem.coordinate(for: focus))
        return true
    }

    /// Also used by the capture probe to isolate a re-anchor at a stationary
    /// camera. Production navigation uses update(focus:).
    package mutating func reanchor(at coordinate: LMSelenographicCoordinate) {
        guard coordinate != frame.anchor else { return }
        frame = frame.coordinateSystem.localFrame(at: coordinate)
        generation += 1
    }
}
