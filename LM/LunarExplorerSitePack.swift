import Foundation
import LMCore

/// Bounds belong to resident contact data, not to the camera mode. A future
/// region publication can replace these together with its geometry/contact.
struct LunarExplorerPanBounds: Equatable, Sendable {
    let north: ClosedRange<Double>
    let east: ClosedRange<Double>

    static let regional = Self(north: -20_000...20_000, east: -20_000...20_000)
}

/// A bundled source pack in the same Moon-centred/ENU authority as global
/// regions. Its authored heights and meshes remain unchanged source data.
struct LunarExplorerSitePack: Sendable {
    let frame: LMSelenographicLocalFrame
    let focusOrigin: LMVector3D
    let panBounds: LunarExplorerPanBounds
    let sourceIDs: [String]

    init(manifest: LMTerrainManifest, focusOrigin: LMVector3D) throws {
        guard let tile = manifest.tile(id: "near-field"), tile.extentMeters > 256 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        frame = manifest.landingLocalFrame
        self.focusOrigin = focusOrigin
        sourceIDs = tile.sourceIDs ?? []
        // Match source selection's 128 m measured morph collar. Offsets are
        // relative to the focus landmark; the coverage is relative to the tile.
        let half = tile.extentMeters / 2 - 128
        panBounds = .init(north: (-half - focusOrigin.x)...(half - focusOrigin.x),
                          east: (-half - focusOrigin.y)...(half - focusOrigin.y))
    }

    func configureInspection(_ camera: inout LunarExplorerCamera) {
        // Explicit reference calibration preserves the pinned Apollo poses.
        // The interactive camera has no per-source presentation-height branch.
        camera.reference?.siteHeightMeters = -0.35
        camera.reference?.fixedGlobeCoordinate = frame.anchor
    }
}
