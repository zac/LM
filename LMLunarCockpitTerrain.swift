import LunarMap
import Foundation
import OSLog
import LMCore
import RealityKit
import simd

/// Cockpit-only residency policy. Explorer planning and Apollo geometry retain
/// their existing paths. Predictions choose work; published coverage gates flight.
enum LMLunarCockpitStreamingPolicy {
    static let lookAheadSeconds = 40.0
    static let maximumPrefetchedTiles = 80

    static func spacing(at altitude: Double) -> Double {
        var policy = LMTerrainDetailPolicy()
        policy.globalBands = true
        return policy.finestSpacingMeters(altitudeMeters: altitude) ?? 512
    }

    static func forecast(_ state: LMVehicleStateSnapshot) -> (east: Double, north: Double, altitude: Double) {
        let p = state.positionMeters, v = state.velocityMetersPerSecond
        let radius = state.landingSite?.radiusMeters ?? 1_737_400
        let radialSpeed = (p.x * v.x + p.y * v.y + (p.z + radius) * v.z)
            / sqrt(p.x * p.x + p.y * p.y + (p.z + radius) * (p.z + radius))
        let currentSpacing = spacing(at: state.altitudeMeters)
        let levels = LMProgressiveTerrainPlanner.globalLevels.sorted { $0.sampleSpacingMeters > $1.sampleSpacingMeters }
        let next = levels.first { $0.sampleSpacingMeters < currentSpacing } ?? levels.last!
        // Bound time and distance together. A fixed 40-second altitude forecast
        // at 500 m would request landing detail while traveling 50 m/s; a 64 m
        // landing footprint would be obsolete long before its bake completed.
        let seconds = min(lookAheadSeconds, next.tileSizeMeters * 4 / max(1, hypot(v.x, v.y)))
        let altitude = max(0, state.altitudeMeters + min(0, radialSpeed) * seconds)
        return (p.y + v.y * seconds, p.x + v.x * seconds, altitude)
    }

    static func plans(_ state: LMVehicleStateSnapshot, sourceSpacing: Double) -> [LMTerrainTilePlan] {
        let future = forecast(state)
        func focus(_ east: Double, _ north: Double, _ altitude: Double) -> [LMTerrainTilePlan] {
            LMLunarTerrainPresentation.plans(sourceSpacing: sourceSpacing, east: east, north: north,
                altitude: altitude, metersAcross: max(64, min(32_000, altitude * 3)), heading: 90)
        }
        let current = focus(state.positionMeters.y, state.positionMeters.x, max(0, state.altitudeMeters))
        let ahead = focus(future.east, future.north, future.altitude)
        let planner = LMProgressiveTerrainPlanner(sourceSpacingMeters: sourceSpacing,
            levels: LMProgressiveTerrainPlanner.globalLevels)
        let combined = planner.rectangularPlansEnclosingChildren(current + ahead)
        // A prediction may spend only this many tiles. Retain the normal
        // current-view request if unusual geometry would exceed the budget.
        return (combined.count <= maximumPrefetchedTiles ? combined : current).sorted {
            if $0.sampleSpacingMeters != $1.sampleSpacingMeters { return $0.sampleSpacingMeters > $1.sampleSpacingMeters }
            if $0.id.northIndex != $1.id.northIndex { return $0.id.northIndex < $1.id.northIndex }
            return $0.id.eastIndex < $1.id.eastIndex
        }
    }

    /// Exact rectangle-union coverage, including disjoint tiles and internal
    /// gaps. Checking only the center or four corners can miss a hole.
    static func covers(_ plans: [LMTerrainTilePlan], east: Double, north: Double,
                       radius: Double, interior: Bool = false) -> Bool {
        guard east.isFinite, north.isFinite, radius.isFinite, radius >= 0 else { return false }
        let west = east - radius, right = east + radius, south = north - radius, top = north + radius
        let rectangles = plans.map { plan -> (w: Double, e: Double, s: Double, n: Double) in
            let half = plan.sizeMeters / 2, collar = interior ? plan.sizeMeters / 4 : 0
            return (plan.centerEastMeters - half + (plan.transitionEdges.contains(.west) ? collar : 0),
                    plan.centerEastMeters + half - (plan.transitionEdges.contains(.east) ? collar : 0),
                    plan.centerNorthMeters - half + (plan.transitionEdges.contains(.south) ? collar : 0),
                    plan.centerNorthMeters + half - (plan.transitionEdges.contains(.north) ? collar : 0))
        }.filter { $0.e >= west && $0.w <= right && $0.n >= south && $0.s <= top }
        if rectangles.contains(where: { $0.w <= west && $0.e >= right && $0.s <= south && $0.n >= top }) { return true }
        let cuts = ([west, right] + rectangles.flatMap { [$0.w, $0.e] }.filter { $0 > west && $0 < right }).sorted()
        for pair in zip(cuts, cuts.dropFirst()) {
            let x = (pair.0 + pair.1) / 2
            let intervals = rectangles.filter { $0.w <= x && $0.e >= x }.sorted { $0.s < $1.s }
            var covered = south
            for interval in intervals {
                if interval.s > covered { break }
                covered = max(covered, interval.n)
            }
            if covered < top { return false }
        }
        return !rectangles.isEmpty
    }

