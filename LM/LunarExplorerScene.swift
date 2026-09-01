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
    private let globePresentationRoot = Entity()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.positron.LM",
        category: "LunarExplorer"
    )
    private var terrainEnvironment: Entity?
    private var measuredNearFieldEntity: ModelEntity?
    private var measuredNearFieldGrid: LMTerrainMeshBuilder.VertexData?
    private var measuredNearFieldMask = Set<LMTerrainTileID>()
    private var globeEntity: ModelEntity?
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
    private var isLoaded = false
    private var loadTask: Task<Void, Never>?

    init() {
        root.name = "Lunar Explorer"
        presentationRoot.name = "Lunar Explorer presentation"
        root.addChild(presentationRoot)
        globePresentationRoot.name = "Lunar Explorer globe presentation"
        root.addChild(globePresentationRoot)

        interactionSurface.name = "Lunar Explorer interaction surface"
        interactionSurface.position = SIMD3(0, 0, -1.15)
        interactionSurface.components.set(InputTargetComponent())
        interactionSurface.components.set(HoverEffectComponent())
        interactionSurface.components.set(CollisionComponent(shapes: [
            .generateBox(size: SIMD3(3.8, 2.6, 0.02)),
        ]))
        root.addChild(interactionSurface)
    }

    func loadIfNeeded(session: LunarExplorerSession) {
        self.session = session
        guard !isLoaded, loadTask == nil else {
            apply(session)
            return
        }
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
                    let globe = try await LMLunarGlobeResource.makeEntity(
                        manifest: manifest
                    )
                    self.globePresentationRoot.addChild(globe.entity)
                    self.globeEntity = globe.entity
                    session.diagnostics.globeTierState = "bundled "
                        + "\(globe.textureTier.mapResolutionPixelsPerDegree) ppd"
                        + (globe.usedFallback ? " fallback" : "")
                    let terminator = try LMLunarGlobeResource.makeTerminator(
                        manifest: manifest,
                        date: session.sunDate
                    )
                    self.globePresentationRoot.addChild(terminator.entity)
                    self.globeTerminator = terminator
                    self.globeTerminatorDate = session.sunDate
                    session.diagnostics.loadMessage = "Global WAC Moon ready"
                    self.apply(session)
                } catch {
                    self.logger.error(
                        "Lunar globe load failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                let heightField = try Apollo11TerrainResource.loadSourceBackedHeightField()
                let assembly = try await LMTerrainWorld.load(
                    detailPipeline: detailPipeline
                )
                let alignment = try LMTerrainFrameAlignment(manifest: assembly.manifest)
                let eagle = alignment.terrainReferenceTouchdown
                let datum = Double(
                    heightField.relativeElevation(
                        eastMeters: eagle.y,
                        northMeters: eagle.x
                    ) ?? 0
                )
                let rocks = try LMLunarRockFieldResource.makeEntity(
                    heightField: heightField,
                    eagleTerrainPosition: eagle
                )
                assembly.worldRoot.addChild(rocks)
                presentationRoot.addChild(assembly.worldRoot)

                self.heightField = heightField
                self.albedoField = try? LMMeasuredAlbedoField.load(tile: heightField.tile)
                self.eagleTerrainPosition = eagle
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
                session.diagnostics.loadMessage = "Apollo 11 terrain ready"
                session.diagnostics.sourceDescription = self.sourceDescription(
                    altitudeMeters: session.altitudeMeters
                )
                self.apply(session)
            } catch {
                self.loadTask = nil
                session.diagnostics.loadMessage = "Terrain failed: \(error.localizedDescription)"
                self.logger.error(
                    "Lunar Explorer load failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    func apply(_ session: LunarExplorerSession) {
        self.session = session
        updatePresentationTransform(session)
        updateGlobeTerminator(session)
        guard isLoaded else { return }

        if activeDetailMode != session.detailMode {
            activateDetailMode(session.detailMode, session: session)
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
        let sitePosition = SIMD3<Float>(0, -0.35, -2.35)
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
        let registeredPosition = Self.registeredSitePresentationPosition(
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
        let crossfadeScale = siteScale * Float(
            LunarExplorerSession.globeHandoffOverscan
        )
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

        let canPresentSite = isLoaded
        let globeOpacity = canPresentSite ? blend.globeOpacity : 1
        let siteOpacity = canPresentSite ? blend.siteOpacity : 0
        globePresentationRoot.isEnabled = globeOpacity > 0.001
        presentationRoot.isEnabled = siteOpacity > 0.001
        Self.applyPresentationOpacity(globeOpacity, to: globePresentationRoot)
        Self.applyPresentationOpacity(siteOpacity, to: presentationRoot)

        let focus = terrainFocus(session)
        terrainEnvironment?.position = SIMD3(
            Float(-focus.x),
            Float(-terrainDatumElevationMeters),
            Float(focus.y)
        )
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
        // Explorer has no vehicle velocity to predict. Its former synthetic
        // forward/rear projections expanded the landing set from the bounded
        // 3x3 neighborhood to 31 fine tiles, overflowed the 32 MB working-set
        // cache, and pushed a Debug Simulator bake past forty seconds. The
        // ordinary focused footprint already covers the selected inspection
        // width; powered descent still uses real six-second velocity prefetch.
        let plans = planner.focusedPlans(
            focusEastMeters: focusEastMeters,
            focusNorthMeters: focusNorthMeters,
            altitudeMeters: altitudeMeters
        )
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
        guard requestedPlans.allSatisfy({ id, plan in
            (progressivePlans[id] == plan
                && progressiveOwnership[id] == requestedOwnership[id])
                || (pendingProgressivePlans[id] == plan
                    && pendingOwnership[id] == requestedOwnership[id])
        }) else { return }

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
        refreshMeasuredNearFieldOwnership()
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
    private func refreshMeasuredNearFieldOwnership() {
        guard let entity = measuredNearFieldEntity,
              let grid = measuredNearFieldGrid else { return }
        let plans = Array(progressivePlans.values)
        let ids = Set(plans.map(\.id))
        guard ids != measuredNearFieldMask else { return }
        do {
            let ownedGrid = LMTerrainMeshBuilder.excludingProgressiveFootprints(
                from: grid,
                plans: plans
            )
            let mesh = try LMTerrainMeshBuilder.mesh(from: ownedGrid)
            guard var model = entity.components[ModelComponent.self] else { return }
            model.mesh = mesh
            entity.components.set(model)
            measuredNearFieldMask = ids
        } catch {
            logger.error(
                "Measured terrain ownership update failed: \(error.localizedDescription, privacy: .public)"
            )
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
        terrainEarthshine?.light.intensity = LMTerrainWorld.earthshineIlluminance(
            sunIlluminanceLux: sunIlluminance,
            illuminatedFraction: illuminatedFraction,
            grade: grade
        )
        session.diagnostics.sunAzimuthDegrees = sun.azimuthDegreesClockwiseFromNorth
        session.diagnostics.sunElevationDegrees = sun.elevationDegrees
        session.diagnostics.earthIlluminatedFraction = illuminatedFraction
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
        session.diagnostics.requestedTileCount = requestedPlans.count
        session.diagnostics.activeTileCount = progressiveEntities.count
        session.diagnostics.finestSpacingMeters = requestedPlans.values
            .map(\.sampleSpacingMeters)
            .min()
        session.diagnostics.sourceDescription = sourceDescription(
            altitudeMeters: session.altitudeMeters
        )
    }

    private func sourceDescription(altitudeMeters: Double) -> String {
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
