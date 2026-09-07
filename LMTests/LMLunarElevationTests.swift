import Foundation
import Testing
import simd
@testable import LM

@Suite("Pinned lunar elevation")
struct LMLunarElevationTests {
    private func sourceJSON(id: String) throws -> [String: Any] {
        let url = try #require(Bundle.main.url(forResource: "TerrainManifest", withExtension: "json"))
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let sources = try #require(root["sources"] as? [[String: Any]])
        return try #require(sources.first { $0["id"] as? String == id })
    }

    private func fixture(seed: Float = 0) throws -> (Data, LMTerrainManifest.Source) {
        var data = Data()
        data.reserveCapacity(184_320)
        for row in 0..<2 {
            for column in 0..<23_040 {
                var bits = (seed + Float(row) * 0.01 + Float(column % 500) * 0.000001).bitPattern.littleEndian
                withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
            }
        }
        var json = try sourceJSON(id: "sldem2015-512-apollo11-slab")
        json["bytes"] = data.count
        json["sha256"] = LMLunarElevationGrid.digest(data)
        json["byteRangeStart"] = 0
        json["byteRangeEnd"] = data.count - 1
        json["sourceRowStart"] = 0
        json["sourceRowEnd"] = 1
        json["coverage"] = ["maximumLatitudeDegrees": 30.0, "minimumLatitudeDegrees": 30 - 2.0 / 512,
                            "westernmostLongitudeDegrees": 0.0, "easternmostLongitudeDegrees": 45.0]
        let source = try JSONDecoder().decode(LMTerrainManifest.Source.self, from: JSONSerialization.data(withJSONObject: json))
        return (data, source)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func bundledBaseAndLabelMatchPinnedBytesAndMeasuredPosts() throws {
        let manifest = try LMTerrainManifest.load()
        let source = try #require(manifest.sources.first { $0.id == "lola-ldem-16ppd-global" })
        let image = try #require(Bundle.main.url(forResource: source.bundledFile, withExtension: nil))
        let label = try #require(Bundle.main.url(forResource: source.bundledLabelFile, withExtension: nil))
        let data = try Data(contentsOf: image)
        let labelData = try Data(contentsOf: label)
        #expect(data.count + labelData.count < 32 * 1_024 * 1_024)
        #expect(LMLunarElevationGrid.digest(labelData) == source.labelSHA256)
        let grid = try LMLunarElevationGrid(data: data, source: source)
        for row in [0, 1, 1440, 2879] {
            for column in [0, 1, 2880, 5759] {
                let coordinate = LMSelenographicCoordinate(
                    latitudeDegrees: 90 - (Double(row) + 0.5) / 16,
                    longitudeDegrees: (Double(column) + 0.5) / 16)
                let raw: Int16 = data.withUnsafeBytes {
                    Int16(littleEndian: $0.loadUnaligned(fromByteOffset: (row * 5760 + column) * 2, as: Int16.self))
                }
                #expect(grid.elevation(at: coordinate) == Double(raw) * 0.5)
            }
        }
        let west = try #require(grid.elevation(at: .init(latitudeDegrees: 10, longitudeDegrees: -0.00000001)))
        let east = try #require(grid.elevation(at: .init(latitudeDegrees: 10, longitudeDegrees: 0.00000001)))
        #expect(abs(west - east) < 0.001)
        for latitude in [-90.0, 90.0] {
            #expect(grid.elevation(at: .init(latitudeDegrees: latitude, longitudeDegrees: 0))
                    == grid.elevation(at: .init(latitudeDegrees: latitude, longitudeDegrees: 130)))
        }
    }

