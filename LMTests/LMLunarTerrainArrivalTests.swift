@testable import LunarMap
import Foundation
import CoreGraphics
import Metal
import RealityKit
import Testing
import simd
@testable import LM

@Suite("Lunar terrain arrival")
struct LMLunarTerrainArrivalTests {
    func tile(level: Int, spacing: Double, fine: Bool) -> LMLunarTerrainMeshTile {
        let plan = LMTerrainTilePlan(id: .init(level: level, eastIndex: 0, northIndex: 0),
                                    centerEastMeters: 2, centerNorthMeters: 2, sizeMeters: 4,
                                    sampleSpacingMeters: spacing, containsProceduralSubresolution: fine)
        let side = Int(4 / spacing) + 1
        var positions = [SIMD3<Float>](), indices = [UInt32]()
        for row in 0..<side {
            for column in 0..<side {
                let e = Double(column) * spacing, n = 4 - Double(row) * spacing
                // A saddle makes bilinear interpolation fail against triangles.
                let residual = fine ? 0.12 * sin(e * .pi / 2) * sin(n * .pi / 2) : 0
                positions.append(SIMD3(Float(n - 2), Float(e * n / 20 + residual), Float(2 - e)))
                if row < side - 1 && column < side - 1 {
                    let nw = UInt32(row * side + column), ne = nw + 1, sw = nw + UInt32(side)
                    indices += [nw, ne, sw, ne, sw + 1, sw]
                }
            }
        }
        return .init(plan: plan, mesh: .init(positions: positions,
            normals: Array(repeating: SIMD3(0, 1, 0), count: positions.count), tangents: [], bitangents: [],
            addedReliefNormalDistribution: .flat, textureCoordinates: [], indices: indices))
    }

