import CoreGraphics
import Foundation
import LMCore
import Metal
import RealityKit
import simd

/// Full-immersion cockpit world mapping at 1:1 life scale.
///
/// The cockpit stays fixed around the user; the entire exterior world moves by
/// the inverse vehicle pose, so no artificial camera motion is ever applied.
/// Terrain entities live in world coordinates (+X north, +Y up, -Z east,
/// landing origin at the entity-space origin), and the world transform places
/// the ground directly below the user at the vehicle's altitude and heading.
struct LMFullDescentMapper: Equatable {
    /// Site-relative ENU position in RealityKit meters, 1:1 with LMCore.
    func position(from state: LMVehicleStateSnapshot) -> SIMD3<Float> {
        let si = state.positionMeters
        return SIMD3(Float(si.x), Float(si.z), Float(-si.y))
    }

    /// World-from-cockpit transform: inverse vehicle rotation about the
    /// vehicle position, so terrain below the LM stays below the user.
    func worldTransform(for state: LMVehicleStateSnapshot) -> Transform {
        let rotation = LMWorldMapper.attitudeOrientation(from: state.attitude)
        let inverse = rotation.inverse
        var transform = Transform()
        transform.scale = SIMD3<Float>(repeating: 1)
        transform.rotation = inverse
        transform.translation = inverse.act(-position(from: state))
        return transform
    }

    static func worldTransform(identityAt origin: SIMD3<Float> = .zero) -> Transform {
        var transform = Transform()
        transform.scale = SIMD3<Float>(repeating: 1)
        transform.rotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        transform.translation = -origin
        return transform
    }

    /// Mission sun direction in RealityKit coordinates (pointing toward the
    /// sun), derived from the manifest's ENU azimuth/elevation.
    static func sunDirection(from manifest: LMTerrainManifest) -> SIMD3<Float> {
        LMWorldMapper.attitudeDirection(from: manifest.sunDirectionENU)
    }

    /// Orientation whose -Z axis points from the sun toward the scene, the
    /// direction a RealityKit DirectionalLight illuminates along.
    static func sunLightOrientation(from manifest: LMTerrainManifest) -> simd_quatf {
        simd_quatf(from: SIMD3(0, 0, -1), to: -sunDirection(from: manifest))
    }

    /// Sun direction for an arbitrary horizon-frame direction. The manifest
    /// pins one instant; `LMLunarEphemeris` supplies the same two angles for
    /// any date, which is what lets mission lighting move with time instead of
    /// being a single baked-in constant.
    static func sunDirection(from angles: LMHorizonAngles) -> SIMD3<Float> {
        let elevation = angles.elevationDegrees * .pi / 180
        let azimuth = angles.azimuthDegreesClockwiseFromNorth * .pi / 180
        return LMWorldMapper.attitudeDirection(from: LMVector3D(
            x: cos(elevation) * cos(azimuth),
            y: cos(elevation) * sin(azimuth),
            z: sin(elevation)
        ))
    }

    static func sunLightOrientation(from angles: LMHorizonAngles) -> simd_quatf {
        simd_quatf(from: SIMD3(0, 0, -1), to: -sunDirection(from: angles))
    }
}

/// How the terrain is presented tonally.
///
/// `calibrated` is the long-standing look every capture baseline was measured
/// against: a flat exposure floor lifts every shadow so the whole surface sits
/// in a narrow mid-grey band. `photographic` removes that floor, fills shadows
/// with a faint directional earthshine instead, and exposes for the sunlit
/// highlights — the way a modern high-dynamic-range camera or a dark-adapted
/// eye actually sees a 4-to-8-percent-albedo surface under a black sky.
enum LMTerrainPresentationGrade: String, CaseIterable, Identifiable, Sendable {
    case calibrated
    case photographic

    var id: Self { self }

    var title: String {
        switch self {
        case .calibrated: "Calibrated"
        case .photographic: "Photographic"
        }
    }
}