    static func permitsStep(_ state: LMVehicleStateSnapshot, snapshot: LMLunarTerrainMeshSnapshot) -> Bool {
        // Bound the entire body/footpad sweep for the largest runtime step,
        // independent of attitude or leg compression. 100 m/s² exceeds the
        // modeled DPS/RCS translational acceleration even at dry mass.
        let step = max(LMSimulationPace.acceleratedDeltaSeconds, LMSimulationPace.realtimeFrameCapSeconds)
        let reach = LMLandingGearGeometry.footpadRadiusMeters
            + LMLandingGearGeometry.primaryStrutStrokeMeters
            + LMLandingGearGeometry.contactProbeLengthMeters
        let v = state.velocityMetersPerSecond
        let radius = reach + hypot(v.x, v.y) * step + 100 * step * step
        return covers(snapshot.tiles.map(\.plan), east: state.positionMeters.y,
                      north: state.positionMeters.x, radius: radius)
    }
}

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
    private var holdsTerrainAtContact = false
    private var reportedTerminalRays = false

    var captureMetrics: [String: Double] {
        ["maximumContactErrorMeters": maximumContactError, "contactSamples": Double(contactSamples),
         "missingContactSamples": Double(missingContactSamples),
         "heldAtContact": holdsTerrainAtContact ? 1 : 0,
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
        presentation.publicationAllowed = { [weak self] in self?.holdsTerrainAtContact != true }
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
        if state.altitudeMeters > 250 {
            // Ignition restart/departure releases the previous landing surface.
            holdsTerrainAtContact = false
            reportedTerminalRays = false
        } else if !holdsTerrainAtContact,
                  state.landingGear?.isProbeContact == true || state.surfaceContact != nil || state.flightOutcome.isTerminal {
            holdsTerrainAtContact = true
            if !presentation.isMorphing {
                // Discard an unpublished replacement instead of retaining its
                // upload resources for the rest of a settled mission.
                presentation.cancel()
                lastPlans = []
                ready = true
            }
        }
        if state.altitudeMeters < 250 {
            for leg in LMLandingGearLeg.allCases {
                let stroke = state.landingGear?.legs.first(where: { $0.leg == leg })?.strokeMeters ?? 0
                let point = state.positionMeters + state.attitude.rotated(LMLandingGearGeometry.footpadBody(leg, strokeMeters: stroke))
                if let contact, let drawn = presentation.snapshot.sample(east: point.y, north: point.x) {
                    let ground = contact.surfaceHeightMeters(northMeters: point.x, eastMeters: point.y)
                    maximumContactError = max(maximumContactError, abs(ground - Double(drawn.elevation)))
                    contactSamples += 1
                } else {
                    missingContactSamples += 1
                }
            }
        }
        if state.flightOutcome.isTerminal, !reportedTerminalRays,
           ProcessInfo.processInfo.arguments.contains("--cockpit-terrain-rays") {
            reportedTerminalRays = true
            let snapshot = presentation.snapshot
            let orientation = LMWorldMapper.attitudeOrientation(from: state.attitude)
            // Nominal Simulator eye, not tracked headset pose. Hull occlusion
            // is deliberately excluded so this isolates terrain ownership.
            let eye = SIMD3(Float(state.positionMeters.x), Float(state.positionMeters.z),
                            Float(-state.positionMeters.y)) + orientation.act(SIMD3(0, 1.45, 0))
            Task.detached(priority: .utility) {
                let logger = Logger(subsystem: "io.positron.LM", category: "TerrainOwnership")
                for v: Float in [-0.3, 0, 0.3] {
                    for u: Float in [-0.5, 0, 0.5] {
                        if let hit = snapshot.raycast(origin: eye, direction: orientation.act(SIMD3(u, v, -1))) {
                            let angularCell = atan2(hit.plan.sampleSpacingMeters, Double(hit.distance)) * 180 / .pi
                            logger.info("Cockpit terrain ray u=\(u) v=\(v) spacing=\(hit.plan.sampleSpacingMeters)m distance=\(hit.distance)m cellAngle=\(angularCell)deg east=\(-hit.position.z)m north=\(hit.position.x)m")
                        } else {
                            logger.info("Cockpit terrain ray u=\(u) v=\(v) missed=true")
                        }
                    }
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
        guard !holdsTerrainAtContact, ready || lastPlans.isEmpty else { return }
        let plans: [LMTerrainTilePlan]
        if let vehicle, vehicle.altitudeMeters < 5_000 {
            let forecast = LMLunarCockpitStreamingPolicy.forecast(vehicle)
            let spacing = LMLunarCockpitStreamingPolicy.spacing(at: forecast.altitude)
            let radius = 8 + min(32, hypot(vehicle.velocityMetersPerSecond.x,
                                           vehicle.velocityMetersPerSecond.y) * 2)
            if lastPlans.map(\.sampleSpacingMeters).min() == spacing,
               LMLunarCockpitStreamingPolicy.covers(lastPlans.filter { $0.sampleSpacingMeters == spacing },
                   east: east, north: north, radius: radius, interior: true) { return }
            plans = LMLunarCockpitStreamingPolicy.plans(vehicle,
                sourceSpacing: presentation.region.terrain.base.spacingMeters)
        } else {
            plans = LMLunarTerrainPresentation.plans(sourceSpacing: presentation.region.terrain.base.spacingMeters,
                east: east, north: north, altitude: altitude, metersAcross: max(64, min(32_000, altitude * 3)), heading: 90)
        }
        guard plans != lastPlans else { return }
        lastPlans = plans
        ready = false
        presentation.update(plans: plans, east: east, north: north) { [weak self] message, _, _, _, milliseconds in
            self?.status = message
            self?.ready = milliseconds != nil
        }
    }

    /// A pending replacement is not a reason to stop flight: the published
    /// generation remains the authority for both rendering and contact.
    var permitsPhysicsStep: Bool {
        guard let vehicle else { return ready }
        if vehicle.altitudeMeters > 250 { return true }
        return contact != nil && LMLunarCockpitStreamingPolicy.permitsStep(vehicle,
            snapshot: presentation.snapshot)
    }
}
