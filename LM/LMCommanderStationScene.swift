import AGC
import LMCore
import OSLog
import RealityKit
import SwiftUI
import UIKit
import simd

/// A focused, life-size approximation of the commander's powered-descent station.
///
/// This milestone intentionally models only the load-bearing sight picture:
/// forward triangular windows, the commander's instrument shelf, side structure,
/// overhead structure, and the lunar exterior. Geometry is procedural so layout
/// can be iterated on-device before committing to a heavyweight cabin asset.
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
    private let acaNeutralPosition = SIMD3<Float>(-0.49, 0.50, -0.37)
    private let rodNeutralPosition = SIMD3<Float>(0.43, 0.58, -0.49)
    private let attitudeModeAutomaticPosition = SIMD3<Float>(0.48, 0.78, -0.675)
    private let panelInstrumentOrientation = simd_quatf(
        angle: -.pi / 10,
        axis: SIMD3(1, 0, 0)
    )

    init() {
        commanderEntryAnchor.name = "Commander entry head anchor"
        commanderEntryAnchor.anchoring.trackingMode = .once
        root.name = "LM Commander Station"
        lunarWorld.name = "Lunar World"
        fdaiMount.name = LMCockpitAssetContract.Node.fdaiMount.rawValue
        dskyFaceRoot.name = LMCockpitAssetContract.Node.dskyMount.rawValue
        dskyDisplayMount.name = LMCockpitAssetContract.Node.dskyDisplayMount.rawValue
        proceduralCabin.name = "Procedural cabin fallback"
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
        entity.position = SIMD3(-0.30, 0.88, -0.675)
        entity.orientation = panelInstrumentOrientation
        entity.scale = SIMD3(repeating: 0.00058)
        fdaiMount.addChild(entity)
    }

    func mountDSKYDisplay(_ entity: Entity) {
        guard entity.parent == nil else { return }
        entity.name = "Live Apollo 11 DSKY display"
        entity.position = SIMD3(
            LMDSKYGeometry.displayCenterMeters.x,
            LMDSKYGeometry.displayCenterMeters.y,
            0.012
        )
        entity.scale = SIMD3(repeating: 0.00035)
        dskyDisplayMount.addChild(entity)
    }

    func apply(_ state: LMVehicleStateSnapshot?) {
        guard let state else { return }
        lastVehicleState = state
        let surfaceElevation = terrainHeightField?.relativeElevation(
            eastMeters: state.positionMeters.x,
            northMeters: state.positionMeters.y
        ) ?? 0
        lunarWorld.transform = Transform(matrix: mapper.lunarWorldMatrix(
            from: state,
            surfaceElevationMeters: Double(surfaceElevation)
        ))
        requestProgressiveTerrain(around: state)
    }

    func loadApollo11Terrain() async throws {
        let heightField = try Apollo11TerrainResource.loadHeightField()
        let terrain = try await Apollo11TerrainResource.makeEntity(
            heightField: heightField
        )
        terrainHeightField = heightField
        terrainEnvironment = terrain
        provisionalTerrain.removeFromParent()
        lunarWorld.addChild(terrain)
        apply(lastVehicleState)
    }

    private func requestProgressiveTerrain(around state: LMVehicleStateSnapshot) {
        guard let heightField = terrainHeightField, let terrainEnvironment else { return }
        let plans = LMProgressiveTerrainPlanner(
            sourceSpacingMeters: heightField.manifest.meshSpacingMeters
        ).focusedPlans(
            focusEastMeters: state.positionMeters.x,
            focusNorthMeters: state.positionMeters.y,
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
        acaHandle.position = acaNeutralPosition + controlMapper.visualACATranslation(for: input)
        acaHandle.orientation = simd_quatf(
            angle: Float(input.roll) * -0.18,
            axis: SIMD3(0, 0, 1)
        ) * simd_quatf(
            angle: Float(input.pitch) * 0.18,
            axis: SIMD3(1, 0, 0)
        )
    }

    func setRODVisual(_ position: PoweredDescentSession.RODSwitchPosition) {
        rodSwitch.position = rodNeutralPosition
            + SIMD3(0, controlMapper.visualRODTranslation(for: position), 0)
    }

    func setAttitudeHoldVisual(_ isAttitudeHold: Bool) {
        attitudeModeSwitch.position = attitudeModeAutomaticPosition
            + SIMD3(0, isAttitudeHold ? 0.028 : 0, 0)
        attitudeModeSwitch.orientation = simd_quatf(
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
            eastMeters: state.positionMeters.x,
            northMeters: state.positionMeters.y
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

        addBox(size: SIMD3(1.36, 0.44, 0.09), position: SIMD3(0, 0.83, -0.72), material: panel, name: "Panel 1")
        addBox(size: SIMD3(1.62, 0.08, 0.32), position: SIMD3(0, 0.59, -0.51), material: dark, name: "Glare shield")
        addBox(size: SIMD3(1.75, 0.08, 1.50), position: SIMD3(0, 0.10, -0.05), material: dark, name: "Cabin floor")
        addBox(size: SIMD3(0.12, 1.80, 1.35), position: SIMD3(-0.92, 1.02, -0.12), material: dark, name: "Commander sidewall")
        addBox(size: SIMD3(0.12, 1.80, 1.35), position: SIMD3(0.92, 1.02, -0.12), material: dark, name: "LMP sidewall")
        addBox(size: SIMD3(1.75, 0.12, 1.30), position: SIMD3(0, 1.98, -0.12), material: dark, name: "Overhead")

        // These rails follow the source-calibrated oblique window plane rather
        // than a facade-parallel approximation. The LMP aperture is mirrored
        // only for the procedural fallback; the artist asset contract carries
        // separate flight-station transforms.
        buildForwardWindowFrames(material: aluminum)

        buildLandingPointDesignator()
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
        for elevation in 0..<60 {
            segments.append((
                landingPointDesignator.point(elevationDegrees: Double(elevation), on: pane),
                landingPointDesignator.point(elevationDegrees: Double(elevation + 1), on: pane)
            ))
        }
        for elevation in LMLandingPointDesignator.elevationDegrees {
            let center = landingPointDesignator.point(elevationDegrees: Double(elevation), on: pane)
            let halfWidth: Float = elevation.isMultiple(of: 10) ? 0.030
                : elevation.isMultiple(of: 5) ? 0.019 : 0.010
            segments.append((center - SIMD3(halfWidth, 0, 0), center + SIMD3(halfWidth, 0, 0)))
        }
        for elevation in LMLandingPointDesignator.horizontalScaleElevations {
            for azimuth in -10..<10 {
                segments.append((
                    landingPointDesignator.point(
                        elevationDegrees: Double(elevation),
                        azimuthDegrees: Double(azimuth),
                        on: pane
                    ),
                    landingPointDesignator.point(
                        elevationDegrees: Double(elevation),
                        azimuthDegrees: Double(azimuth + 1),
                        on: pane
                    )
                ))
            }
            for azimuth in LMLandingPointDesignator.azimuthDegrees {
                let center = landingPointDesignator.point(
                    elevationDegrees: Double(elevation),
                    azimuthDegrees: Double(azimuth),
                    on: pane
                )
                let halfHeight: Float = azimuth.isMultiple(of: 5) ? 0.016 : 0.009
                segments.append((center - SIMD3(0, halfHeight, 0), center + SIMD3(0, halfHeight, 0)))
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

        dskyFaceRoot.position = SIMD3(-0.07, 0.735, -0.665)
        dskyFaceRoot.orientation = panelInstrumentOrientation

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
            size: SIMD3(0.24, 0.08, 0.28),
            position: SIMD3(acaNeutralPosition.x, 0.365, acaNeutralPosition.z),
            material: housing,
            name: "ACA pedestal"
        )
        acaHandle.name = "Attitude Controller Assembly"
        acaHandle.model = ModelComponent(
            mesh: .generateCylinder(height: 0.25, radius: 0.028),
            materials: [handleMaterial]
        )
        acaHandle.position = acaNeutralPosition
        acaHandle.components.set(InputTargetComponent())
        acaHandle.components.set(HoverEffectComponent())
        acaHandle.components.set(CollisionComponent(shapes: [
            .generateBox(size: SIMD3(0.14, 0.30, 0.14))
        ]))
        root.addChild(acaHandle)

        addBox(
            size: SIMD3(0.18, 0.07, 0.18),
            position: SIMD3(rodNeutralPosition.x, 0.49, rodNeutralPosition.z),
            material: housing,
            name: "ROD switch pedestal"
        )
        rodSwitch.name = "Rate of Descent switch"
        rodSwitch.model = ModelComponent(
            mesh: .generateBox(size: SIMD3(0.10, 0.10, 0.08)),
            materials: [switchMaterial]
        )
        rodSwitch.position = rodNeutralPosition
        rodSwitch.components.set(InputTargetComponent())
        rodSwitch.components.set(HoverEffectComponent())
        rodSwitch.components.set(CollisionComponent(shapes: [
            .generateBox(size: SIMD3(0.16, 0.18, 0.14))
        ]))
        root.addChild(rodSwitch)

        attitudeModeSwitch.name = "Mode Control attitude hold"
        attitudeModeSwitch.model = ModelComponent(
            mesh: .generateBox(size: SIMD3(0.08, 0.13, 0.055)),
            materials: [switchMaterial]
        )
        attitudeModeSwitch.position = attitudeModeAutomaticPosition
        attitudeModeSwitch.components.set(InputTargetComponent())
        attitudeModeSwitch.components.set(HoverEffectComponent())
        attitudeModeSwitch.components.set(CollisionComponent(shapes: [
            .generateBox(size: SIMD3(0.16, 0.20, 0.12))
        ]))
        setAttitudeHoldVisual(false)
        root.addChild(attitudeModeSwitch)
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
