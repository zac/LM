import AGC
import RealityKit

/// Production boundary for SpatialTapGesture.onEnded. Hover and cancelled
/// recognition do not call this adapter. PRO remains a bounded FIFO pulse.
@MainActor
enum LMInstrumentInteraction {
    @discardableResult
    static func completedTap(
        on entity: Entity,
        station: LMCommanderStationScene,
        sendKey: (DSKYKeyCode) -> Void,
        didAccept: (DSKYKeyCode) -> Void = { _ in }
    ) -> Bool {
        guard let key = station.dskyKeyCode(for: entity) else { return false }
        station.animateDSKYKeyPress(key)
        sendKey(key)
        didAccept(key)
        return true
    }
}