/// Assembles the full-immersion exterior scene: nested near, medium, and far
/// terrain bands plus the mission sun.
@MainActor
enum LMTerrainWorld {
    /// Renderer-space exposure for the mission sun. RealityKit measures this
    /// in lux; 25,000 preserves the low-Sun relief without clipping the
    /// reflectance-calibrated terrain against a black immersive sky.
    ///
    /// This is the reference exposure, defined at `referenceSunElevationDegrees`.
    /// `missionSunIlluminance(elevationDegrees:)` is what the scene actually
    /// installs.
    nonisolated static let missionSunIlluminanceLux: Float = 25_000

    /// The elevation the reference exposure was tuned at: Eagle's touchdown.
    nonisolated static let referenceSunElevationDegrees = 10.689

    /// Ceiling for the low-Sun end of the exposure ramp, reached at about four
    /// degrees of elevation. Past that the surface is allowed to fall into the
    /// terminator instead of being pushed to a constant brightness, which is
    /// both what a camera does and what makes a sunrise read as a sunrise.
    nonisolated static let maximumMissionSunIlluminanceLux: Float = 60_000

    /// Illuminance for the mission sun at a given solar elevation.
    ///
    /// A full-immersion RealityKit scene has no camera exposure control, so the
    /// light's own intensity is the only exposure knob available. Holding it
    /// fixed was correct while the Sun was a single pinned direction, but flat
    /// ground receives the beam scaled by sin(elevation): three days after
    /// touchdown that is four times brighter, and by local noon five times,
    /// which clipped the surface to white as soon as the Sun became movable.
    ///
    /// Normalizing the product of illuminance and sin(elevation) holds sunlit
    /// ground at a constant exposure the way a metering camera would, while
    /// shadows, slopes, and crater relief keep their true relative contrast —
    /// the low-Sun drama comes from long shadows, not from a dim surface. At
    /// the reference elevation this returns exactly the pinned value, so
    /// mission-time renders are unchanged.
    nonisolated static func missionSunIlluminance(
        elevationDegrees: Double,
        grade: LMTerrainPresentationGrade = .calibrated
    ) -> Float {
        let reference = sin(referenceSunElevationDegrees * .pi / 180)
        let target = missionSunIlluminanceLux * Float(reference)
        let sine = Float(sin(max(elevationDegrees, 0) * .pi / 180))
        let scale = photographicSunIlluminanceScale(grade: grade)
        guard sine > 0 else { return maximumMissionSunIlluminanceLux * scale }
        return min(target / sine, maximumMissionSunIlluminanceLux) * scale
    }

    /// The photographic grade drops the flat exposure floor, which was
    /// contributing roughly half of every rendered level. The direct beam has
    /// to make that up for sunlit ground, which is exactly the trade a
    /// photographer makes: expose for the highlights and let the shadows go.
    nonisolated static func photographicSunIlluminanceScale(
        grade: LMTerrainPresentationGrade
    ) -> Float {
        switch grade {
        case .calibrated: 1
        case .photographic: 2.0
        }
    }

    /// Earthshine as a fraction of the direct beam.
    ///
    /// Physically this is nearer one part in ten thousand, which would render
    /// as pure black. What a long exposure or a dark-adapted eye actually
    /// resolves on the lunar night side is far more than the raw ratio implies,
    /// so this is deliberately a perceptual value: enough to keep shape in the
    /// shadows, far too little to compete with the Sun.
    nonisolated static let earthshineIlluminanceFraction: Float = 0.02

    /// Earth hangs nearly fixed over the near side and shows the Moon the
    /// opposite phase, so this peaks over a lunar night — which is precisely
    /// when a shadow needs the fill.
    nonisolated static func earthshineIlluminance(
        sunIlluminanceLux: Float,
        illuminatedFraction: Double,
        grade: LMTerrainPresentationGrade
    ) -> Float {
        guard grade == .photographic else { return 0 }
        return sunIlluminanceLux * earthshineIlluminanceFraction
            * Float(min(max(illuminatedFraction, 0), 1))
    }

    /// Sunlight reflected off Earth's oceans and atmosphere arrives noticeably
    /// cooler than direct sunlight.
    nonisolated static let earthshineColor = LMTerrainWorld.Color(
        red: 0.72,
        green: 0.80,
        blue: 1.0,
        alpha: 1
    )

    typealias Color = PhysicallyBasedMaterial.Color

    /// Presentation grade in force. Materials read the exposure floor from
    /// here, so changing it requires rebuilding resident tiles.
    static var presentationGrade: LMTerrainPresentationGrade = .calibrated

