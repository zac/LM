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

    /// Orientation whose -Z axis points from the scene toward the sun, the
    /// direction a RealityKit DirectionalLight illuminates along.
    static func sunLightOrientation(from manifest: LMTerrainManifest) -> simd_quatf {
        simd_quatf(from: SIMD3(0, 0, -1), to: -sunDirection(from: manifest))
    }
}

/// Assembles the full-immersion exterior scene: near-field and horizon terrain
/// tiles, the mission sun, and a faint ambient floor so shadowed regolith
/// never goes fully black on device.
@MainActor
enum LMTerrainWorld {
    struct Assembly {
        let worldRoot: Entity
        let sun: DirectionalLight
        let manifest: LMTerrainManifest
    }

    enum WorldError: Error, Equatable {
        case missingTile(String)
    }

    nonisolated static let nearFieldTileID = "near-field"
    nonisolated static let horizonTileID = "horizon"

    static func load(bundle: Bundle = .main) async throws -> Assembly {
        let manifest = try LMTerrainManifest.load(bundle: bundle)

        let worldRoot = Entity()
        worldRoot.name = "TerrainWorld"

        let nearTile = try requireTile(manifest, id: nearFieldTileID)
        let horizonTile = try requireTile(manifest, id: horizonTileID)
        // Punch the near field out of the horizon ring so the two tiles never
        // overlap; the horizon resumes one post spacing beyond the near edge.
        let holeExtent = nearTile.extentMeters / 2.0 + horizonTile.postSpacingMeters

        for (tile, hole) in [(nearTile, 0.0), (horizonTile, holeExtent)] {
            let heightURL = try resourceURL(bundle: bundle, file: tile.heightFile)
            let albedoURL = try resourceURL(bundle: bundle, file: tile.albedoFile)
            let heightMap = try LMTerrainHeightMap.load(contentsOf: heightURL)
            let grid = try LMTerrainMeshBuilder.grid(
                tile: tile,
                heightMap: heightMap,
                holeExtentMeters: hole
            )
            let mesh = try LMTerrainMeshBuilder.mesh(from: grid)
            let texture = try await TextureResource(contentsOf: albedoURL)
            var material = SimpleMaterial(color: .white, isMetallic: false)
            material.color = SimpleMaterial.BaseColor(tint: .white, texture: .init(texture))
            let model = ModelEntity(mesh: mesh, materials: [material])
            model.name = "Terrain-\(tile.id)"
            worldRoot.addChild(model)
        }

        let sun = DirectionalLight()
        sun.name = "MissionSun"
        sun.light.intensity = 25_000
        sun.orientation = LMFullDescentMapper.sunLightOrientation(from: manifest)
        worldRoot.addChild(sun)

        return Assembly(worldRoot: worldRoot, sun: sun, manifest: manifest)
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
