import UIKit
import RealityKit
import LMCore

/// P63 range-to-go on the table: site at the pad, PDI at the far end of a
/// moon-dark ribbon. The kinematic LM on the pad is the vehicle; this bead
/// is the map.
final class DescentRangeStrip {
    let root = Entity()
    private let bead: ModelEntity

    init(mapper: LMWorldMapper = .tabletop) {
        root.name = "DescentRangeStrip"

        let length = Float(mapper.stripLengthMeters)
        let ribbon = ModelEntity(
            mesh: .generateBox(width: 0.045, height: 0.006, depth: length),
            materials: [
                SimpleMaterial(
                    color: UIColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1),
                    roughness: 0.95,
                    isMetallic: false
                )
            ]
        )
        ribbon.name = "RangeRibbon"
        ribbon.position = SIMD3(0, 0.004, -length / 2)
        root.addChild(ribbon)

        let site = ModelEntity(
            mesh: .generateSphere(radius: 0.012),
            materials: [UnlitMaterial(color: UIColor(red: 0.85, green: 0.78, blue: 0.45, alpha: 1))]
        )
        site.name = "RangeSite"
        site.position = SIMD3(0, 0.016, 0)
        root.addChild(site)

        let far = ModelEntity(
            mesh: .generateSphere(radius: 0.007),
            materials: [UnlitMaterial(color: UIColor(red: 0.55, green: 0.52, blue: 0.48, alpha: 1))]
        )
        far.name = "RangePDI"
        far.position = SIMD3(0, 0.014, -length)
        root.addChild(far)

        bead = ModelEntity(
            mesh: .generateSphere(radius: 0.018),
            materials: [UnlitMaterial(color: UIColor(red: 0.95, green: 0.92, blue: 0.82, alpha: 1))]
        )
        bead.name = "RangeBead"
        root.addChild(bead)
        apply(downrangeMeters: -mapper.pdiRangeMeters, mapper: mapper, visible: true)
    }

    func apply(rangeMeters: Double, mapper: LMWorldMapper, visible: Bool) {
        apply(downrangeMeters: -rangeMeters, mapper: mapper, visible: visible)
    }

    func apply(downrangeMeters: Double, mapper: LMWorldMapper, visible: Bool) {
        root.isEnabled = visible
        guard visible else { return }
        bead.position = mapper.stripBeadOffset(downrangeMeters: downrangeMeters)
    }
}