    /// The flat emissive lift applied to every terrain material. The
    /// photographic grade removes it so shadows can actually be dark.
    static var exposureFloor: Float {
        switch presentationGrade {
        case .calibrated: regolithExposureFloor
        case .photographic: 0
        }
    }

    /// Keep the terminal-descent shadow map tightly fitted around the lander.
    /// A 120 m fixed projection made each shadow texel several times larger
    /// than necessary during the final tens of meters and blurred the LM shape.
    nonisolated static let missionShadowMinimumDistanceMeters: Float = 12
    nonisolated static let missionShadowMaximumDistanceMeters: Float = 45

    /// A restrained texture-derived exposure floor keeps shadowed regolith
    /// readable in an unlit immersive sky while the mission sun still supplies
    /// the dominant directional relief. This is deliberately below 1 so it
    /// cannot flatten the low-Sun topography into an unlit texture.
    nonisolated static let regolithExposureFloor: Float = 0.08
    @MainActor private static var tileEdgeOpacityTextures = [Int: TextureResource]()

    struct Assembly {
        let worldRoot: Entity
        let sun: DirectionalLight
        /// Faint fill from the Earth's direction. Dark in the calibrated
        /// grade, where the flat exposure floor already lifts every shadow.
        let earthshine: DirectionalLight
        let manifest: LMTerrainManifest
        let nearAlbedoTexture: TextureResource
        let nearFieldEntity: ModelEntity
        let nearFieldGrid: LMTerrainMeshBuilder.VertexData
    }

    enum WorldError: Error, Equatable {
        case missingTile(String)
    }

    nonisolated static let nearFieldTileID = "near-field"
    nonisolated static let mediumFieldTileID = "medium-field"
    nonisolated static let farFieldTileID = "far-field"

    static func load(
        bundle: Bundle = .main,
        detailPipeline: LMTerrainDetailPipeline = Apollo11TerrainResource
            .detailPipeline
    ) async throws -> Assembly {
        let loadInterval = LMLunarTerrainTiming.begin("apollo-base-load")
        LMLunarTerrainTiming.memory("apollo-base-before")
        defer {
            LMLunarTerrainTiming.end(loadInterval)
            LMLunarTerrainTiming.memory("apollo-base-after")
        }
        async let terrainDetailPreparation: Void =
            Apollo11TerrainResource.prepareTerrainDetail(
                pipeline: detailPipeline
            )
        let manifest = try LMTerrainManifest.load(bundle: bundle)

        let worldRoot = Entity()
        worldRoot.name = "TerrainWorld"

        let preparation = Task.detached(priority: .userInitiated) {
            try prepareBaseBands(manifest: manifest, bundle: bundle)
        }
        let bands = try await withTaskCancellationHandler(
            operation: { try await preparation.value },
            onCancel: { preparation.cancel() }
        )
        try Task.checkCancellation()
        let nearGrid = bands[0].grid
        var nearAlbedoTexture: TextureResource?
        var nearFieldEntity: ModelEntity?

        for band in bands {
            try Task.checkCancellation()
            let tile = band.tile
            let grid = band.grid
            let albedoURL = try resourceURL(bundle: bundle, file: tile.albedoFile)
            let meshInterval = LMLunarTerrainTiming.begin("base-mesh-async")
            let mesh = try await LMTerrainMeshBuilder.meshAsync(from: grid)
            LMLunarTerrainTiming.end(meshInterval)
            let texture = try await TextureResource(
                contentsOf: albedoURL,
                options: terrainTextureCreateOptions(semantic: .color)
            )
            try Task.checkCancellation()
            if tile.id == nearFieldTileID {
                nearAlbedoTexture = texture
            }
            let material = terrainMaterial(texture: texture)
            let model = ModelEntity(mesh: mesh, materials: [material])
            model.name = "Terrain-\(tile.id)"
            worldRoot.addChild(model)
            if tile.id == nearFieldTileID {
                nearFieldEntity = model
            }
        }

        let sun = DirectionalLight()
        sun.name = "MissionSun"
        sun.light.intensity = missionSunIlluminance(
            elevationDegrees: manifest.sun.elevationDegrees
        )
        sun.shadow = missionShadow(altitudeMeters: nil)
        sun.orientation = LMFullDescentMapper.sunLightOrientation(from: manifest)
        worldRoot.addChild(sun)

        // Earthshine casts no shadows of its own: it is an area source two
        // degrees wide, so its own shadowing is far too soft to model with a
        // second shadow map, and stacking one would darken the very shadows it
        // exists to fill.
        let earthshine = DirectionalLight()
        earthshine.name = "Earthshine"
        earthshine.light.color = earthshineColor
        earthshine.light.intensity = 0
        earthshine.shadow = nil
        worldRoot.addChild(earthshine)

        guard let nearAlbedoTexture, let nearFieldEntity else {
            throw WorldError.missingTile(nearFieldTileID)
        }
        await terrainDetailPreparation
        return Assembly(
            worldRoot: worldRoot,
            sun: sun,
            earthshine: earthshine,
            manifest: manifest,
            nearAlbedoTexture: nearAlbedoTexture,
            nearFieldEntity: nearFieldEntity,
            nearFieldGrid: nearGrid
        )
    }

