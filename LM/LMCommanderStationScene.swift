import AGC
import LMCore
import OSLog
import RealityKit
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

    let commanderEntryAnchor = AnchorEntity(.head)
    let root = Entity()
    let lunarWorld = Entity()
    let acaHandle = ModelEntity()
    let rodSwitch = ModelEntity()
    let attitudeModeSwitch = ModelEntity()
    let landingPointCalledAngleMarker = ModelEntity()
    let dskyFaceRoot = Entity()

    private let fdaiMount = Entity()
    private let dskyDisplayMount = Entity()
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
    private var terrainEnvironment: Entity?
    private var progressiveTerrainEntities = [LMTerrainTileID: ModelEntity]()
    private var requestedTerrainTileIDs = Set<LMTerrainTileID>()
    private var terrainRefreshTask: Task<Void, Never>?
    private var artistCabin: Entity?
    private var lastVehicleState: LMVehicleStateSnapshot?
    private var dskyKeyEntitiesByRawValue = [Int: ModelEntity]()
    private var dskyKeyRestPositions = [Int: SIMD3<Float>]()
    private var dskyKeyResetTasks = [Int: Task<Void, Never>]()
    private let acaNeutralPosition = LMCommanderStationGeometry.acaPivotPositionMeters
    private let rodNeutralPosition = LMCommanderStationGeometry.rodPivotPositionMeters
    private let attitudeModeAutomaticPosition =
        LMCommanderStationGeometry.attitudeHoldPivotPositionMeters

    init() {
        commanderEntryAnchor.name = "Commander entry head anchor"
        commanderEntryAnchor.anchoring.trackingMode = .once
        root.name = "LM Commander Station"
        lunarWorld.name = "Lunar World"
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
        // world space. Offsetting the cabin by the optical datum puts the
        // calibrated CDR design eye at the captured head origin without
        // head-locking the cabin during flight.
        root.position = -landingPointDesignator.commanderEyeMeters
        commanderEntryAnchor.addChild(root)

        root.addChild(proceduralCabin)
        buildCabin()
        buildLandingPointCalledAngleMarker()
        buildPhysicalDSKY()
        buildPhysicalControls()
        buildProvisionalSurface()
        buildDustCloud()

        root.addChild(lunarWorld)
        root.addChild(fdaiMount)
    }

    func mountFDAI(_ entity: Entity) {
        guard entity.parent == nil else { return }
        entity.name = "Commander FDAI"
        entity.position = .zero
        entity.orientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
        entity.scale = SIMD3(repeating: 0.00058)
        fdaiMount.addChild(entity)
    }

    func mountDSKYDisplay(_ entity: Entity) {
        guard entity.parent == nil else { return }
        entity.name = "Live Apollo 11 DSKY display"
        entity.position = SIMD3(0, 0, 0.012)
        entity.scale = SIMD3(repeating: 0.00035)
        dskyDisplayMount.addChild(entity)
    }

    func apply(_ state: LMVehicleStateSnapshot?) {
        guard let state else { return }
        lastVehicleState = state
        let surfaceElevation = terrainHeightField?.relativeElevation(
            eastMeters: state.positionMeters.y,
            northMeters: state.positionMeters.x
        ) ?? 0
        lunarWorld.transform = Transform(matrix: mapper.lunarWorldMatrix(
            from: state,
            surfaceElevationMeters: Double(surfaceElevation)
        ))
        requestProgressiveTerrain(around: state)
    }

    func loadApollo11Terrain() async throws {
        let heightField = try Apollo11TerrainResource.loadSourceBackedHeightField()
        let terrain = try await LMTerrainWorld.load().worldRoot
        terrainHeightField = heightField
        terrainEnvironment = terrain
        provisionalTerrain.removeFromParent()
        lunarWorld.addChild(terrain)
        apply(lastVehicleState)
    }

    private func requestProgressiveTerrain(around state: LMVehicleStateSnapshot) {
        guard let heightField = terrainHeightField, let terrainEnvironment else { return }
        let plans = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: heightField.spacingMeters
        ).focusedPlans(
            focusEastMeters: state.positionMeters.y,
            focusNorthMeters: state.positionMeters.x,
            altitudeMeters: state.altitudeMeters
        )
        let requestedIDs = Set(plans.map(\.id))
        guard requestedIDs != requestedTerrainTileIDs else { return }
        requestedTerrainTileIDs = requestedIDs
        terrainRefreshTask?.cancel()
        terrainRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var replacements = [LMTerrainTileID: ModelEntity]()
            for plan in plans {
                guard !Task.isCancelled else { return }
                if let existing = self.progressiveTerrainEntities[plan.id] {
                    replacements[plan.id] = existing
                } else {
                    do {
                        if let entity = try await Apollo11TerrainResource
                            .makeProgressiveTileEntity(heightField: heightField, plan: plan) {
                            replacements[plan.id] = entity
                        }
                    } catch {
                        self.logger.error(
                            "Terrain tile L\(plan.id.level) E\(plan.id.eastIndex) N\(plan.id.northIndex) failed: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            }
            guard !Task.isCancelled,
                  self.requestedTerrainTileIDs == requestedIDs else { return }
            for (id, entity) in self.progressiveTerrainEntities where replacements[id] == nil {
                entity.removeFromParent()
            }
            for (id, entity) in replacements where self.progressiveTerrainEntities[id] == nil {
                terrainEnvironment.addChild(entity)
            }
            self.progressiveTerrainEntities = replacements
        }
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
        root.addChild(cabin)
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
        let surfaceElevation = terrainHeightField?.relativeElevation(
            eastMeters: state.positionMeters.y,
            northMeters: state.positionMeters.x
        ) ?? 0
        dustCloud.position = mapper.realityPosition(from: LMVector3D(
            x: state.positionMeters.x,
            y: state.positionMeters.y,
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
        root.addChild(landingPointCalledAngleMarker)
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

        root.addChild(dskyFaceRoot)
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
        dskyKeyEntitiesByRawValue.first { _, keyEntity in
            keyEntity === entity
        }.flatMap { DSKYKeyCode(rawValue: $0.key) }
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
        root.addChild(acaHandle)

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
        root.addChild(rodSwitch)
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
        root.addChild(attitudeModeSwitch)
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
        root.addChild(legend)
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

        let sun = Entity()
        sun.components.set(DirectionalLightComponent(color: .white, intensity: 42_000))
        sun.orientation = simd_quatf(angle: -.pi / 3, axis: SIMD3(1, 0.25, 0))
        lunarWorld.addChild(sun)
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
