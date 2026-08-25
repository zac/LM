import Foundation
import LMCore
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
}

/// Assembles the full-immersion exterior scene: nested near, medium, and far
/// terrain bands plus the mission sun.
@MainActor
enum LMTerrainWorld {
    /// Renderer-space exposure for the mission sun. RealityKit measures this
    /// in lux; 25,000 preserves the low-Sun relief without clipping the
    /// reflectance-calibrated terrain against a black immersive sky.
    nonisolated static let missionSunIlluminanceLux: Float = 25_000

    /// Covers the terminal-descent altitude range where the lander's cast
    /// shadow becomes a useful, physically grounded height cue.
    nonisolated static let missionShadowMaximumDistanceMeters: Float = 120

    /// A restrained texture-derived exposure floor keeps shadowed regolith
    /// readable in an unlit immersive sky while the mission sun still supplies
    /// the dominant directional relief. This is deliberately below 1 so it
    /// cannot flatten the low-Sun topography into an unlit texture.
    nonisolated static let regolithExposureFloor: Float = 0.08

    struct Assembly {
        let worldRoot: Entity
        let sun: DirectionalLight
        let manifest: LMTerrainManifest
        let nearAlbedoTexture: TextureResource
    }

    enum WorldError: Error, Equatable {
        case missingTile(String)
    }

    nonisolated static let nearFieldTileID = "near-field"
    nonisolated static let mediumFieldTileID = "medium-field"
    nonisolated static let farFieldTileID = "far-field"

    static func load(bundle: Bundle = .main) async throws -> Assembly {
        let manifest = try LMTerrainManifest.load(bundle: bundle)

        let worldRoot = Entity()
        worldRoot.name = "TerrainWorld"

        let nearTile = try requireTile(manifest, id: nearFieldTileID)
        let mediumTile = try requireTile(manifest, id: mediumFieldTileID)
        let farTile = try requireTile(manifest, id: farFieldTileID)
        // Each power-of-two-plus-one grid shares its inner boundary exactly
        // with the next denser tile. Punch nested square holes at those grid
        // lines so the bands neither overlap nor leave a geometric gap.
        let bands = [
            (tile: nearTile, holeHalfExtent: 0.0),
            (tile: mediumTile, holeHalfExtent: nearTile.extentMeters / 2.0),
            (tile: farTile, holeHalfExtent: mediumTile.extentMeters / 2.0),
        ]
        var nearAlbedoTexture: TextureResource?

        for (tile, hole) in bands {
            let heightURL = try resourceURL(bundle: bundle, file: tile.heightFile)
            let albedoURL = try resourceURL(bundle: bundle, file: tile.albedoFile)
            let heightMap = try LMTerrainHeightMap.load(contentsOf: heightURL)
            let grid = try LMTerrainMeshBuilder.grid(
                tile: tile,
                heightMap: heightMap,
                holeHalfExtentMeters: hole
            )
            let mesh = try LMTerrainMeshBuilder.mesh(from: grid)
            let texture = try await TextureResource(contentsOf: albedoURL)
            if tile.id == nearFieldTileID {
                nearAlbedoTexture = texture
            }
            let material = terrainMaterial(texture: texture)
            let model = ModelEntity(mesh: mesh, materials: [material])
            model.name = "Terrain-\(tile.id)"
            worldRoot.addChild(model)
        }

        let sun = DirectionalLight()
        sun.name = "MissionSun"
        sun.light.intensity = missionSunIlluminanceLux
        sun.shadow = DirectionalLightComponent.Shadow(
            shadowProjection: .automatic(
                maximumDistance: missionShadowMaximumDistanceMeters
            ),
            depthBias: 1
        )
        sun.orientation = LMFullDescentMapper.sunLightOrientation(from: manifest)
        worldRoot.addChild(sun)

        guard let nearAlbedoTexture else {
            throw WorldError.missingTile(nearFieldTileID)
        }
        return Assembly(
            worldRoot: worldRoot,
            sun: sun,
            manifest: manifest,
            nearAlbedoTexture: nearAlbedoTexture
        )
    }

    static func terrainMaterial(texture: TextureResource) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        let reflectance = MaterialParameters.Texture(texture)
        material.baseColor = .init(tint: .white, texture: reflectance)
        material.roughness = .init(floatLiteral: 0.96)
        material.metallic = .init(floatLiteral: 0)
        // RealityKit multiplies the emissive texture by this color. Be
        // explicit: the initializer's black default would erase the texture.
        material.emissiveColor = .init(color: .white, texture: reflectance)
        material.emissiveIntensity = regolithExposureFloor
        return material
    }

    static func worldTransform(for state: LMVehicleStateSnapshot?) -> Transform {
        guard let state else {
            return LMFullDescentMapper.worldTransform()
        }
        return LMFullDescentMapper().worldTransform(for: state)
    }

    private static func requireTile(
        _ manifest: LMTerrainManifest,
        id: String
    ) throws -> LMTerrainManifest.Tile {
        guard let tile = manifest.tile(id: id) else {
            throw WorldError.missingTile(id)
        }
        return tile
    }

    private static func resourceURL(bundle: Bundle, file: String) throws -> URL {
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
