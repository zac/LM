#if DEBUG
import AGC
import Foundation
import OSLog
import RealityKit
import simd

/// Opt-in observer and trace harness; never substitutes instrument state.
@MainActor
enum LMInstrumentValidation {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--instrument-validation") }
    static let logger = Logger(subsystem: "io.positron.LM", category: "InstrumentValidation")

    private static var observer: [String: Any] = [:]
    private static var completedTaps: [[String: Any]] = []

    static func recordCompletedTap(_ key: DSKYKeyCode, entity: Entity) {
        guard enabled else { return }
        completedTaps.append([
            "key": key.label, "entity": entity.name,
            "date": ISO8601DateFormatter().string(from: Date()),
            "inputKind": "SpatialTapGesture.onEnded"
        ])
    }

    static func frameObserver(_ root: Entity) {
        guard enabled else { return }
        let eye = LMCommanderStationGeometry.comfortableEntryEyeMeters
        let target = LMCommanderStationGeometry.cabinFrameOffsetMeters + LMCommanderStationGeometry.dskyMountPositionMeters
        let forward = simd_normalize(target - eye)
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_cross(right, forward)
        let inverseObserver = simd_quatf(simd_float3x3(columns: (right, up, -forward))).inverse
        // Inverse observer pose on the complete scene; local instrument and
        // cabin mounts, metric scale and relative occlusion remain unchanged.
        root.orientation = inverseObserver
        root.position = inverseObserver.act(-eye)
        observer = [
            "eyeMeters": [eye.x, eye.y, eye.z],
            "targetMeters": [target.x, target.y, target.z],
            "rootPositionMeters": [root.position.x, root.position.y, root.position.z],
            "rootQuaternionXYZW": [root.orientation.imag.x, root.orientation.imag.y,
                                   root.orientation.imag.z, root.orientation.real],
            "cameraMethod": "inverse observer on complete scene; native simulator camera reset"
        ]
        logger.notice("DEBUG observer aimed at DSKY; instrument mounts unchanged")
    }

    static func run(session: PoweredDescentSession) async {
        guard enabled else { return }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let file = directory.appendingPathComponent("InstrumentValidation.jsonl")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        let start = Date()
        let automatic = ProcessInfo.processInfo.arguments.contains("--instrument-validation-inputs")
        completedTaps.removeAll()
        for tick in 0..<2400 {
            guard !Task.isCancelled else { return }
            var action = "observe"
            if automatic {
                switch tick {
                case 20:
                    session.sendDSKYScript(.v16n36e)
                    action = "programmatic V16N36E via session queue"
                case 60:
                    session.sendDSKYKey(.pro)
                    action = "programmatic PRO via session queue"
                case 100:
                    session.sendDSKYScript(.v35e)
                    action = "programmatic V35E via session queue"
                case 160:
                    session.sendDSKYKey(.reset)
                    action = "programmatic RSET via session queue"
                default: break
                }
            }
            var row: [String: Any] = ["processID": ProcessInfo.processInfo.processIdentifier, "elapsedSeconds": Date().timeIntervalSince(start), "date": ISO8601DateFormatter().string(from: Date()), "action": action, "inputKind": automatic ? "programmatic-session-input" : "observation-only"]
            row["observer"] = observer
            row["completedSpatialTaps"] = completedTaps
            if let s = session.dsky {
                row["mode"] = s.mode; row["verb"] = s.verb; row["noun"] = s.noun
                row["r1"] = s.r1; row["r2"] = s.r2; row["r3"] = s.r3
                row["channel163"] = s.channel163; row["flashBlank"] = s.verbNounFlash
                row["proPressed"] = s.proKeyPressed; row["lampTest"] = s.lampTest
                row["compActy"] = s.compActy
                row["litIndicators"] = DSKYSnapshot.indicatorIDs.filter { s.indicatorIsOn($0) }
            }
            if let state = session.vehicleState {
                row["altitudeMeters"] = state.altitudeMeters
                row["attitude"] = [state.attitude.w, state.attitude.x, state.attitude.y, state.attitude.z]
            }
            if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) {
                try? handle.write(contentsOf: data + Data([10]))
            }
            if action != "observe" { logger.notice("\(action, privacy: .public)") }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}
#endif