    /// Material for a fine clipmap tile that has baked its own appearance.
    ///
    /// The tile carries a resampled slice of the measured reflectance and a
    /// tangent-space normal map for the sub-triangle regolith, both addressed
    /// by tile-local UVs. RealityKit's PBR materials expose a single texture
    /// coordinate buffer, so baking per tile is what makes a normal map
    /// possible at all without giving up the measured albedo underneath it.
    @MainActor static func detailTerrainMaterial(
        _ detail: LMTerrainTileDetailTextures,
        plan: LMTerrainTilePlan
    ) async throws -> any Material {
        // Capture-only residency map: paint each progressive tile a flat color
        // keyed by its level and grid parity so a screenshot attributes every
        // rendered rectangle to one concrete tile. Never set for production or
        // interactive launches.
        if ProcessInfo.processInfo.arguments.contains(
            "--lunar-explorer-tile-tint=id"
        ) {
            // Keep the diagnostic palette independent of lighting and tone
            // mapping so all seven global LODs can be segmented unambiguously.
            var material = UnlitMaterial(applyPostProcessToneMap: false)
            let hue = 0.13 + Double(plan.id.level) * 0.23
            let parity = Double((plan.id.eastIndex & 1) + (plan.id.northIndex & 1))
            let tint = PhysicallyBasedMaterial.Color(
                hue: hue.truncatingRemainder(dividingBy: 1),
                saturation: 0.85,
                brightness: 0.45 + parity * 0.25,
                alpha: 1
            )
            material.color = .init(tint: tint)
            return material
        }
        guard let albedoImage = LMTerrainTileDetailBaker.image(
            from: detail.albedo,
            resolution: detail.resolution,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        ) else {
            throw WorldError.missingTile("tile detail textures")
        }
        let albedo = try await TextureResource(
            image: albedoImage,
            options: terrainTextureCreateOptions(semantic: .color)
        )
        var material = terrainMaterial(texture: albedo)
        // Repeatable Explorer captures can isolate the reflectance/geometry
        // path from tangent-space normal realization. This is deliberately an
        // opt-out launch diagnostic; production and interactive launches keep
        // the exact shipping material unless the explicit argument is present.
        if !ProcessInfo.processInfo.arguments.contains(
            "--lunar-explorer-normal-maps=off"
        ) {
            guard let normalImage = LMTerrainTileDetailBaker.image(
                from: detail.normal,
                resolution: detail.resolution,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            ) else {
                throw WorldError.missingTile("tile detail normal texture")
            }
            let normal = try await TextureResource(
                image: normalImage,
                options: terrainTextureCreateOptions(semantic: .normal)
            )
            material.normal = .init(texture: terrainTexture(normal))
        }
        // Keep every tile on the same opaque render path. Geometry, albedo,
        // and normals already converge to the exact rendered parent through
        // the full-width perimeter morph. A texture-opacity collar routed the
        // outer tiles through RealityKit's transparent pass and exposed them
        // as rectangular cards even where their sampled opacity was nearly 1.
        return material
    }

