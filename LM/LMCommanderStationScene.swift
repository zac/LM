import AGC
import LMCore
import OSLog
import RealityKit
import RealityKitContent
import LMKit
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
    enum LandingPointMarkingOwner { case appGenerated, importedWindows }
    private(set) var landingPointMarkingOwner: LandingPointMarkingOwner = .appGenerated
    private var landingPointMarkEntities: [(entity: ModelEntity, pane: LMLPDPane)] = []
    private var landingPointDiagnosticColors = false
    private(set) var planningLabelsVisible = ProcessInfo.processInfo.arguments.contains("--cockpit-planning-labels")

    func setPlanningLabelsVisible(_ visible: Bool) {
        planningLabelsVisible = visible
        commanderAssembly?.setPlanningLabelsVisible(visible)
    }
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
    private var globalCockpitTerrain: LMLunarCockpitTerrain?
    var globalTerrainReady: Bool { globalCockpitTerrain?.permitsPhysicsStep ?? true }
    var globalTerrainDescription: String {
        guard let terrain = globalCockpitTerrain else { return "Lunar terrain" }
        return String(format: "Measured floor: %.0f m · finer relief modeled", terrain.presentation.region.measuredFloorMeters)
    }

    /// Resolve global-site lighting before publishing the first RealityView frame.
    /// Apollo metadata is already configured by buildProvisionalSurface().
    func prepareProvisionalLighting(at coordinate: LMSelenographicCoordinate?, date: Date) {
        guard provisionalTerrain.parent != nil else { return }
        if let coordinate {
            let angles = LMLunarEphemeris.sunAngles(at: date, site: coordinate)
            let sun = LMTerrainWorld.makeMissionSun(orientation: LMFullDescentMapper.sunLightOrientation(from: angles),
                elevationDegrees: angles.elevationDegrees, altitudeMeters: 1_000)
            provisionalTerrain.findEntity(named: "MissionSun")?.removeFromParent()
            provisionalTerrain.addChild(sun)
            // Global terrain retains its existing fixed initial shadow range.
            terrainSun = nil
        }
        recordLighting(stage: "before-first-publication")
    }

    func recordLighting(stage: String) {
        guard ProcessInfo.processInfo.arguments.contains("--cockpit-startup-timing") else { return }
        let suns = LMCommanderStationAssembly.descendants(root).filter { $0.name == "MissionSun" }
        let summary = suns.map { node in
            let light = node.components[DirectionalLightComponent.self]
            return "lux=\(light?.intensity ?? 0) rotation=\(node.orientation(relativeTo: root).vector) shadow=\((node as? DirectionalLight)?.shadow != nil)"
        }.joined(separator: "; ")
        logger.notice("Cockpit lighting stage=\(stage, privacy: .public) uptime=\(ProcessInfo.processInfo.systemUptime, privacy: .public) imported=\(self.commanderAssembly != nil) suns=\(suns.count) \(summary, privacy: .public)")
    }

    func loadGlobalTerrain(at coordinate: LMSelenographicCoordinate, session: PoweredDescentSession, date: Date) async throws {
        try Task.checkCancellation()
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LunarElevation-v1", isDirectory: true)
        let store = try LMLunarElevationStore(directory: directory)
        let region = try await Task.detached(priority: .userInitiated) {
            try await LMLunarTerrainRegion.load(at: coordinate, store: store)
        }.value
        // A dismissed cockpit must not retarget a newer mission when its
        // detached source load eventually completes.
        try Task.checkCancellation()
        let terrain = try LMLunarCockpitTerrain(region: region, gate: session.terrainSimulationGate, date: date)
        session.selectLandingSite(terrain.site)
        let publishContact = session.contactPublisher()
        terrain.contactChanged = { [weak self] surface in
            self?.contactSurface = surface
            publishContact(surface)
        }
        installGlobalTerrain(terrain)
        session.terrainReady = { [weak self] in self?.globalTerrainReady ?? false }
        session.vehicleDidAdvance = { [weak self] state in self?.apply(state) }
        session.terrainCaptureMetrics = { [weak terrain] in terrain?.captureMetrics ?? [:] }
        try await terrain.prepare()
    }

    func installGlobalTerrain(_ terrain: LMLunarCockpitTerrain) {
        globalCockpitTerrain = terrain
        terrainSun = nil
        recordLighting(stage: "before-global-terrain-swap")
        provisionalTerrain.removeFromParent()
        // The global controller owns the inverse vehicle pose and floating
        // frame. Clear any Apollo pose applied while sources were loading.
        lunarWorld.transform = Transform()
        dustCloud.removeFromParent()
        terrain.root.addChild(dustCloud)
        lunarWorld.addChild(terrain.root)
        // Preserve an already-present vehicle view before the next publication.
        if let state = lastVehicleState { terrain.apply(state) }
        recordLighting(stage: "after-global-terrain-swap")
    }

    private var terrainHeightField: Apollo11TerrainHeightField?
    private var terrainFrameAlignment: LMTerrainFrameAlignment?
    private var terrainEnvironment: Entity?
    private var terrainRockField: Entity?
    private var terrainSun: DirectionalLight?
    /// CPU copy of the measured reflectance so each fine tile can bake its own
    /// slice instead of sharing the 2 km near-field atlas at 0.5 m per texel.
    private var terrainAlbedoField: LMMeasuredAlbedoField?
    /// Terrain elevation under Eagle. The lunar world is offset by this
    /// constant so the mesh sits at its true relief; it is no longer pinned to
    /// whatever happens to be under the vehicle.
    private var terrainDatumElevationMeters: Double = 0
    private var contactSurface: LMTerrainContactSurface?
    private var contactSurfaceTask: Task<Void, Never>?
    private var contactSurfacePlans: [LMTerrainTileID] = []
    /// Publishes the surface the landing gear touches. The view forwards it to
    /// the simulation so physics and rendering share one ground.
    var onContactSurfaceChange: ((LMTerrainContactSurface?) -> Void)?
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
    private(set) var commanderAssembly: LMCommanderStationAssembly?
    private var exteriorLunarModule: Entity?
    private var fdaiBall: Entity?
    private var importedFDAI: LMImportedFDAI?
    private(set) var importedPilotFDAI: LMImportedFDAI?
    private(set) var importedACA: LMImportedACA?
    private(set) var importedAltitudeRate: LMImportedAltitudeRate?
    private(set) var importedCrossPointer: LMImportedCrossPointer?
    private(set) var importedAttitudeMode: LMImportedDescentControl?
    private(set) var importedDescentRate: LMImportedDescentControl?
    private(set) var staticOverlays: [String: Entity] = [:]
    private var lastAttitudeHold = false
    private var lastRODPosition = PoweredDescentSession.RODSwitchPosition.neutral
    private var retiredCommanderEntryAnchors = [AnchorEntity]()
    private var lastVehicleState: LMVehicleStateSnapshot?
    private var dskyKeyEntitiesByRawValue = [Int: Entity]()
    private var importedDSKY: LMImportedDSKY?
    private var dskyKeyRestPositions = [Int: SIMD3<Float>]()
    private var dskyKeyResetTasks = [Int: Task<Void, Never>]()
    private var lastPhysicalDSKYSignature: String?
    private var lastPhysicalDSKYHeader: String?
    private let acaNeutralPosition = LMCommanderStationGeometry.acaPivotPositionMeters
    private let rodNeutralPosition = LMCommanderStationGeometry.rodPivotPositionMeters
    private let attitudeModeAutomaticPosition =
        LMCommanderStationGeometry.attitudeHoldPivotPositionMeters

    init(loadACA: Bool = true, lightingManifest: LMTerrainManifest? = try? LMTerrainManifest.load()) {
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
        installImportedDSKY()
        buildPhysicalControls()
        if loadACA { installImportedACA() }
        // RealityKit models cast dynamic-light shadows by default, even when
        // they have no DynamicLightShadowComponent. Explicitly opt every
        // layered cabin model out before restoring the pressure shell as the
        // ascent-stage silhouette; otherwise the close, overlapping panel
        // faces quantize into moving light/dark blocks on Vision Pro.
        setDynamicShadowCasting(false, in: proceduralCabin)
        if let shell = proceduralCabin.findEntity(
            named: LMCockpitAssetContract.Node.cabinShell.rawValue
        ) {
            setDynamicShadowCasting(true, in: shell)
        }
        buildProvisionalSurface(lightingManifest: lightingManifest)
        buildDustCloud()

        root.addChild(lunarWorld)
        cabinFrame.addChild(fdaiMount)
        buildPhysicalFDAI()
        installImportedFDAI()
        #if DEBUG
        LMInstrumentValidation.frameObserver(root)
        LMCommanderStationAssemblyObserver.frame(root)
        LMACAValidation.frame(root)
        #endif
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

    /// Both imported and fallback renderers consume the same AGC snapshot.
    func applyDSKY(_ snapshot: DSKYSnapshot?) {
        importedDSKY?.apply(snapshot)
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
        let scene = try Entity.load(contentsOf: LMKitAssets.legacySceneURL)
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
        setDynamicShadowCasting(true, in: lander)

        let registration = Entity()
        registration.name = "LM exterior asset registration"
        registration.scale = SIMD3(repeating: LMCommanderStationGeometry.exteriorModelScale)
        registration.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        registration.addChild(lander)
        root.addChild(registration)
        exteriorLunarModule = registration
    }

    private func setDynamicShadowCasting(_ castsShadow: Bool, in entity: Entity) {
        if entity.components[ModelComponent.self] != nil {
            entity.components.set(DynamicLightShadowComponent(castsShadow: castsShadow))
        }
        for child in entity.children {
            setDynamicShadowCasting(castsShadow, in: child)
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
        if let globalCockpitTerrain {
            globalCockpitTerrain.apply(state)
            applyFDAIAttitude(state.attitude)
            return
        }
        applyFDAIAttitude(state.attitude)
        updateMissionShadow(altitudeMeters: state.altitudeMeters)
        updateRockDetail(altitudeMeters: state.altitudeMeters)
        let terrainPosition = terrainPosition(for: state.positionMeters)
        let surfaceSample = progressiveSurfaceSample(
            at: terrainPosition,
            altitudeMeters: state.altitudeMeters
        )
        if let surfaceSample {
            logTerrainPresentationIfNeeded(
                surfaceSample,
                altitudeMeters: state.altitudeMeters
            )
        }
        // The world sits at its true relief around a fixed datum under Eagle.
        // Pinning it to the local surface used to slide the whole moon
        // vertically as the vehicle crossed relief, and made every touchdown
        // land on a flat plane no matter what was drawn underneath it.
        lunarWorld.transform = Transform(matrix: mapper.lunarWorldMatrix(
            position: terrainPosition,
            attitude: state.attitude,
            surfaceElevationMeters: terrainDatumElevationMeters
        ))
        requestProgressiveTerrain(
            around: terrainPosition,
            velocityNorthMetersPerSecond: state.velocityMetersPerSecond.x,
            velocityEastMetersPerSecond: state.velocityMetersPerSecond.y,
            altitudeMeters: state.altitudeMeters
        )
        refreshContactSurfaceIfNeeded(
            around: terrainPosition,
            altitudeMeters: state.altitudeMeters
        )
    }

    /// Keep a contact patch resident around the vehicle once the gear is within
    /// a few seconds of the ground. Generation runs off the main actor because
    /// it evaluates the same recursive clipmap surface a tile mesh does.
    private func refreshContactSurfaceIfNeeded(
        around terrainPosition: LMVector3D,
        altitudeMeters: Double
    ) {
        guard let heightField = terrainHeightField else { return }
        guard altitudeMeters <= LMTerrainContactSurfaceBuilder.buildAltitudeMeters else {
            return
        }
        let plans = Array(progressiveTerrainPlans.values)
        let planIDs = plans.map(\.id).sorted {
            ($0.level, $0.eastIndex, $0.northIndex)
                < ($1.level, $1.eastIndex, $1.northIndex)
        }
        if let contactSurface, planIDs == contactSurfacePlans {
            let drift = hypot(
                terrainPosition.y - contactSurface.centerEastMeters,
                terrainPosition.x - contactSurface.centerNorthMeters
            )
            guard drift > LMTerrainContactSurfaceBuilder.rebuildDriftMeters else {
                return
            }
        }
        guard contactSurfaceTask == nil else { return }

        contactSurfacePlans = planIDs
        let alignment = terrainFrameAlignment
        contactSurfaceTask = Task { @MainActor [weak self] in
            let generation = Task.detached(priority: .userInitiated) {
                try LMTerrainContactSurfaceBuilder.build(
                    heightField: heightField,
                    alignment: alignment,
                    activePlans: plans,
                    altitudeMeters: altitudeMeters,
                    centerTerrainEastMeters: terrainPosition.y,
                    centerTerrainNorthMeters: terrainPosition.x
                )
            }
            defer { self?.contactSurfaceTask = nil }
            guard let surface = try? await generation.value, let self else { return }
            self.contactSurface = surface
            self.onContactSurfaceChange?(surface)
            self.logger.info(
                "Contact surface ready spacing=\(surface.spacingMeters, privacy: .public)m posts=\(surface.columns * surface.rows, privacy: .public) datum=\(self.terrainDatumElevationMeters, privacy: .public)m"
            )
        }
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
        terrainAlbedoField = try? LMMeasuredAlbedoField.load(tile: heightField.tile)
        if terrainAlbedoField == nil {
            logger.error("Measured albedo unavailable; tiles bake procedural contrast only")
        }
        let eagle = terrainFrameAlignment?.terrainReferenceTouchdown ?? .zero
        terrainDatumElevationMeters = Double(
            heightField.relativeElevation(eastMeters: eagle.y, northMeters: eagle.x) ?? 0
        )
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
        recordLighting(stage: "before-apollo-terrain-swap")
        // Keep adaptive fallback ownership until all throwing preparation succeeds.
        terrainSun = assembly.sun
        lastMissionShadowDistanceMeters = nil
        provisionalTerrain.removeFromParent()
        lunarWorld.addChild(terrain)
        apply(lastVehicleState)
        recordLighting(stage: "after-apollo-terrain-swap")
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
              let terrainEnvironment else { return }
        let albedoField = terrainAlbedoField
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
        let nextRequestedPlans = Dictionary(
            uniqueKeysWithValues: plans.map { ($0.id, $0) }
        )
        let requestedIDs = Set(nextRequestedPlans.keys)
        let requiredIDs = Set(requiredPlans.map(\.id))
        guard nextRequestedPlans != requestedTerrainPlans
                || requiredIDs != requiredTerrainTileIDs else { return }
        logger.info(
            "Terrain LOD request count=\(plans.count, privacy: .public) required=\(requiredPlans.count, privacy: .public) altitude=\(altitudeMeters, privacy: .public)m model=\(LMLunarGeologyModel.modelID, privacy: .public)"
        )
        let previousRequestedPlans = requestedTerrainPlans
        requestedTerrainTileIDs = requestedIDs
        requestedTerrainPlans = nextRequestedPlans
        requiredTerrainTileIDs = requiredIDs

        let cancelledIDs = Array(terrainGenerationTasks.keys).filter {
            requestedTerrainPlans[$0] != previousRequestedPlans[$0]
        }
        for id in cancelledIDs {
            terrainGenerationTasks[id]?.cancel()
            terrainGenerationTasks.removeValue(forKey: id)
            terrainGenerationTokens.removeValue(forKey: id)
        }
        retireUndesiredTerrainEntities()

        for plan in plans where progressiveTerrainPlans[plan.id] != plan
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
                        activePlans: plans,
                        albedoField: albedoField
                    )
                    guard self.finishTerrainGeneration(plan.id, token: token),
                          !Task.isCancelled,
                          self.requestedTerrainPlans[plan.id] == plan,
                          let entity else { return }
                    terrainEnvironment.addChild(entity)
                    self.progressiveTerrainEntities[plan.id]?.removeFromParent()
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
        guard requiredTerrainTileIDs.isSubset(of: activeIDs),
              requestedTerrainPlans.allSatisfy({
                  progressiveTerrainPlans[$0.key] == $0.value
              }) else { return 0 }
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
    func loadArtistCabinIfAvailable(arguments: [String] = ProcessInfo.processInfo.arguments) async throws -> Bool {
        guard !arguments.contains("--procedural-cockpit") else { return false }
        let installed = installCommanderAssembly()
        if installed {
            _ = installPilotFDAI()
            _ = installAltitudeRate()
            _ = installCrossPointer()
            _ = installDescentControl(.attitudeMode)
            _ = installDescentControl(.descentRate)
            if !arguments.contains("--no-interior-details") {
                _ = installStaticOverlay("InteriorDetails", assetURL: LMKitAssets.interiorDetailsURL,
                    interfaceURL: LMKitAssets.interiorDetailsInterfaceURL, schema: "lmkit.interior-details.v1")
                _ = installStaticOverlay("BreakerBanks", assetURL: LMKitAssets.breakerBanksURL,
                    interfaceURL: LMKitAssets.breakerBanksInterfaceURL, schema: "lmkit.breaker-banks.interface.v1")
            }
        }
        return installed
    }

    /// The pilot uses the same supported attitude source as the commander.
    /// Source selection, rate/error needles and mechanical seating remain unqualified.
    @discardableResult
    func installPilotFDAI(loader: @MainActor () throws -> LMImportedFDAI = {
        try LMImportedFDAI(asset: Entity.load(contentsOf: LMKitAssets.fdaiURL))
    }) -> Bool {
        guard importedPilotFDAI == nil else { return true }
        guard let assembly = commanderAssembly else { return false }
        do {
            let instrument = try loader()
            // Scope semantic lookup to this newly loaded instance. Duplicate FDAI
            // names in the commander subtree are intentional and never searched here.
            let root = try LMCockpitComponentSupport.neutralRoot("FDAI_Mount", asset: instrument.root)
            let bounds = root.visualBounds(relativeTo: root)
            // The accepted Panel 2 reservation is 150 mm square. This checks the
            // visual face envelope only; the rear housing is not a qualified cutout.
            guard !bounds.isEmpty, bounds.min.x >= -0.075, bounds.max.x <= 0.075,
                  bounds.min.y >= -0.075, bounds.max.y <= 0.075 else {
                throw LMCommanderStationAssembly.AssemblyError.invalidContract("Pilot FDAI face exceeds its reservation")
            }
            LMCockpitComponentSupport.removeInput(root)
            if let state = lastVehicleState { instrument.apply(state.attitude) }
            try assembly.installOccupant(slotID: "Panel2__FDAI", componentID: "Pilot FDAI") { root }
            importedPilotFDAI = instrument
            return true
        } catch {
            logger.error("Pilot FDAI unavailable; panel blank retained: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    @discardableResult
    func installAltitudeRate(loader: @MainActor () throws -> LMImportedAltitudeRate = { try LMImportedAltitudeRate.load() }) -> Bool {
        guard importedAltitudeRate == nil else { return true }
        guard let assembly = commanderAssembly else { return false }
        do {
            let instrument = try loader()
            try assembly.installPartialOccupant(slotID: instrument.contract.slot, componentID: "AltitudeRate", pose: instrument.slotPose) { instrument.root }
            importedAltitudeRate = instrument
            return true
        } catch {
            logger.error("Altitude/rate unavailable; blank retained: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    @discardableResult
    func installCrossPointer(loader: @MainActor () throws -> LMImportedCrossPointer = { try LMImportedCrossPointer.load() }) -> Bool {
        guard importedCrossPointer == nil else { return true }
        guard let assembly = commanderAssembly else { return false }
        do {
            let instrument = try loader()
            try assembly.installPartialOccupant(slotID: instrument.contract.mounting.slot_id, componentID: "CrossPointer") { instrument.root }
            importedCrossPointer = instrument
            return true
        } catch {
            logger.error("Cross-pointer unavailable; blank retained: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    @discardableResult
    func installDescentControl(_ kind: LMImportedDescentControl.Kind,
        loader: (@MainActor () throws -> LMImportedDescentControl)? = nil) -> Bool {
        if kind == .attitudeMode ? importedAttitudeMode != nil : importedDescentRate != nil { return true }
        guard let assembly = commanderAssembly else { return false }
        do {
            let control = try loader?() ?? LMImportedDescentControl.load(kind)
            guard control.kind == kind else { throw LMCommanderStationAssembly.AssemblyError.invalidContract("Control kind") }
            try assembly.installPartialOccupant(slotID: control.definition.slot, componentID: kind.rawValue,
                backingMaterial: kind == .attitudeMode ? control.backingMaterials.first : nil) { control.root }
            if kind == .attitudeMode {
                importedAttitudeMode = control
                attitudeModeSwitch.isEnabled = false
                setAttitudeHoldVisual(lastAttitudeHold)
            } else {
                importedDescentRate = control
                rodSwitch.isEnabled = false
                for node in LMCommanderStationAssembly.descendants(cabinFrame)
                    where node.name == "Panel 5 DES RATE legend" || node.name == "Panel 5 DES RATE switch plate" { node.isEnabled = false }
                setRODVisual(lastRODPosition)
            }
            return true
        } catch {
            logger.error("Descent control unavailable; functional fallback retained: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    @discardableResult
    func installStaticOverlay(_ name: String, assetURL: URL, interfaceURL: URL, schema: String,
        loader: (@MainActor () throws -> LMCockpitStaticOverlay)? = nil) -> Bool {
        guard staticOverlays[name] == nil else { return true }
        guard let assembly = commanderAssembly else { return false }
        do {
            let overlay = try loader?() ?? LMCockpitStaticOverlay(asset: Entity.load(contentsOf: assetURL),
                interfaceData: Data(contentsOf: interfaceURL), name: name, schema: schema)
            try assembly.installStaticOverlay(overlay)
            staticOverlays[name] = overlay.root
            return true
        } catch {
            logger.error("Optional detail unavailable: \(name, privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func applyLandingReadouts(_ state: LMVehicleStateSnapshot?, program: Int?) {
        importedAltitudeRate?.apply(LMAltitudeRateReading(state: state))
        importedCrossPointer?.apply(LMCrossPointerReading(state: state, program: program))
    }

    var rodGestureCoordinateSpace: Entity { importedDescentRate?.root ?? cabinFrame }
    var rodGestureActuationAxis: SIMD3<Float> { importedDescentRate == nil ? LMCommanderStationGeometry.rodActuationAxis : [0, 1, 0] }

    func isRODEntity(_ entity: Entity) -> Bool { isDescendant(entity, of: importedDescentRate?.target ?? rodSwitch) }
    func isAttitudeModeEntity(_ entity: Entity) -> Bool { isDescendant(entity, of: importedAttitudeMode?.target ?? attitudeModeSwitch) }
    private func isDescendant(_ entity: Entity, of root: Entity) -> Bool {
        var node: Entity? = entity
        while let current = node { if current === root { return true }; node = current.parent }
        return false
    }

    @discardableResult
    func installCommanderAssembly(
        load: @MainActor () throws -> LMCommanderStationAssembly = { try LMCommanderStationAssembly.load() }
    ) -> Bool {
        guard commanderAssembly == nil else { return true }
        do {
            // All IO and validation precede any mutation of the active scene.
            let assembly = try load()
            guard importedDSKY != nil, importedFDAI != nil else {
                logger.error("Cabin assembly requires both live imported instruments; fallback retained")
                return false
            }
            let dskyReservation = try LMCommanderStationAssembly.unique("Mount_DSKY", in: assembly.cabin)
            let fdaiReservation = try LMCommanderStationAssembly.unique("Mount_FDAI", in: assembly.cabin)
            // Resolve external reservations before committing any active scene changes.
            try assembly.confirmExternalOccupant(slotID: "Panel4__DSKY", occupantName: "DSKY")
            try assembly.confirmExternalOccupant(slotID: "Panel1__FDAI", occupantName: "FDAI_CDR")
            assembly.setPlanningLabelsVisible(planningLabelsVisible)
            // Move existing mounts, preserving instruments and their live key dictionaries.
            dskyFaceRoot.position = dskyReservation.position(relativeTo: assembly.cabin)
            dskyFaceRoot.orientation = dskyReservation.orientation(relativeTo: assembly.cabin)
            fdaiMount.position = fdaiReservation.position(relativeTo: assembly.cabin)
            fdaiMount.orientation = fdaiReservation.orientation(relativeTo: assembly.cabin)
            let retained = Entity()
            retained.name = "App functional control supports"
            // Retain live control backing only. WindowsLPD owns all optical geometry.
            var retainedNames: Set<String> = ["Panel 5 DES RATE switch plate"]
            if importedACA == nil { retainedNames.insert("ACA pedestal") }
            for entity in Array(proceduralCabin.children)
                where retainedNames.contains(entity.name) {
                retained.addChild(entity)
            }
            assembly.root.addChild(retained)
            cabinFrame.addChild(assembly.root)
            proceduralCabin.isEnabled = false
            artistCabin?.removeFromParent()
            artistCabin = assembly.root
            commanderAssembly = assembly
            setLandingPointMarkingOwner(.importedWindows)
            logger.notice("Enclosed commander foundation installed atomically; live instrument identities retained")
            return true
        } catch {
            logger.error("Enclosed commander foundation unavailable; procedural fallback retained: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    @discardableResult
    func installImportedACA(loader: @MainActor () throws -> LMImportedACA = { try LMImportedACA.load() }) -> Bool {
        guard importedACA == nil else { return true }
        do {
            let imported = try loader()
            for child in Array(acaHandle.children) { child.removeFromParent() }
            acaHandle.components.remove(CollisionComponent.self)
            acaHandle.components.remove(InputTargetComponent.self)
            acaHandle.components.remove(HoverEffectComponent.self)
            acaHandle.components.remove(LMACAInteractionTarget.self)
            acaHandle.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            imported.root.position = LMImportedACA.registration
            acaHandle.addChild(imported.root)
            importedACA = imported
            return true
        } catch {
            logger.error("Articulated ACA unavailable; functional fallback retained: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func isACAEntity(_ entity: Entity) -> Bool {
        var node: Entity? = entity
        while let current = node {
            if current === acaHandle { return true }
            node = current.parent
        }
        return false
    }

    func setACAVisual(_ input: LMACANormalizedInput) {
        let input = input.clamped
        if let importedACA { importedACA.apply(input); return }
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
        lastRODPosition = position
        if let importedDescentRate {
            let value: String = switch position { case .descendPlus: "descendPlus"; case .neutral: "center"; case .descendMinus: "descendMinus" }
            importedDescentRate.apply(runtimeValue: value)
            return
        }
        rodSwitch.position = rodNeutralPosition
        rodSwitch.orientation = LMCommanderStationGeometry.rodNeutralOrientation * simd_quatf(
            angle: controlMapper.visualRODDeflectionRadians(for: position),
            axis: SIMD3(1, 0, 0)
        )
    }

    func setAttitudeHoldVisual(_ isAttitudeHold: Bool) {
        lastAttitudeHold = isAttitudeHold
        if let importedAttitudeMode {
            importedAttitudeMode.apply(runtimeValue: isAttitudeHold ? "attitudeHold" : "automatic")
            return
        }
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
        guard landingPointMarkingOwner == .appGenerated, trainingOverlayVisible, let angleDegrees else {
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
              state.surfaceContact == nil,
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
        let surfaceElevation = contactSurface.map {
            Float($0.referenceElevationMeters) + Float($0.surfaceHeightMeters(
                northMeters: state.positionMeters.x,
                eastMeters: state.positionMeters.y
            ))
        }
            ?? progressiveSurfaceSample(
                at: terrainPosition,
                altitudeMeters: state.altitudeMeters
            )?.renderedElevationMeters
            ?? terrainHeightField?.relativeElevation(
                eastMeters: terrainPosition.y,
                northMeters: terrainPosition.x
            )
            ?? 0
        let dustPosition = LMVector3D(x: terrainPosition.x, y: terrainPosition.y,
                                      z: Double(surfaceElevation) + 0.18)
        dustCloud.position = globalCockpitTerrain?.anchorPosition(dustPosition)
            ?? mapper.realityPosition(from: dustPosition)
        let spread = 0.8 + intensity * 2.6
        dustCloud.scale = SIMD3(spread, 0.25 + intensity * 0.45, spread)
        dustCloud.components.set(OpacityComponent(opacity: 0.08 + intensity * 0.34))
    }

    private func buildCabin() {
        let dark = UnlitMaterial(
            color: UIColor(red: 0.105, green: 0.115, blue: 0.105, alpha: 1)
        )
        let pressureShell = UnlitMaterial(
            color: UIColor(red: 0.105, green: 0.115, blue: 0.105, alpha: 1)
        )
        let panel = UnlitMaterial(
            color: UIColor(red: 0.19, green: 0.205, blue: 0.18, alpha: 1)
        )
        let aluminum = UnlitMaterial(
            color: UIColor(red: 0.49, green: 0.50, blue: 0.46, alpha: 1)
        )

        // This procedural blockout has no separate lightmapped interior mesh.
        // Keep its broad crew-visible finishes stable instead of letting the
        // low lunar sun project a moving terrain-scale shadow map across faces
        // only millimeters apart. A production cabin can replace these with
        // baked/PBR interior materials and a separate exterior shadow mesh.
        buildCabinShell(material: pressureShell)
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

    private func buildCabinShell(material: UnlitMaterial) {
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

    private func buildForwardFaceStructure(material: any RealityKit.Material) {
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

    private func buildDeckDetails(material: any RealityKit.Material) {
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
        panelMaterial: any RealityKit.Material,
        switchMaterial: any RealityKit.Material
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
        panelMaterial: any RealityKit.Material,
        rimMaterial: any RealityKit.Material
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
        material: any RealityKit.Material,
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
            let entity = ModelEntity(
                mesh: mesh,
                materials: [landingPointMarkMaterial(pane: pane)]
            )
            landingPointMarkEntities.append((entity, pane))
            entity.name = pane == .inner
                ? LMCockpitAssetContract.Node.landingPointDesignatorInner.rawValue
                : LMCockpitAssetContract.Node.landingPointDesignatorOuter.rawValue
            proceduralCabin.addChild(entity)
            addLandingPointDesignatorLabels(pane: pane)
        }
    }

    /// Call only after imported window assets have successfully installed their marks.
    /// Retains app entities for fallback while preventing double grids and labels.
    func setLandingPointMarkingOwner(_ owner: LandingPointMarkingOwner) {
        landingPointMarkingOwner = owner
        if owner == .importedWindows { landingPointCalledAngleMarker.isEnabled = false }
        for mark in landingPointMarkEntities {
            mark.entity.isEnabled = owner == .appGenerated
        }
    }

    func setLandingPointDiagnosticColors(_ enabled: Bool) {
        guard landingPointDiagnosticColors != enabled else { return }
        landingPointDiagnosticColors = enabled
        for mark in landingPointMarkEntities {
            mark.entity.model?.materials = [landingPointMarkMaterial(pane: mark.pane)]
        }
    }

    private func landingPointMarkMaterial(pane: LMLPDPane) -> any RealityKit.Material {
        if landingPointDiagnosticColors {
            // Deliberately synthetic pane distinction; never historical ink colors.
            let tint = pane == .inner
                ? UIColor(red: 0.95, green: 0.26, blue: 0.55, alpha: 0.82)
                : UIColor(red: 0.34, green: 0.94, blue: 0.82, alpha: 0.72)
            return UnlitMaterial(color: tint)
        }
        // Approximate warm scribed appearance: NASA Eppler landing report, slide 38.
        // RGB is an artistic choice, not a measured pigment. Geometry remains provisional.
        return SimpleMaterial(
            color: UIColor(red: 0.72, green: 0.65, blue: 0.43, alpha: 1),
            roughness: 1, isMetallic: false
        )
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

    private func addLandingPointDesignatorLabels(pane: LMLPDPane) {
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
            let label = ModelEntity(mesh: mesh, materials: [landingPointMarkMaterial(pane: pane)])
            landingPointMarkEntities.append((label, pane))
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
                let label = ModelEntity(mesh: mesh, materials: [landingPointMarkMaterial(pane: pane)])
                landingPointMarkEntities.append((label, pane))
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

    private func buildForwardWindowFrames(material: any RealityKit.Material) {
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
        material: any RealityKit.Material,
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

    private func installImportedDSKY() {
        do {
            let asset = try Entity.load(contentsOf: LMKitAssets.dskyURL)
            let binding = try LMImportedDSKY(asset: asset)
            // Commit replacement only after the complete contract validates.
            for child in Array(dskyFaceRoot.children) { child.removeFromParent() }
            dskyFaceRoot.addChild(binding.root)
            dskyKeyEntitiesByRawValue = binding.keys
            dskyKeyRestPositions = binding.keys.mapValues(\.position)
            importedDSKY = binding
            binding.apply(nil)
        } catch {
            logger.error("Imported DSKY unavailable; procedural fallback retained: \(String(describing: error), privacy: .public)")
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

    private func installImportedFDAI() {
        do {
            let binding = try LMImportedFDAI(asset: Entity.load(contentsOf: LMKitAssets.fdaiURL))
            for child in Array(fdaiMount.children) { child.removeFromParent() }
            fdaiMount.addChild(binding.root)
            importedFDAI = binding
            fdaiBall = nil
            binding.apply(lastVehicleState?.attitude ?? .identity)
        } catch {
            logger.error("Imported FDAI unavailable; legacy fallback retained: \(String(describing: error), privacy: .public)")
        }
    }

    private func applyFDAIAttitude(_ attitude: LMQuaternion) {
        if let importedFDAI { importedFDAI.apply(attitude) }
        else { fdaiBall?.orientation = FDAIOrientation.ballOrientation(for: attitude) }
        importedPilotFDAI?.apply(attitude)
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

    var dskyKeyEntities: [Entity] {
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
            relativeTo: key.parent,
            duration: 0.035,
            timingFunction: .easeInOut
        )
        dskyKeyResetTasks[rawValue] = Task { @MainActor [weak self, weak key] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled, self != nil, let key else { return }
            key.move(
                to: Transform(translation: restPosition),
                relativeTo: key.parent,
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
        acaHandle.components.set(LMACAInteractionTarget())
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
        rodSwitch.components.set(LMDescentRateInteractionTarget())
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
        attitudeModeSwitch.components.set(LMAttitudeModeInteractionTarget())
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

    private func buildProvisionalSurface(lightingManifest: LMTerrainManifest?) {
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
        let sun: DirectionalLight
        if let manifest = lightingManifest {
            sun = LMTerrainWorld.makeMissionSun(orientation: LMFullDescentMapper.sunLightOrientation(from: manifest),
                elevationDegrees: manifest.sun.elevationDegrees)
        } else {
            logger.error("Mission light metadata unavailable; retaining a shadowed reference-exposure fallback")
            sun = LMTerrainWorld.makeMissionSun(orientation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
                elevationDegrees: LMTerrainWorld.referenceSunElevationDegrees)
        }
        provisionalTerrain.addChild(sun)
        terrainSun = sun
    }

    private func addBox(
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        orientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
        material: any RealityKit.Material,
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
        material: any RealityKit.Material,
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
