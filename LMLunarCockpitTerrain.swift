import Foundation
import LMCore
import RealityKit
import simd

/// One immutable source region shared by a cockpit mission and its terrain.
@MainActor
final class LMLunarCockpitTerrain {
    let presentation: LMLunarTerrainPresentation
    let root = Entity()
    let sun = DirectionalLight()
    let site: LMLunarLandingSite
    private let sourceSunOrientation: simd_quatf
    private var origin: LMLunarFloatingOrigin
    private(set) var status = "Loading lunar terrain"
    private(set) var ready = false
    private var vehicle: LMVehicleStateSnapshot?
    private var contact: LMTerrainContactSurface?
    private var maximumContactError = 0.0
    private var contactSamples = 0
    private var missingContactSamples = 0

    var captureMetrics: [String: Double] {
        ["maximumContactErrorMeters": maximumContactError, "contactSamples": Double(contactSamples),
         "missingContactSamples": Double(missingContactSamples),
         "reanchorGeneration": Double(origin.generation), "tiles": Double(presentation.snapshot.tiles.count),
         "measuredFloorMeters": presentation.region.measuredFloorMeters, "ready": ready ? 1 : 0]
    }
    private var lastPlans: [LMTerrainTilePlan] = []
    var contactChanged: ((LMTerrainContactSurface) -> Void)?

    init(region: LMLunarTerrainRegion, gate: LMTerrainSimulationGate, date: Date) throws {
        site = try LMLunarLandingSite(latitudeDegrees: region.frame.anchor.latitudeDegrees,
            longitudeDegrees: region.frame.anchor.longitudeDegrees,
            radiusMeters: region.frame.coordinateSystem.datumRadiusMeters + region.frame.anchor.heightMeters)
        origin = .init(frame: region.frame)
        presentation = .init(region: region, mode: .procedural, simulationGate: gate)
        root.addChild(presentation.root)
        root.addChild(sun)
        let angles = LMLunarEphemeris.sunAngles(at: date, site: region.frame.anchor)
        sourceSunOrientation = LMFullDescentMapper.sunLightOrientation(from: angles)
        sun.orientation = sourceSunOrientation
        sun.light.intensity = LMTerrainWorld.missionSunIlluminance(elevationDegrees: angles.elevationDegrees, grade: .calibrated)
        sun.shadow = LMTerrainWorld.missionShadow(altitudeMeters: 1_000)
        presentation.presentationChanged = { [weak self] in
            guard let self else { return }
            let surface = LMTerrainContactSurfaceBuilder.build(region: region, snapshot: self.presentation.snapshot)
            self.contact = surface
            self.contactChanged?(surface)
        }
    }

    func prepare() async throws {
        request(east: 0, north: 0, altitude: 1_000)
        for _ in 0..<600 {
            try Task.checkCancellation()
            if ready { return }
            if status.hasPrefix("Lunar terrain failed") { throw CocoaError(.fileReadCorruptFile) }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CocoaError(.fileReadUnknown)
    }

    func apply(_ state: LMVehicleStateSnapshot) {
        vehicle = state
        if let contact, state.altitudeMeters < 250 {
            for leg in LMLandingGearLeg.allCases {
                let stroke = state.landingGear?.legs.first(where: { $0.leg == leg })?.strokeMeters ?? 0
                let point = state.positionMeters + state.attitude.rotated(LMLandingGearGeometry.footpadBody(leg, strokeMeters: stroke))
                if let drawn = presentation.snapshot.sample(east: point.y, north: point.x) {
                    let ground = contact.surfaceHeightMeters(northMeters: point.x, eastMeters: point.y)
                    maximumContactError = max(maximumContactError, abs(ground - Double(drawn.elevation)))
                    contactSamples += 1
                } else {
                    missingContactSamples += 1
                }
            }
        }
        let frame = presentation.region.frame
        let focus = LMSiteENUPosition(northMeters: state.positionMeters.x,
            eastMeters: state.positionMeters.y, upMeters: state.positionMeters.z)
        _ = origin.update(focus: frame.moonCenteredPosition(for: focus))
        presentation.apply(anchor: origin.frame)
        let local = LMLunarFrameTransform(from: frame, to: origin.frame)
        sun.orientation = simd_quatf(vector: SIMD4<Float>(simd_quatd(local.renderRotation).vector)) * sourceSunOrientation
        let placement = LMLunarAnchoredPlacement(source: frame, anchor: origin.frame, focus: focus)
        let inverseAttitude = simd_float4x4(LMWorldMapper.attitudeOrientation(from: state.attitude).inverse)
        root.transform = Transform(matrix: inverseAttitude * placement.viewTransform.matrix)
        // Keep the target region resident during the high, accelerated approach.
        let followsVehicle = state.altitudeMeters < 5_000
        request(east: followsVehicle ? state.positionMeters.y : 0,
                north: followsVehicle ? state.positionMeters.x : 0,
                altitude: max(0, state.altitudeMeters))
    }

    func anchorPosition(_ position: LMVector3D) -> SIMD3<Float> {
        let local = LMLunarFrameTransform(from: presentation.region.frame, to: origin.frame)
        return SIMD3<Float>(LMLunarFrameTransform.renderVector(local.position(SIMD3(position.x, position.y, position.z))))
    }

    private func request(east: Double, north: Double, altitude: Double) {
        // A moving approach can cross tile boundaries faster than a generation
        // completes. Finish the bounded request, then use the latest vehicle
        // pose; cancellation on every frame otherwise starves publication.
        guard ready || lastPlans.isEmpty else { return }
        let plans = LMLunarTerrainPresentation.plans(sourceSpacing: presentation.region.terrain.base.spacingMeters,
            east: east, north: north, altitude: altitude, metersAcross: max(64, min(32_000, altitude * 3)), heading: 90)
        guard plans != lastPlans else { return }
        lastPlans = plans
        ready = false
        presentation.update(plans: plans, east: east, north: north) { [weak self] message, _, _, _, milliseconds in
            self?.status = message
            self?.ready = milliseconds != nil
        }
    }

    /// Near touchdown, wait for requested detail rather than let AGC touch a
    /// fallback surface that is absent from the visible triangle snapshot.
    var permitsPhysicsStep: Bool {
        guard let vehicle else { return ready }
        if vehicle.altitudeMeters > 250 { return true }
        return ready && presentation.snapshot.sample(east: vehicle.positionMeters.y,
                                                      north: vehicle.positionMeters.x) != nil
    }
}