    @MainActor private static func tileEdgeOpacityTexture(
        resolution: Int,
        transitionEdges: LMTerrainTileEdges
    ) throws -> TextureResource? {
        guard !transitionEdges.isEmpty else { return nil }
        let key = (resolution << 8) | Int(transitionEdges.rawValue)
        if let texture = tileEdgeOpacityTextures[key] {
            return texture
        }
        guard let image = tileEdgeOpacityImage(
            resolution: resolution,
            transitionEdges: transitionEdges
        ) else {
            return nil
        }
        let texture = try TextureResource(
            image: image,
            options: TextureResource.CreateOptions(
                semantic: .scalar,
                mipmapsMode: .none
            )
        )
        tileEdgeOpacityTextures[key] = texture
        return texture
    }

    /// Fade a child tile into its measured parent through the same collar used
    /// by its procedural relief and albedo. This removes coplanar color/depth
    /// contention at the exact edge while keeping the parent available for a
    /// continuous transition between independently resident neighbors.
    nonisolated private static func tileEdgeOpacityImage(
        resolution: Int,
        transitionEdges: LMTerrainTileEdges
    ) -> CGImage? {
        let collar = max(
            1.0,
            Double(resolution) * LMTerrainTileDetailBaker.edgeFadeFraction
        )
        var values = [UInt8](repeating: 255, count: resolution * resolution)
        for row in 0..<resolution {
            for column in 0..<resolution {
                var distances = [Int]()
                distances.reserveCapacity(4)
                if transitionEdges.contains(.west) {
                    distances.append(column)
                }
                if transitionEdges.contains(.east) {
                    distances.append(resolution - 1 - column)
                }
                if transitionEdges.contains(.north) {
                    distances.append(row)
                }
                if transitionEdges.contains(.south) {
                    distances.append(resolution - 1 - row)
                }
                let distance = Double(distances.min() ?? resolution)
                let normalized = min(max(distance / collar, 0), 1)
                let fade = normalized * normalized * (3 - 2 * normalized)
                values[row * resolution + column] = UInt8((fade * 255).rounded())
            }
        }
        let data = Data(values)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: resolution,
            height: resolution,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: resolution,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    static func terrainMaterial(texture: TextureResource) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        if ProcessInfo.processInfo.arguments.contains(
            "--lunar-explorer-terrain-reflectance=constant"
        ) {
            material.baseColor = .init(tint: .init(white: 0.25, alpha: 1))
            material.roughness = .init(floatLiteral: 0.96)
            material.metallic = .init(floatLiteral: 0)
            material.emissiveColor = .init(color: .init(white: 0.25, alpha: 1))
            material.emissiveIntensity = exposureFloor
            return material
        }
        let reflectance = terrainTexture(texture)
        material.baseColor = .init(tint: .white, texture: reflectance)
        material.roughness = .init(floatLiteral: 0.96)
        material.metallic = .init(floatLiteral: 0)
        // RealityKit multiplies the emissive texture by this color. Be
        // explicit: the initializer's black default would erase the texture.
        material.emissiveColor = .init(color: .white, texture: reflectance)
        material.emissiveIntensity = exposureFloor
        return material
    }

    /// Terrain is commonly viewed at a grazing angle with radically different
    /// texel densities in adjacent measured bands. Make the sampling contract
    /// explicit so the dense NAC texture minifies through a full mip chain and
    /// blends smoothly toward the WAC parent instead of reading as a sharp
    /// rectangular card at regional scale.
    static func terrainTextureCreateOptions(
        semantic: TextureResource.Semantic
    ) -> TextureResource.CreateOptions {
        TextureResource.CreateOptions(
            semantic: semantic,
            mipmapsMode: .allocateAndGenerateAll
        )
    }

    static func terrainTexture(
        _ texture: TextureResource
    ) -> MaterialParameters.Texture {
        MaterialParameters.Texture(texture, sampler: terrainTextureSampler())
    }

    static func terrainTextureSampler() -> MaterialParameters.Texture.Sampler {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.maxAnisotropy = 8
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        return MaterialParameters.Texture.Sampler(descriptor)
    }

