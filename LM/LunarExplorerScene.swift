import LMCore
import OSLog
import RealityKit
import UIKit
import simd

/// Terrain-only RealityKit scene used to inspect the same assets, materials,
/// geology, rocks, lighting, and progressive tiles as terminal descent.
@MainActor
final class LunarExplorerScene {
    let root = Entity()
    let interactionSurface = Entity()

    private let presentationRoot = Entity()
    private let terrainAnchorRoot = Entity()
    private var sourceFrame: LMSelenographicLocalFrame?
    private var elevationPreviewDescription: String?
    private var globalTerrain: LMLunarTerrainPresentation?
    private var floatingOrigin: LMLunarFloatingOrigin?
    private var reanchorProbePending = false
    private var globalReanchorProbeStarted = false
    private let globePresentationRoot = Entity()
    private let selectionMarker = Entity()
    private let markerBillboard = Entity()
    private var globePlacementRoot: AnchorEntity?
    private var appliedPlacementRevision = -1
    private var appliedInteractionRadius: Float?
    private var placePins = [String: ModelEntity]()
    private var appliedMarkerScale: Float?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.positron.LM",
        category: "LunarExplorer"
    )
    private var terrainEnvironment: Entity?
    private var measuredNearFieldEntity: ModelEntity?
    private var measuredNearFieldGrid: LMTerrainMeshBuilder.VertexData?
    private var measuredNearFieldMask = Set<LMTerrainTileID>()
    private var ownershipPreparation: Task<Void, Never>?
    private var ownershipPreparationToken: UUID?
    private var ownershipPreparationIDs: Set<LMTerrainTileID>?
    private var preparedOwnershipMesh: MeshResource?
    private var globeEntity: ModelEntity?
    private var appliedGlobeLinearRadianceMultiplier: Double?
    private var globeTerminator: LMLunarGlobeResource.TerminatorResource?
    private var globeTerminatorDate: Date?
    private var terrainSun: DirectionalLight?
    private var terrainEarthshine: DirectionalLight?
    private var activeGrade: LMTerrainPresentationGrade?
    private var terrainRockField: Entity?
    private var heightField: Apollo11TerrainHeightField?
    private var albedoField: LMMeasuredAlbedoField?
    private var eagleTerrainPosition = LMVector3D.zero
    private var terrainDatumElevationMeters = 0.0
    /// The site the ephemeris evaluates mission lighting for.
    private var siteCoordinate: LMSelenographicCoordinate?
    private var progressiveEntities = [LMTerrainTileID: ModelEntity]()
    private var progressivePlans = [LMTerrainTileID: LMTerrainTilePlan]()
    private var progressiveOwnership = [LMTerrainTileID: Set<LMTerrainTileID>]()
    private var pendingProgressiveEntities = [LMTerrainTileID: ModelEntity]()
    private var pendingProgressivePlans = [LMTerrainTileID: LMTerrainTilePlan]()
    private var pendingOwnership = [LMTerrainTileID: Set<LMTerrainTileID>]()
    private var requestedPlans = [LMTerrainTileID: LMTerrainTilePlan]()
    private var requestedOwnership = [LMTerrainTileID: Set<LMTerrainTileID>]()
    private var generationTasks = [LMTerrainTileID: Task<Void, Never>]()
    private var generationTokens = [LMTerrainTileID: UUID]()
    private var detailPipelines = [
        LMTerrainDetailMode: LMTerrainDetailPipeline
    ]()
    private var activeDetailMode: LMTerrainDetailMode?
    private weak var session: LunarExplorerSession?
    private var appliedLandingRequest = 0
    private var landingTask: Task<Void, Never>?
    private var landingEntity: Entity?
    private var landingPose: (position: LMVector3D, attitude: LMQuaternion, frame: LMSelenographicLocalFrame)?
    private var appliedNavigationRevision = 0
    private var globeFrontCoordinate: LMSelenographicCoordinate?
    private var isLoaded = false
    private var loadTask: Task<Void, Never>?

    init() {
        root.name = "Lunar Explorer"
        presentationRoot.name = "Lunar Explorer presentation"
        root.addChild(presentationRoot)
        terrainAnchorRoot.name = "Floating lunar ENU"
        presentationRoot.addChild(terrainAnchorRoot)
        globePresentationRoot.name = "Lunar Explorer globe presentation"
        root.addChild(globePresentationRoot)
        selectionMarker.name = "Selected lunar place"
        selectionMarker.position = SIMD3(0, 0, Float(LunarExplorerSession.lunarGlobeRadiusMeters) * 1.006)
        selectionMarker.isEnabled = false
        globePresentationRoot.addChild(selectionMarker)
        markerBillboard.name = "Lunar place label"
        markerBillboard.components.set(BillboardComponent())
        markerBillboard.isEnabled = false
        root.addChild(markerBillboard)

        interactionSurface.name = "Lunar Explorer interaction surface"
        interactionSurface.position = SIMD3(0, 0, -1.15)
        interactionSurface.components.set(InputTargetComponent())
        interactionSurface.components.set(HoverEffectComponent())
        interactionSurface.components.set(CollisionComponent(shapes: [
            .generateBox(size: SIMD3(3.8, 2.6, 0.02)),
        ]))
        root.addChild(interactionSurface)
    }

    func installPlaceMarker(_ marker: Entity, scale: Float) {
        // Attachment layout only changes with its identity or text scale;
        // avoid measuring and rewriting it on every observed scene update.
        guard marker.parent !== markerBillboard || appliedMarkerScale != scale else { return }
        appliedMarkerScale = scale
        // Derive the foot from the rendered attachment bounds. A fixed 1 mm/pt
        // conversion is incorrect for this RealityView and shifts the marker.
        let bounds = marker.visualBounds(relativeTo: marker)
        marker.position = SIMD3(
            -bounds.min.x - bounds.extents.x * (24.0 / 260.0),
            -bounds.max.y + bounds.extents.y * (76.0 / 80.0), 0)
        guard marker.parent !== markerBillboard else { return }
        markerBillboard.addChild(marker)
        if ProcessInfo.processInfo.arguments.contains("--lunar-explorer-profile") {
            let bounds = marker.visualBounds(relativeTo: marker)
            logger.info("Moon label bounds min=\(String(describing: bounds.min), privacy: .public) max=\(String(describing: bounds.max), privacy: .public)")
        }
    }

    func place(for entity: Entity, session: LunarExplorerSession) -> LMLunarPOICatalog.Place? {
        guard entity.name.hasPrefix("moon-place:") else { return nil }
        return session.catalogPlaces.first { "moon-place:" + $0.id == entity.name }
    }

    private func updatePlacePins(_ session: LunarExplorerSession) {
        guard session.isExplorerExperience, session.isBrowsingGlobe, let anchor = globePlacementRoot else {
            for pin in placePins.values { pin.isEnabled = false }
            return
        }
        let radius = Float(LunarExplorerSession.lunarGlobeRadiusMeters) * session.globePresentationScale * 0.32
        for place in session.catalogPlaces {
            let pin: ModelEntity
            if let existing = placePins[place.id] { pin = existing }
            else {
                pin = ModelEntity(mesh: .generateSphere(radius: 0.007),
                                  materials: [UnlitMaterial(color: place.category == "apollo" ? .white : .systemCyan)])
                pin.name = "moon-place:" + place.id
                pin.components.set(InputTargetComponent())
                pin.components.set(HoverEffectComponent())
                pin.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.02)]))
                pin.isAccessibilityElement = true
                pin.accessibilityLabelKey = "\(place.name)"
                pin.accessibilityTraits = .button
                placePins[place.id] = pin
            }
            if pin.parent !== anchor { anchor.addChild(pin) }
            let direction = LunarExplorerMapGeometry.direction(to: place.coordinate, centeredOn: session.browseCoordinate)
            pin.position = session.globePosition + direction * radius * 1.006
            pin.scale = SIMD3(repeating: place.id == session.selectedPlaceID ? 1.6 : 1)
            pin.isEnabled = LunarExplorerMapGeometry.isVisible(direction: direction,
                globePosition: session.globePosition, radius: radius)
        }
    }

    func loadIfNeeded(session: LunarExplorerSession) {
        self.session = session
        guard !isLoaded, loadTask == nil else {
            apply(session)
            return
        }
        if let coordinate = session.captureElevationCoordinate {
            loadElevationPreview(coordinate: coordinate, session: session)
            return
        }
        if let coordinate = session.destinationCoordinate {
            let manifest = try? LMTerrainManifest.load()
            session.usesBundledSite = manifest.flatMap { LMLunarTerrainRegion.bundledSitePosition(at: coordinate, manifest: $0) } != nil
            if !session.usesBundledSite {
                loadGlobalTerrain(coordinate: coordinate, session: session)
                return
            }
        } else { session.usesBundledSite = true }
        let detailMode = session.detailMode
        let detailPipeline = pipeline(for: detailMode)
        activeDetailMode = detailMode
        // The base bands bake their materials during load, so the grade has to
        // be in force before it starts rather than patched afterwards.
        activeGrade = session.presentationGrade
        LMTerrainWorld.presentationGrade = session.presentationGrade
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let manifest = try LMTerrainManifest.load()
                do {
                    if self.globeEntity == nil {
                    let globe = try await LMLunarGlobeResource.makeEntity(
                        manifest: manifest
                    )
                    try Task.checkCancellation()
                    self.globePresentationRoot.children.removeAll()
                    self.globePresentationRoot.addChild(self.selectionMarker)
                    self.globeFrontCoordinate = manifest.landingOriginCoordinate
                    if session.pendingArrival { session.flightCoordinate = nil }
                    self.globePresentationRoot.addChild(globe.entity)
                    self.globeEntity = globe.entity
                    self.appliedGlobeLinearRadianceMultiplier = nil
                    session.diagnostics.globeTierState = "bundled "
                        + "\(globe.textureTier.mapResolutionPixelsPerDegree) ppd"
                        + (globe.usedFallback ? " fallback" : "")
                    let terminatorDate = session.sunDate
                    let terminator = try await LMLunarGlobeResource.makeTerminator(
                        manifest: manifest,
                        date: terminatorDate
                    )
                    try Task.checkCancellation()
                    self.globePresentationRoot.addChild(terminator.entity)
                    self.globeTerminator = terminator
                    self.globeTerminatorDate = terminatorDate
                    } else {
                        session.diagnostics.globeTierState = "resident global atlas"
                    }
                    session.diagnostics.loadMessage = "Global WAC Moon ready"
                    self.apply(session)
                } catch is CancellationError { return }
                catch {
                    self.logger.error(
                        "Lunar globe load failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                // Browsing needs only the globe. Load the landing stack after
                // an explicit Explore action, preserving the capture path.
                if session.isBrowsingGlobe { self.loadTask = nil; return }
                let heightField = try Apollo11TerrainResource.loadSourceBackedHeightField()
                let assembly = try await LMTerrainWorld.load(
                    detailPipeline: detailPipeline
                )
                try Task.checkCancellation()
                let alignment = try LMTerrainFrameAlignment(manifest: assembly.manifest)
                let eagle = alignment.terrainReferenceTouchdown
                let datum = Double(
                    heightField.relativeElevation(
                        eastMeters: eagle.y,
                        northMeters: eagle.x
                    ) ?? 0
                )
                let rocks = try LMLunarTerrainTiming.measure("apollo-rocks") {
                    try LMLunarRockFieldResource.makeEntity(
                        heightField: heightField,
                        eagleTerrainPosition: eagle
                    )
                }
                assembly.worldRoot.addChild(rocks)
                terrainAnchorRoot.addChild(assembly.worldRoot)
                self.sourceFrame = assembly.manifest.landingLocalFrame
                self.floatingOrigin = LMLunarFloatingOrigin(frame: assembly.manifest.landingLocalFrame)
                self.reanchorProbePending = session.captureReanchorProbe
                if session.captureReanchorProbe {
                    // Hold a stationary view in an offset frame for 100 seconds.
                    // Its 4.2 km focus drift then exercises the production trigger.
                    let offset = assembly.manifest.landingLocalFrame.coordinate(for:
                        LMSiteENUPosition(northMeters: eagle.x + 4_200,
                                          eastMeters: eagle.y, upMeters: datum))
                    self.floatingOrigin?.reanchor(at: offset)
                    Task { @MainActor [weak self, weak session] in
                        try? await Task.sleep(for: .seconds(100))
                        guard let self, let session else { return }
                        self.reanchorProbePending = false
                        self.apply(session)
                    }
                }

                self.heightField = heightField
                self.albedoField = try? LMMeasuredAlbedoField.load(tile: heightField.tile)
                self.eagleTerrainPosition = eagle
                if let destination = session.destinationCoordinate,
                   let point = LMLunarTerrainRegion.bundledSitePosition(at: destination, manifest: assembly.manifest) {
                    session.focusNorthOffsetMeters = point.northMeters - eagle.x
                    session.focusEastOffsetMeters = point.eastMeters - eagle.y
                }
                self.terrainDatumElevationMeters = datum
                self.siteCoordinate = assembly.manifest.landingOriginCoordinate
                self.terrainEnvironment = assembly.worldRoot
                self.measuredNearFieldEntity = assembly.nearFieldEntity
                self.measuredNearFieldGrid = assembly.nearFieldGrid
                self.terrainSun = assembly.sun
                self.terrainEarthshine = assembly.earthshine
                self.terrainRockField = rocks
                self.isLoaded = true
                self.loadTask = nil
                session.navigationMessage = ""
                session.diagnostics.measuredFloorMeters = assembly.manifest
                    .measuredFloorMeters(at: assembly.manifest.landingOriginCoordinate)
                session.diagnostics.loadMessage = "Apollo 11 terrain ready"
                session.beginArrival()
                session.diagnostics.sourceDescription = self.sourceDescription(
                    altitudeMeters: session.altitudeMeters
                )
                self.apply(session)
            } catch is CancellationError { return }
            catch {
                self.loadTask = nil
                session.navigationPhase = .idle
                session.diagnostics.loadMessage = "Terrain failed: \(error.localizedDescription)"
                self.logger.error(
                    "Lunar Explorer load failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func loadGlobalTerrain(coordinate: LMSelenographicCoordinate, session: LunarExplorerSession) {
        activeDetailMode = session.detailMode
        activeGrade = session.presentationGrade
        LMTerrainWorld.presentationGrade = session.presentationGrade
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let manifest = try LMTerrainManifest.load()
                // Keep the atlas resident across destinations. Only its frame changes;
                // decoding another 64 ppd texture peaked at 881 MiB during fly-to.
                if self.globeEntity == nil {
                    let atlasInterval = LMLunarTerrainTiming.begin("global-atlas")
                    let globe = try await LMLunarGlobeResource.makeEntity(manifest: manifest, frontCoordinate: coordinate)
                    LMLunarTerrainTiming.end(atlasInterval)
                    try Task.checkCancellation()
                    self.globeFrontCoordinate = coordinate
                    self.globePresentationRoot.addChild(globe.entity)
                    self.globeEntity = globe.entity
                    self.appliedGlobeLinearRadianceMultiplier = nil
                    let terminatorDate = session.sunDate
                    let terminatorInterval = LMLunarTerrainTiming.begin("global-terminator")
                    let terminator = try await LMLunarGlobeResource.makeTerminator(manifest: manifest, date: terminatorDate,
                                                                             frontCoordinate: coordinate)
                    LMLunarTerrainTiming.end(terminatorInterval)
                    self.globePresentationRoot.addChild(terminator.entity)
                    self.globeTerminator = terminator
                    self.globeTerminatorDate = terminatorDate
                    session.diagnostics.globeTierState = "bundled \(globe.textureTier.mapResolutionPixelsPerDegree) ppd"
                } else {
                    session.diagnostics.globeTierState = "resident global atlas"
                }
                self.updatePresentationTransform(session)
                let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("LunarElevation-v1", isDirectory: true)
                let store = try LMLunarElevationStore(directory: directory)
                let offline = session.regionOffline
                let region = try await Task.detached(priority: .userInitiated) {
                    try await LMLunarTerrainRegion.load(at: coordinate, store: store, offline: offline)
                }.value
                try Task.checkCancellation()
                let terrain = LMLunarTerrainPresentation(region: region, mode: session.detailMode)
                let world = Entity()
                world.addChild(terrain.root)
                let sun = DirectionalLight()
                world.addChild(sun)
                let earthshine = DirectionalLight()
                world.addChild(earthshine)
                self.terrainAnchorRoot.addChild(world)
                self.terrainEnvironment = world
                self.globalTerrain = terrain
                terrain.presentationChanged = { [weak self, weak session] in
                    guard let self, let session else { return }
                    self.updatePresentationTransform(session)
                }
                self.sourceFrame = region.frame
                self.floatingOrigin = .init(frame: region.frame)
                self.reanchorProbePending = session.captureReanchorProbe
                if session.captureReanchorProbe {
                    self.floatingOrigin?.reanchor(at: region.frame.coordinate(for:
                        .init(northMeters: 4_200, eastMeters: 0, upMeters: 0)))
                }
                self.siteCoordinate = region.frame.anchor
                self.terrainSun = sun
                self.terrainEarthshine = earthshine
                self.eagleTerrainPosition = .zero
                self.terrainDatumElevationMeters = 0
                self.isLoaded = true
                self.loadTask = nil
                session.navigationMessage = ""
                session.diagnostics.measuredFloorMeters = region.measuredFloorMeters
                session.diagnostics.sourceDescription = region.sourceIDs.joined(separator: ", ")
                    + (region.albedo.lunarField?.slabs.isEmpty == true ? "; uniform modeled reflectance" : "; normalized WAC reflectance")
                    + (region.unavailableSourceIDs.isEmpty ? "" : "; \(region.unavailableSourceIDs.count) sources unavailable")
                self.logger.info("Global sources ready floor=\(region.measuredFloorMeters)m missing=\(region.unavailableSourceIDs.count)")
                self.apply(session)
            } catch is CancellationError { return }
            catch {
                self.loadTask = nil
                session.navigationPhase = .idle
                session.diagnostics.loadMessage = "Global terrain failed: \(error.localizedDescription)"
            }
        }
    }

    private func beginLanding(session: LunarExplorerSession, terrain: LMLunarTerrainPresentation, focus: LMVector3D) {
        terrain.cancel()
        let surface = LMTerrainContactSurfaceBuilder.build(region: terrain.region, snapshot: terrain.snapshot)
        var drop = LMLunarLandingRehearsal(surface: surface, north: focus.x, east: focus.y)
        landingEntity?.removeFromParent()
        let vehicle = Entity()
        let body = ModelEntity(mesh: .generateBox(size: SIMD3(2, 1.5, 2)), materials: [UnlitMaterial(color: .gray)])
        body.position.y = 2.2
        vehicle.addChild(body)
        var pads = [(LMLandingGearLeg, ModelEntity)]()
        for leg in LMLandingGearLeg.allCases {
            let pad = ModelEntity(mesh: .generateBox(size: SIMD3(0.5, 0.05, 0.5)), materials: [UnlitMaterial(color: .yellow)])
            vehicle.addChild(pad); pads.append((leg, pad))
        }
        terrainAnchorRoot.addChild(vehicle)
        landingEntity = vehicle
        session.landingRunning = true
        landingTask = Task { @MainActor [weak self, weak session] in
            defer { session?.landingRunning = false }
            while !drop.finished {
                guard let self, let session, let anchor = self.floatingOrigin?.frame else { return }
                drop.step()
                let placement = LMLunarAnchoredPlacement.chunkTransform(
                    origin: .init(northMeters: drop.position.x, eastMeters: drop.position.y, upMeters: drop.position.z),
                    source: terrain.region.frame, anchor: anchor)
                self.landingPose = (drop.position, drop.attitude, terrain.region.frame)
                vehicle.transform = placement
                vehicle.orientation = placement.rotation * LMWorldMapper.attitudeOrientation(from: drop.attitude)
                for (leg, entity) in pads {
                    let pad = LMLandingGearGeometry.footpadBody(leg, strokeMeters: drop.gear.snapshot(leg)?.strokeMeters ?? 0)
                    entity.position = SIMD3(Float(pad.x), Float(pad.z) + 0.025, Float(-pad.y))
                }
                session.landingMessage = drop.message
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
            session?.landingMessage = drop.message
            self?.logger.info("Global contact rehearsal: \(drop.message, privacy: .public)")
        }
    }

    private func loadElevationPreview(coordinate: LMSelenographicCoordinate, session: LunarExplorerSession) {
        activeDetailMode = session.detailMode
        activeGrade = session.presentationGrade
        LMTerrainWorld.presentationGrade = session.presentationGrade
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let manifest = try LMTerrainManifest.load()
                let assembly = try await LMLunarElevationPreview.load(
                    coordinate: coordinate, offline: session.captureElevationOffline, manifest: manifest
                )
                self.terrainAnchorRoot.addChild(assembly.root)
                self.terrainEnvironment = assembly.root
                self.sourceFrame = assembly.frame
                self.floatingOrigin = LMLunarFloatingOrigin(frame: assembly.frame)
                self.siteCoordinate = assembly.frame.anchor
                self.terrainSun = assembly.sun
                self.elevationPreviewDescription = "Measured elevation diagnostic: " + assembly.sourceID
                    + "; constant reflectance"
                self.isLoaded = true
                self.loadTask = nil
                session.navigationMessage = ""
                session.diagnostics.measuredFloorMeters = assembly.sourceSpacingMeters
                session.diagnostics.loadMessage = "Measured elevation ready"
                self.logger.info("Elevation preview source=\(assembly.sourceID, privacy: .public) floor=\(assembly.sourceSpacingMeters)m load=\(assembly.loadMilliseconds)ms fallback=\(assembly.fallbackReason ?? "none", privacy: .public)")
                self.apply(session)
            } catch is CancellationError { return }
            catch {
                self.loadTask = nil
                session.diagnostics.loadMessage = "Elevation failed: " + error.localizedDescription
                self.logger.error("Elevation preview failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func apply(_ session: LunarExplorerSession) {
        self.session = session
        // Read action state even while destination loading takes the early path.
        // RealityView tracks only reads made synchronously in its update closure.
        let landingRequest = session.landingRequest
        let navigationPhase = session.navigationPhase
        if appliedNavigationRevision != session.navigationRevision {
            appliedNavigationRevision = session.navigationRevision
            loadTask?.cancel(); loadTask = nil
            globalTerrain?.cancel(); globalTerrain = nil
            generationTasks.values.forEach { $0.cancel() }
            generationTasks = [:]; generationTokens = [:]
            progressiveEntities = [:]; progressivePlans = [:]; progressiveOwnership = [:]
            pendingProgressiveEntities = [:]; pendingProgressivePlans = [:]; pendingOwnership = [:]
            requestedPlans = [:]; requestedOwnership = [:]
            landingTask?.cancel(); landingEntity?.removeFromParent(); landingEntity = nil; landingPose = nil
            terrainAnchorRoot.children.removeAll()
            heightField = nil; albedoField = nil; sourceFrame = nil; floatingOrigin = nil
            cancelOwnershipPreparation()
            terrainRockField = nil; measuredNearFieldEntity = nil; measuredNearFieldGrid = nil
            measuredNearFieldMask = []; terrainSun = nil; terrainEarthshine = nil
            terrainEnvironment = nil; isLoaded = false; activeDetailMode = nil
            session.diagnostics = .init()
            loadIfNeeded(session: session)
            updatePresentationTransform(session)
            return
        }
        if let frame = sourceFrame {
            let focus = terrainFocus(session)
            let position = LMSiteENUPosition(northMeters: focus.x, eastMeters: focus.y, upMeters: 0)
            let coordinate = session.usesBundledSite
                ? frame.coordinateSystem.coordinate(forSitePosition: position, relativeTo: frame.anchor)
                : frame.coordinate(for: position)
            if session.currentCoordinate != coordinate { session.currentCoordinate = coordinate }
        }
        updatePresentationTransform(session)
        updateGlobeTerminator(session)
        if !isLoaded, loadTask == nil, !session.isBrowsingGlobe, navigationPhase == .idle {
            loadIfNeeded(session: session)
            return
        }
        guard isLoaded, !session.isBrowsingGlobe else { return }

        if activeDetailMode != session.detailMode {
            if let globalTerrain {
                activeDetailMode = session.detailMode
                globalTerrain.setMode(session.detailMode)
            } else {
                activateDetailMode(session.detailMode, session: session)
            }
        }

        // The exposure floor is baked into each tile material, so a grade
        // change has to discard and regenerate resident tiles rather than
        // leaving a mix of two tonal treatments on screen.
        if activeGrade != session.presentationGrade {
            activeGrade = session.presentationGrade
            LMTerrainWorld.presentationGrade = session.presentationGrade
            applyExposureFloorToResidentMaterials()
        }

        updateRockDetail(altitudeMeters: session.altitudeMeters)
        terrainSun?.shadow = session.missionShadowsEnabled
            ? LMTerrainWorld.missionShadow(altitudeMeters: session.altitudeMeters)
            : nil
        updateMissionSun(session)

        let focus = terrainFocus(session)
        if navigationPhase == .departing || navigationPhase == .arriving { return }
        if let globalTerrain {
            if session.landingRunning { return }
            if landingRequest != appliedLandingRequest,
               session.diagnostics.loadMessage == "Lunar terrain ready",
               session.diagnostics.finestSpacingMeters == 0.125 {
                appliedLandingRequest = session.landingRequest
                beginLanding(session: session, terrain: globalTerrain, focus: focus)
                return
            }
            globalTerrain.update(east: focus.y, north: focus.x,
                                 altitude: session.pendingArrival ? LunarExplorerSession.Preset.regional.altitudeMeters : session.altitudeMeters,
                                 metersAcross: session.pendingArrival ? LunarExplorerSession.Preset.regional.metersAcross : session.metersAcross,
                                 heading: session.headingDegrees) { [weak self, weak session] message, requested, active, spacing, milliseconds in
                guard let self, let session else { return }
                session.diagnostics.loadMessage = message
                if message.hasPrefix("Lunar terrain failed") {
                    session.navigationPhase = .idle
                    session.pendingArrival = false
                    session.flightCoordinate = nil
                    session.navigationMessage = "Destination terrain failed. Reload to retry."
                }
                session.diagnostics.requestedTileCount = requested
                session.diagnostics.activeTileCount = active
                session.diagnostics.finestSpacingMeters = spacing
                session.diagnostics.latestGenerationMilliseconds = milliseconds
                self.updatePresentationTransform(session)
                if milliseconds != nil {
                    if ProcessInfo.processInfo.arguments.contains("--lunar-explorer-ownership-probe") {
                        let snapshot = globalTerrain.snapshot
                        let focus = SIMD3(Float(focus.x), snapshot.sample(east: focus.y, north: focus.x)?.elevation ?? 0, Float(-focus.y))
                        let inverse = self.presentationRoot.orientation.inverse
                        let scale = self.presentationRoot.scale.x
                        let origin = focus + inverse.act(SIMD3(0, 1.45, 0) - self.presentationRoot.position) / scale
                        Task.detached {
                            let logger = Logger(subsystem: "io.positron.LM", category: "TerrainOwnership")
                            for v: Float in [-0.5, 0, 0.5] {
                                for u: Float in [-0.9, 0, 0.9] {
                                    if let hit = snapshot.raycast(origin: origin, direction: inverse.act(SIMD3(u, v, -1))) {
                                        let owner = snapshot.sample(east: Double(-hit.position.z), north: Double(hit.position.x))
                                        logger.info("Ownership ray u=\(u) v=\(v) east=\(-hit.position.z)m north=\(hit.position.x)m height=\(hit.position.y)m spacing=\(hit.plan.sampleSpacingMeters)m verticalOwner=\(owner?.spacing ?? 0)m distance=\(hit.distance)m")
                                    }
                                }
                            }
                        }
                    }
                    if session.pendingArrival { session.flightCoordinate = nil }
                    session.beginArrival()
                }
                if session.landingRequest != self.appliedLandingRequest, milliseconds != nil { self.apply(session) }
                if active > 0, milliseconds != nil, self.reanchorProbePending, !self.globalReanchorProbeStarted {
                    self.globalReanchorProbeStarted = true
                    Task { @MainActor [weak self, weak session] in
                        try? await Task.sleep(for: .seconds(100))
                        guard let self, let session else { return }
                        self.reanchorProbePending = false
                        self.apply(session)
                    }
                }
            }
            return
        }
        requestProgressiveTerrain(
            focusEastMeters: focus.y,
            focusNorthMeters: focus.x,
            altitudeMeters: session.altitudeMeters
        )
        updateProgressiveTerrainPresentation(
            altitudeMeters: session.altitudeMeters
        )
        updateDiagnostics(session)
    }

    private func updateGlobeTerminator(_ session: LunarExplorerSession) {
        guard let globeTerminator else { return }
        let date = session.sunDate
        guard globeTerminatorDate != date else { return }
        do {
            try LMLunarGlobeResource.updateTerminator(
                globeTerminator,
                date: date
            )
            globeTerminatorDate = date
        } catch {
            logger.error(
                "Lunar globe terminator update failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func updatePresentationTransform(_ session: LunarExplorerSession) {
        if session.isExplorerExperience {
            root.components.set(OpacityComponent(opacity: session.transitionOpacity))
        }
        if session.isBrowsingGlobe {
            if globePlacementRoot == nil || appliedPlacementRevision != session.globePlacementRevision {
                let previous = globePlacementRoot
                let anchor = AnchorEntity(.head, trackingMode: .once)
                root.addChild(anchor)
                for entity in [globePresentationRoot, interactionSurface, markerBillboard] {
                    anchor.addChild(entity)
                }
                previous?.removeFromParent()
                globePlacementRoot = anchor
                appliedPlacementRevision = session.globePlacementRevision
            }
            if let anchor = globePlacementRoot {
                for entity in [globePresentationRoot, interactionSurface, markerBillboard]
                    where entity.parent !== anchor { anchor.addChild(entity) }
            }
        } else {
            for entity in [globePresentationRoot, interactionSurface, markerBillboard]
                where entity.parent !== root { root.addChild(entity) }
        }
        updateGlobeRadiance(session)
        let siteScale = session.presentationScale
        let blend = session.globeSiteBlend
        globePresentationRoot.scale = SIMD3(
            repeating: session.globePresentationScale
        )
        // Keep the nearest surface at a stable viewing depth as the sphere
        // grows. A fixed center put the camera inside the Moon once the 64 ppd
        // map zoomed far enough to hand off to the regional tangent plane.
        let displayedGlobeRadius = Float(
            LunarExplorerSession.lunarGlobeRadiusMeters
        ) * session.globePresentationScale
        let globePosition = SIMD3<Float>(
            0,
            1.45,
            -(LunarExplorerSession.globeSurfaceDepthMeters + displayedGlobeRadius)
        )
        // Global navigation promises the selected coordinate at the view center.
        // Apollo retains its established oblique capture framing.
        let sitePosition = SIMD3<Float>(0, session.usesBundledSite ? -0.35 : 1.45, -2.35)
        globePresentationRoot.position = globePosition
        let heading = simd_quatf(
            angle: Float(session.headingDegrees * .pi / 180),
            axis: SIMD3(0, 1, 0)
        )
        let tilt = simd_quatf(
            angle: Float(session.tiltDegrees * .pi / 180),
            axis: SIMD3(1, 0, 0)
        )
        let globeOrientation = tilt * heading
        globePresentationRoot.orientation = globeOrientation

        // The globe coordinate authority authors Apollo 11 at +z. Project its
        // rotated surface point onto a foreground presentation plane along
        // the same eye ray. This keeps the regional map centered on the real
        // globe point without making a 262 km patch physically tiny at whole-
        // Moon scale. It also puts the complete plane in front of the sphere,
        // avoiding depth intersections while both representations crossfade.
        let apolloSurfacePosition = globePosition + globeOrientation.act(
            SIMD3(0, 0, displayedGlobeRadius)
        )
        var registeredPosition = Self.registeredSitePresentationPosition(
            apolloSurfacePosition: apolloSurfacePosition,
            eyePosition: SIMD3(0, globePosition.y, 0),
            depthMeters: LunarExplorerSession.globeSurfaceDepthMeters - 0.01
        )
        // Site terrain is +x north, +y elevation, -z east. At the start of
        // the overlap, rotate its up axis onto the globe's Apollo radial so
        // the map is tangent and north/east stay registered. Once the globe
        // is gone, tip toward the normal regional inspection view.
        let siteToGlobeTangent = simd_quatf(
            angle: .pi / 2,
            axis: SIMD3(1, 0, 0)
        )
        let registeredOrientation = globeOrientation * siteToGlobeTangent
        // A zoom that starts from the globe also eases into the Orbit viewing
        // angle. Named site presets retain their own calibrated angles exactly
        // (Approach through Surface are intentionally shallower than Orbit).
        let siteTiltDegrees = session.selectedPreset == .globe
            ? LunarExplorerSession.Preset.orbit.tiltDegrees
            : session.tiltDegrees
        let siteTilt = simd_quatf(
            angle: Float(siteTiltDegrees * .pi / 180),
            axis: SIMD3(1, 0, 0)
        )
        let siteOrientation = siteTilt * heading
        // The blend starts only once the finite 262 km regional base covers
        // the selected view, so both representations can use the same scale.
        // This removes the visible translucent Moon-over-map double image.
        var crossfadeScale = siteScale * Float(
            LunarExplorerSession.globeHandoffOverscan
        )
        if let globalTerrain, !globalTerrain.snapshot.tiles.isEmpty {
            let focus = terrainFocus(session)
            let focusHeight = globalTerrain.snapshot.sample(east: focus.y, north: focus.x)?.elevation ?? 0
            let offset = SIMD3(Float(focus.x), focusHeight, Float(-focus.y))
            let safe = Self.foregroundProjection(
                position: registeredPosition, orientation: registeredOrientation, scale: crossfadeScale,
                minimum: globalTerrain.boundsMinimum - offset, maximum: globalTerrain.boundsMaximum - offset,
                eye: SIMD3(0, globePosition.y, 0), maximumDepth: LunarExplorerSession.globeSurfaceDepthMeters - 0.01
            )
            registeredPosition = safe.position
            crossfadeScale = safe.scale
        }
        let settledScale = siteScale * Float(
            session.siteCoverageScaleMultiplier
        )
        let progress = Float(blend.morphProgress)
        let logarithmicScale = exp(
            log(crossfadeScale) * (1 - progress)
                + log(settledScale) * progress
        )
        presentationRoot.scale = SIMD3(repeating: logarithmicScale)
        presentationRoot.position = simd_mix(
            registeredPosition,
            sitePosition,
            SIMD3(repeating: progress)
        )
        presentationRoot.orientation = simd_slerp(
            registeredOrientation,
            siteOrientation,
            progress
        )

        let globeFocus = (session.isBrowsingGlobe ? session.browseCoordinate : nil) ?? session.flightCoordinate
            ?? (isLoaded ? (session.usesBundledSite ? siteCoordinate : session.currentCoordinate) : nil)
        if let flight = globeFocus, let front = globeFrontCoordinate {
            let rotation = front == flight ? simd_quatf() : LMLunarNavigation.displayRotation(from: front, to: flight)
            globeEntity?.orientation = rotation
            globeTerminator?.entity.orientation = rotation
        } else {
            globeEntity?.orientation = .init()
            globeTerminator?.entity.orientation = .init()
        }
        if session.isBrowsingGlobe {
            // A bounded, reachable globe in passthrough. Zoom cannot turn it
            // into a room-filling surface; Explore explicitly enters full space.
            let scale = session.globePresentationScale * 0.32
            globePresentationRoot.scale = SIMD3(repeating: scale)
            globePresentationRoot.position = session.globePosition
            globePresentationRoot.orientation = .init()
            interactionSurface.position = globePresentationRoot.position
            let radius = Float(LunarExplorerSession.lunarGlobeRadiusMeters) * scale
            if appliedInteractionRadius != radius {
                appliedInteractionRadius = radius
                interactionSurface.components.set(CollisionComponent(shapes: [.generateSphere(radius: radius)]))
            }
        } else {
            interactionSurface.position = SIMD3(0, 0, -1.15)
            if appliedInteractionRadius != nil {
                appliedInteractionRadius = nil
                interactionSurface.components.set(CollisionComponent(shapes: [
                    .generateBox(size: SIMD3(3.8, 2.6, 0.02))
                ]))
            }
        }
        updatePlacePins(session)
        markerBillboard.isEnabled = session.isExplorerExperience && session.isBrowsingGlobe
        if markerBillboard.isEnabled {
            let coordinate = session.selectedMarkerPlace?.coordinate ?? session.browseCoordinate
            let direction = LunarExplorerMapGeometry.direction(to: coordinate, centeredOn: session.browseCoordinate)
            let radius = Float(LunarExplorerSession.lunarGlobeRadiusMeters) * session.globePresentationScale * 0.32
            markerBillboard.position = session.globePosition + direction * radius * 1.006
            markerBillboard.isEnabled = LunarExplorerMapGeometry.isVisible(direction: direction,
                globePosition: session.globePosition, radius: radius)
        }
        let canPresentSite = !session.isBrowsingGlobe && session.flightCoordinate == nil && isLoaded && (globalTerrain == nil || globalTerrain?.snapshot.tiles.isEmpty == false)
        let globeOpacity = canPresentSite ? blend.globeOpacity : 1
        let siteOpacity = canPresentSite ? blend.siteOpacity : 0
        globePresentationRoot.isEnabled = globeOpacity > 0.001
        presentationRoot.isEnabled = siteOpacity > 0.001
        Self.applyPresentationOpacity(globeOpacity, to: globePresentationRoot)
        Self.applyPresentationOpacity(siteOpacity, to: presentationRoot)

        updateFloatingAnchor(session)
        if let pose = landingPose, let anchor = floatingOrigin?.frame {
            let placement = LMLunarAnchoredPlacement.chunkTransform(
                origin: .init(northMeters: pose.position.x, eastMeters: pose.position.y, upMeters: pose.position.z),
                source: pose.frame, anchor: anchor)
            landingEntity?.transform = placement
            landingEntity?.orientation = placement.rotation * LMWorldMapper.attitudeOrientation(from: pose.attitude)
        }
    }

    /// A homothety about the eye preserves every projected vertex. Bound the
    /// entire generated region ahead of the globe's nearest surface rather
    /// than assuming its kilometer-scale relief fits a 1 cm depth offset.
    static func foregroundProjection(position: SIMD3<Float>, orientation: simd_quatf, scale: Float,
                                     minimum: SIMD3<Float>, maximum: SIMD3<Float>, eye: SIMD3<Float>,
                                     maximumDepth: Float) -> (position: SIMD3<Float>, scale: Float) {
        var farthestDepth: Float = 0
        for x in [minimum.x, maximum.x] {
            for y in [minimum.y, maximum.y] {
                for z in [minimum.z, maximum.z] {
                    let point = position + orientation.act(SIMD3(x, y, z) * scale)
                    farthestDepth = max(farthestDepth, eye.z - point.z)
                }
            }
        }
        let ratio = min(1, maximumDepth / max(maximumDepth, farthestDepth))
        return (eye + (position - eye) * ratio, scale * ratio)
    }

    private func updateFloatingAnchor(_ session: LunarExplorerSession) {
        guard let sourceFrame, var origin = floatingOrigin, let terrainEnvironment else { return }
        let focus = terrainFocus(session)
        let sourceFocus = LMSiteENUPosition(
            northMeters: focus.x, eastMeters: focus.y,
            upMeters: globalTerrain?.snapshot.sample(east: focus.y, north: focus.x)
                .map { Double($0.elevation) } ?? terrainDatumElevationMeters
        )
        let moonFocus = sourceFrame.moonCenteredPosition(for: sourceFocus)
        if !reanchorProbePending, origin.update(focus: moonFocus) {
            logger.info("Reanchor generation=\(origin.generation) resident=\(self.globalTerrain?.snapshot.tiles.count ?? self.progressiveEntities.count) pending=\(self.generationTasks.count)")
        }
        floatingOrigin = origin
        let placement = LMLunarAnchoredPlacement(
            source: sourceFrame, anchor: origin.frame, focus: sourceFocus
        )
        // Both assignments happen synchronously on the main actor. Resident
        // meshes, ownership, textures, lights, and pending builds stay attached.
        if let globalTerrain {
            terrainEnvironment.transform = .identity
            globalTerrain.apply(anchor: origin.frame)
        } else {
            terrainEnvironment.transform = placement.sourceTransform
        }
        terrainAnchorRoot.transform = placement.viewTransform
    }

    /// RealityKit's unlit base-color tint is evaluated in linear space. An
    /// extended-linear color preserves a multiplier above one without
    /// changing the texture, its transfer function, or the terminator shell.
    private func updateGlobeRadiance(_ session: LunarExplorerSession) {
        // Cartographic globe against a bright room; immersive/capture radiance
        // keeps the accepted handoff calibration exactly.
        let multiplier = session.isBrowsingGlobe ? 3.0 : session.globeHandoffLinearRadianceMultiplier
        guard appliedGlobeLinearRadianceMultiplier != multiplier,
              let globeEntity,
              var model = globeEntity.components[ModelComponent.self],
              var material = model.materials.first as? UnlitMaterial,
              let colorSpace = CGColorSpace(
                  name: CGColorSpace.extendedLinearSRGB
              ),
              let tint = CGColor(
                  colorSpace: colorSpace,
                  components: [multiplier, multiplier, multiplier, 1]
              )
        else { return }
        material.color.tint = UIColor(cgColor: tint)
        model.materials[0] = material
        globeEntity.components.set(model)
        appliedGlobeLinearRadianceMultiplier = multiplier
    }

    /// Projects the Apollo surface point onto a nearer plane without changing
    /// its view ray. The screen-space registration residual is therefore zero
    /// before rasterization; only the planar-versus-spherical scale model is
    /// deliberately different during the presentation handoff.
    static func registeredSitePresentationPosition(
        apolloSurfacePosition: SIMD3<Float>,
        eyePosition: SIMD3<Float>,
        depthMeters: Float
    ) -> SIMD3<Float> {
        let ray = simd_normalize(apolloSurfacePosition - eyePosition)
        return eyePosition + ray * depthMeters
    }

    /// Do not leave a no-op opacity component on either fully opaque endpoint.
    /// Besides avoiding transparent-render sorting, this preserves the exact
    /// RealityKit path used by the existing named site capture baselines.
    static func applyPresentationOpacity(
        _ opacity: Double,
        to entity: Entity
    ) {
        if opacity >= 0.999 {
            entity.components.remove(OpacityComponent.self)
        } else {
            entity.components.set(OpacityComponent(opacity: Float(opacity)))
        }
    }

    private func terrainFocus(_ session: LunarExplorerSession) -> LMVector3D {
        LMVector3D(
            x: eagleTerrainPosition.x + session.focusNorthOffsetMeters,
            y: eagleTerrainPosition.y + session.focusEastOffsetMeters,
            z: 0
        )
    }

    private func requestProgressiveTerrain(
        focusEastMeters: Double,
        focusNorthMeters: Double,
        altitudeMeters: Double
    ) {
        guard let heightField,
              terrainEnvironment != nil,
              let activeDetailMode else { return }
        let detailPipeline = pipeline(for: activeDetailMode)
        let planner = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: heightField.spacingMeters
        )
        // Capture-only control for a same-camera, same-feature LOD A/B. It is
        // more reliable than comparing different lunar pixels on opposite
        // sides of a footprint boundary after residency geometry changes.
        let terminalOnlyCapture = ProcessInfo.processInfo.arguments.contains(
            "--lunar-explorer-capture-max-detail=terminal"
        ) && ProcessInfo.processInfo.arguments.contains(
            "--lunar-explorer-capture"
        )
        let requestedAltitude = terminalOnlyCapture
            ? max(
                altitudeMeters,
                LMTerrainDetailPolicy().landingAltitudeMeters + 1
            )
            : altitudeMeters
        let heading = session?.headingDegrees ?? 0
        let metersAcross = session?.metersAcross ?? 0
        // The compact footprint owns contact around the selected point. The
        // oblique Explorer camera also needs a bounded forward corridor so its
        // frame never sees the rectangular outer morph into the parent level.
        // Keep the expensive 0.125 m landing corridor asymmetric but complete:
        // 48 m into the view and 32 m behind the focus. The rear coverage is
        // load-bearing at Surface, where the nearest footprint perimeter is
        // otherwise visible as a broad normal-frequency collar. This is 24
        // Eagle tiles, still bounded below the former 31-tile blanket. The
        // cheaper 0.5 m terminal corridor can follow wider inspection views.
        let basePlans = planner.focusedPlans(
            focusEastMeters: focusEastMeters,
            focusNorthMeters: focusNorthMeters,
            altitudeMeters: requestedAltitude
        )
        var corridorPlans = basePlans
        if !terminalOnlyCapture,
           altitudeMeters <= LMTerrainDetailPolicy().landingAltitudeMeters {
            corridorPlans += planner.viewCorridorPlans(
                focusEastMeters: focusEastMeters,
                focusNorthMeters: focusNorthMeters,
                headingDegrees: heading,
                forwardDistanceMeters: 48,
                altitudeMeters: altitudeMeters
            )
            corridorPlans += planner.viewCorridorPlans(
                focusEastMeters: focusEastMeters,
                focusNorthMeters: focusNorthMeters,
                headingDegrees: heading + 180,
                forwardDistanceMeters: 32,
                altitudeMeters: altitudeMeters
            )
        }
        let terminalDistance = min(384, max(48, metersAcross * 0.75))
        if altitudeMeters <= LMTerrainDetailPolicy().terminalAltitudeMeters {
            // Asking at 61 m selects only the terminal level when the landing
            // level is also resident, avoiding a large hidden fine-tile set.
            let terminalOnlyAltitude = max(
                altitudeMeters,
                LMTerrainDetailPolicy().landingAltitudeMeters + 1
            )
            corridorPlans += planner.viewCorridorPlans(
                focusEastMeters: focusEastMeters,
                focusNorthMeters: focusNorthMeters,
                headingDegrees: heading,
                forwardDistanceMeters: terminalDistance,
                altitudeMeters: terminalOnlyAltitude
            )
        }
        let plans = planner.mergedPlans(corridorPlans)
        let nextPlans = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })
        let policy = LMTerrainDetailPolicy()
        let replacementPlans = plans.filter {
            policy.presentationBlend(
                sampleSpacingMeters: $0.sampleSpacingMeters,
                altitudeMeters: altitudeMeters
            ) >= 0.999
        }
        let nextOwnership = Dictionary(uniqueKeysWithValues: plans.map { plan in
            (plan.id, Self.finerOwners(of: plan, in: replacementPlans))
        })
        guard nextPlans != requestedPlans
                || nextOwnership != requestedOwnership else { return }
        let previousRequestedPlans = requestedPlans
        let previousRequestedOwnership = requestedOwnership
        requestedPlans = nextPlans
        requestedOwnership = nextOwnership

        for id in Array(generationTasks.keys)
            where nextPlans[id] != previousRequestedPlans[id]
                || nextOwnership[id] != previousRequestedOwnership[id] {
            generationTasks[id]?.cancel()
            generationTasks.removeValue(forKey: id)
            generationTokens.removeValue(forKey: id)
        }
        for id in Array(pendingProgressiveEntities.keys)
            where nextPlans[id] != pendingProgressivePlans[id]
                || nextOwnership[id] != pendingOwnership[id] {
            pendingProgressiveEntities.removeValue(forKey: id)
            pendingProgressivePlans.removeValue(forKey: id)
            pendingOwnership.removeValue(forKey: id)
        }
        publishRequestedTerrainIfReady()

        for plan in plans where (progressivePlans[plan.id] != plan
            || progressiveOwnership[plan.id] != nextOwnership[plan.id])
            && (pendingProgressivePlans[plan.id] != plan
                || pendingOwnership[plan.id] != nextOwnership[plan.id])
            && generationTasks[plan.id] == nil {
            let ownership = nextOwnership[plan.id] ?? []
            let token = UUID()
            generationTokens[plan.id] = token
            let started = ContinuousClock.now
            generationTasks[plan.id] = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let build = try await Apollo11TerrainResource
                        .makeProgressiveTileEntityBuild(
                        heightField: heightField,
                        plan: plan,
                        activePlans: plans,
                        geometryReplacementPlans: replacementPlans,
                        albedoField: self.albedoField,
                        detailPipeline: detailPipeline
                    )
                    guard self.finishGeneration(id: plan.id, token: token),
                          !Task.isCancelled,
                          self.requestedPlans[plan.id] == plan,
                          self.requestedOwnership[plan.id] == ownership,
                          let build else { return }
                    let entity = build.entity
                    self.pendingProgressiveEntities[plan.id] = entity
                    self.pendingProgressivePlans[plan.id] = plan
                    self.pendingOwnership[plan.id] = ownership
                    let elapsed = started.duration(to: .now)
                    let milliseconds = Int(
                        elapsed.components.seconds * 1_000
                            + elapsed.components.attoseconds / 1_000_000_000_000_000
                    )
                    self.session?.diagnostics.latestGenerationMilliseconds = milliseconds
                    self.session?.diagnostics.latestGenerationMetrics = build.metrics
                    self.logger.info(
                        "Terrain tile ready L\(plan.id.level, privacy: .public) E\(plan.id.eastIndex, privacy: .public) N\(plan.id.northIndex, privacy: .public) spacing=\(plan.sampleSpacingMeters, privacy: .public)m generation=\(milliseconds, privacy: .public)ms"
                    )
                    self.publishRequestedTerrainIfReady()
                    if let session = self.session {
                        self.updateDiagnostics(session)
                    }
                } catch is CancellationError {
                    _ = self.finishGeneration(id: plan.id, token: token)
                } catch {
                    _ = self.finishGeneration(id: plan.id, token: token)
                    self.logger.error(
                        "Terrain tile failed L\(plan.id.level, privacy: .public) E\(plan.id.eastIndex, privacy: .public) N\(plan.id.northIndex, privacy: .public) spacing=\(plan.sampleSpacingMeters, privacy: .public)m: \(error.localizedDescription, privacy: .public)"
                    )
                    self.session?.diagnostics.loadMessage =
                        "Tile L\(plan.id.level) failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Residency and presentation are deliberately separate. The landing
    /// tiles become resident at 60 m so generation can finish ahead of the
    /// vehicle, then their complete visual contribution fades in from 40 m to
    /// 25 m. Applying the same policy to the whole entity prevents an entire
    /// high-frequency footprint from appearing on the frame that crosses the
    /// residency gate. The surface sampler uses this exact blend for the
    /// cockpit/contact datum.
    private func updateProgressiveTerrainPresentation(
        altitudeMeters: Double
    ) {
        for (id, entity) in progressiveEntities {
            guard let plan = progressivePlans[id] else { continue }
            applyPresentationBlend(
                to: entity,
                plan: plan,
                altitudeMeters: altitudeMeters
            )
        }
    }

    private func applyPresentationBlend(
        to entity: ModelEntity,
        plan: LMTerrainTilePlan,
        altitudeMeters: Double
    ) {
        let opacity = LMTerrainDetailPolicy().presentationBlend(
            sampleSpacingMeters: plan.sampleSpacingMeters,
            altitudeMeters: altitudeMeters
        )
        // A no-op OpacityComponent still routes the mesh through RealityKit's
        // transparent pass. Once the measured/parent quads have handed their
        // footprint to this tile, that path can sort behind the resulting
        // geometric hole and expose the immersive black background. Use the
        // same opaque-endpoint contract as the globe/site presentation blend.
        Self.applyPresentationOpacity(opacity, to: entity)
    }

    @discardableResult
    private func finishGeneration(id: LMTerrainTileID, token: UUID) -> Bool {
        guard generationTokens[id] == token else { return false }
        generationTokens.removeValue(forKey: id)
        generationTasks.removeValue(forKey: id)
        return true
    }

    /// Publish a complete residency generation as one main-actor transaction.
    /// Parent meshes are allowed to contain child holes only when every child
    /// in the same generation is ready, so the viewer never sees the immersive
    /// background while asynchronous tiles arrive.
    private func publishRequestedTerrainIfReady() {
        guard let terrainEnvironment else { return }
        prepareMeasuredNearFieldOwnership()
        let nextMask = Set(requestedPlans.keys)
        guard measuredNearFieldEntity == nil || nextMask == measuredNearFieldMask
            || (ownershipPreparationIDs == nextMask && preparedOwnershipMesh != nil) else { return }
        guard requestedPlans.allSatisfy({ id, plan in
            (progressivePlans[id] == plan
                && progressiveOwnership[id] == requestedOwnership[id])
                || (pendingProgressivePlans[id] == plan
                    && pendingOwnership[id] == requestedOwnership[id])
        }) else { return }

        let publication = LMLunarTerrainTiming.begin("apollo-publication")
        defer { LMLunarTerrainTiming.end(publication) }
        let altitude = session?.altitudeMeters ?? .greatestFiniteMagnitude
        for (id, plan) in requestedPlans {
            guard pendingProgressivePlans[id] == plan,
                  pendingOwnership[id] == requestedOwnership[id],
                  let entity = pendingProgressiveEntities.removeValue(forKey: id) else {
                continue
            }
            pendingProgressivePlans.removeValue(forKey: id)
            pendingOwnership.removeValue(forKey: id)
            applyPresentationBlend(to: entity, plan: plan, altitudeMeters: altitude)
            terrainEnvironment.addChild(entity)
            progressiveEntities[id]?.removeFromParent()
            progressiveEntities[id] = entity
            progressivePlans[id] = plan
            progressiveOwnership[id] = requestedOwnership[id] ?? []
        }

        let activeIDs = Set(progressiveEntities.keys)
        let requestedIDs = Set(requestedPlans.keys)
        for id in activeIDs.subtracting(requestedIDs) {
            progressiveEntities.removeValue(forKey: id)?.removeFromParent()
            progressivePlans.removeValue(forKey: id)
            progressiveOwnership.removeValue(forKey: id)
        }
        if nextMask != measuredNearFieldMask,
           let entity = measuredNearFieldEntity,
           let mesh = preparedOwnershipMesh,
           var model = entity.model {
            model.mesh = mesh
            entity.model = model
            measuredNearFieldMask = nextMask
        }
        preparedOwnershipMesh = nil
    }

    static func finerOwners(
        of plan: LMTerrainTilePlan,
        in candidates: [LMTerrainTilePlan]
    ) -> Set<LMTerrainTileID> {
        let half = plan.sizeMeters / 2
        return Set(candidates.compactMap { candidate in
            guard candidate.sampleSpacingMeters
                    < plan.sampleSpacingMeters - 1e-9 else { return nil }
            let candidateHalf = candidate.sizeMeters / 2
            let overlaps = candidate.centerEastMeters + candidateHalf
                    > plan.centerEastMeters - half
                && candidate.centerEastMeters - candidateHalf
                    < plan.centerEastMeters + half
                && candidate.centerNorthMeters + candidateHalf
                    > plan.centerNorthMeters - half
                && candidate.centerNorthMeters - candidateHalf
                    < plan.centerNorthMeters + half
            return overlaps ? candidate.id : nil
        })
    }

    /// The measured near field and fine clipmap are alternate owners of the
    /// same physical surface. Mask the measured triangles only after the full
    /// requested replacement is resident, so asynchronous generation cannot
    /// expose a hole. The fine mesh already converges to the measured parent
    /// at this exact grid-aligned perimeter.
    private func prepareMeasuredNearFieldOwnership() {
        guard let grid = measuredNearFieldGrid else { return }
        let ids = Set(requestedPlans.keys)
        guard ids != measuredNearFieldMask else {
            cancelOwnershipPreparation()
            return
        }
        guard ownershipPreparationIDs != ids else { return }
        cancelOwnershipPreparation()
        ownershipPreparationIDs = ids
        let token = UUID()
        ownershipPreparationToken = token
        let plans = Array(requestedPlans.values)
        ownershipPreparation = Task { [weak self] in
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    let owned = try LMLunarTerrainTiming.measure("ownership-grid") {
                        try LMTerrainMeshBuilder.excludingProgressiveFootprints(from: grid, plans: plans)
                    }
                    try Task.checkCancellation()
                    return owned
                }
                let grid = try await withTaskCancellationHandler(
                    operation: { try await worker.value }, onCancel: { worker.cancel() }
                )
                let interval = LMLunarTerrainTiming.begin("ownership-mesh-async")
                let mesh = try await LMTerrainMeshBuilder.meshAsync(from: grid)
                LMLunarTerrainTiming.end(interval)
                try Task.checkCancellation()
                guard let self, self.ownershipPreparationToken == token else { return }
                self.preparedOwnershipMesh = mesh
                self.ownershipPreparation = nil
                self.publishRequestedTerrainIfReady()
            } catch is CancellationError {
                // A newer footprint or scene owns publication.
            } catch {
                guard let self, self.ownershipPreparationToken == token else { return }
                self.ownershipPreparation = nil
                self.logger.error("Measured terrain ownership preparation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func cancelOwnershipPreparation() {
        ownershipPreparation?.cancel()
        ownershipPreparation = nil
        ownershipPreparationToken = nil
        ownershipPreparationIDs = nil
        preparedOwnershipMesh = nil
    }

    /// Retain the existing synchronous reset for explicit appearance-mode
    /// changes. Ordinary residency publication prepares its mesh beforehand.
    private func refreshMeasuredNearFieldOwnership() {
        guard let entity = measuredNearFieldEntity,
              let grid = measuredNearFieldGrid else { return }
        let plans = Array(progressivePlans.values)
        let ids = Set(plans.map(\.id))
        guard ids != measuredNearFieldMask else { return }
        do {
            let ownedGrid = try LMTerrainMeshBuilder.excludingProgressiveFootprints(
                from: grid, plans: plans)
            let mesh = try LMTerrainMeshBuilder.mesh(from: ownedGrid)
            guard var model = entity.model else { return }
            model.mesh = mesh
            entity.model = model
            measuredNearFieldMask = ids
        } catch {
            logger.error("Measured terrain ownership reset failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Points the mission sun where it actually was at the session's instant.
    ///
    /// The manifest pins a single touchdown direction; the ephemeris supplies
    /// the same two angles for any date, so scrubbing time sweeps the real
    /// terminator across the site instead of interpolating an invented one.
    private func updateMissionSun(_ session: LunarExplorerSession) {
        guard let siteCoordinate, let terrainSun else { return }
        let date = session.sunDate
        let grade = session.presentationGrade
        let sun = LMLunarEphemeris.sunAngles(at: date, site: siteCoordinate)
        terrainSun.orientation = LMFullDescentMapper.sunLightOrientation(from: sun)
        if globalTerrain != nil, let sourceFrame, let floatingOrigin {
            let rotation = LMLunarFrameTransform(from: sourceFrame, to: floatingOrigin.frame).renderRotation
            terrainSun.orientation = simd_quatf(vector: SIMD4<Float>(simd_quatd(rotation).vector)) * terrainSun.orientation
        }
        // Re-expose for the new solar elevation. Without this the surface
        // clips to white within a few days of the landing, because flat ground
        // takes the beam scaled by sin(elevation).
        let sunIlluminance = LMTerrainWorld.missionSunIlluminance(
            elevationDegrees: sun.elevationDegrees,
            grade: grade
        )
        terrainSun.light.intensity = sunIlluminance

        let earth = LMLunarEphemeris.earthAngles(at: date, site: siteCoordinate)
        let illuminatedFraction = LMLunarEphemeris
            .earthIlluminatedFractionFromMoon(at: date)
        terrainEarthshine?.orientation = LMFullDescentMapper
            .sunLightOrientation(from: earth)
        if globalTerrain != nil, let sourceFrame, let floatingOrigin, let terrainEarthshine {
            let rotation = LMLunarFrameTransform(from: sourceFrame, to: floatingOrigin.frame).renderRotation
            terrainEarthshine.orientation = simd_quatf(vector: SIMD4<Float>(simd_quatd(rotation).vector)) * terrainEarthshine.orientation
        }
        terrainEarthshine?.light.intensity = LMTerrainWorld.earthshineIlluminance(
            sunIlluminanceLux: sunIlluminance,
            illuminatedFraction: illuminatedFraction,
            grade: grade
        )
        // RealityView observes diagnostics while deciding whether an arrival
        // is ready. Publishing identical values here can retrigger its update
        // closure indefinitely when returning to an already resident site.
        if session.diagnostics.sunAzimuthDegrees != sun.azimuthDegreesClockwiseFromNorth {
            session.diagnostics.sunAzimuthDegrees = sun.azimuthDegreesClockwiseFromNorth
        }
        if session.diagnostics.sunElevationDegrees != sun.elevationDegrees {
            session.diagnostics.sunElevationDegrees = sun.elevationDegrees
        }
        if session.diagnostics.earthIlluminatedFraction != illuminatedFraction {
            session.diagnostics.earthIlluminatedFraction = illuminatedFraction
        }
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

    private func pipeline(
        for mode: LMTerrainDetailMode
    ) -> LMTerrainDetailPipeline {
        if let pipeline = detailPipelines[mode] {
            return pipeline
        }
        let pipeline = mode.makePipeline()
        detailPipelines[mode] = pipeline
        return pipeline
    }

    /// Retunes every resident terrain material to the current grade in place.
    ///
    /// The exposure floor is the only grade-dependent material property, so
    /// patching it costs nothing next to discarding and re-baking tiles — and
    /// unlike a progressive-tile rebuild it also reaches the measured base
    /// bands, which are built once at load and would otherwise keep the old
    /// tone under the new one.
    private func applyExposureFloorToResidentMaterials() {
        guard let terrainEnvironment else { return }
        applyExposureFloor(LMTerrainWorld.exposureFloor, to: terrainEnvironment)
    }

    private func applyExposureFloor(_ floor: Float, to entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            var didChange = false
            model.materials = model.materials.map { material in
                guard var physical = material as? PhysicallyBasedMaterial else {
                    return material
                }
                physical.emissiveIntensity = floor
                didChange = true
                return physical
            }
            if didChange {
                entity.components.set(model)
            }
        }
        for child in entity.children {
            applyExposureFloor(floor, to: child)
        }
    }

    private func activateDetailMode(
        _ mode: LMTerrainDetailMode,
        session: LunarExplorerSession
    ) {
        activeDetailMode = mode
        for task in generationTasks.values {
            task.cancel()
        }
        generationTasks.removeAll(keepingCapacity: false)
        generationTokens.removeAll(keepingCapacity: false)
        requestedPlans.removeAll(keepingCapacity: false)
        requestedOwnership.removeAll(keepingCapacity: false)
        progressivePlans.removeAll(keepingCapacity: false)
        progressiveOwnership.removeAll(keepingCapacity: false)
        pendingProgressivePlans.removeAll(keepingCapacity: false)
        pendingOwnership.removeAll(keepingCapacity: false)
        pendingProgressiveEntities.removeAll(keepingCapacity: false)
        cancelOwnershipPreparation()
        for entity in progressiveEntities.values {
            entity.removeFromParent()
        }
        progressiveEntities.removeAll(keepingCapacity: false)
        refreshMeasuredNearFieldOwnership()
        session.diagnostics.latestGenerationMilliseconds = nil
        session.diagnostics.latestGenerationMetrics = nil
        let detailPipeline = pipeline(for: mode)
        Task {
            await detailPipeline.prepare()
        }
    }

    private func updateDiagnostics(_ session: LunarExplorerSession) {
        var diagnostics = session.diagnostics
        diagnostics.requestedTileCount = requestedPlans.count
        diagnostics.activeTileCount = progressiveEntities.count
        diagnostics.finestSpacingMeters = requestedPlans.values
            .map(\.sampleSpacingMeters)
            .min()
        diagnostics.sourceDescription = sourceDescription(
            altitudeMeters: session.altitudeMeters
        )
        session.publishDiagnostics(diagnostics)
    }

    private func sourceDescription(altitudeMeters: Double) -> String {
        if let elevationPreviewDescription { return elevationPreviewDescription }
        if let session, session.presentsGlobe, session.presentsSite {
            return "Pinned WAC globe + Apollo 11 site crossfade"
        }
        if session?.presentsGlobe == true {
            return "Pinned WAC_GLOBAL 64 ppd morphologic map"
        }
        return switch altitudeMeters {
        case ...60:
            "2 m LROC plus 0.5 m and 0.125 m procedural geometry"
        case ...250:
            "2 m LROC plus 0.5 m procedural geometry"
        case ...2_500:
            "2 m LROC measured near field"
        default:
            "SLDEM regional geometry with WAC reflectance"
        }
    }
}
