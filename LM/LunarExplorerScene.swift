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
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.positron.LM",
        category: "LunarExplorer"
    )
    private var terrainEnvironment: Entity?
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
    private var requestedPlans = [LMTerrainTileID: LMTerrainTilePlan]()
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

    private func updatePresentationTransform(_ session: LunarExplorerSession) {
        let scale = session.presentationScale
        presentationRoot.scale = SIMD3(repeating: scale)
        presentationRoot.position = SIMD3(0, -0.35, -2.35)
        let heading = simd_quatf(
            angle: Float(session.headingDegrees * .pi / 180),
            axis: SIMD3(0, 1, 0)
        )
        let tilt = simd_quatf(
            angle: Float(session.tiltDegrees * .pi / 180),
            axis: SIMD3(1, 0, 0)
        )
        presentationRoot.orientation = tilt * heading

        let focus = terrainFocus(session)
        terrainEnvironment?.position = SIMD3(
            Float(-focus.x),
            Float(-terrainDatumElevationMeters),
            Float(focus.y)
        )
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
              let terrainEnvironment,
              let activeDetailMode else { return }
        let detailPipeline = pipeline(for: activeDetailMode)
        let planner = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: heightField.spacingMeters
        )
        // Explorer's low-altitude camera is deliberately more oblique than
        // the contact footprint. Reuse the production prefetch union to keep
        // a narrow forward corridor in the viewed direction instead of
        // growing the working set to a symmetric square. The surface camera's
        // grazing view reaches well beyond one 16 m tile; a 48 m projection
        // keeps the landing-frequency handoff downrange of the inspected
        // foreground while retaining only three rows. Heading zero looks
        // toward positive terrain east; rotating the terrain rotates the
        // projected direction with it. Terminal descent supplies real vehicle
        // velocity to the same planner boundary.
        let viewProjectionMeters = altitudeMeters <= 60 ? 48.0 : 0
        let headingRadians = (session?.headingDegrees ?? 0) * .pi / 180
        let lookaheadSeconds = 6.0
        let forwardPlans = planner.prefetchedPlans(
            focusEastMeters: focusEastMeters,
            focusNorthMeters: focusNorthMeters,
            velocityEastMetersPerSecond: cos(headingRadians)
                * viewProjectionMeters / lookaheadSeconds,
            velocityNorthMetersPerSecond: sin(headingRadians)
                * viewProjectionMeters / lookaheadSeconds,
            altitudeMeters: altitudeMeters
        )
        let rearProjectionMeters = altitudeMeters <= 60 ? 32.0 : 0
        let rearPlans = planner.focusedPlans(
            focusEastMeters: focusEastMeters
                - cos(headingRadians) * rearProjectionMeters,
            focusNorthMeters: focusNorthMeters
                - sin(headingRadians) * rearProjectionMeters,
            altitudeMeters: altitudeMeters
        )
        let plans = planner.mergedPlans(forwardPlans + rearPlans)
        let nextPlans = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })
        guard nextPlans != requestedPlans else { return }
        let previousRequestedPlans = requestedPlans
        requestedPlans = nextPlans

        for id in Array(generationTasks.keys)
            where nextPlans[id] != previousRequestedPlans[id] {
            generationTasks[id]?.cancel()
            generationTasks.removeValue(forKey: id)
            generationTokens.removeValue(forKey: id)
        }
        retireTilesIfReplacementIsReady()

        for plan in plans where progressivePlans[plan.id] != plan
            && generationTasks[plan.id] == nil {
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
                        albedoField: self.albedoField,
                        detailPipeline: detailPipeline
                    )
                    guard self.finishGeneration(id: plan.id, token: token),
                          !Task.isCancelled,
                          self.requestedPlans[plan.id] == plan,
                          let build else { return }
                    let entity = build.entity
                    self.applyPresentationBlend(
                        to: entity,
                        plan: plan,
                        altitudeMeters: self.session?.altitudeMeters
                            ?? altitudeMeters
                    )
                    terrainEnvironment.addChild(entity)
                    self.progressiveEntities[plan.id]?.removeFromParent()
                    self.progressiveEntities[plan.id] = entity
                    self.progressivePlans[plan.id] = plan
                    let elapsed = started.duration(to: .now)
                    let milliseconds = Int(
                        elapsed.components.seconds * 1_000
                            + elapsed.components.attoseconds / 1_000_000_000_000_000
                    )
                    self.session?.diagnostics.latestGenerationMilliseconds = milliseconds
                    self.session?.diagnostics.latestGenerationMetrics = build.metrics
                    self.retireTilesIfReplacementIsReady()
                    if let session = self.session {
                        self.updateDiagnostics(session)
                    }
                } catch is CancellationError {
                    _ = self.finishGeneration(id: plan.id, token: token)
                } catch {
                    _ = self.finishGeneration(id: plan.id, token: token)
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
        entity.components.set(OpacityComponent(opacity: Float(opacity)))
    }

    @discardableResult
    private func finishGeneration(id: LMTerrainTileID, token: UUID) -> Bool {
        guard generationTokens[id] == token else { return false }
        generationTokens.removeValue(forKey: id)
        generationTasks.removeValue(forKey: id)
        return true
    }

    private func retireTilesIfReplacementIsReady() {
        let activeIDs = Set(progressiveEntities.keys)
        let requestedIDs = Set(requestedPlans.keys)
        guard requestedIDs.isSubset(of: activeIDs),
              requestedPlans.allSatisfy({ progressivePlans[$0.key] == $0.value }) else {
            return
        }
        for id in activeIDs.subtracting(requestedIDs) {
            progressiveEntities.removeValue(forKey: id)?.removeFromParent()
            progressivePlans.removeValue(forKey: id)
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
        progressivePlans.removeAll(keepingCapacity: false)
        for entity in progressiveEntities.values {
            entity.removeFromParent()
        }
        progressiveEntities.removeAll(keepingCapacity: false)
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
        switch altitudeMeters {
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
