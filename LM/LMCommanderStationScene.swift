import AGC
import LMCore
import OSLog
import RealityKit
import RealityKitContent
import SwiftUI
import UIKit
import simd

/// A life-size, source-backed blockout of the commander's powered-descent station.
///
/// Controlled cabin dimensions, panel relationships, and optical datums are kept
/// separate from digitized panel envelopes so the procedural scene and a future
/// production asset share one physical coordinate system.
@MainActor
final class LMCommanderStationScene {
    enum AssetError: Error {
        case invalidArtistCabin([LMCockpitAssetContract.ValidationIssue])
    }

    private(set) var commanderEntryAnchor = AnchorEntity(.head)
    let root = Entity()
    let lunarWorld = Entity()
    let acaHandle = ModelEntity()
    let rodSwitch = ModelEntity()
    let attitudeModeSwitch = ModelEntity()
    let missionControlButton = ModelEntity()
    let landingPointCalledAngleMarker = ModelEntity()
    let dskyFaceRoot = Entity()

    private let cabinFrame = Entity()
    private let fdaiMount = Entity()
    private let dskyDisplayMount = Entity()
    private let physicalDSKYAnnunciatorLegends = ModelEntity()
    private let physicalDSKYAnnunciatorLights = ModelEntity()
    private let physicalDSKYRegisters = ModelEntity()
    private let proceduralCabin = Entity()
    private let provisionalTerrain = Entity()
    private let dustCloud = Entity()
    private let mapper = LMCockpitWorldMapper.fullScale
    private let controlMapper = LMSpatialControlMapper()
    private let landingPointDesignator = LMLandingPointDesignator()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.positron.LM",
        category: "ProgressiveTerrain"
    )
    private var terrainHeightField: Apollo11TerrainHeightField?
    private var terrainFrameAlignment: LMTerrainFrameAlignment?
    private var terrainEnvironment: Entity?
    private var terrainRockField: Entity?
    private var terrainSun: DirectionalLight?
    private var terrainAlbedoTexture: TextureResource?
    private var progressiveTerrainEntities = [LMTerrainTileID: ModelEntity]()
    private var progressiveTerrainPlans = [LMTerrainTileID: LMTerrainTilePlan]()
    private var requestedTerrainTileIDs = Set<LMTerrainTileID>()
    private var requestedTerrainPlans = [LMTerrainTileID: LMTerrainTilePlan]()
    private var requiredTerrainTileIDs = Set<LMTerrainTileID>()
    private var terrainGenerationTasks = [LMTerrainTileID: Task<Void, Never>]()
    private var terrainGenerationTokens = [LMTerrainTileID: UUID]()
    private var lastTerrainPresentationBlendBucket: Int?
    private var lastMissionShadowDistanceMeters: Float?
    private var artistCabin: Entity?
    private var exteriorLunarModule: Entity?
    private var fdaiBall: Entity?
    private var retiredCommanderEntryAnchors = [AnchorEntity]()
    private var lastVehicleState: LMVehicleStateSnapshot?
    private var dskyKeyEntitiesByRawValue = [Int: ModelEntity]()
    private var dskyKeyRestPositions = [Int: SIMD3<Float>]()
    private var dskyKeyResetTasks = [Int: Task<Void, Never>]()
    private var lastPhysicalDSKYSignature: String?
    private var lastPhysicalDSKYHeader: String?
    private let acaNeutralPosition = LMCommanderStationGeometry.acaPivotPositionMeters
    private let rodNeutralPosition = LMCommanderStationGeometry.rodPivotPositionMeters
    private let attitudeModeAutomaticPosition =
        LMCommanderStationGeometry.attitudeHoldPivotPositionMeters

    init() {
        commanderEntryAnchor.name = "Commander entry head anchor"
        commanderEntryAnchor.anchoring.trackingMode = .once
        root.name = "LM Commander Station"
        lunarWorld.name = "Lunar World"
        cabinFrame.name = "LM cabin datum frame"
        cabinFrame.position = LMCommanderStationGeometry.cabinFrameOffsetMeters
        fdaiMount.name = LMCockpitAssetContract.Node.fdaiMount.rawValue
        fdaiMount.position = LMCommanderStationGeometry.fdaiMountPositionMeters
        fdaiMount.orientation = LMCommanderStationGeometry.fdaiMountOrientation
        dskyFaceRoot.name = LMCockpitAssetContract.Node.dskyMount.rawValue
        dskyDisplayMount.name = LMCockpitAssetContract.Node.dskyDisplayMount.rawValue
        dskyDisplayMount.position = SIMD3(
            LMDSKYGeometry.displayCenterMeters.x,
            LMDSKYGeometry.displayCenterMeters.y,
            0
        )
        proceduralCabin.name = LMCockpitAssetContract.Node.cabinRoot.rawValue
        provisionalTerrain.name = "Provisional terrain"
        dustCloud.name = "Descent engine dust"

        // Capture the wearer's entry pose once, then keep the vehicle fixed in
        // world space. Start aft of the optical datum so the panel stack is
        // visible; leaning forward still reaches the exact flight design eye.
        root.position = -LMCommanderStationGeometry.comfortableEntryEyeMeters
        commanderEntryAnchor.addChild(root)

        root.addChild(cabinFrame)
        cabinFrame.addChild(proceduralCabin)
        buildCabin()
        buildLandingPointCalledAngleMarker()
        buildPhysicalDSKY()
        buildPhysicalControls()
        // The cabin's layered panel faces generated moving shadow-map acne on
        // Vision Pro. Keep only the pressure shell as the ascent-stage shadow
        // silhouette; the exterior model supplies the descent stage and legs.
        if let shell = proceduralCabin.findEntity(
            named: LMCockpitAssetContract.Node.cabinShell.rawValue
        ) {
            setDynamicShadowCasting(in: shell)
        }
        buildProvisionalSurface()
        buildDustCloud()

        root.addChild(lunarWorld)
        cabinFrame.addChild(fdaiMount)
        buildPhysicalFDAI()
    }

    func mountFDAI(_ entity: Entity) {
        guard entity.parent == nil else { return }
        entity.name = "Commander FDAI"
        entity.position = SIMD3(0, 0, 0.004)
        entity.orientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        entity.scale = SIMD3(repeating: 0.00095)
        fdaiMount.addChild(entity)
        logger.notice("Mounted live FDAI flight face")
    }

    /// Re-captures the current headset pose while preserving the live vehicle,
    /// terrain, instruments, and control entities under `root`.
    func recenterAtCurrentHeadPose() {
        let retiredAnchor = commanderEntryAnchor
        root.removeFromParent()
        retiredCommanderEntryAnchors.append(retiredAnchor)

        let newAnchor = AnchorEntity(.head)
        newAnchor.name = "Commander recentered head anchor"
        newAnchor.anchoring.trackingMode = .once
        root.position = -LMCommanderStationGeometry.comfortableEntryEyeMeters
        newAnchor.addChild(root)
        commanderEntryAnchor = newAnchor
    }

    func takeRetiredCommanderEntryAnchors() -> [AnchorEntity] {
        defer { retiredCommanderEntryAnchors.removeAll(keepingCapacity: true) }
        return retiredCommanderEntryAnchors
    }

    func mountDSKYDisplay(_ entity: Entity) {
        guard entity.parent == nil else { return }
        entity.name = "Live Apollo 11 DSKY display"
        entity.position = SIMD3(0, 0, 0.012)
        entity.scale = SIMD3(repeating: 0.00035)
        dskyDisplayMount.addChild(entity)
        logger.notice("Mounted live DSKY display")
    }

    /// Keeps the flight display readable when RealityView has not mounted its
    /// SwiftUI attachment yet. The physical text sits behind that attachment,
    /// so the live SwiftUI face remains the preferred presentation while both
    /// renderers consume the same immutable AGC snapshot.
    func applyDSKY(_ snapshot: DSKYSnapshot?) {
        let presentation = LMPhysicalDSKYPresentation(snapshot: snapshot)
        guard presentation.signature != lastPhysicalDSKYSignature else { return }
        lastPhysicalDSKYSignature = presentation.signature

        updatePhysicalDSKYText(
            physicalDSKYAnnunciatorLights,
            text: presentation.activeAnnunciatorText,
            size: physicalDSKYAnnunciatorSize,
            fontSize: 0.00355,
            color: UIColor(red: 1.0, green: 0.78, blue: 0.22, alpha: 1),
            weight: .semibold,
            alignment: .left
        )
        updatePhysicalDSKYText(
            physicalDSKYRegisters,
            text: presentation.registerText,
            size: physicalDSKYRegisterSize,
            fontSize: 0.0092,
            color: UIColor(red: 0.62, green: 1.0, blue: 0.49, alpha: 1),
            weight: .medium,
            alignment: .center
        )

        if presentation.header != lastPhysicalDSKYHeader {
            lastPhysicalDSKYHeader = presentation.header
            logger.notice("Physical DSKY display \(presentation.header, privacy: .public)")
        }
    }

    /// Loads the existing full LM art around the flight-datum cockpit. The
    /// terrain remains a sibling so vehicle/world mapping is unaffected.
    func loadExteriorLunarModule() throws {
        guard exteriorLunarModule == nil else { return }
        let scene = try Entity.load(named: "lm", in: realityKitContentBundle)
        guard let authoredLander = scene.findEntity(named: "lunarlander") else { return }

        let lander = authoredLander.clone(recursive: true)
        lander.name = "Flight-scale lunar module exterior"
        lander.transform = Transform(matrix: authoredLander.transformMatrix(relativeTo: scene))
        // The bundled art's monolithic ascent-stage skin has no interior and
        // cuts through the reconstructed pressure cabin when viewed from the
        // design station. Keep the landing gear, descent stage, and low external
        // appendages, while the source-backed cabin supplies the crew-visible
        // ascent-stage surfaces.
        lander.findEntity(named: "polySurfac")?.isEnabled = false
        suppressAuthoredAscentGeometry(in: lander, relativeTo: lander)
        setDynamicShadowCasting(in: lander)

        let registration = Entity()
        registration.name = "LM exterior asset registration"
        registration.scale = SIMD3(repeating: LMCommanderStationGeometry.exteriorModelScale)
        registration.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        registration.addChild(lander)
        root.addChild(registration)
        exteriorLunarModule = registration
    }

    private func setDynamicShadowCasting(in entity: Entity) {
        if entity.components[ModelComponent.self] != nil {
            entity.components.set(DynamicLightShadowComponent(castsShadow: true))
        }
        for child in entity.children {
            setDynamicShadowCasting(in: child)
        }
    }

    /// The existing model is useful for the descent stage and landing gear but
    /// was never authored as a walkable cabin. Remove objects wholly above the
    /// ascent/descent interface; otherwise antennas and closed outer panels are
    /// visible from inside the reconstructed pressure vessel.
    private func suppressAuthoredAscentGeometry(in entity: Entity, relativeTo root: Entity) {
        for child in entity.children {
            let bounds = child.visualBounds(relativeTo: root)
            if !bounds.isEmpty, bounds.min.y > 2.05 {
                child.isEnabled = false
            } else {
                suppressAuthoredAscentGeometry(in: child, relativeTo: root)
            }
        }
    }

    func apply(_ state: LMVehicleStateSnapshot?) {
        guard let state else { return }
        lastVehicleState = state
        fdaiBall?.orientation = FDAIOrientation.ballOrientation(
            for: state.attitude
        )
        updateMissionShadow(altitudeMeters: state.altitudeMeters)
        updateRockDetail(altitudeMeters: state.altitudeMeters)
        let terrainPosition = terrainPosition(for: state.positionMeters)
        let surfaceSample = progressiveSurfaceSample(
            at: terrainPosition,
            altitudeMeters: state.altitudeMeters
        )
        let surfaceElevation = surfaceSample?.presentationElevationMeters
            ?? terrainHeightField?.conservativeContactElevation(
                eastMeters: terrainPosition.y,
                northMeters: terrainPosition.x
            )
            ?? 0
        if let surfaceSample {
            logTerrainPresentationIfNeeded(
                surfaceSample,
                altitudeMeters: state.altitudeMeters
            )
        }
        lunarWorld.transform = Transform(matrix: mapper.lunarWorldMatrix(
            position: terrainPosition,
            attitude: state.attitude,
            surfaceElevationMeters: Double(surfaceElevation)
        ))
        requestProgressiveTerrain(
            around: terrainPosition,
            velocityNorthMetersPerSecond: state.velocityMetersPerSecond.x,
            velocityEastMetersPerSecond: state.velocityMetersPerSecond.y,
            altitudeMeters: state.altitudeMeters
        )
    }

    func loadApollo11Terrain() async throws {
        let heightField = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let assembly = try await LMTerrainWorld.load()
        let terrain = assembly.worldRoot
        terrainHeightField = heightField
        terrainFrameAlignment = try LMTerrainFrameAlignment(manifest: assembly.manifest)
        if let alignment = terrainFrameAlignment {
            logger.info(
                "Terrain aligned to Eagle at north \(alignment.terrainReferenceTouchdown.x, privacy: .public)m east \(alignment.terrainReferenceTouchdown.y, privacy: .public)m"
            )
        }
        terrainEnvironment = terrain
        terrainSun = assembly.sun
        terrainAlbedoTexture = assembly.nearAlbedoTexture
        terrainRockField?.removeFromParent()
        let rockField = try LMLunarRockFieldResource.makeEntity(
            heightField: heightField,
            eagleTerrainPosition: terrainFrameAlignment?.terrainReferenceTouchdown ?? .zero
        )
        terrain.addChild(rockField)
        terrainRockField = rockField
        logger.info(
            "Terrain rock field ready count=\(rockField.children.count, privacy: .public) model=\(LMLunarRockFieldModel.modelID, privacy: .public)"
        )
        provisionalTerrain.removeFromParent()
        lunarWorld.addChild(terrain)
        apply(lastVehicleState)
    }

    private func updateMissionShadow(altitudeMeters: Double) {
        guard let terrainSun else { return }
        let distance = LMTerrainWorld.missionShadowDistance(
            altitudeMeters: altitudeMeters
        )
        guard lastMissionShadowDistanceMeters.map({ abs($0 - distance) >= 0.5 })
                ?? true else { return }
        lastMissionShadowDistanceMeters = distance
        terrainSun.shadow = LMTerrainWorld.missionShadow(
            altitudeMeters: altitudeMeters
        )
    }

    private func updateRockDetail(altitudeMeters: Double) {
        guard let terrainRockField else { return }
        for rock in terrainRockField.children {
            rock.isEnabled = LMLunarRockDetailPolicy.isVisible(
                maximumDimensionMeters: max(rock.scale.x, rock.scale.z),
                altitudeMeters: altitudeMeters
            )
        }
    }

    private func terrainPosition(for guidancePosition: LMVector3D) -> LMVector3D {
        terrainFrameAlignment?.terrainPosition(from: guidancePosition) ?? guidancePosition
    }

    private func requestProgressiveTerrain(
        around terrainPosition: LMVector3D,
        velocityNorthMetersPerSecond: Double,
        velocityEastMetersPerSecond: Double,
        altitudeMeters: Double
    ) {
        guard let heightField = terrainHeightField,
              let terrainEnvironment,
              let terrainAlbedoTexture else { return }
        let planner = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: heightField.spacingMeters
        )
        let requiredPlans = planner.focusedPlans(
            focusEastMeters: terrainPosition.y,
            focusNorthMeters: terrainPosition.x,
            altitudeMeters: altitudeMeters
        )
        let plans = planner.prefetchedPlans(
            focusEastMeters: terrainPosition.y,
            focusNorthMeters: terrainPosition.x,
            velocityEastMetersPerSecond: velocityEastMetersPerSecond,
            velocityNorthMetersPerSecond: velocityNorthMetersPerSecond,
            altitudeMeters: altitudeMeters
        )
        let requestedIDs = Set(plans.map(\.id))
        let requiredIDs = Set(requiredPlans.map(\.id))
        guard requestedIDs != requestedTerrainTileIDs
                || requiredIDs != requiredTerrainTileIDs else { return }
        logger.info(
            "Terrain LOD request count=\(plans.count, privacy: .public) required=\(requiredPlans.count, privacy: .public) altitude=\(altitudeMeters, privacy: .public)m model=\(LMLunarGeologyModel.modelID, privacy: .public)"
        )
        requestedTerrainTileIDs = requestedIDs
        requestedTerrainPlans = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })
        requiredTerrainTileIDs = requiredIDs

        let cancelledIDs = terrainGenerationTasks.keys.filter {
            requestedTerrainPlans[$0] == nil
        }
        for id in cancelledIDs {
            terrainGenerationTasks[id]?.cancel()
            terrainGenerationTasks.removeValue(forKey: id)
            terrainGenerationTokens.removeValue(forKey: id)
        }
        retireUndesiredTerrainEntities()

        for plan in plans where progressiveTerrainEntities[plan.id] == nil
            && terrainGenerationTasks[plan.id] == nil {
            let token = UUID()
            terrainGenerationTokens[plan.id] = token
            terrainGenerationTasks[plan.id] = Task { @MainActor [weak self] in
                guard let self else { return }
                let generationStarted = Date()
                do {
                    let entity = try await Apollo11TerrainResource.makeProgressiveTileEntity(
                        heightField: heightField,
                        plan: plan,
                        albedoTexture: terrainAlbedoTexture
                    )
                    guard self.finishTerrainGeneration(plan.id, token: token),
                          !Task.isCancelled,
                          self.requestedTerrainPlans[plan.id] == plan,
                          let entity else { return }
                    terrainEnvironment.addChild(entity)
                    self.progressiveTerrainEntities[plan.id] = entity
                    self.progressiveTerrainPlans[plan.id] = plan
                    let elapsedMilliseconds = Int(
                        Date().timeIntervalSince(generationStarted) * 1_000
                    )
                    let samples = Int(plan.sizeMeters / plan.sampleSpacingMeters) + 1
                    self.logger.info(
                        "Terrain tile ready L\(plan.id.level, privacy: .public) E\(plan.id.eastIndex, privacy: .public) N\(plan.id.northIndex, privacy: .public) spacing=\(plan.sampleSpacingMeters, privacy: .public)m vertices=\(samples * samples, privacy: .public) generation=\(elapsedMilliseconds, privacy: .public)ms"
                    )
                    let retiredCount = self.retireUndesiredTerrainEntities()
                    self.logger.info(
                        "Terrain LOD active=\(self.progressiveTerrainEntities.count, privacy: .public) added=1 retired=\(retiredCount, privacy: .public)"
                    )
                    self.refreshTerrainPresentationAfterResidencyChange()
                } catch is CancellationError {
                    _ = self.finishTerrainGeneration(plan.id, token: token)
                } catch {
                    guard self.finishTerrainGeneration(plan.id, token: token) else { return }
                    self.requestedTerrainTileIDs.remove(plan.id)
                    self.requestedTerrainPlans.removeValue(forKey: plan.id)
                    self.logger.error(
                        "Terrain tile L\(plan.id.level) E\(plan.id.eastIndex) N\(plan.id.northIndex) failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }

    @discardableResult
    private func finishTerrainGeneration(
        _ id: LMTerrainTileID,
        token: UUID
    ) -> Bool {
        guard terrainGenerationTokens[id] == token else { return false }
        terrainGenerationTasks.removeValue(forKey: id)
        terrainGenerationTokens.removeValue(forKey: id)
        return true
    }

    @discardableResult
    private func retireUndesiredTerrainEntities() -> Int {
        let activeIDs = Set(progressiveTerrainEntities.keys)
        guard requiredTerrainTileIDs.isSubset(of: activeIDs) else { return 0 }
        let retiredIDs = activeIDs.subtracting(requestedTerrainTileIDs)
        for id in retiredIDs {
            progressiveTerrainEntities.removeValue(forKey: id)?.removeFromParent()
            progressiveTerrainPlans.removeValue(forKey: id)
        }
        return retiredIDs.count
    }

    private func refreshTerrainPresentationAfterResidencyChange() {
        guard let state = lastVehicleState else { return }
        let terrainPosition = terrainPosition(for: state.positionMeters)
        if let surface = progressiveSurfaceSample(
            at: terrainPosition,
            altitudeMeters: state.altitudeMeters
        ) {
            let spacing = surface.sampleSpacingMeters
                .map { String(format: "%.3f", $0) } ?? "measured"
            let residual = surface.renderedElevationMeters
                - surface.measuredElevationMeters
            logger.info(
                "Terrain presentation spacing=\(spacing, privacy: .public)m renderedResidual=\(residual, privacy: .public)m blend=\(surface.presentationBlend, privacy: .public)"
            )
        }
        apply(state)
    }

    private func progressiveSurfaceSample(
        at terrainPosition: LMVector3D,
        altitudeMeters: Double
    ) -> LMTerrainSurfaceSample? {
        guard let terrainHeightField else { return nil }
        return LMProgressiveTerrainSurfaceSampler(
            heightField: terrainHeightField
        ).sample(
            eastMeters: terrainPosition.y,
            northMeters: terrainPosition.x,
            altitudeMeters: altitudeMeters,
            activePlans: Array(progressiveTerrainPlans.values)
        )
    }

    private func logTerrainPresentationIfNeeded(
        _ sample: LMTerrainSurfaceSample,
        altitudeMeters: Double
    ) {
        guard let spacing = sample.sampleSpacingMeters,
              abs(spacing - LMTerrainDetailPolicy().landingSpacingMeters) < 1e-6 else {
            lastTerrainPresentationBlendBucket = nil
            return
        }
        let bucket = min(Int(floor(sample.presentationBlend * 4)), 4)
        guard bucket != lastTerrainPresentationBlendBucket else { return }
        lastTerrainPresentationBlendBucket = bucket
        let renderedResidual = sample.renderedElevationMeters
            - sample.measuredElevationMeters
        let presentationResidual = sample.presentationElevationMeters
            - sample.measuredElevationMeters
        logger.info(
            "Terrain datum altitude=\(altitudeMeters, privacy: .public)m blend=\(sample.presentationBlend, privacy: .public) renderedResidual=\(renderedResidual, privacy: .public)m presentationResidual=\(presentationResidual, privacy: .public)m"
        )
    }

    @discardableResult
    func loadArtistCabinIfAvailable() async throws -> Bool {
        guard let cabin = try await LMCockpitAssetContract.loadIfAvailable() else {
            return false
        }
        let issues = LMCockpitAssetContract.validate(cabin)
        guard issues.isEmpty else {
            throw AssetError.invalidArtistCabin(issues)
        }
        artistCabin?.removeFromParent()
        cabin.name = LMCockpitAssetContract.Node.cabinRoot.rawValue
        cabinFrame.addChild(cabin)
        artistCabin = cabin
        proceduralCabin.isEnabled = false
        return true
    }

    func setACAVisual(_ input: LMACANormalizedInput) {
        let travel = LMCommanderStationGeometry.acaProportionalTravelDegrees * .pi / 180
        acaHandle.position = acaNeutralPosition
        acaHandle.orientation = simd_quatf(
            angle: Float(input.yaw) * travel,
            axis: SIMD3(0, 1, 0)
        ) * simd_quatf(
            angle: Float(input.pitch) * travel,
            axis: SIMD3(1, 0, 0)
        ) * simd_quatf(
            angle: Float(input.roll) * -travel,
            axis: SIMD3(0, 0, 1)
        )
    }

    func setRODVisual(_ position: PoweredDescentSession.RODSwitchPosition) {
        rodSwitch.position = rodNeutralPosition
        rodSwitch.orientation = LMCommanderStationGeometry.rodNeutralOrientation * simd_quatf(
            angle: controlMapper.visualRODDeflectionRadians(for: position),
            axis: SIMD3(1, 0, 0)
        )
    }

    func setAttitudeHoldVisual(_ isAttitudeHold: Bool) {
        attitudeModeSwitch.position = attitudeModeAutomaticPosition
            + SIMD3(0, isAttitudeHold ? 0.028 : 0, 0)
        attitudeModeSwitch.orientation = LMCommanderStationGeometry.attitudeHoldOrientation * simd_quatf(
            angle: isAttitudeHold ? -.pi / 7 : .pi / 7,
            axis: SIMD3(1, 0, 0)
        )
    }

    func setLandingPointCalledAngle(
        _ angleDegrees: Double?,
        trainingOverlayVisible: Bool
    ) {
        guard trainingOverlayVisible, let angleDegrees else {
            landingPointCalledAngleMarker.isEnabled = false
            return
        }
        landingPointCalledAngleMarker.position = landingPointDesignator.point(
            elevationDegrees: min(max(angleDegrees, 0), 60),
            on: .inner
        ) + landingPointDesignator.panePlane(.inner).normalTowardEye * 0.004
        landingPointCalledAngleMarker.isEnabled = true
    }

    func updateDust(
        state: LMVehicleStateSnapshot?,
        commands: LMVehicleSnapshot?
    ) {
        guard let state,
              state.flightOutcome == .inFlight,
              state.altitudeMeters < 35,
              commands?.mainEngineOn == true,
              commands?.mainEngineOff != true else {
            dustCloud.isEnabled = false
            return
        }

        let thrust = commands?.dps.commandedThrustNewtons ?? 0
        let throttle = Float(min(max(thrust / 46_710, 0), 1))
        let proximity = Float(min(max((35 - state.altitudeMeters) / 35, 0), 1))
        let intensity = throttle * proximity
        guard intensity > 0.015 else {
            dustCloud.isEnabled = false
            return
        }

        dustCloud.isEnabled = true
        let terrainPosition = terrainPosition(for: state.positionMeters)
        let surfaceElevation = progressiveSurfaceSample(
            at: terrainPosition,
            altitudeMeters: state.altitudeMeters
        )?.renderedElevationMeters
            ?? terrainHeightField?.conservativeContactElevation(
                eastMeters: terrainPosition.y,
                northMeters: terrainPosition.x
            )
            ?? 0
        dustCloud.position = mapper.realityPosition(from: LMVector3D(
            x: terrainPosition.x,
            y: terrainPosition.y,
            z: Double(surfaceElevation) + 0.18
        ))
        let spread = 0.8 + intensity * 2.6
        dustCloud.scale = SIMD3(spread, 0.25 + intensity * 0.45, spread)
        dustCloud.components.set(OpacityComponent(opacity: 0.08 + intensity * 0.34))
    }

    private func buildCabin() {
        let dark = SimpleMaterial(
            color: UIColor(red: 0.105, green: 0.115, blue: 0.105, alpha: 1),
            roughness: 0.78,
            isMetallic: false
        )
        let panel = SimpleMaterial(
            color: UIColor(red: 0.19, green: 0.205, blue: 0.18, alpha: 1),
            roughness: 0.68,
            isMetallic: false
        )
        let aluminum = SimpleMaterial(
            color: UIColor(red: 0.49, green: 0.50, blue: 0.46, alpha: 1),
            roughness: 0.48,
            isMetallic: true
        )

        buildCabinShell(material: dark)
        for surface in LMCommanderStationGeometry.reconstructedSurfaces {
            let material = switch surface.id {
            case .panelOne, .panelTwo, .panelThree, .panelFour, .panelFive, .panelSix:
                panel
            default:
                dark
            }
            addBox(
                size: surface.sizeMeters,
                position: surface.centerMeters,
                orientation: surface.orientation,
                material: material,
                name: surface.id.rawValue
            )
        }

        buildForwardFaceStructure(material: aluminum)
        buildDeckDetails(material: panel)
        buildPanelDetails(panelMaterial: dark, switchMaterial: aluminum)
        buildFDAIBezel(panelMaterial: dark, rimMaterial: aluminum)
        installProceduralDatumNodes()

        // These rails follow the source-calibrated oblique window plane rather
        // than a facade-parallel approximation. The LMP aperture is mirrored
        // only for the procedural fallback; the artist asset contract carries
        // separate flight-station transforms.
        buildForwardWindowFrames(material: aluminum)

        buildLandingPointDesignator()
    }

    private func buildCabinShell(material: SimpleMaterial) {
        let shell = Entity()
        shell.name = LMCockpitAssetContract.Node.cabinShell.rawValue
        proceduralCabin.addChild(shell)
        for segment in LMCommanderStationGeometry.shellSegments {
            let entity = ModelEntity(
                mesh: .generateBox(size: segment.sizeMeters),
                materials: [material]
            )
            entity.name = String(format: "Cabin shell segment %02d", segment.id + 1)
            entity.position = segment.centerMeters
            entity.orientation = segment.orientation
            shell.addChild(entity)
        }

        let radius = LMCommanderStationGeometry.crewCompartmentDiameterMeters / 2
        for (name, x) in [
            ("Commander lower pressure wall", -radius),
            ("LMP lower pressure wall", radius),
        ] {
            let wall = ModelEntity(
                mesh: .generateBox(size: SIMD3(
                    LMCommanderStationGeometry.shellThicknessMeters,
                    LMCommanderStationGeometry.shellLowerSideHeightMeters,
                    LMCommanderStationGeometry.crewCompartmentDepthMeters
                )),
                materials: [material]
            )
            wall.name = name
            wall.position = SIMD3(
                x,
                LMCommanderStationGeometry.shellFloorCenterMeters.y
                    + LMCommanderStationGeometry.shellLowerSideHeightMeters / 2,
                LMCommanderStationGeometry.shellCenterZMeters
            )
            shell.addChild(wall)
        }

        let floor = ModelEntity(
            mesh: .generateBox(size: LMCommanderStationGeometry.shellFloorSizeMeters),
            materials: [material]
        )
        floor.name = "Pressure vessel floor"
        floor.position = LMCommanderStationGeometry.shellFloorCenterMeters
        shell.addChild(floor)

        let aftBulkhead = ModelEntity(
            mesh: .generateBox(size: SIMD3(
                LMCommanderStationGeometry.shellBulkheadSizeMeters.x,
                LMCommanderStationGeometry.shellBulkheadSizeMeters.y,
                LMCommanderStationGeometry.shellThicknessMeters
            )),
            materials: [material]
        )
        aftBulkhead.name = "Aft pressure bulkhead"
        aftBulkhead.position = LMCommanderStationGeometry.shellAftBulkheadCenterMeters
        shell.addChild(aftBulkhead)

        do {
            let forwardBulkhead = ModelEntity(
                mesh: try makeForwardPressureBulkheadMesh(),
                materials: [material]
            )
            forwardBulkhead.name = "Forward pressure bulkhead"
            shell.addChild(forwardBulkhead)
        } catch {
            logger.fault(
                "Forward pressure bulkhead mesh failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Builds an opaque forward cabin face with only the two flight-window
    /// apertures omitted. The bulkhead is triangulated around the exact
    /// source-calibrated pane silhouettes so their edges remain smooth.
    private func makeForwardPressureBulkheadMesh() throws -> MeshResource {
        let diameter = LMCommanderStationGeometry.crewCompartmentDiameterMeters
        let radius = diameter / 2
        let minX = -radius
        let minY = LMCommanderStationGeometry.shellCenterYMeters - radius
        let maxX = radius
        let maxY = LMCommanderStationGeometry.shellCenterYMeters + radius
        let z = LMCommanderStationGeometry.shellForwardBulkheadZMeters
        let commanderWindow = landingPointDesignator.windowCorners(on: .inner).map {
            SIMD2<Float>($0.x, $0.y)
        }
        let lmpWindow = commanderWindow.map { SIMD2<Float>(-$0.x, $0.y) }
        var positions = [SIMD3<Float>]()
        var indices = [UInt32]()

        func appendPolygon(_ suppliedPoints: [SIMD2<Float>]) {
            guard suppliedPoints.count >= 3 else { return }
            let signedArea = suppliedPoints.indices.reduce(Float.zero) { partial, index in
                let next = suppliedPoints[(index + 1) % suppliedPoints.count]
                let point = suppliedPoints[index]
                return partial + point.x * next.y - next.x * point.y
            }
            var points = suppliedPoints
            if signedArea < 0 {
                points.reverse()
            }
            let base = UInt32(positions.count)
            positions.append(contentsOf: points.map { SIMD3($0.x, $0.y, z) })
            for index in 1..<(points.count - 1) {
                indices.append(contentsOf: [
                    base,
                    base + UInt32(index),
                    base + UInt32(index + 1),
                ])
            }
        }

        let commanderMinX = commanderWindow.map(\.x).min()!
        let commanderMaxX = commanderWindow.map(\.x).max()!
        let windowMinY = commanderWindow.map(\.y).min()!
        let windowMaxY = commanderWindow.map(\.y).max()!
        let lmpMinX = lmpWindow.map(\.x).min()!
        let lmpMaxX = lmpWindow.map(\.x).max()!

        // Five rectangles close the pressure wall outside the two window boxes.
        appendPolygon([
            SIMD2(minX, windowMaxY), SIMD2(maxX, windowMaxY),
            SIMD2(maxX, maxY), SIMD2(minX, maxY),
        ])
        appendPolygon([
            SIMD2(minX, minY), SIMD2(maxX, minY),
            SIMD2(maxX, windowMinY), SIMD2(minX, windowMinY),
        ])
        appendPolygon([
            SIMD2(minX, windowMinY), SIMD2(commanderMinX, windowMinY),
            SIMD2(commanderMinX, windowMaxY), SIMD2(minX, windowMaxY),
        ])
        appendPolygon([
            SIMD2(commanderMaxX, windowMinY), SIMD2(lmpMinX, windowMinY),
            SIMD2(lmpMinX, windowMaxY), SIMD2(commanderMaxX, windowMaxY),
        ])
        appendPolygon([
            SIMD2(lmpMaxX, windowMinY), SIMD2(maxX, windowMinY),
            SIMD2(maxX, windowMaxY), SIMD2(lmpMaxX, windowMaxY),
        ])

        appendBulkheadAroundWindow(
            commanderWindow,
            appendPolygon: appendPolygon
        )
        appendBulkheadAroundWindow(
            lmpWindow,
            appendPolygon: appendPolygon
        )

        var descriptor = MeshDescriptor(name: "LM forward pressure bulkhead")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    private func appendBulkheadAroundWindow(
        _ triangle: [SIMD2<Float>],
        appendPolygon: ([SIMD2<Float>]) -> Void
    ) {
        precondition(triangle.count == 3)
        let minX = triangle.map(\.x).min()!
        let maxX = triangle.map(\.x).max()!
        let minY = triangle.map(\.y).min()!
        let maxY = triangle.map(\.y).max()!
        let topLeft = SIMD2<Float>(minX, maxY)
        let topRight = SIMD2<Float>(maxX, maxY)
        let bottomRight = SIMD2<Float>(maxX, minY)
        let bottomLeft = SIMD2<Float>(minX, minY)
        let upperOutboard = triangle.min(by: { $0.x < $1.x })!
        let upperInboard = triangle.max(by: { $0.x < $1.x })!
        let lower = triangle.min(by: { $0.y < $1.y })!

        appendPolygon([topLeft, topRight, upperInboard, upperOutboard])
        appendPolygon([topRight, bottomRight, lower, upperInboard])
        appendPolygon([bottomRight, bottomLeft, upperOutboard, lower])
        appendPolygon([bottomLeft, topLeft, upperOutboard])
    }

    private func buildForwardFaceStructure(material: SimpleMaterial) {
        addBeam(
            from: SIMD3(-0.79, 0.14, -0.62),
            to: SIMD3(-0.86, 2.03, -0.60),
            thickness: 0.065,
            material: material,
            name: "Commander forward structural beam"
        )
        addBeam(
            from: SIMD3(0.79, 0.14, -0.62),
            to: SIMD3(0.86, 2.03, -0.60),
            thickness: 0.065,
            material: material,
            name: "LMP forward structural beam"
        )

        let hatch = LMCommanderStationGeometry.surface(.forwardHatch)
        let halfWidth = hatch.sizeMeters.x / 2
        let halfHeight = hatch.sizeMeters.y / 2
        let z = hatch.centerMeters.z + hatch.sizeMeters.z / 2 + 0.012
        let corners = [
            SIMD3(-halfWidth, hatch.centerMeters.y + halfHeight, z),
            SIMD3(halfWidth, hatch.centerMeters.y + halfHeight, z),
            SIMD3(halfWidth, hatch.centerMeters.y - halfHeight, z),
            SIMD3(-halfWidth, hatch.centerMeters.y - halfHeight, z),
        ]
        for index in corners.indices {
            addBeam(
                from: corners[index],
                to: corners[(index + 1) % corners.count],
                thickness: 0.030,
                material: material,
                name: "Forward hatch frame \(index + 1)"
            )
        }
    }

    private func buildDeckDetails(material: SimpleMaterial) {
        let deck = LMCommanderStationGeometry.surface(.cabinDeck)
        let deckTopY = deck.centerMeters.y + deck.sizeMeters.z / 2
        for index in 0..<12 {
            let fraction = (Float(index) + 0.5) / 12
            let z = deck.centerMeters.z + deck.sizeMeters.y * (fraction - 0.5)
            addBox(
                size: SIMD3(deck.sizeMeters.x * 0.91, 0.004, 0.022),
                position: SIMD3(0, deckTopY + 0.002, z),
                material: material,
                name: "Deck Velcro pile strip \(index + 1)"
            )
        }
    }

    private func buildPanelDetails(
        panelMaterial: SimpleMaterial,
        switchMaterial: SimpleMaterial
    ) {
        let panelOneLayout: [(SIMD2<Float>, SIMD2<Float>)] = [
            (SIMD2(-0.10, 0.14), SIMD2(0.13, 0.075)),
            (SIMD2(0.09, 0.14), SIMD2(0.13, 0.075)),
            (SIMD2(-0.10, -0.09), SIMD2(0.13, 0.12)),
            (SIMD2(0.09, -0.09), SIMD2(0.13, 0.12)),
        ]
        for panelID in [
            LMCommanderStationGeometry.SurfaceID.panelOne,
            .panelTwo,
        ] {
            for (index, detail) in panelOneLayout.enumerated() {
                addPanelDetail(
                    on: panelID,
                    center: detail.0,
                    size: detail.1,
                    depth: 0.010,
                    material: panelMaterial,
                    name: "\(panelID.rawValue) instrument bay \(index + 1)"
                )
            }
        }

        for index in 0..<12 {
            addPanelDetail(
                on: .panelThree,
                center: SIMD2(-0.385 + Float(index) * 0.07, 0),
                size: SIMD2(0.026, 0.052),
                depth: 0.012,
                material: index.isMultiple(of: 3) ? switchMaterial : panelMaterial,
                name: "Panel 3 control \(index + 1)"
            )
        }

        for panelID in [
            LMCommanderStationGeometry.SurfaceID.panelFive,
            .panelSix,
        ] {
            for row in 0..<2 {
                for column in 0..<4 {
                    addPanelDetail(
                        on: panelID,
                        center: SIMD2(-0.105 + Float(column) * 0.07, -0.055 + Float(row) * 0.11),
                        size: SIMD2(0.025, 0.045),
                        depth: 0.010,
                        material: panelMaterial,
                        name: "\(panelID.rawValue) control R\(row + 1)C\(column + 1)"
                    )
                }
            }
        }
    }

    private func buildFDAIBezel(
        panelMaterial: SimpleMaterial,
        rimMaterial: SimpleMaterial
    ) {
        let panel = LMCommanderStationGeometry.surface(.panelOne)
        let center = SIMD2<Float>(-0.055, -0.015)
        let aperture: Float = 0.205
        let rim: Float = 0.016
        let faceOffset = panel.sizeMeters.z / 2 + 0.012

        addBox(
            size: SIMD3(aperture, aperture, 0.008),
            position: panel.scenePoint(local: SIMD3(center.x, center.y, faceOffset - 0.005)),
            orientation: panel.orientation,
            material: panelMaterial,
            name: "Commander FDAI aperture"
        )
        for (name, localCenter, size) in [
            ("FDAI top bezel", SIMD2(center.x, center.y + aperture / 2 + rim / 2), SIMD2(aperture + rim * 2, rim)),
            ("FDAI bottom bezel", SIMD2(center.x, center.y - aperture / 2 - rim / 2), SIMD2(aperture + rim * 2, rim)),
            ("FDAI left bezel", SIMD2(center.x - aperture / 2 - rim / 2, center.y), SIMD2(rim, aperture)),
            ("FDAI right bezel", SIMD2(center.x + aperture / 2 + rim / 2, center.y), SIMD2(rim, aperture)),
        ] {
            addBox(
                size: SIMD3(size.x, size.y, 0.012),
                position: panel.scenePoint(local: SIMD3(localCenter.x, localCenter.y, faceOffset)),
                orientation: panel.orientation,
                material: rimMaterial,
                name: name
            )
        }
    }

    private func addPanelDetail(
        on surfaceID: LMCommanderStationGeometry.SurfaceID,
        center: SIMD2<Float>,
        size: SIMD2<Float>,
        depth: Float,
        material: SimpleMaterial,
        name: String
    ) {
        let surface = LMCommanderStationGeometry.surface(surfaceID)
        addBox(
            size: SIMD3(size.x, size.y, depth),
            position: surface.scenePoint(local: SIMD3(
                center.x,
                center.y,
                surface.sizeMeters.z / 2 + depth / 2 + 0.001
            )),
            orientation: surface.orientation,
            material: material,
            name: name
        )
    }

    private func installProceduralDatumNodes() {
        let eye = Entity()
        eye.name = LMCockpitAssetContract.Node.commanderEye.rawValue
        eye.position = landingPointDesignator.commanderEyeMeters
        proceduralCabin.addChild(eye)

        for (node, pane) in [
            (LMCockpitAssetContract.Node.commanderWindowInner, LMLPDPane.inner),
            (.commanderWindowOuter, .outer),
        ] {
            let datum = Entity()
            datum.name = node.rawValue
            datum.position = landingPointDesignator.panePlane(pane).referencePointMeters
            datum.orientation = landingPointDesignator.paneOrientation(pane)
            proceduralCabin.addChild(datum)
        }
    }

    private func buildLandingPointDesignator() {
        for pane in LMLPDPane.allCases {
            guard let mesh = try? makeLandingPointDesignatorMesh(pane: pane) else { continue }
            let color: UIColor = pane == .inner
                ? UIColor(red: 0.95, green: 0.26, blue: 0.55, alpha: 0.82)
                : UIColor(red: 0.34, green: 0.94, blue: 0.82, alpha: 0.72)
            let entity = ModelEntity(
                mesh: mesh,
                materials: [UnlitMaterial(color: color)]
            )
            entity.name = pane == .inner
                ? LMCockpitAssetContract.Node.landingPointDesignatorInner.rawValue
                : LMCockpitAssetContract.Node.landingPointDesignatorOuter.rawValue
            proceduralCabin.addChild(entity)
            addLandingPointDesignatorLabels(pane: pane, color: color)
        }
    }

    private func buildLandingPointCalledAngleMarker() {
        landingPointCalledAngleMarker.name = "Training LPD called-angle marker"
        landingPointCalledAngleMarker.model = ModelComponent(
            mesh: .generateSphere(radius: 0.007),
            materials: [UnlitMaterial(color: UIColor(
                red: 1,
                green: 0.78,
                blue: 0.12,
                alpha: 0.92
            ))]
        )
        landingPointCalledAngleMarker.isEnabled = false
        cabinFrame.addChild(landingPointCalledAngleMarker)
    }

    private func makeLandingPointDesignatorMesh(pane: LMLPDPane) throws -> MeshResource {
        var segments = [(SIMD3<Float>, SIMD3<Float>)]()
        segments.append((
            landingPointDesignator.point(elevationDegrees: 0, on: pane),
            landingPointDesignator.point(elevationDegrees: 60, on: pane)
        ))
        for elevation in LMLandingPointDesignator.elevationMarkDegrees {
            let endpoints = landingPointDesignator.elevationTickEndpoints(
                elevationDegrees: elevation,
                on: pane
            )
            segments.append((endpoints.start, endpoints.end))
        }
        for elevation in LMLandingPointDesignator.horizontalScaleElevations {
            segments.append((
                landingPointDesignator.point(
                    elevationDegrees: Double(elevation),
                    azimuthDegrees: -10,
                    on: pane
                ),
                landingPointDesignator.point(
                    elevationDegrees: Double(elevation),
                    azimuthDegrees: 10,
                    on: pane
                )
            ))
            for azimuth in LMLandingPointDesignator.azimuthMarkDegrees {
                let endpoints = landingPointDesignator.azimuthTickEndpoints(
                    azimuthDegrees: azimuth,
                    scaleElevationDegrees: elevation,
                    on: pane
                )
                segments.append((endpoints.start, endpoints.end))
            }
        }

        var positions = [SIMD3<Float>]()
        var indices = [UInt32]()
        let halfThickness: Float = 0.00085
        let paneNormal = landingPointDesignator.panePlane(pane).normalTowardEye
        for (start, end) in segments {
            let direction = simd_normalize(end - start)
            let perpendicular = simd_normalize(simd_cross(paneNormal, direction))
                * halfThickness
            let base = UInt32(positions.count)
            positions.append(contentsOf: [
                start - perpendicular,
                start + perpendicular,
                end - perpendicular,
                end + perpendicular,
            ])
            indices.append(contentsOf: [base, base + 2, base + 1, base + 1, base + 2, base + 3])
        }

        var descriptor = MeshDescriptor(name: "Apollo LM dual-pane LPD \(pane)")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    private func addLandingPointDesignatorLabels(pane: LMLPDPane, color: UIColor) {
        let basis = landingPointDesignator.paneBasis(pane)
        let orientation = landingPointDesignator.paneOrientation(pane)
        for elevation in stride(from: 0, through: 60, by: 10) {
            let mesh = MeshResource.generateText(
                "\(elevation)",
                extrusionDepth: 0.0002,
                font: .monospacedDigitSystemFont(ofSize: 0.023, weight: .medium),
                containerFrame: .zero,
                alignment: .left,
                lineBreakMode: .byClipping
            )
            let label = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
            label.name = "LPD \(pane) \(elevation) degree label"
            label.position = landingPointDesignator.point(
                elevationDegrees: Double(elevation),
                on: pane
            ) + basis.right * 0.036 - basis.up * 0.010 + basis.normal * 0.0005
            label.orientation = orientation
            proceduralCabin.addChild(label)
        }

        for elevation in LMLandingPointDesignator.horizontalScaleElevations {
            for azimuth in stride(from: -10, through: 10, by: 5) {
                let mesh = MeshResource.generateText(
                    "\(abs(azimuth))",
                    extrusionDepth: 0.0002,
                    font: .monospacedDigitSystemFont(ofSize: 0.018, weight: .medium),
                    containerFrame: .zero,
                    alignment: .center,
                    lineBreakMode: .byClipping
                )
                let label = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
                label.name = "LPD \(pane) E\(elevation) A\(azimuth) label"
                label.position = landingPointDesignator.point(
                    elevationDegrees: Double(elevation),
                    azimuthDegrees: Double(azimuth),
                    on: pane
                ) + basis.up * 0.020 + basis.normal * 0.0005
                label.orientation = orientation
                proceduralCabin.addChild(label)
            }
        }
    }

    private func buildForwardWindowFrames(material: SimpleMaterial) {
        let commanderCorners = landingPointDesignator.windowCorners(on: .inner)
        addWindowFrame(
            corners: commanderCorners,
            material: material,
            namePrefix: "Commander window"
        )
        addWindowFrame(
            corners: commanderCorners.map { SIMD3(-$0.x, $0.y, $0.z) },
            material: material,
            namePrefix: "LMP window"
        )
    }

    private func addWindowFrame(
        corners: [SIMD3<Float>],
        material: SimpleMaterial,
        namePrefix: String
    ) {
        precondition(corners.count == 3)
        for index in corners.indices {
            addBeam(
                from: corners[index],
                to: corners[(index + 1) % corners.count],
                thickness: 0.055,
                material: material,
                name: "\(namePrefix) rail \(index + 1)"
            )
        }
    }

    private func buildPhysicalDSKY() {
        let faceMaterial = SimpleMaterial(
            color: UIColor(red: 0.20, green: 0.205, blue: 0.18, alpha: 1),
            roughness: 0.66,
            isMetallic: true
        )
        let keyMaterial = SimpleMaterial(
            color: UIColor(red: 0.69, green: 0.70, blue: 0.64, alpha: 1),
            roughness: 0.50,
            isMetallic: false
        )
        let screwMaterial = SimpleMaterial(
            color: UIColor(red: 0.40, green: 0.42, blue: 0.39, alpha: 1),
            roughness: 0.34,
            isMetallic: true
        )
        let faceDepth: Float = 0.012
        let keyDepth: Float = 0.008

        dskyFaceRoot.position = LMCommanderStationGeometry.dskyMountPositionMeters
        dskyFaceRoot.orientation = LMCommanderStationGeometry.dskyMountOrientation

        let face = ModelEntity(
            mesh: .generateBox(size: SIMD3(
                LMDSKYGeometry.faceWidthMeters,
                LMDSKYGeometry.faceHeightMeters,
                faceDepth
            )),
            materials: [faceMaterial]
        )
        face.name = LMCockpitAssetContract.Node.dskyFace.rawValue
        dskyFaceRoot.addChild(face)

        let apertureBacking = ModelEntity(
            mesh: .generateBox(size: SIMD3(
                LMDSKYGeometry.innerFaceWidthMeters,
                LMDSKYGeometry.displayHeightInches * LMDSKYGeometry.metersPerInch,
                0.002
            )),
            materials: [SimpleMaterial(color: .black, roughness: 0.9, isMetallic: false)]
        )
        apertureBacking.name = "DSKY display aperture"
        apertureBacking.position = SIMD3(
            LMDSKYGeometry.displayCenterMeters.x,
            LMDSKYGeometry.displayCenterMeters.y,
            faceDepth / 2 + 0.001
        )
        dskyFaceRoot.addChild(apertureBacking)

        buildPhysicalDSKYReadout(faceDepth: faceDepth)

        dskyFaceRoot.addChild(dskyDisplayMount)

        for placement in LMDSKYGeometry.keyPlacements {
            let key = ModelEntity(
                mesh: .generateBox(size: SIMD3(
                    placement.sizeMeters.x,
                    placement.sizeMeters.y,
                    keyDepth
                )),
                materials: [keyMaterial]
            )
            key.name = LMDSKYGeometry.artistNodeName(for: placement.code)
            var position = LMDSKYGeometry.faceLocalPosition(for: placement)
            position.z = faceDepth / 2 + keyDepth / 2 + 0.001
            key.position = position
            key.components.set(InputTargetComponent())
            key.components.set(HoverEffectComponent())
            key.components.set(CollisionComponent(shapes: [
                .generateBox(size: SIMD3(
                    placement.sizeMeters.x + 0.006,
                    placement.sizeMeters.y + 0.006,
                    0.020
                )),
            ]))
            addDSKYKeyLabel(placement.code, to: key, size: placement.sizeMeters, depth: keyDepth)
            dskyFaceRoot.addChild(key)
            dskyKeyEntitiesByRawValue[placement.code.rawValue] = key
            dskyKeyRestPositions[placement.code.rawValue] = position
        }

        let screwInset: Float = 0.012
        for (index, point) in [
            SIMD2(-LMDSKYGeometry.faceWidthMeters / 2 + screwInset,
                  LMDSKYGeometry.faceHeightMeters / 2 - screwInset),
            SIMD2(LMDSKYGeometry.faceWidthMeters / 2 - screwInset,
                  LMDSKYGeometry.faceHeightMeters / 2 - screwInset),
            SIMD2(-LMDSKYGeometry.faceWidthMeters / 2 + screwInset,
                  -LMDSKYGeometry.faceHeightMeters / 2 + screwInset),
            SIMD2(LMDSKYGeometry.faceWidthMeters / 2 - screwInset,
                  -LMDSKYGeometry.faceHeightMeters / 2 + screwInset),
            SIMD2(-LMDSKYGeometry.faceWidthMeters / 2 + screwInset, 0),
            SIMD2(LMDSKYGeometry.faceWidthMeters / 2 - screwInset, 0),
        ].enumerated() {
            let screw = ModelEntity(
                mesh: .generateCylinder(height: 0.003, radius: 0.0036),
                materials: [screwMaterial]
            )
            screw.name = "DSKY face screw \(index + 1)"
            screw.position = SIMD3(point.x, point.y, faceDepth / 2 + 0.0015)
            screw.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
            dskyFaceRoot.addChild(screw)
        }

        cabinFrame.addChild(dskyFaceRoot)
    }

    private var physicalDSKYDisplaySize: SIMD2<Float> {
        SIMD2(
            LMDSKYGeometry.innerFaceWidthMeters - 0.010,
            LMDSKYGeometry.displayHeightInches * LMDSKYGeometry.metersPerInch - 0.010
        )
    }

    private var physicalDSKYAnnunciatorSize: SIMD2<Float> {
        SIMD2(physicalDSKYDisplaySize.x * 0.36, physicalDSKYDisplaySize.y)
    }

    private var physicalDSKYRegisterSize: SIMD2<Float> {
        SIMD2(physicalDSKYDisplaySize.x * 0.61, physicalDSKYDisplaySize.y)
    }

    private func buildPhysicalDSKYReadout(faceDepth: Float) {
        let annunciatorSize = physicalDSKYAnnunciatorSize
        let gap = physicalDSKYDisplaySize.x * 0.03
        let leftEdge = LMDSKYGeometry.displayCenterMeters.x
            - physicalDSKYDisplaySize.x / 2
        let bottomEdge = LMDSKYGeometry.displayCenterMeters.y
            - physicalDSKYDisplaySize.y / 2
        let textZ = faceDepth / 2 + 0.0031

        physicalDSKYAnnunciatorLegends.name = "DSKY annunciator legends"
        physicalDSKYAnnunciatorLegends.position = SIMD3(leftEdge, bottomEdge, textZ)
        updatePhysicalDSKYText(
            physicalDSKYAnnunciatorLegends,
            text: LMPhysicalDSKYPresentation.annunciatorLegendText,
            size: annunciatorSize,
            fontSize: 0.00355,
            color: UIColor(red: 0.19, green: 0.27, blue: 0.18, alpha: 1),
            weight: .regular,
            alignment: .left
        )
        dskyFaceRoot.addChild(physicalDSKYAnnunciatorLegends)

        physicalDSKYAnnunciatorLights.name = "DSKY illuminated annunciators"
        physicalDSKYAnnunciatorLights.position = SIMD3(leftEdge, bottomEdge, textZ + 0.0002)
        dskyFaceRoot.addChild(physicalDSKYAnnunciatorLights)

        physicalDSKYRegisters.name = "DSKY physical registers"
        physicalDSKYRegisters.position = SIMD3(
            leftEdge + annunciatorSize.x + gap,
            bottomEdge,
            textZ + 0.0001
        )
        dskyFaceRoot.addChild(physicalDSKYRegisters)
        applyDSKY(nil)
    }

    private func updatePhysicalDSKYText(
        _ entity: ModelEntity,
        text: String,
        size: SIMD2<Float>,
        fontSize: CGFloat,
        color: UIColor,
        weight: UIFont.Weight,
        alignment: CTTextAlignment
    ) {
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.00010,
            font: .monospacedSystemFont(ofSize: fontSize, weight: weight),
            containerFrame: CGRect(
                x: 0,
                y: 0,
                width: CGFloat(size.x),
                height: CGFloat(size.y)
            ),
            alignment: alignment,
            lineBreakMode: .byClipping
        )
        entity.model = ModelComponent(
            mesh: mesh,
            materials: [UnlitMaterial(color: color)]
        )
    }

    var physicalDSKYDisplayEntityNames: [String] {
        [
            physicalDSKYAnnunciatorLegends.name,
            physicalDSKYAnnunciatorLights.name,
            physicalDSKYRegisters.name,
        ]
    }

    var physicalDSKYDisplayedText: (registers: String, annunciators: String) {
        let parts = lastPhysicalDSKYSignature?.components(separatedBy: "\u{1F}") ?? []
        return (
            registers: parts.first ?? "",
            annunciators: parts.count > 1 ? parts[1] : ""
        )
    }

    private func buildPhysicalFDAI() {
        guard let instrument = try? Entity.load(
            named: "FDAI",
            in: realityKitContentBundle
        ) else {
            logger.error("Could not load the physical FDAI ball")
            return
        }
        instrument.name = "Physical FDAI ball"
        instrument.position = SIMD3(0, 0, -0.040)
        instrument.orientation = FDAIOrientation.ballOrientation(
            for: .identity
        )
        fdaiMount.addChild(instrument)
        fdaiBall = instrument

        let reticleMaterial = UnlitMaterial(color: .white)
        for (name, position, size) in [
            ("FDAI fixed left wing", SIMD3<Float>(-0.066, 0, 0.055), SIMD3<Float>(0.050, 0.003, 0.002)),
            ("FDAI fixed right wing", SIMD3<Float>(0.066, 0, 0.055), SIMD3<Float>(0.050, 0.003, 0.002)),
            ("FDAI fixed upper index", SIMD3<Float>(0, 0.077, 0.055), SIMD3<Float>(0.003, 0.026, 0.002)),
            ("FDAI fixed lower index", SIMD3<Float>(0, -0.077, 0.055), SIMD3<Float>(0.003, 0.026, 0.002)),
        ] {
            let marker = ModelEntity(
                mesh: .generateBox(size: size),
                materials: [reticleMaterial]
            )
            marker.name = name
            marker.position = position
            fdaiMount.addChild(marker)
        }
    }

    private func addDSKYKeyLabel(
        _ code: DSKYKeyCode,
        to key: ModelEntity,
        size: SIMD2<Float>,
        depth: Float
    ) {
        let text = switch code {
        case .keyRelease: "KEY\nREL"
        default: code.label
        }
        let fontSize: CGFloat = text.count <= 2 ? 0.0115 : 0.0053
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.00015,
            font: .systemFont(ofSize: fontSize, weight: .semibold),
            containerFrame: CGRect(
                x: 0,
                y: 0,
                width: CGFloat(size.x),
                height: CGFloat(size.y)
            ),
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        let label = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .black)])
        label.name = "\(code.label) legend"
        label.position = SIMD3(-size.x / 2, -size.y / 2, depth / 2 + 0.0003)
        key.addChild(label)
    }

    var dskyKeyEntities: [ModelEntity] {
        LMDSKYGeometry.keyPlacements.compactMap {
            dskyKeyEntitiesByRawValue[$0.code.rawValue]
        }
    }

    func dskyKeyCode(for entity: Entity) -> DSKYKeyCode? {
        var candidate: Entity? = entity
        while let current = candidate {
            if let rawValue = dskyKeyEntitiesByRawValue.first(where: { _, keyEntity in
                keyEntity === current
            })?.key {
                return DSKYKeyCode(rawValue: rawValue)
            }
            candidate = current.parent
        }
        return nil
    }

    func isMissionControlButton(_ entity: Entity) -> Bool {
        var candidate: Entity? = entity
        while let current = candidate {
            if current === missionControlButton { return true }
            candidate = current.parent
        }
        return false
    }

    func animateDSKYKeyPress(_ code: DSKYKeyCode) {
        let rawValue = code.rawValue
        guard let key = dskyKeyEntitiesByRawValue[rawValue],
              let restPosition = dskyKeyRestPositions[rawValue] else { return }

        dskyKeyResetTasks[rawValue]?.cancel()
        key.stopAllAnimations(recursive: false)
        var pressedPosition = restPosition
        pressedPosition.z -= 0.003
        key.move(
            to: Transform(translation: pressedPosition),
            relativeTo: dskyFaceRoot,
            duration: 0.035,
            timingFunction: .easeInOut
        )
        dskyKeyResetTasks[rawValue] = Task { @MainActor [weak self, weak key] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled, let self, let key else { return }
            key.move(
                to: Transform(translation: restPosition),
                relativeTo: self.dskyFaceRoot,
                duration: 0.065,
                timingFunction: .easeInOut
            )
        }
    }

    private func buildPhysicalControls() {
        let housing = SimpleMaterial(
            color: UIColor(red: 0.12, green: 0.13, blue: 0.115, alpha: 1),
            roughness: 0.72,
            isMetallic: false
        )
        let handleMaterial = SimpleMaterial(
            color: UIColor(red: 0.29, green: 0.27, blue: 0.20, alpha: 1),
            roughness: 0.58,
            isMetallic: false
        )
        let switchMaterial = SimpleMaterial(
            color: UIColor(red: 0.72, green: 0.69, blue: 0.54, alpha: 1),
            roughness: 0.45,
            isMetallic: true
        )

        addBox(
            size: SIMD3(0.18, 0.055, 0.20),
            position: acaNeutralPosition - SIMD3(0, 0.040, 0),
            material: housing,
            name: "ACA pedestal"
        )
        acaHandle.name = LMCockpitAssetContract.Node.acaPivot.rawValue
        acaHandle.position = acaNeutralPosition
        addACAHandleGeometry(to: acaHandle, material: handleMaterial, housing: housing)
        acaHandle.components.set(InputTargetComponent())
        acaHandle.components.set(HoverEffectComponent())
        acaHandle.components.set(CollisionComponent(shapes: [
            .generateBox(size: SIMD3(0.13, 0.29, 0.13))
        ]))
        cabinFrame.addChild(acaHandle)

        let panelFive = LMCommanderStationGeometry.surface(.panelFive)
        let rodBasePosition = panelFive.scenePoint(local: SIMD3(
            -0.095,
            0.060,
            panelFive.sizeMeters.z / 2 + 0.008
        ))
        addBox(
            size: SIMD3(0.074, 0.105, 0.016),
            position: rodBasePosition,
            orientation: panelFive.orientation,
            material: housing,
            name: "Panel 5 DES RATE switch plate"
        )
        rodSwitch.name = LMCockpitAssetContract.Node.rodPivot.rawValue
        rodSwitch.position = rodNeutralPosition
        addDescentRateSwitchGeometry(to: rodSwitch, material: switchMaterial)
        rodSwitch.components.set(InputTargetComponent())
        rodSwitch.components.set(HoverEffectComponent())
        rodSwitch.components.set(CollisionComponent(shapes: [
            .generateBox(size: SIMD3(0.075, 0.12, 0.10))
        ]))
        setRODVisual(.neutral)
        cabinFrame.addChild(rodSwitch)
        addDescentRateSwitchLegend(on: panelFive)

        attitudeModeSwitch.name = LMCockpitAssetContract.Node.attitudeHoldPivot.rawValue
        attitudeModeSwitch.model = ModelComponent(
            mesh: .generateBox(size: SIMD3(0.08, 0.13, 0.055)),
            materials: [switchMaterial]
        )
        attitudeModeSwitch.position = attitudeModeAutomaticPosition
        attitudeModeSwitch.orientation = LMCommanderStationGeometry.attitudeHoldOrientation
        attitudeModeSwitch.components.set(InputTargetComponent())
        attitudeModeSwitch.components.set(HoverEffectComponent())
        attitudeModeSwitch.components.set(CollisionComponent(shapes: [
            .generateBox(size: SIMD3(0.16, 0.20, 0.12))
        ]))
        setAttitudeHoldVisual(false)
        cabinFrame.addChild(attitudeModeSwitch)

        missionControlButton.name = "MISSION CONTROL"
        missionControlButton.model = ModelComponent(
            mesh: .generateBox(size: SIMD3(0.105, 0.052, 0.022), cornerRadius: 0.006),
            materials: [SimpleMaterial(
                color: UIColor(red: 0.58, green: 0.20, blue: 0.10, alpha: 1),
                roughness: 0.55,
                isMetallic: false
            )]
        )
        missionControlButton.position =
            LMCommanderStationGeometry.missionControlButtonPositionMeters
        missionControlButton.orientation =
            LMCommanderStationGeometry.missionControlButtonOrientation
        missionControlButton.components.set(InputTargetComponent())
        missionControlButton.components.set(HoverEffectComponent())
        missionControlButton.components.set(CollisionComponent(shapes: [
            .generateBox(size: SIMD3(0.13, 0.08, 0.06))
        ]))
        addMissionControlButtonLegend()
        cabinFrame.addChild(missionControlButton)
    }

    private func addMissionControlButtonLegend() {
        let mesh = MeshResource.generateText(
            "MISSION",
            extrusionDepth: 0.00015,
            font: .systemFont(ofSize: 0.010, weight: .bold),
            containerFrame: CGRect(x: 0, y: 0, width: 0.095, height: 0.025),
            alignment: .center,
            lineBreakMode: .byClipping
        )
        let legend = ModelEntity(
            mesh: mesh,
            materials: [UnlitMaterial(color: .white)]
        )
        legend.name = "MISSION button legend"
        legend.position = SIMD3(-0.0475, -0.0125, 0.0112)
        missionControlButton.addChild(legend)
    }

    private func addACAHandleGeometry(
        to pivot: Entity,
        material: SimpleMaterial,
        housing: SimpleMaterial
    ) {
        let boot = ModelEntity(
            mesh: .generateCylinder(height: 0.025, radius: 0.046),
            materials: [housing]
        )
        boot.name = "ACA flexible boot"
        boot.position = SIMD3(0, 0.0125, 0)
        pivot.addChild(boot)

        let shaft = ModelEntity(
            mesh: .generateCylinder(height: 0.125, radius: 0.016),
            materials: [material]
        )
        shaft.name = "ACA grip shaft"
        shaft.position = SIMD3(0, 0.082, 0)
        pivot.addChild(shaft)

        let grip = ModelEntity(
            mesh: .generateBox(size: SIMD3(0.057, 0.105, 0.052), cornerRadius: 0.014),
            materials: [material]
        )
        grip.name = "ACA pistol grip"
        grip.position = SIMD3(0, 0.175, -0.008)
        grip.orientation = simd_quatf(angle: -0.10, axis: SIMD3(1, 0, 0))
        pivot.addChild(grip)

        let pushToTalk = ModelEntity(
            mesh: .generateBox(size: SIMD3(0.024, 0.030, 0.010), cornerRadius: 0.004),
            materials: [housing]
        )
        pushToTalk.name = "ACA push-to-talk switch"
        pushToTalk.position = SIMD3(0, 0.185, -0.037)
        pivot.addChild(pushToTalk)
    }

    private func addDescentRateSwitchGeometry(
        to pivot: Entity,
        material: SimpleMaterial
    ) {
        let stem = ModelEntity(
            mesh: .generateCylinder(height: 0.050, radius: 0.0065),
            materials: [material]
        )
        stem.name = "DES RATE switch stem"
        stem.position = SIMD3(0, 0, 0.025)
        stem.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
        pivot.addChild(stem)

        let bat = ModelEntity(
            mesh: .generateCylinder(height: 0.029, radius: 0.012),
            materials: [material]
        )
        bat.name = "DES RATE switch bat"
        bat.position = SIMD3(0, 0, 0.062)
        bat.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
        pivot.addChild(bat)
    }

    private func addDescentRateSwitchLegend(
        on panel: LMCommanderStationGeometry.Surface
    ) {
        let mesh = MeshResource.generateText(
            "DES RATE\n+1 FPS\n−1 FPS",
            extrusionDepth: 0.0002,
            font: .systemFont(ofSize: 0.010, weight: .semibold),
            containerFrame: CGRect(x: 0, y: 0, width: 0.075, height: 0.075),
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        let legend = ModelEntity(
            mesh: mesh,
            materials: [UnlitMaterial(color: UIColor(white: 0.82, alpha: 1))]
        )
        legend.name = "Panel 5 DES RATE legend"
        legend.position = panel.scenePoint(local: SIMD3(
            -0.132,
            0.107,
            panel.sizeMeters.z / 2 + 0.017
        ))
        legend.orientation = panel.orientation
        cabinFrame.addChild(legend)
    }

    private func buildDustCloud() {
        let dustMaterial = SimpleMaterial(
            color: UIColor(red: 0.56, green: 0.53, blue: 0.46, alpha: 0.22),
            roughness: 1,
            isMetallic: false
        )
        for index in 0..<18 {
            let angle = Float(index) * 2 * .pi / 18
            let radius = Float(4 + (index % 5) * 3)
            let sheet = ModelEntity(
                mesh: .generateCylinder(height: 0.018, radius: 2.8 + Float(index % 4)),
                materials: [dustMaterial]
            )
            sheet.position = SIMD3(cos(angle) * radius, Float(index % 3) * 0.05, sin(angle) * radius)
            dustCloud.addChild(sheet)
        }
        dustCloud.isEnabled = false
        lunarWorld.addChild(dustCloud)
    }

    private func buildProvisionalSurface() {
        let surfaceMaterial = SimpleMaterial(
            color: UIColor(red: 0.37, green: 0.36, blue: 0.33, alpha: 1),
            roughness: 1,
            isMetallic: false
        )
        let surface = ModelEntity(
            mesh: .generatePlane(width: 1_200, depth: 1_200),
            materials: [surfaceMaterial]
        )
        surface.name = "Provisional lunar surface"
        provisionalTerrain.addChild(surface)

        let markerMaterial = SimpleMaterial(
            color: UIColor(red: 0.66, green: 0.64, blue: 0.57, alpha: 1),
            roughness: 1,
            isMetallic: false
        )
        for index in 0..<24 {
            let angle = Float(index) * 2 * .pi / 24
            let radius = Float(14 + (index % 6) * 13)
            let rock = ModelEntity(
                mesh: .generateBox(size: SIMD3(1.4 + Float(index % 4), 0.35, 0.9 + Float(index % 3))),
                materials: [markerMaterial]
            )
            rock.position = SIMD3(cos(angle) * radius, 0.17, sin(angle) * radius)
            rock.orientation = simd_quatf(angle: angle * 0.37, axis: SIMD3(0, 1, 0))
            provisionalTerrain.addChild(rock)
        }
        lunarWorld.addChild(provisionalTerrain)

        // Keep fallback lighting inside the fallback subtree. Loading the
        // source-backed terrain removes `provisionalTerrain`, which must also
        // remove this light before the mission-calibrated sun is installed.
        let sun = Entity()
        sun.name = "Provisional terrain sun"
        sun.components.set(DirectionalLightComponent(color: .white, intensity: 42_000))
        sun.orientation = simd_quatf(angle: -.pi / 3, axis: SIMD3(1, 0.25, 0))
        provisionalTerrain.addChild(sun)
    }

    private func addBox(
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        orientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
        material: SimpleMaterial,
        name: String
    ) {
        let entity = ModelEntity(mesh: .generateBox(size: size), materials: [material])
        entity.name = name
        entity.position = position
        entity.orientation = orientation
        proceduralCabin.addChild(entity)
    }

    private func addBeam(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        thickness: Float,
        material: SimpleMaterial,
        name: String
    ) {
        let delta = end - start
        let length = simd_length(delta)
        let entity = ModelEntity(
            mesh: .generateBox(size: SIMD3(thickness, thickness, length)),
            materials: [material]
        )
        entity.name = name
        entity.position = (start + end) / 2
        entity.orientation = simd_quatf(
            from: SIMD3<Float>(0, 0, 1),
            to: delta / length
        )
        proceduralCabin.addChild(entity)
    }
}