    @Test func commonRefinementMatchesBothTriangleEndpointsAndContact() throws {
        let coarse = LMLunarTerrainMeshSnapshot(tiles: [tile(level: 0, spacing: 2, fine: false)])
        let fine = LMLunarTerrainMeshSnapshot(tiles: [tile(level: 1, spacing: 0.5, fine: true)])
        for (before, after) in [(coarse, fine), (fine, coarse)] {
            let morph = try LMLunarTerrainMorph(from: before, to: after)
            for weight: Float in [0, 0.1, 0.5, 0.9, 1] {
                let displayed = morph.snapshot(weight: weight)
                for i in 0..<40 {
                    let east = 0.07 + Double(i % 8) * 0.49, north = 0.13 + Double(i / 8) * 0.73
                    let a = try #require(before.sample(east: east, north: north)).elevation
                    let b = try #require(after.sample(east: east, north: north)).elevation
                    let expected = a + (b - a) * weight
                    let contact = try #require(displayed.sample(east: east, north: north)).elevation
                    let ray = try #require(displayed.raycast(origin: SIMD3(Float(north), 2, Float(-east)),
                                                            direction: SIMD3(0, -1, 0)))
                    #expect(abs(contact - expected) < 0.000001)
                    #expect(abs(ray.position.y - contact) < 0.000001)
                }
                // Native coarse posts never acquire the fine residual.
                for east in [0.0, 2, 4] {
                    for north in [0.0, 2, 4] {
                        let a = try #require(coarse.sample(east: east, north: north)).elevation
                        #expect(displayed.sample(east: east, north: north)?.elevation == a)
                    }
                }
            }
            // Fine ownership must remove every covered parent triangle.
            #expect(morph.tiles.first { $0.plan.id.level == 0 }?.mesh.indices.isEmpty == true)
        }
    }

    @Test func interruptedMorphCanStartFromTheDisplayedTriangles() throws {
        let coarse = LMLunarTerrainMeshSnapshot(tiles: [tile(level: 0, spacing: 2, fine: false)])
        let fine = LMLunarTerrainMeshSnapshot(tiles: [tile(level: 1, spacing: 0.5, fine: true)])
        let first = try LMLunarTerrainMorph(from: coarse, to: fine).snapshot(weight: 0.37)
        let restarted = try LMLunarTerrainMorph(from: first, to: coarse).snapshot(weight: 0)
        for i in 0..<30 {
            let east = 0.1 + Double(i % 6) * 0.61, north = 0.2 + Double(i / 6) * 0.71
            let a = try #require(first.sample(east: east, north: north)).elevation
            let b = try #require(restarted.sample(east: east, north: north)).elevation
            #expect(abs(a - b) < 0.000001)
        }
    }

    @Test func hiddenParentRefinementDoesNotRequireADynamicRenderMesh() throws {
        let original = tile(level: 0, spacing: 0.5, fine: false)
        func replacingPositions(_ mesh: LMProgressiveTerrainMeshData, _ positions: [SIMD3<Float>]) -> LMProgressiveTerrainMeshData {
            .init(positions: positions, normals: mesh.normals, tangents: mesh.tangents,
                  bitangents: mesh.bitangents, addedReliefNormalDistribution: .flat,
                  textureCoordinates: mesh.textureCoordinates, indices: mesh.indices)
        }
        let coarseMesh = replacingPositions(original.mesh, original.mesh.positions.map { SIMD3($0.x * 2, 0, $0.z * 2) })
        let coarse = LMLunarTerrainMeshTile(plan: .init(id: original.plan.id,
            centerEastMeters: 4, centerNorthMeters: 4, sizeMeters: 8,
            sampleSpacingMeters: 1, containsProceduralSubresolution: false), mesh: coarseMesh)
        let originalFine = tile(level: 1, spacing: 0.5, fine: true)
        let finePositions = originalFine.mesh.positions.map { point in
            let e = 2 - point.z, n = point.x + 2
            let height: Float = e == 0 || e == 4 || n == 0 || n == 4 ? 0 : 0.12 * sin(e * .pi / 4) * sin(n * .pi / 4)
            return SIMD3(point.x, height, point.z)
        }
        let fineMesh = replacingPositions(originalFine.mesh, finePositions)
        let fine = LMLunarTerrainMeshTile(plan: originalFine.plan, mesh: fineMesh)
        let morph = try LMLunarTerrainMorph(from: .init(tiles: [coarse]), to: .init(tiles: [fine, coarse]))
        let parent = try #require(morph.tiles.first { $0.plan.id == coarse.plan.id })
        #expect(!parent.mesh.indices.isEmpty)
        #expect(parent.endpoints.start != parent.endpoints.end)
        #expect(!parent.changesGeometry)
    }

    @Test @MainActor func gpuVerticesMatchContactAndAppearanceBlendsInLinearLight() async throws {
        let a = tile(level: 0, spacing: 2, fine: false), b = tile(level: 1, spacing: 0.5, fine: true)
        let morph = try LMLunarTerrainMorph(from: .init(tiles: [a]), to: .init(tiles: [b]))
        func build(_ tile: LMLunarTerrainMeshTile, base: UInt8) async throws -> Apollo11TerrainResource.ProgressiveTileEntityBuild {
            var color = [UInt8](), normal = [UInt8]()
            for row in 0..<8 {
                for _ in 0..<8 {
                    let c = base + UInt8(row * 8)
                    color += [c, c, c, 255]
                    normal += [128, 128, 255, 255]
                }
            }
            let detail = LMTerrainTileDetailTextures(resolution: 8, albedo: color, normal: normal)
            let material = try await LMTerrainWorld.detailTerrainMaterial(detail, plan: tile.plan)
            return .init(entity: ModelEntity(mesh: .generatePlane(width: 1, depth: 1), materials: [material]), mesh: tile.mesh,
                metrics: .init(meshMilliseconds: 0, detailMilliseconds: 0, realizationMilliseconds: 0,
                               detailModelID: "fixture", detailCacheHit: false))
        }
        let before = try await build(a, base: 32), after = try await build(b, base: 128)
        let renderer = try await LMLunarTerrainMorphRenderer(morph: morph,
            from: [(a.plan, before)], to: [(b.plan, after)])
        let entry = try #require(renderer.entries.first)
        let appearance = try #require(renderer.appearances.first)
        // Retaining only source level zero must preserve uploaded pixels; the
        // existing checks below compare all weights and both north/south rows.
        #expect(appearance.a.color.mipmapLevelCount == 1)
        #expect(appearance.b.normal.mipmapLevelCount == 1)
        #expect(appearance.color.read().mipmapLevelCount == 4)
        let fine = try #require(morph.tiles.first { $0.plan.id.level == 1 })
        // The first resource must already contain the displayed endpoint,
        // before any replacement command is submitted after registration.
        for (weight, submit): (Float, Bool) in [(0, false), (0, true), (0.25, true), (0.5, true), (1, true)] {
            if submit {
                let submission = try renderer.update(weight: weight)
                try await submission.complete()
                #expect(submission.command.status == .completed)
            }
            let displayed = fine.displayed(weight: weight)
            entry.mesh.withUnsafeBytes(bufferIndex: 0) { raw in
                let vertices = raw.bindMemory(to: LMLunarTerrainMorphRenderer.Vertex.self)
                for index in fine.mesh.positions.indices {
                    #expect(vertices[index].position.vector == displayed.position(at: index))
                    #expect(simd_length(vertices[index].normal.vector - displayed.normal(at: index)) < 0.000001)
                }
            }
            let texture = appearance.color.read()
            let device = texture.device
            let queue = try #require(device.makeCommandQueue())
            let copy = try #require(queue.makeCommandBuffer())
            let blit = try #require(copy.makeBlitCommandEncoder())
            let buffer = try #require(device.makeBuffer(length: 256 * 8, options: .storageModeShared))
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0, y: 0, z: 0),
                      sourceSize: .init(width: 8, height: 8, depth: 1), to: buffer, destinationOffset: 0,
                      destinationBytesPerRow: 256, destinationBytesPerImage: 256 * 8)
            blit.endEncoding()
            copy.commit()
            copy.waitUntilCompleted()
            #expect(copy.status == .completed)
            #expect(texture.pixelFormat == .rgba8Unorm_srgb)
            let values = buffer.contents().bindMemory(to: UInt8.self, capacity: 256 * 8)
            func linear(_ byte: Float) -> Float {
                let v = byte / 255
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            func uploaded(_ texture: any MTLTexture, row: Int) -> Float {
                var bytes = [UInt8](repeating: 0, count: 4)
                bytes.withUnsafeMutableBytes { raw in
                    texture.getBytes(raw.baseAddress!, bytesPerRow: 4,
                        from: MTLRegionMake2D(0, row, 1, 1), mipmapLevel: 0)
                }
                return linear(Float(bytes[0]))
            }
            // Compare actual uploaded endpoints, including color management.
            // Both resource paths must preserve the same northern row.
            let an = uploaded(appearance.a.color, row: 0), bn = uploaded(appearance.b.color, row: 0)
            let asouth = uploaded(appearance.a.color, row: 7), bs = uploaded(appearance.b.color, row: 7)
            let expectedNorth = an + (bn - an) * weight
            let expectedSouth = asouth + (bs - asouth) * weight
            func encoded(_ value: Float) -> Float {
                (value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055) * 255
            }
            #expect(abs(Float(values[0]) - encoded(expectedNorth)) <= 0.6)
            #expect(abs(Float(values[7 * 256]) - encoded(expectedSouth)) <= 0.6)
        }
    }

    @Test @MainActor func alternatingOwnersRetainBothSourcePlanVariants() async throws {
        let base = tile(level: 0, spacing: 1, fine: false)
        func parent(fine: Bool) -> LMLunarTerrainMeshTile {
            .init(plan: .init(id: base.plan.id, centerEastMeters: 4, centerNorthMeters: 4,
                             sizeMeters: 8, sampleSpacingMeters: 2, containsProceduralSubresolution: fine),
                  mesh: .init(positions: base.mesh.positions.map { SIMD3($0.x * 2, $0.y, $0.z * 2) },
                              normals: base.mesh.normals, tangents: [], bitangents: [],
                              addedReliefNormalDistribution: .flat, textureCoordinates: [], indices: base.mesh.indices))
        }
        func child(east: Int, north: Int) -> LMLunarTerrainMeshTile {
            let value = tile(level: 1, spacing: 0.5, fine: true)
            return .init(plan: .init(id: .init(level: 1, eastIndex: east, northIndex: north),
                                    centerEastMeters: 2 + Double(east * 4), centerNorthMeters: 2 + Double(north * 4),
                                    sizeMeters: 4, sampleSpacingMeters: 0.5, containsProceduralSubresolution: true),
                         mesh: value.mesh)
        }
        let a = parent(fine: false), b = parent(fine: true)
        let before = [child(east: 0, north: 0), child(east: 1, north: 1), a]
        let after = [child(east: 1, north: 0), child(east: 0, north: 1), b]
        func builds(_ tiles: [LMLunarTerrainMeshTile]) async throws -> [(LMTerrainTilePlan, Apollo11TerrainResource.ProgressiveTileEntityBuild)] {
            var result = [(LMTerrainTilePlan, Apollo11TerrainResource.ProgressiveTileEntityBuild)]()
            for tile in tiles {
                let value: UInt8 = tile.plan.containsProceduralSubresolution ? 192 : 32
                let detail = LMTerrainTileDetailTextures(resolution: 8,
                    albedo: Array(repeating: [value, value, value, 255], count: 64).flatMap { $0 },
                    normal: Array(repeating: [UInt8(128), 128, 255, 255], count: 64).flatMap { $0 })
                let material = try await LMTerrainWorld.detailTerrainMaterial(detail, plan: tile.plan)
                result.append((tile.plan, .init(entity: ModelEntity(mesh: .generatePlane(width: 1, depth: 1), materials: [material]),
                    mesh: tile.mesh, metrics: .init(meshMilliseconds: 0, detailMilliseconds: 0, realizationMilliseconds: 0,
                                                   detailModelID: "fixture", detailCacheHit: false))))
            }
            return result
        }
        let old = try await builds(before), new = try await builds(after)
        let morph = try LMLunarTerrainMorph(from: .init(tiles: before), to: .init(tiles: after))
        let renderer = try await LMLunarTerrainMorphRenderer(morph: morph, from: old, to: new)
        #expect(renderer.appearances.count == 4)
        let sources = renderer.appearances.flatMap { [$0.a, $0.b] }
        // Four unique children and two variants of one parent ID. Each parent
        // must remain distinct and each repeated owner must share its copy.
        #expect(Set(sources.map { ObjectIdentifier($0.color) }).count == 6)
        let parents = sources.filter { $0.plan.id == a.plan.id }
        #expect(parents.count == 4)
        for plan in [a.plan, b.plan] {
            let copies = parents.filter { $0.plan == plan }
            #expect(copies.count == 2)
            #expect(Set(copies.map { ObjectIdentifier($0.color) }).count == 1)
        }
    }

    @Test @MainActor func productionLifecycleCancelsPendingWorkAndReanchorsDuringMorph() async throws {
        let region = try LMLunarContactTests().region(at: .init(latitudeDegrees: -42, longitudeDegrees: 120))
        let presentation = LMLunarTerrainPresentation(region: region, mode: .procedural)
        let coarse = tile(level: 0, spacing: 2, fine: false).plan
        let fine = tile(level: 1, spacing: 0.5, fine: true).plan
        var ready = [String](), frameChecks = 0
        func request(_ plans: [LMTerrainTilePlan], label: String) {
            presentation.update(plans: plans, east: 1, north: 1) { message, _, _, _, _ in
                if message == "Lunar terrain ready" {
                    #expect(!presentation.isMorphing)
                    ready.append(label)
                }
            }
        }
        func waitUntil(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            #expect(condition())
        }
        request([coarse], label: "initial")
        try await waitUntil { ready == ["initial"] }
        presentation.setMode(.procedural)
        presentation.presentationChanged = {
            guard let height = presentation.snapshot.sample(east: 1.13, north: 1.37)?.elevation,
                  let ray = presentation.snapshot.raycast(origin: SIMD3(1.37, height + 10, -1.13),
                                                         direction: SIMD3(0, -1, 0)) else {
                Issue.record("Displayed contact has no submitted triangle")
                return
            }
            #expect(abs(height - ray.position.y) < 0.00001)
            #expect(presentation.root.children.count == 1)
            frameChecks += 1
        }
        request([coarse, fine], label: "cancelled-registration")
        try await waitUntil { presentation.root.children.count == 2 }
        #expect(presentation.snapshot.tiles.count == 1)
        #expect(presentation.root.children.allSatisfy {
            $0.components[OpacityComponent.self] == nil
        })
        let registrationHeight = presentation.snapshot.sample(east: 1.13, north: 1.37)?.elevation
        let registrationAnchor = region.frame.coordinateSystem.localFrame(at: region.frame.coordinate(for:
            .init(northMeters: 2_100, eastMeters: 0, upMeters: 0)))
        presentation.apply(anchor: registrationAnchor)
        #expect(presentation.snapshot.sample(east: 1.13, north: 1.37)?.elevation == registrationHeight)
        presentation.cancel()
        try await waitUntil { presentation.root.children.count == 1 }
        #expect(presentation.snapshot.tiles.count == 1)
        #expect(ready == ["initial"])
        request([coarse, fine], label: "superseded")
        try await waitUntil { presentation.isMorphing }
        let before = presentation.snapshot.sample(east: 1.13, north: 1.37)?.elevation
        let shifted = region.frame.coordinateSystem.localFrame(at: region.frame.coordinate(for:
            .init(northMeters: 4_200, eastMeters: 0, upMeters: 0)))
        presentation.apply(anchor: shifted)
        #expect(presentation.snapshot.sample(east: 1.13, north: 1.37)?.elevation == before)
        presentation.cancel()
        request([coarse], label: "cancelled-reversal")
        presentation.cancel()
        request([coarse, fine], label: "cancelled-repeat")
        presentation.cancel()
        request([coarse], label: "final")
        try await waitUntil { ready.contains("final") }
        #expect(ready == ["initial", "final"])
        #expect(presentation.snapshot.tiles.count == 1)
        #expect(presentation.root.children.count == 1)
        #expect(!presentation.isMorphing)
        #expect(frameChecks > 2)
        presentation.presentationChanged = nil
        presentation.cancel()
    }

    @Test func easingHasExactEndpointsAndMonotonicWeights() {
        #expect(LMLunarTerrainMorph.weight(fraction: -1) == 0)
        #expect(LMLunarTerrainMorph.weight(fraction: 2) == 1)
        var last: Float = 0
        for i in 0...100 {
            let next = LMLunarTerrainMorph.weight(fraction: Double(i) / 100)
            #expect(next >= last && next <= 1)
            last = next
        }
    }

    @Test @MainActor func uploadedNormalEncodingRetainsNorthToSouthRows() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        var bytes = [UInt8]()
        for row in 0..<8 {
            for column in 0..<8 { bytes += [UInt8(64 + row * 8), UInt8(96 + column * 8), 240, 255] }
        }
        let image = try #require(LMTerrainTileDetailBaker.image(from: bytes, resolution: 8,
                                                               colorSpace: CGColorSpaceCreateDeviceRGB()))
        for semantic in [TextureResource.Semantic.normal] {
            let resource = try await TextureResource(image: image,
                options: LMTerrainWorld.terrainTextureCreateOptions(semantic: semantic))
            print("LUNAR_ENDPOINT semantic=\(semantic) format=\(resource.pixelFormat.rawValue) mips=\(resource.mipmapLevelCount)")
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: resource.pixelFormat,
                width: 8, height: 8, mipmapped: true)
            descriptor.storageMode = .shared
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
            let texture = try #require(device.makeTexture(descriptor: descriptor))
            try await resource.copy(to: texture)
            var actual = [UInt8](repeating: 0, count: 8 * 8 * 16)
            actual.withUnsafeMutableBytes { raw in
                texture.getBytes(raw.baseAddress!, bytesPerRow: 8 * 16,
                                 from: MTLRegionMake2D(0, 0, 8, 8), mipmapLevel: 0)
            }
            for row in 0..<8 {
                #expect(Array(actual[row * 128..<row * 128 + 32]) == Array(bytes[row * 32..<row * 32 + 32]))
            }
        }
    }
}
