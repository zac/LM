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
    private var terrainRockField: Entity?
    private var heightField: Apollo11TerrainHeightField?
    private var albedoField: LMMeasuredAlbedoField?
    private var eagleTerrainPosition = LMVector3D.zero
    private var terrainDatumElevationMeters = 0.0
    private var progressiveEntities = [LMTerrainTileID: ModelEntity]()
    private var progressivePlans = [LMTerrainTileID: LMTerrainTilePlan]()
    private var requestedPlans = [LMTerrainTileID: LMTerrainTilePlan]()
    private var generationTasks = [LMTerrainTileID: Task<Void, Never>]()
    private var generationTokens = [LMTerrainTileID: UUID]()
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
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let heightField = try Apollo11TerrainResource.loadSourceBackedHeightField()
                let assembly = try await LMTerrainWorld.load()
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
                self.terrainEnvironment = assembly.worldRoot
                self.terrainSun = assembly.sun
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

        updateRockDetail(altitudeMeters: session.altitudeMeters)
        terrainSun?.shadow = LMTerrainWorld.missionShadow(
            altitudeMeters: session.altitudeMeters
        )

        let focus = terrainFocus(session)
        requestProgressiveTerrain(
            focusEastMeters: focus.y,
            focusNorthMeters: focus.x,
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
        guard let heightField, let terrainEnvironment else { return }
        let plans = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: heightField.spacingMeters
        ).focusedPlans(
            focusEastMeters: focusEastMeters,
            focusNorthMeters: focusNorthMeters,
            altitudeMeters: altitudeMeters
        )
        let nextPlans = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })
        guard nextPlans != requestedPlans else { return }
        requestedPlans = nextPlans

        for id in generationTasks.keys where nextPlans[id] == nil {
            generationTasks[id]?.cancel()
            generationTasks.removeValue(forKey: id)
            generationTokens.removeValue(forKey: id)
        }
        retireTilesIfReplacementIsReady()

        for plan in plans where progressiveEntities[plan.id] == nil
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
                        albedoField: self.albedoField
                    )
                    guard self.finishGeneration(id: plan.id, token: token),
                          !Task.isCancelled,
                          self.requestedPlans[plan.id] == plan,
                          let build else { return }
                    let entity = build.entity
                    terrainEnvironment.addChild(entity)
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
        guard requestedIDs.isSubset(of: activeIDs) else { return }
        for id in activeIDs.subtracting(requestedIDs) {
            progressiveEntities.removeValue(forKey: id)?.removeFromParent()
            progressivePlans.removeValue(forKey: id)
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