    @Test func sldemPixelRegistrationUnitsAndIntegrityAreExact() throws {
        let (data, source) = try fixture(seed: -2)
        let grid = try LMLunarElevationGrid(data: data, source: source)
        for row in 0..<2 {
            for column in [0, 1, 17, 23_039] {
                let coordinate = LMSelenographicCoordinate(
                    latitudeDegrees: 30 - (Double(row) + 0.5) / 512,
                    longitudeDegrees: (Double(column) + 0.5) / 512)
                let raw = Float(bitPattern: data.withUnsafeBytes {
                    UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: (row * 23040 + column) * 4, as: UInt32.self))
                })
                #expect(grid.elevation(at: coordinate) == Double(raw) * 1_000)
            }
        }
        #expect(grid.elevation(at: .init(latitudeDegrees: 29, longitudeDegrees: 25)) == nil)
        var corrupt = data
        corrupt[0] ^= 1
        #expect(throws: LMLunarElevationGrid.GridError.digestMismatch) {
            try LMLunarElevationGrid(data: corrupt, source: source)
        }
        #expect(throws: LMLunarElevationGrid.GridError.invalidDimensions) {
            try LMLunarElevationGrid(data: data.dropLast(), source: source)
        }
    }

    @Test func coarseGeometryKeepsCurvatureAndIsDeterministic() throws {
        let source = try #require(LMTerrainManifest.load().sources.first { $0.id == "lola-ldem-16ppd-global" })
        let url = try #require(Bundle.main.url(forResource: source.bundledFile, withExtension: nil))
        let grid = try LMLunarElevationGrid(data: Data(contentsOf: url), source: source)
        let coordinate = LMSelenographicCoordinate(latitudeDegrees: -42, longitudeDegrees: 179.99)
        let a = try LMLunarElevationPreview.makeMesh(grid: grid, coordinate: coordinate)
        let b = try LMLunarElevationPreview.makeMesh(grid: grid, coordinate: coordinate)
        #expect(a.positions == b.positions)
        #expect(a.normals == b.normals)
        #expect(a.indices == b.indices)
        for index in stride(from: 0, to: a.positions.count, by: 97) {
            let point = a.positions[index]
            let moon = a.frame.coordinate(for: .init(northMeters: Double(point.x),
                                                     eastMeters: Double(-point.z), upMeters: Double(point.y)))
            let expectedHeight = try #require(grid.elevation(at: moon))
            #expect(abs(moon.heightMeters - expectedHeight) < 0.001)
            #expect(abs(simd_length(a.normals[index]) - 1) < 1e-5)
            #expect(a.normals[index].y > 0)
        }
    }

    actor Counter {
        var calls = 0
        func increment() { calls += 1 }
    }

    @Test func persistentCacheReopensOfflineAndRepairsCorruption() async throws {
        let (data, source) = try fixture()
        let path = try directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let counter = Counter()
        let store = try LMLunarElevationStore(directory: path, capacityBytes: data.count) { _ in
            await counter.increment()
            return data
        }
        let first = try await store.data(for: source)
        #expect(first == data)
        let reopened = try LMLunarElevationStore(directory: path, capacityBytes: data.count) { _ in
            throw LMLunarElevationStore.StoreError.unavailableOffline
        }
        let offline = try await reopened.data(for: source, offline: true)
        #expect(offline == data)
        try Data([0]).write(to: path.appendingPathComponent(source.sha256 + ".bin"))
        let repaired = try await store.data(for: source)
        #expect(repaired == data)
        let count = await counter.calls
        #expect(count == 2)
    }

    @Test func cacheEvictsLeastRecentlyUsedAndRejectsUnpinnedResponses() async throws {
        let fixtures = try [fixture(seed: 1), fixture(seed: 2), fixture(seed: 3)]
        let path = try directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = try LMLunarElevationStore(directory: path, capacityBytes: fixtures[0].0.count * 2) { source in
            try #require(fixtures.first { $0.1.sha256 == source.sha256 }?.0)
        }
        _ = try await store.data(for: fixtures[0].1)
        _ = try await store.data(for: fixtures[1].1)
        _ = try await store.data(for: fixtures[0].1)
        _ = try await store.data(for: fixtures[2].1)
        do {
            _ = try await store.data(for: fixtures[1].1, offline: true)
            Issue.record("Evicted slab remained available offline")
        } catch { #expect(error as? LMLunarElevationStore.StoreError == .unavailableOffline) }
        let bytes = try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.pathExtension == "bin" }
            .reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        #expect(bytes <= fixtures[0].0.count * 2)
        do {
            try await store.prefetch(fixtures.map(\.1))
            Issue.record("Oversized region was accepted")
        } catch { #expect(error as? LMLunarElevationStore.StoreError == .capacityExceeded) }

        let badPath = try directory()
        defer { try? FileManager.default.removeItem(at: badPath) }
        let bad = try LMLunarElevationStore(directory: badPath) { _ in fixtures[1].0 }
        do {
            _ = try await bad.data(for: fixtures[0].1)
            Issue.record("Unpinned bytes entered the cache")
        } catch { #expect(error as? LMLunarElevationStore.StoreError == .digestMismatch) }
        #expect(!FileManager.default.fileExists(atPath: badPath.appendingPathComponent(fixtures[0].1.sha256 + ".bin").path))
    }

    @Test func httpMustHonorTheExactRangeBeforeBodyConsumption() throws {
        let (_, source) = try fixture()
        let url = try #require(URL(string: source.url))
        let count = try #require(source.bytes)
        let total = try #require(source.sourceBytes)
        func response(_ status: Int, _ range: String, encoding: String = "identity") throws -> HTTPURLResponse {
            try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Range": range, "Content-Length": String(count),
                               "Content-Encoding": encoding]))
        }
        let correct = "bytes 0-\(count - 1)/\(total)"
        try LMLunarElevationStore.validateResponse(response(206, correct), source: source)
        for status in [200, 204, 404] {
            #expect(throws: LMLunarElevationStore.StoreError.responseMismatch) {
                try LMLunarElevationStore.validateResponse(response(status, correct), source: source)
            }
        }
        for range in ["bytes 1-\(count)/\(total)", "bytes 0-\(count - 1)/*", ""] {
            #expect(throws: LMLunarElevationStore.StoreError.responseMismatch) {
                try LMLunarElevationStore.validateResponse(response(206, range), source: source)
            }
        }
        #expect(throws: LMLunarElevationStore.StoreError.responseMismatch) {
            try LMLunarElevationStore.validateResponse(response(206, correct, encoding: "gzip"), source: source)
        }
    }

    actor InterruptedRegion {
        let blobs: [String: Data]
        let stopAt: String
        var didFail = false
        var counts = [String: Int]()
        init(blobs: [String: Data], stopAt: String) { self.blobs = blobs; self.stopAt = stopAt }
        func read(_ source: LMTerrainManifest.Source) throws -> Data {
            counts[source.sha256, default: 0] += 1
            if source.sha256 == stopAt, !didFail {
                didFail = true
                throw URLError(.networkConnectionLost)
            }
            return try #require(blobs[source.sha256])
        }
    }

    @Test func regionPrefetchResumesAtCompletedVerifiedSlabs() async throws {
        let fixtures = try [fixture(seed: 1), fixture(seed: 2), fixture(seed: 3)].sorted { $0.1.sha256 < $1.1.sha256 }
        let path = try directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let transport = InterruptedRegion(
            blobs: Dictionary(uniqueKeysWithValues: fixtures.map { ($0.1.sha256, $0.0) }),
            stopAt: fixtures[1].1.sha256)
        let store = try LMLunarElevationStore(directory: path, capacityBytes: fixtures[0].0.count * 3) {
            try await transport.read($0)
        }
        do {
            try await store.prefetch(fixtures.map(\.1))
            Issue.record("Interrupted transfer unexpectedly completed")
        } catch { #expect(error is URLError) }
        try await store.prefetch(fixtures.map(\.1))
        let counts = await transport.counts
        #expect(counts[fixtures[0].1.sha256] == 1)
        #expect(counts[fixtures[1].1.sha256] == 2)
        #expect(counts[fixtures[2].1.sha256] == 1)
        let reopened = try LMLunarElevationStore(directory: path) { _ in throw URLError(.notConnectedToInternet) }
        for fixture in fixtures {
            let data = try await reopened.data(for: fixture.1, offline: true)
            #expect(data == fixture.0)
        }
    }

    @Test func concurrentRequestsShareOneVerifiedDownload() async throws {
        let (data, source) = try fixture()
        let path = try directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let counter = Counter()
        let store = try LMLunarElevationStore(directory: path) { _ in
            await counter.increment()
            try await Task.sleep(for: .milliseconds(100))
            return data
        }
        async let a = store.data(for: source)
        async let b = store.data(for: source)
        let results = try await (a, b)
        #expect(results.0 == data && results.1 == data)
        let count = await counter.calls
        #expect(count == 1)
    }

    @Test func cancelledPrefetchPublishesNoPartialProduct() async throws {
        let (data, source) = try fixture()
        let path = try directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = try LMLunarElevationStore(directory: path) { _ in
            try await Task.sleep(for: .seconds(30))
            return data
        }
        let task = Task { try await store.prefetch([source]) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do {
            try await task.value
            Issue.record("Cancelled prefetch completed")
        } catch { #expect(error is CancellationError) }
        #expect(!FileManager.default.fileExists(atPath: path.appendingPathComponent(source.sha256 + ".bin").path))
    }

    private actor BatchTransport {
        var active = 0
        var peak = 0
        var calls = 0
        let blobs: [String: Data]
        let failed: String?
        init(blobs: [String: Data], failed: String? = nil) {
            self.blobs = blobs
            self.failed = failed
        }
        func read(_ source: LMTerrainManifest.Source) async throws -> Data {
            active += 1
            calls += 1
            peak = max(peak, active)
            defer { active -= 1 }
            // Different lengths force completion order to differ from catalog order.
            try await Task.sleep(for: .milliseconds(source.sha256 == failed ? 10 : 100))
            if source.sha256 == failed { throw URLError(.networkConnectionLost) }
            return try #require(blobs[source.sha256])
        }
    }

    @Test func regionBatchBoundsConcurrencyPreservesOrderAndIsolatesFailures() async throws {
        let fixtures = try (1...9).map { try fixture(seed: Float($0)) }
        let path = try directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let failed = fixtures[2].1.sha256
        let transport = BatchTransport(
            blobs: Dictionary(uniqueKeysWithValues: fixtures.map { ($0.1.sha256, $0.0) }),
            failed: failed)
        let store = try LMLunarElevationStore(directory: path) { try await transport.read($0) }
        let results = try await store.data(for: fixtures.map(\.1))
        #expect(results.count == fixtures.count)
        for (index, result) in results.enumerated() {
            if index == 2 {
                if case .success = result { Issue.record("Failed source was accepted") }
            } else { #expect(try result.get() == fixtures[index].0) }
        }
        let peak = await transport.peak
        #expect(peak > 1 && peak <= 4)
        let cached = try await store.data(for: fixtures.enumerated().filter { $0.offset != 2 }.map { $0.element.1 }, offline: true)
        #expect(cached.count == 8)
        #expect(try cached.map { try $0.get() } == fixtures.enumerated().filter { $0.offset != 2 }.map { $0.element.0 })
        #expect(await transport.calls == 9)
        #expect(try await store.data(for: []).isEmpty)
    }

    @Test func cancelledRegionBatchCancelsWorkersAndPublishesNoPartialSlabs() async throws {
        let fixtures = try (1...8).map { try fixture(seed: Float($0)) }
        let path = try directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let counter = Counter()
        let store = try LMLunarElevationStore(directory: path) { _ in
            await counter.increment()
            try await Task.sleep(for: .seconds(30))
            return fixtures[0].0
        }
        let task = Task { try await store.data(for: fixtures.map(\.1)) }
        for _ in 0..<200 {
            if await counter.calls == 4 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await counter.calls == 4)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled batch completed")
        } catch { #expect(error is CancellationError) }
        #expect(await counter.calls == 4)
        let files = try FileManager.default.contentsOfDirectory(atPath: path.path)
        #expect(!files.contains { $0.hasSuffix(".bin") })
    }

    @Test @MainActor func elevationDiagnosticRequiresCaptureMode() {
        let session = LunarExplorerSession()
        session.configure(arguments: ["--lunar-explorer-elevation-preview=0.67,25"])
        #expect(session.captureElevationCoordinate == nil)
        session.configure(arguments: ["--lunar-explorer-capture", "--lunar-explorer-elevation-preview=0.67,25",
                                      "--lunar-explorer-elevation-offline"])
        #expect(session.captureElevationCoordinate == .init(latitudeDegrees: 0.67, longitudeDegrees: 25))
        #expect(session.captureElevationOffline)
        session.configure(arguments: [])
        #expect(session.captureElevationCoordinate == nil)
        #expect(!session.captureElevationOffline)
    }
}
