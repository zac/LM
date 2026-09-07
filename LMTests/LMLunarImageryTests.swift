import CryptoKit
import Foundation
import Testing
@testable import LM

@Suite @MainActor
struct LMLunarImageryTests {
    private func pyramid() throws -> LMLunarImageryPyramid {
        let reference = try #require(LMTerrainManifest.load().globe.imageryPyramid)
        let url = try #require(Bundle.main.url(forResource: reference.file, withExtension: nil, subdirectory: "Terrain")
            ?? Bundle.main.url(forResource: reference.file, withExtension: nil))
        let data = try Data(contentsOf: url)
        #expect(LMLunarImageryPyramid.digest(data) == reference.sha256)
        let result = try JSONDecoder().decode(LMLunarImageryPyramid.self, from: data)
        try result.validate()
        return result
    }

    @Test func pinnedManifestAndBoundedRanges() throws {
        let pyramid = try pyramid()
        #expect(pyramid.tiles.filter { $0.ppd == 32 }.count == 512)
        #expect(pyramid.tiles.filter { $0.ppd == 64 }.count == 2048)
        for slab in pyramid.slabs {
            let source = LMLunarImageryTileStore.source(slab, pyramid: pyramid)
            try LMLunarElevationStore.validate(source)
            #expect(source.bytes! <= 12 * 1024 * 1024)
        }
        let url = try #require(Bundle.main.url(forResource: pyramid.base.file, withExtension: nil, subdirectory: "Terrain")
            ?? Bundle.main.url(forResource: pyramid.base.file, withExtension: nil))
        let base = try Data(contentsOf: url)
        #expect(base.count == pyramid.base.bytes)
        #expect(LMLunarImageryPyramid.digest(base) == pyramid.base.sha256)
        #expect(!LMLunarGlobeImagery.isEnabled(arguments: ["--lunar-explorer-capture"]))
        #expect(!LMLunarGlobeImagery.isEnabled(arguments: ["--lunar-globe-texture-tier=wac-global-64ppd"]))
        #expect(LMLunarGlobeImagery.isEnabled(arguments: ["--lunar-explorer"]))
    }

    @Test func selectionWrapsAndStaysBoundedAtPoles() throws {
        let pyramid = try pyramid()
        for ppd in [32, 64] {
            for latitude in [-90.0, -80, -42, 0, 80, 90] {
                for longitude in [-180.0, -179.999, 0, 179.999] {
                    let selected = LMLunarGlobeImagery.selectedTiles(in: pyramid, ppd: ppd,
                        latitude: latitude, longitude: longitude)
                    #expect(!selected.isEmpty && selected.count <= 15)
                    #expect(Set(selected.map(\.id)).count == selected.count)
                }
            }
            let seam = LMLunarGlobeImagery.selectedTiles(in: pyramid, ppd: ppd, latitude: 0, longitude: -180)
            #expect(seam.contains { $0.column == 0 })
            #expect(seam.contains { $0.column == 360 * ppd / 360 - 1 })
        }
    }

    @Test func patchesAndCoarseMapOwnExactlyTheOriginalTriangles() throws {
        let pyramid = try pyramid()
        let data = LMLunarGlobeResource.globeMeshData(radiusMeters: 1_737_400,
            frontCoordinate: .init(latitudeDegrees: 0.6741, longitudeDegrees: 23.473))
        func triangles(_ data: LMLunarGlobeResource.GlobeMeshData) -> [String] {
            stride(from: 0, to: data.indices.count, by: 3).map { offset in
                (0..<3).map { corner in
                    let value = data.positions[Int(data.indices[offset + corner])]
                    return "\(value.x.bitPattern):\(value.y.bitPattern):\(value.z.bitPattern)"
                }.joined(separator: "/")
            }
        }
        let expected = triangles(data).sorted()
        for coordinate in [(0.67, 23.47, 64), (90.0, -180.0, 32), (-42.0, 120.0, 64)] {
            let selected = LMLunarGlobeImagery.selectedTiles(in: pyramid, ppd: coordinate.2,
                latitude: coordinate.0, longitude: coordinate.1)
            let partition = LMLunarGlobeImagery.partition(data, tiles: selected, pyramid: pyramid)
            let actual = triangles(partition.remainder) + partition.patches.values.flatMap(triangles)
            #expect(actual.sorted() == expected)
            for patch in partition.patches.values {
                #expect(patch.textureCoordinates.allSatisfy { $0.x > 0 && $0.x < 1 && $0.y > 0 && $0.y < 1 })
            }
        }
    }

    @Test func patchSamplesMatchTheWholeTextureVConvention() throws {
        let pyramid = try pyramid()
        let data = LMLunarGlobeResource.globeMeshData(radiusMeters: 1_737_400,
            frontCoordinate: .init(latitudeDegrees: 0.6741, longitudeDegrees: 23.473))
        let addresses = Dictionary(zip(data.positions, data.textureCoordinates), uniquingKeysWith: { first, _ in first })
        for ppd in [32, 64] {
            let tiles = LMLunarGlobeImagery.selectedTiles(in: pyramid, ppd: ppd, latitude: 0.67, longitude: 23.47)
            let partition = LMLunarGlobeImagery.partition(data, tiles: tiles, pyramid: pyramid)
            for tile in tiles {
                let patch = try #require(partition.patches[tile.id])
                for (position, local) in zip(patch.positions, patch.textureCoordinates) {
                    let global = try #require(addresses[position])
                    let x = Float(tile.column * 360) + local.x * 364 - 2
                    let y = Float(tile.row * 360) + (1 - local.y) * 364 - 2
                    #expect(abs(x - global.x * Float(360 * ppd)) < 0.002)
                    #expect(abs(y - (1 - global.y) * Float(180 * ppd)) < 0.002)
                }
            }
        }
    }

    @Test func transferAndBoxAverageHaveFixedValues() throws {
        #expect(LMLunarImageryPyramid.encodeReflectance(0) == 33)
        #expect(LMLunarImageryPyramid.encodeReflectance(.nan) == 33)
        #expect(LMLunarImageryPyramid.encodeReflectance(-1) == 33)
        #expect(LMLunarImageryPyramid.encodeReflectance(1) == 33)
        #expect(LMLunarImageryPyramid.encodeReflectance(0.04) == 56)
        #expect(LMLunarImageryPyramid.encodeReflectance(0.08) == 80)
        #expect(LMLunarImageryPyramid.encodeReflectance(0.12) == 97)
        #expect(LMLunarImageryPyramid.encodeReflectance(0.16) == 111)
        let pyramid = try pyramid()
        let tile = try #require(pyramid.tiles.first { $0.ppd == 32 && $0.row == 1 && $0.column == 1 })
        let range = pyramid.sourceRows(for: tile)
        var rowA = Data(), rowB = Data()
        for column in 0..<23040 {
            var a = Float(column % 2 == 0 ? 0.04 : 0.08).bitPattern.littleEndian
            var b = Float(column % 2 == 0 ? 0.12 : 0.16).bitPattern.littleEndian
            withUnsafeBytes(of: &a) { rowA.append(contentsOf: $0) }
            withUnsafeBytes(of: &b) { rowB.append(contentsOf: $0) }
        }
        var rows = Data()
        for row in range { rows.append(row % 2 == 0 ? rowA : rowB) }
        let pixels = try pyramid.pixels(for: tile, sourceRows: rows, firstRow: range.lowerBound)
        #expect(pixels.count == 364 * 364)
        #expect(pixels.allSatisfy { $0 == 86 })
        #expect(throws: (any Error).self) {
            try pyramid.pixels(for: tile, sourceRows: Data(), firstRow: range.lowerBound)
        }
    }

    @Test func verifiedSlabsReconstructAnEvictedTileOffline() async throws {
        let original = try pyramid()
        let index = try #require(original.tiles.firstIndex { $0.ppd == 64 && $0.row == 1 && $0.column == 1 })
        var source = Data(count: 128 * 23040 * 4)
        source.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                bytes.storeBytes(of: Float(0.04).bitPattern.littleEndian, toByteOffset: offset, as: UInt32.self)
            }
        }
        let expected = Data(repeating: 56, count: 364 * 364)
        let digest = LMLunarImageryPyramid.digest(expected)
        let encoded = try JSONEncoder().encode(original)
        var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var tiles = try #require(json["tiles"] as? [[String: Any]])
        tiles[index]["sha256"] = digest; json["tiles"] = tiles
        var slabs = try #require(json["slabs"] as? [[String: Any]])
        for i in slabs.indices { slabs[i]["sha256"] = LMLunarImageryPyramid.digest(source) }
        json["slabs"] = slabs
        let fixture = try JSONDecoder().decode(LMLunarImageryPyramid.self,
            from: JSONSerialization.data(withJSONObject: json))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        actor FetchCount {
            var value = 0
            func increment() { value += 1 }
        }
        let counter = FetchCount(), payload = source
        let store = try LMLunarImageryTileStore(pyramid: fixture, directory: directory) { _ in
            await counter.increment()
            return payload
        }
        #expect(try await store.pixels(for: fixture.tiles[index]) == expected)
        let count = await counter.value
        let file = directory.appendingPathComponent("tiles/\(digest).r8")
        try FileManager.default.removeItem(at: file)
        #expect(try await store.pixels(for: fixture.tiles[index], offline: true) == expected)
        #expect(await counter.value == count)
        // A corrupted derived cache entry also rebuilds only from verified slabs.
        try Data(repeating: 0, count: expected.count).write(to: file)
        #expect(try await store.pixels(for: fixture.tiles[index], offline: true) == expected)
        #expect(await counter.value == count)
    }

    @Test func offlineMissingTileNeverFetches() async throws {
        let pyramid = try pyramid()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LMLunarImageryTileStore(pyramid: pyramid, directory: directory) { _ in
            Issue.record("Offline imagery attempted a fetch")
            throw CocoaError(.fileReadUnknown)
        }
        await #expect(throws: LMLunarElevationStore.StoreError.unavailableOffline) {
            try await store.pixels(for: pyramid.tiles[0], offline: true)
        }
    }
}
