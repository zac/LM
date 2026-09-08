import Foundation
import LMCore
import LMKit
import RealityKit
import simd

@MainActor
final class LMImportedAltitudeRate {
    struct Contract: Decodable {
        struct Tape: Decodable {
            struct Row: Decodable { let name: String; let value: Double }
            let group: String
            let pointer: String
            let unavailable: String
            let valid_range: [Double]
            let q_knots: [[Double]]?
            let q_abs_knots: [[Double]]?
            let origin_m: [Float]
            let rows: [Row]
            let unavailable_active_position_m: [Float]
            let unavailable_parked_position_m: [Float]
        }
        struct Motion: Decodable {
            let visible_aperture_half_height_m: Float
            let row_max_half_height_m: Float
            let row_center_limit_m: Float
            let tape_group_moves: Bool
        }
        let schema: String
        let root: String
        let units: String
        let slot: String
        let slot_local_pose: LMCommanderStationAssembly.Inventory.Pose
        let altitude: Tape
        let altitude_rate: Tape
        let motion: Motion
    }
    private struct TapeBinding {
        let definition: Contract.Tape
        let group: Entity
        let invalid: Entity
        let rows: [(Entity, Double)]
        let scale: LMTapeScale
    }
    let root: Entity
    let contract: Contract
    let slotPose: Transform
    private let altitude: TapeBinding
    private let rate: TapeBinding
    private(set) var reading = LMAltitudeRateReading(state: nil)

    static func load() throws -> LMImportedAltitudeRate {
        try .init(asset: Entity.load(contentsOf: LMKitAssets.altitudeRateURL),
                  interfaceData: Data(contentsOf: LMKitAssets.altitudeRateInterfaceURL))
    }
    init(asset: Entity, interfaceData: Data) throws {
        contract = try JSONDecoder().decode(Contract.self, from: interfaceData)
        guard contract.schema == "lmkit.altitude-rate.interface.v1", contract.units == "meters",
              contract.root == "AltitudeRate", contract.slot == "Panel1__RangeThrust",
              contract.altitude.valid_range == [0, 60000], contract.altitude_rate.valid_range == [-700, 700],
              !contract.motion.tape_group_moves, contract.motion.row_center_limit_m > 0,
              contract.motion.row_center_limit_m + contract.motion.row_max_half_height_m <= contract.motion.visible_aperture_half_height_m else {
            throw LMCommanderStationAssembly.AssemblyError.invalidContract("Altitude/rate contract")
        }
        root = try LMCockpitComponentSupport.neutralRoot(contract.root, asset: asset)
        slotPose = try contract.slot_local_pose.transform()
        altitude = try Self.bind(contract.altitude, signed: false, root: root)
        rate = try Self.bind(contract.altitude_rate, signed: true, root: root)
        LMCockpitComponentSupport.removeInput(root)
        apply(.init(state: nil))
    }
    private static func bind(_ definition: Contract.Tape, signed: Bool, root: Entity) throws -> TapeBinding {
        let group = try LMCommanderStationAssembly.unique(definition.group, in: root)
        let invalid = try LMCommanderStationAssembly.unique(definition.unavailable, in: root)
        let pointer = try LMCommanderStationAssembly.unique(definition.pointer, in: root)
        let scale = LMTapeScale(knots: (signed ? definition.q_abs_knots : definition.q_knots) ?? [], signed: signed)
        guard scale.isValid, group.parent === root, invalid.parent === root,
              simd_distance(group.position, try LMCockpitComponentSupport.vector(definition.origin_m)) < 0.00001,
              !definition.rows.isEmpty, Set(definition.rows.map(\.name)).count == definition.rows.count else {
            throw LMCommanderStationAssembly.AssemblyError.invalidContract("Tape origin or scale")
        }
        _ = try LMCockpitComponentSupport.vector(definition.unavailable_active_position_m)
        _ = try LMCockpitComponentSupport.vector(definition.unavailable_parked_position_m)
        let rows = try definition.rows.map { row -> (Entity, Double) in
            let entity = try LMCommanderStationAssembly.unique(row.name, in: group)
            guard entity.parent === group, scale.coordinate(for: row.value) != nil else {
                throw LMCommanderStationAssembly.AssemblyError.invalidContract("Tape row")
            }
            LMCockpitComponentSupport.readableMarkings(entity)
            return (entity, row.value)
        }
        LMCockpitComponentSupport.readableMarkings(pointer)
        LMCockpitComponentSupport.readableMarkings(invalid)
        return .init(definition: definition, group: group, invalid: invalid, rows: rows, scale: scale)
    }
    func apply(_ reading: LMAltitudeRateReading) {
        self.reading = reading
        apply(reading.altitudeFeet, to: altitude)
        apply(reading.rateFeetPerSecond, to: rate)
    }
    private func apply(_ value: Double?, to tape: TapeBinding) {
        let coordinate = value.flatMap { tape.scale.coordinate(for: $0) }
        tape.group.isEnabled = coordinate != nil
        tape.invalid.isEnabled = coordinate == nil
        let position = coordinate == nil ? tape.definition.unavailable_active_position_m : tape.definition.unavailable_parked_position_m
        tape.invalid.position = SIMD3(position[0], position[1], position[2])
        for (row, rowValue) in tape.rows {
            guard let coordinate, let target = tape.scale.coordinate(for: rowValue) else { row.isEnabled = false; continue }
            let y = Float(target - coordinate)
            row.position = [0, y, 0]
            row.isEnabled = abs(y) <= contract.motion.row_center_limit_m
        }
    }
}
