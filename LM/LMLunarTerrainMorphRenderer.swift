import Foundation
import Metal
import RealityKit
import simd

/// Transient opaque resources. One command buffer updates both geometry and
/// appearance; RealityKit waits for that buffer before consuming either.
@MainActor
final class LMLunarTerrainMorphRenderer {
    typealias Build = Apollo11TerrainResource.ProgressiveTileEntityBuild
    struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
        var tangent: SIMD3<Float>
        var bitangent: SIMD3<Float>
        var uv: SIMD2<Float>
    }
    struct Source {
        let color: any MTLTexture
        let normal: any MTLTexture
        let plan: LMTerrainTilePlan
    }
    struct Entry {
        let mesh: LowLevelMesh
        let first: any MTLBuffer
        let last: any MTLBuffer
        let count: UInt32
    }
    struct Appearance {
        let color: LowLevelTexture
        let normal: LowLevelTexture
        let a: Source
        let b: Source
        let aMap: SIMD4<Float>
        let bMap: SIMD4<Float>
    }
    struct Submission {
        let command: any MTLCommandBuffer
        let completion: AsyncStream<Bool>

        func complete() async throws {
            for await succeeded in completion {
                guard succeeded else { throw GPUError.commandFailed }
                return
            }
            throw GPUError.commandFailed
        }
    }
    let root = Entity()
    private(set) var entities = [(Entity, LMTerrainTilePlan)]()
    private(set) var entries = [Entry]()
    private(set) var appearances = [Appearance]()
    private let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let vertices: any MTLComputePipelineState
    private let appearance: any MTLComputePipelineState

    init(morph: LMLunarTerrainMorph,
         from: [(LMTerrainTilePlan, Build)], to: [(LMTerrainTilePlan, Build)]) async throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw GPUError.unavailable }
        self.device = device
        self.queue = queue
        let library = try device.makeDefaultLibrary(bundle: .main)
        guard let vf = library.makeFunction(name: "lunarMorphVertices"),
              let af = library.makeFunction(name: "lunarMorphAppearance") else { throw GPUError.unavailable }
        vertices = try await device.makeComputePipelineState(function: vf)
        appearance = try await device.makeComputePipelineState(function: af)
        var oldSources = [LMTerrainTileID: Source](), newSources = [LMTerrainTileID: Source]()
        func owner(_ builds: [(LMTerrainTilePlan, Build)], for plan: LMTerrainTilePlan) throws -> (LMTerrainTilePlan, Build) {
            guard let value = builds.filter({
                $0.0.sampleSpacingMeters >= plan.sampleSpacingMeters &&
                abs($0.0.centerEastMeters - plan.centerEastMeters) < $0.0.sizeMeters / 2 &&
                abs($0.0.centerNorthMeters - plan.centerNorthMeters) < $0.0.sizeMeters / 2
            }).min(by: { $0.0.sampleSpacingMeters < $1.0.sampleSpacingMeters }) else { throw GPUError.missingAppearance }
            return value
        }
        for tile in morph.tiles where !tile.end.indices.isEmpty {
            try Task.checkCancellation()
            let oldOwner = try? owner(from, for: tile.plan), newOwner = try? owner(to, for: tile.plan)
            guard let a = oldOwner ?? newOwner, let b = newOwner ?? oldOwner else { throw GPUError.missingAppearance }
            guard let template = (to.first { $0.0.id == tile.plan.id } ?? from.first { $0.0.id == tile.plan.id })?.1 else {
                throw GPUError.missingAppearance
            }
            if !tile.changesGeometry && tile.end.indices == template.mesh.indices && a.0 == b.0 {
                let entity = template.entity.clone(recursive: true)
                root.addChild(entity)
                entities.append((entity, tile.plan))
                continue
            }
            func source(_ item: (LMTerrainTilePlan, Build),
                        cache: inout [LMTerrainTileID: Source]) async throws -> Source {
                if let cached = cache[item.0.id] { return cached }
                let material = item.1.entity.model?.materials.first as? PhysicallyBasedMaterial
                func texture(_ resource: TextureResource?, fallback: [UInt8], color: Bool) async throws -> any MTLTexture {
                    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: resource?.pixelFormat ?? (color ? .rgba8Unorm_srgb : .rgba8Unorm),
                        width: resource?.width ?? 1, height: resource?.height ?? 1,
                        mipmapped: (resource?.mipmapLevelCount ?? 1) > 1)
                    descriptor.storageMode = .shared
                    descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
                    guard let texture = device.makeTexture(descriptor: descriptor) else { throw GPUError.unavailable }
                    if let resource {
                        // Preserve the actual uploaded color conversion, normal
                        // encoding, orientation and mips used by the endpoint.
                        try await resource.copy(to: texture)
                    } else {
                        fallback.withUnsafeBytes { raw in
                            texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                                            withBytes: raw.baseAddress!, bytesPerRow: 4)
                        }
                    }
                    return texture
                }
                let value = Source(color: try await texture(material?.baseColor.texture?.resource,
                        fallback: [64, 64, 64, 255], color: true),
                    normal: try await texture(material?.normal.texture?.resource,
                        fallback: [128, 128, 255, 255], color: false), plan: item.0)
                cache[item.0.id] = value
                return value
            }
            let resource: MeshResource
            if tile.changesGeometry {
                let first = Self.vertexData(tile.start)
                func endpoint(_ mesh: LMProgressiveTerrainMeshData) -> [SIMD4<Float>] {
                    mesh.positions.indices.map { SIMD4(mesh.normals[$0], mesh.positions[$0].y) }
                }
                func buffer(_ data: [SIMD4<Float>]) throws -> any MTLBuffer {
                    guard let buffer = data.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!,
                        length: $0.count, options: .storageModeShared) }) else { throw GPUError.unavailable }
                    return buffer
                }
                var descriptor = LowLevelMesh.Descriptor()
                descriptor.vertexCapacity = first.count
                descriptor.indexCapacity = tile.end.indices.count
                descriptor.indexType = .uint32
                descriptor.vertexAttributes = [
                    .init(semantic: .position, format: .float3, offset: MemoryLayout<Vertex>.offset(of: \.position)!),
                    .init(semantic: .normal, format: .float3, offset: MemoryLayout<Vertex>.offset(of: \.normal)!),
                    .init(semantic: .tangent, format: .float3, offset: MemoryLayout<Vertex>.offset(of: \.tangent)!),
                    .init(semantic: .bitangent, format: .float3, offset: MemoryLayout<Vertex>.offset(of: \.bitangent)!),
                    .init(semantic: .uv0, format: .float2, offset: MemoryLayout<Vertex>.offset(of: \.uv)!)
                ]
                descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride)]
                let mesh = try LowLevelMesh(descriptor: descriptor)
                mesh.withUnsafeMutableBytes(bufferIndex: 0) { output in
                    first.withUnsafeBytes { output.copyMemory(from: $0) }
                }
                mesh.withUnsafeMutableIndices { output in
                    tile.end.indices.withUnsafeBytes { output.copyMemory(from: $0) }
                }
                var minimum = SIMD3<Float>(repeating: .infinity), maximum = SIMD3<Float>(repeating: -.infinity)
                for point in tile.start.positions + tile.end.positions {
                    minimum = simd_min(minimum, point)
                    maximum = simd_max(maximum, point)
                }
                mesh.parts.replaceAll([.init(indexCount: tile.end.indices.count, topology: .triangle,
                                             bounds: .init(min: minimum, max: maximum))])
                entries.append(.init(mesh: mesh, first: try buffer(endpoint(tile.start)),
                                     last: try buffer(endpoint(tile.end)), count: UInt32(first.count)))
                resource = try await MeshResource(from: mesh)
            } else {
                var descriptor = MeshDescriptor(name: "Static lunar arrival ownership")
                descriptor.positions = .init(tile.start.positions)
                descriptor.normals = .init(tile.start.normals)
                descriptor.tangents = .init(tile.start.tangents)
                descriptor.bitangents = .init(tile.start.bitangents)
                descriptor.textureCoordinates = .init(tile.start.textureCoordinates)
                descriptor.primitives = .triangles(tile.start.indices)
                resource = try MeshResource.generate(from: [descriptor])
            }
            let materials: [any Material]
            // A region's appearance is deterministic for a fixed plan. Retain
            // its existing material when only geometry or ownership changed.
            if (a.0 == b.0 || ProcessInfo.processInfo.arguments.contains("--lunar-explorer-tile-tint=id")),
               let original = template.entity.model?.materials {
                materials = original
            } else {
                let firstSource = try await source(a, cache: &oldSources)
                let lastSource = try await source(b, cache: &newSources)
                let resolution = max(firstSource.color.width, lastSource.color.width, firstSource.normal.width, lastSource.normal.width)
                func outputTexture(_ format: MTLPixelFormat) throws -> LowLevelTexture {
                    var descriptor = LowLevelTexture.Descriptor()
                    descriptor.textureType = .type2D
                    descriptor.pixelFormat = format
                    descriptor.width = resolution
                    descriptor.height = resolution
                    descriptor.depth = 1
                    descriptor.arrayLength = 1
                    descriptor.mipmapLevelCount = Int(floor(log2(Double(resolution)))) + 1
                    descriptor.textureUsage = [.shaderRead, .shaderWrite]
                    return try LowLevelTexture(descriptor: descriptor)
                }
                // Match the native endpoint format. The shader still mixes in
                // linear light; the sRGB target encodes only the final result.
                let color = try outputTexture(.rgba8Unorm_srgb)
                let normal = try outputTexture(.rgba8Unorm)
                appearances.append(.init(color: color, normal: normal,
                    a: firstSource, b: lastSource,
                    aMap: Self.textureMap(from: tile.plan, to: a.0),
                    bMap: Self.textureMap(from: tile.plan, to: b.0)))
                // Initialize the current backing texture before RealityKit
                // creates its resource. Registering an empty texture and then
                // replacing it can expose that empty first backing for a frame.
                try await submit(weight: 0, meshes: [], textures: [appearances.last!]).complete()
                let colorResource = try await TextureResource(from: color)
                let normalResource = try await TextureResource(from: normal)
                var material = LMTerrainWorld.terrainMaterial(texture: colorResource)
                if !ProcessInfo.processInfo.arguments.contains("--lunar-explorer-normal-maps=off") {
                    material.normal = .init(texture: LMTerrainWorld.terrainTexture(normalResource))
                }
                materials = [material]
            }
            let entity = ModelEntity(mesh: resource, materials: materials)
            entity.name = "Lunar terrain arrival"
            root.addChild(entity)
            entities.append((entity, tile.plan))
        }
        // Meshes were initialized through their CPU buffers; each appearance
        // was initialized before registration with RealityKit above.
    }

    static func vertexData(_ mesh: LMProgressiveTerrainMeshData) -> [Vertex] {
        mesh.positions.indices.map { i in
            Vertex(position: mesh.positions[i], normal: mesh.normals[i],
                   tangent: mesh.tangents[i], bitangent: mesh.bitangents[i],
                   uv: mesh.textureCoordinates.isEmpty ? .zero : mesh.textureCoordinates[i])
        }
    }

    /// UVs already include the shared sampling gutter. Keep that convention
    /// when mapping a child to a coarser endpoint's baked texture.
    static func textureMap(from child: LMTerrainTilePlan, to parent: LMTerrainTilePlan) -> SIMD4<Float> {
        let scale = Float(child.sizeMeters / parent.sizeMeters)
        let east = Float((child.centerEastMeters - child.sizeMeters / 2 -
                          parent.centerEastMeters + parent.sizeMeters / 2) / parent.sizeMeters)
        let south = Float((parent.centerNorthMeters + parent.sizeMeters / 2 -
                           child.centerNorthMeters - child.sizeMeters / 2) / parent.sizeMeters)
        let gutter = Float(LMTerrainTileDetailBaker.samplingGutterTexels)
        let content = Float(LMTerrainTileDetailBaker.resolution - 1)
        let total = Float(LMTerrainTileDetailBaker.renderingResolution - 1)
        return SIMD4(scale, scale, (gutter * (1 - scale) + content * east) / total,
                     (gutter * (1 - scale) + content * south) / total)
    }

    @discardableResult
    func update(weight: Float) throws -> Submission {
        try submit(weight: weight, meshes: entries, textures: appearances)
    }

    private func submit(weight: Float, meshes: [Entry], textures: [Appearance]) throws -> Submission {
        guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { throw GPUError.unavailable }
        var weight = min(1, max(0, weight))
        encoder.setComputePipelineState(vertices)
        for entry in meshes {
            var count = entry.count
            encoder.setBuffer(entry.first, offset: 0, index: 0)
            encoder.setBuffer(entry.last, offset: 0, index: 1)
            // X/Z and UVs are immutable. Read them from the existing mesh;
            // endpoint buffers need only normal.xyz and elevation.w.
            encoder.setBuffer(entry.mesh.read(bufferIndex: 0, using: command), offset: 0, index: 5)
            encoder.setBuffer(entry.mesh.replace(bufferIndex: 0, using: command), offset: 0, index: 2)
            encoder.setBytes(&weight, length: 4, index: 3)
            encoder.setBytes(&count, length: 4, index: 4)
            encoder.dispatchThreads(.init(width: Int(count), height: 1, depth: 1),
                                    threadsPerThreadgroup: .init(width: 64, height: 1, depth: 1))
        }
        encoder.setComputePipelineState(appearance)
        var mipmaps = [any MTLTexture]()
        for entry in textures {
            var aMap = entry.aMap, bMap = entry.bMap
            let color = entry.color.replace(using: command), normal = entry.normal.replace(using: command)
            for (index, texture) in [entry.a.color, entry.b.color, entry.a.normal, entry.b.normal, color, normal].enumerated() {
                encoder.setTexture(texture, index: index)
            }
            encoder.setBytes(&aMap, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.setBytes(&bMap, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            encoder.setBytes(&weight, length: 4, index: 2)
            encoder.dispatchThreads(.init(width: color.width, height: color.height, depth: 1),
                                    threadsPerThreadgroup: .init(width: 8, height: 8, depth: 1))
            mipmaps += [color, normal]
        }
        encoder.endEncoding()
        guard let blit = command.makeBlitCommandEncoder() else { throw GPUError.unavailable }
        for texture in mipmaps { blit.generateMipmaps(for: texture) }
        blit.endEncoding()
        let (completion, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        command.addCompletedHandler { buffer in
            continuation.yield(buffer.status == .completed)
            continuation.finish()
        }
        command.commit()
        return Submission(command: command, completion: completion)
    }

    enum GPUError: Error { case unavailable, missingAppearance, commandFailed }
}
