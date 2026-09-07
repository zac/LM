import CoreGraphics
import Foundation
import OSLog
import RealityKit
import UIKit

/// A coarse map is always present. Fine patches replace exactly the same sphere
/// triangles, so a late/cancelled fetch cannot leave a hole or a depth overlap.
@MainActor
final class LMLunarGlobeImagery {
    private weak var entity: ModelEntity?
    var realizationAllowed: (@MainActor () -> Bool)?
    private let baseMesh: MeshResource
    private let pyramid: LMLunarImageryPyramid
    private let radius: Double
    private let front: LMSelenographicCoordinate
    private let patches = Entity()
    private var store: LMLunarImageryTileStore?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var requested = [LMLunarImageryPyramid.Tile]()
    private var requestedOffline = false
    private var meshData: LMLunarGlobeResource.GlobeMeshData?
    private var textures = [String: TextureResource]()
    private var access = [String: Int]()
    private var clock = 0
    private var multiplier = 1.0
    private let logger = Logger(subsystem: "io.positron.LM", category: "LunarImagery")

    init(entity: ModelEntity, pyramid: LMLunarImageryPyramid, radius: Double,
         front: LMSelenographicCoordinate) {
        self.entity = entity
        self.baseMesh = entity.model!.mesh
        self.pyramid = pyramid
        self.radius = radius
        self.front = front
        patches.name = "Verified WAC imagery patches"
        entity.addChild(patches)
    }

    static func isEnabled(arguments: [String]) -> Bool {
        if arguments.contains("--lunar-globe-tiled-imagery") { return true }
        return !arguments.contains("--lunar-explorer-capture") && !arguments.contains {
            $0.hasPrefix("--lunar-globe-texture-tier=") || $0.hasPrefix("--lunar-globe-texture-override=")
        }
    }

    nonisolated static func selectedTiles(in pyramid: LMLunarImageryPyramid, ppd: Int,
                                         latitude: Double, longitude: Double) -> [LMLunarImageryPyramid.Tile] {
        let columns = 360 * ppd / pyramid.tileSize, rows = 180 * ppd / pyramid.tileSize
        let centerColumn = Int(floor((longitude + 180) * Double(ppd) / Double(pyramid.tileSize)))
        // Match the base TextureResource sampler: image rows run opposite UV V.
        let centerRow = min(max(Int(floor((90 + latitude) * Double(ppd) / Double(pyramid.tileSize))), 0), rows - 1)
        // A larger longitude band near the poles preserves context; the resident
        // texture count remains bounded and uncovered areas keep their coarse map.
        let halfColumns = abs(latitude) > 70 ? 2 : 1
        let rowRange = max(0, centerRow - 1)...min(rows - 1, centerRow + 1)
        let columnSet = Set((-halfColumns...halfColumns).map { ((centerColumn + $0) % columns + columns) % columns })
        return pyramid.tiles.filter { $0.ppd == ppd && rowRange.contains($0.row) && columnSet.contains($0.column) }
    }

