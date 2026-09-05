import RealityKit
import simd

/// Places an immutable source-local mesh in the active ENU and compensates the
/// view in the same transaction. Apollo's source geometry remains planar; this
/// rigid change of coordinates never reprojects or resamples it.
struct LMLunarAnchoredPlacement {
    let sourceTransform: Transform
    let viewTransform: Transform

    static func chunkTransform(origin: LMSiteENUPosition, source: LMSelenographicLocalFrame,
                               anchor: LMSelenographicLocalFrame) -> Transform {
        let local = LMLunarFrameTransform(from: source, to: anchor)
        return Transform(scale: .one,
                         rotation: simd_quatf(vector: SIMD4<Float>(simd_quatd(local.renderRotation).vector)),
                         translation: SIMD3<Float>(LMLunarFrameTransform.renderVector(local.position(origin.vector))))
    }

    init(source: LMSelenographicLocalFrame, anchor: LMSelenographicLocalFrame,
         focus: LMSiteENUPosition) {
        let local = LMLunarFrameTransform(from: source, to: anchor)
        let reverse = LMLunarFrameTransform(from: anchor, to: source)
        sourceTransform = Transform(
            scale: .one,
            rotation: simd_quatf(vector: SIMD4<Float>(simd_quatd(local.renderRotation).vector)),
            translation: SIMD3<Float>(local.renderTranslation)
        )
        // Subtract in Double before converting to renderer coordinates.
        viewTransform = Transform(
            scale: .one,
            rotation: simd_quatf(vector: SIMD4<Float>(simd_quatd(reverse.renderRotation).vector)),
            translation: SIMD3<Float>(LMLunarFrameTransform.renderVector(
                reverse.translation - focus.vector
            ))
        )
    }
}