    nonisolated static func missionShadowDistance(altitudeMeters: Double?) -> Float {
        guard let altitudeMeters else { return missionShadowMaximumDistanceMeters }
        let fitted = Float(max(0, altitudeMeters)) * 1.35 + 8
        return min(
            missionShadowMaximumDistanceMeters,
            max(missionShadowMinimumDistanceMeters, fitted)
        )
    }

    nonisolated static func missionShadow(
        altitudeMeters: Double?
    ) -> DirectionalLightComponent.Shadow {
        DirectionalLightComponent.Shadow(
            shadowProjection: .automatic(
                maximumDistance: missionShadowDistance(altitudeMeters: altitudeMeters)
            ),
            depthBias: 1
        )
    }

    static func worldTransform(for state: LMVehicleStateSnapshot?) -> Transform {
        guard let state else {
            return LMFullDescentMapper.worldTransform()
        }
        return LMFullDescentMapper().worldTransform(for: state)
    }

    struct PreparedBaseBand: Sendable {
        let tile: LMTerrainManifest.Tile
        let grid: LMTerrainMeshBuilder.VertexData
    }

    /// CPU-only source decoding and the exact existing parent collars.
    /// No RealityKit resources or mutable presentation state cross this boundary.
    nonisolated static func prepareBaseBands(
        manifest: LMTerrainManifest, bundle: Bundle = .main
    ) throws -> [PreparedBaseBand] {
        try Task.checkCancellation()
        let gridInterval = LMLunarTerrainTiming.begin("apollo-base-grids")
        defer { LMLunarTerrainTiming.end(gridInterval) }
        let nearTile = try requireTile(manifest, id: nearFieldTileID)
        let mediumTile = try requireTile(manifest, id: mediumFieldTileID)
        let farTile = try requireTile(manifest, id: farFieldTileID)
        let nearHeightMap = try LMTerrainHeightMap.load(
            contentsOf: resourceURL(bundle: bundle, file: nearTile.heightFile)
        )
        let mediumHeightMap = try LMTerrainHeightMap.load(
            contentsOf: resourceURL(bundle: bundle, file: mediumTile.heightFile)
        )
        let farHeightMap = try LMTerrainHeightMap.load(
            contentsOf: resourceURL(bundle: bundle, file: farTile.heightFile)
        )

        // Each power-of-two-plus-one grid shares its inner boundary exactly
        // with the next denser tile. Punch nested square holes at those grid
        // lines so the bands neither overlap nor leave a geometric gap.
        let farGrid = try LMTerrainMeshBuilder.grid(
            tile: farTile,
            heightMap: farHeightMap,
            holeHalfExtentMeters: mediumTile.extentMeters / 2
        )
        try Task.checkCancellation()
        let rawMediumGrid = try LMTerrainMeshBuilder.grid(
            tile: mediumTile,
            heightMap: mediumHeightMap,
            holeHalfExtentMeters: nearTile.extentMeters / 2
        )
        let mediumGrid = try LMTerrainMeshBuilder.morphToParent(
            child: rawMediumGrid,
            parent: farGrid,
            parentTile: farTile,
            childHalfExtentMeters: mediumTile.extentMeters / 2
        )
        try Task.checkCancellation()
        let rawNearGrid = try LMTerrainMeshBuilder.grid(
            tile: nearTile,
            heightMap: nearHeightMap
        )
        let nearGrid = try LMTerrainMeshBuilder.morphToParent(
            child: rawNearGrid,
            parent: mediumGrid,
            parentTile: mediumTile,
            childHalfExtentMeters: nearTile.extentMeters / 2
        )
        LMLunarTerrainTiming.memory("apollo-grids-after")
        try Task.checkCancellation()
        return [
            .init(tile: nearTile, grid: nearGrid),
            .init(tile: mediumTile, grid: mediumGrid),
            .init(tile: farTile, grid: farGrid),
        ]
    }

    nonisolated private static func requireTile(
        _ manifest: LMTerrainManifest,
        id: String
    ) throws -> LMTerrainManifest.Tile {
        guard let tile = manifest.tile(id: id) else {
            throw WorldError.missingTile(id)
        }
        return tile
    }

    nonisolated private static func resourceURL(bundle: Bundle, file: String) throws -> URL {
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        guard let url = bundle.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "Terrain"
        ) ?? bundle.url(forResource: name, withExtension: ext) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }
}