    func update(width: Double, coordinate: LMSelenographicCoordinate, offline: Bool) {
        guard let entity else { cancel(); return }
        if width >= 680_000 || width <= 120_000 {
            guard !requested.isEmpty || !patches.children.isEmpty else { return }
            cancel()
            requested = []
            patches.children.removeAll()
            if var model = entity.model { model.mesh = baseMesh; entity.model = model }
            return
        }
        guard width < 600_000 || !requested.isEmpty else { return }
        let ppd = width < 320_000 || (requested.first?.ppd == 64 && width < 350_000) ? 64 : 32
        let wanted = Self.selectedTiles(in: pyramid, ppd: ppd,
            latitude: coordinate.latitudeDegrees, longitude: coordinate.longitudeDegrees)
        guard wanted != requested || requestedOffline != offline else { return }
        let previous = task
        cancel()
        requested = wanted
        requestedOffline = offline
        let token = UUID()
        generation = token
        task = Task { [weak self] in
            guard let self else { return }
            do {
                await previous?.value
                try Task.checkCancellation()
                if self.store == nil {
                    let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("LunarImagery-\(self.pyramid.version)")
                    self.store = try LMLunarImageryTileStore(pyramid: self.pyramid, directory: directory)
                }
                guard let store = self.store else { return }
                if self.meshData == nil {
                    let radius = self.radius, front = self.front
                    self.meshData = await Task.detached(priority: .utility) {
                        LMLunarGlobeResource.globeMeshData(radiusMeters: radius, frontCoordinate: front)
                    }.value
                }
                guard let data = self.meshData else { return }
                var loaded = [(LMLunarImageryPyramid.Tile, TextureResource)]()
                for tile in wanted {
                    try Task.checkCancellation()
                    let texture: TextureResource
                    if let cached = self.textures[tile.id] { texture = cached }
                    else {
                        let pixels = try await store.pixels(for: tile, offline: offline)
                        let side = self.pyramid.tilePixelWidth
                        let preparation = Task.detached(priority: .utility) { try Self.image(pixels, side: side) }
                        let image = try await withTaskCancellationHandler(operation: { try await preparation.value },
                            onCancel: { preparation.cancel() })
                        try Task.checkCancellation()
                        try await self.waitForImportSlot()
                        texture = try LMLunarTerrainTiming.measure("globe-tile-upload") {
                            try TextureResource.generate(from: image, withName: tile.sha256,
                                options: LMTerrainWorld.terrainTextureCreateOptions(semantic: .color))
                        }
                        self.textures[tile.id] = texture
                    }
                    self.clock += 1; self.access[tile.id] = self.clock
                    loaded.append((tile, texture))
                    self.trimTextures(keeping: Set(wanted.map(\.id)))
                    await Task.yield()
                }
                try Task.checkCancellation()
                let pyramid = self.pyramid
                let preparation = Task.detached(priority: .utility) {
                    Self.partition(data, tiles: wanted, pyramid: pyramid)
                }
                let partition = await preparation.value
                try Task.checkCancellation()
                var realized = [ModelEntity]()
                for (tile, texture) in loaded {
                    guard let patch = partition.patches[tile.id] else { continue }
                    try await self.waitForImportSlot()
                    let mesh = try Self.realize(patch, name: tile.id)
                    var material = UnlitMaterial(applyPostProcessToneMap: false)
                    material.color = .init(tint: self.tint, texture: Self.texture(texture))
                    realized.append(ModelEntity(mesh: mesh, materials: [material]))
                    await Task.yield()
                }
                try await self.waitForImportSlot()
                let remainder = try Self.realize(partition.remainder, name: "WAC coarse remainder")
                try await self.waitForImportSlot()
                try Task.checkCancellation()
                guard self.generation == token, let entity = self.entity, var model = entity.model else { return }
                // One actor turn publishes complementary ownership. No transparent
                // endpoints, mesh offsets, skirts, or ShaderGraph materials.
                model.mesh = remainder
                entity.model = model
                self.patches.children.removeAll()
                for patch in realized { self.patches.addChild(patch) }
                self.setRadiance(self.multiplier)
                self.logger.info("Imagery ready ppd=\(ppd) tiles=\(realized.count) cached=\(self.textures.count)")
                LMLunarTerrainTiming.memory("globe-tiles-ready")
            } catch is CancellationError {
            } catch {
                self.logger.error("Imagery stays on its previous verified map: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Tile imports must not contend with the first terrain import. Task.yield()
    /// can resume repeatedly inside one frame; wait for actual scene updates.
    private func waitForImportSlot() async throws {
        repeat {
            try Task.checkCancellation()
            if let scene = entity?.scene {
                let (updates, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
                let subscription = scene.subscribe(to: SceneEvents.Update.self) { _ in continuation.yield(()) }
                let timeout = Task {
                    try? await Task.sleep(for: .seconds(1))
                    continuation.finish()
                }
                defer { subscription.cancel(); timeout.cancel(); continuation.finish() }
                for await _ in updates { break }
            } else {
                try await Task.sleep(for: .milliseconds(16))
            }
        } while realizationAllowed?() == false
        try Task.checkCancellation()
    }

    func suspend() {
        cancel()
        requested = []
    }

    func cancel() {
        task?.cancel()
        // Keep the cancelled task so the next request can drain its source reads.
        generation = UUID()
    }

    func setRadiance(_ value: Double) {
        multiplier = value
        for child in patches.children {
            guard var model = child.components[ModelComponent.self],
                  var material = model.materials.first as? UnlitMaterial else { continue }
            material.color.tint = tint
            model.materials[0] = material
            child.components.set(model)
        }
    }

    private var tint: UIColor {
        UIColor(cgColor: CGColor(colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
            components: [multiplier, multiplier, multiplier, 1])!)
    }

    private func trimTextures(keeping ids: Set<String>) {
        while textures.count > 16 {
            guard let oldest = access.filter({ !ids.contains($0.key) }).min(by: { $0.value < $1.value })?.key else { break }
            textures.removeValue(forKey: oldest); access.removeValue(forKey: oldest)
        }
    }

    nonisolated static func image(_ pixels: Data, side: Int) throws -> CGImage {
        guard pixels.count == side * side else { throw CocoaError(.fileReadCorruptFile) }
        var rgba = Data(count: pixels.count * 4)
        pixels.withUnsafeBytes { source in
            rgba.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) in
                for i in 0..<pixels.count {
                    let value = source[i]
                    destination[4 * i] = value; destination[4 * i + 1] = value
                    destination[4 * i + 2] = value; destination[4 * i + 3] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: rgba as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: side * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return image
    }

    struct Partition: Sendable {
        let remainder: LMLunarGlobeResource.GlobeMeshData
        let patches: [String: LMLunarGlobeResource.GlobeMeshData]
    }

    nonisolated static func partition(_ data: LMLunarGlobeResource.GlobeMeshData,
        tiles: [LMLunarImageryPyramid.Tile], pyramid: LMLunarImageryPyramid) -> Partition {
        var owned = Set<Int>(), patches = [String: LMLunarGlobeResource.GlobeMeshData]()
        for tile in tiles {
            let columns = 360 * tile.ppd / pyramid.tileSize, rows = 180 * tile.ppd / pyramid.tileSize
            let firstX = tile.column * 256 / columns, lastX = (tile.column + 1) * 256 / columns
            let geometryRow = rows - 1 - tile.row
            let firstY = geometryRow * 128 / rows, lastY = (geometryRow + 1) * 128 / rows
            var indices = [UInt32]()
            for y in firstY..<lastY {
                for x in firstX..<lastX {
                    let cell = y * 256 + x
                    owned.insert(cell)
                    indices.append(contentsOf: data.indices[(cell * 6)..<(cell * 6 + 6)])
                }
            }
            let vertices = Array(Set(indices)).sorted()
            let mapping = Dictionary(uniqueKeysWithValues: vertices.enumerated().map { ($0.element, UInt32($0.offset)) })
            let uv = vertices.map { index -> SIMD2<Float> in
                let source = data.textureCoordinates[Int(index)] * SIMD2(Float(360 * tile.ppd), Float(180 * tile.ppd))
                return (source - SIMD2(Float(tile.column * pyramid.tileSize), Float(geometryRow * pyramid.tileSize))
                    + SIMD2(repeating: Float(pyramid.gutter))) / Float(pyramid.tilePixelWidth)
            }
            patches[tile.id] = .init(positions: vertices.map { data.positions[Int($0)] },
                normals: vertices.map { data.normals[Int($0)] }, textureCoordinates: uv,
                indices: indices.map { mapping[$0]! })
        }
        var remainder = [UInt32]()
        for cell in 0..<(256 * 128) where !owned.contains(cell) {
            remainder.append(contentsOf: data.indices[(cell * 6)..<(cell * 6 + 6)])
        }
        return .init(remainder: .init(positions: data.positions, normals: data.normals,
            textureCoordinates: data.textureCoordinates, indices: remainder), patches: patches)
    }

    private static func realize(_ data: LMLunarGlobeResource.GlobeMeshData, name: String) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = .init(data.positions); descriptor.normals = .init(data.normals)
        descriptor.textureCoordinates = .init(data.textureCoordinates)
        descriptor.primitives = .triangles(data.indices)
        return try LMLunarTerrainTiming.measure("globe-tile-mesh-upload") { try MeshResource.generate(from: [descriptor]) }
    }

    private static func texture(_ resource: TextureResource) -> MaterialParameters.Texture {
        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .linear; sampler.magFilter = .linear; sampler.mipFilter = .linear
        sampler.maxAnisotropy = 8
        sampler.sAddressMode = .clampToEdge; sampler.tAddressMode = .clampToEdge
        return .init(resource, sampler: MaterialParameters.Texture.Sampler(sampler))
    }
}
