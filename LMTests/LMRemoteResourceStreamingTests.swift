import Foundation
import Testing
@testable import LM

@Suite("Durable remote lunar resources")
struct LMRemoteResourceStreamingTests {
    @Test func rangeRequestUsesExactInclusivePDSBytes() throws {
        let request = try fixtureRequest(
            payload: Data([1, 2, 3, 4]),
            range: 92_160...92_163
        )
        #expect(request.rangeHeaderValue == "bytes=92160-92163")
        #expect(request.expectedByteCount == 4)
    }

    @Test func existingPinnedSLDEMSlabUsesTheGenericBoundary() throws {
        let manifest = try LMTerrainManifest.load()
        let source = try #require(
            manifest.sources.first { $0.id == "sldem2015-512-apollo11-slab" }
        )
        let request = try source.remoteResourceRequest()

        #expect(request.id == source.id)
        #expect(request.rangeHeaderValue == "bytes=1370787840-1396869119")
        #expect(request.expectedByteCount == 26_081_280)
        #expect(request.sha256 == source.sha256)
    }

    @Test func httpFetcherSendsRangeAndRejectsAFullFileResponse() async throws {
        let payload = Data([4, 3, 2, 1])
        let request = try fixtureRequest(
            payload: payload,
            range: 92_160...92_163
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RangeFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        RangeFixtureURLProtocol.configure(payload: payload, statusCode: 206)

        let received = try await LMHTTPByteRangeFetcher(session: session)
            .fetch(request)
        #expect(received == payload)
        #expect(RangeFixtureURLProtocol.lastRange == "bytes=92160-92163")

        RangeFixtureURLProtocol.configure(payload: payload, statusCode: 200)
        await #expect(throws: LMRemoteResourceError.rangedResponseRequired) {
            try await LMHTTPByteRangeFetcher(session: session).fetch(request)
        }
    }

    @Test func coldFetchPersistsAsAWarmContentAddressedHit() async throws {
        let directory = temporaryDirectory("persistent-hit")
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = Data("pinned lunar slab".utf8)
        let request = try fixtureRequest(payload: payload)
        let firstFetcher = FixtureFetcher(payloads: [payload])
        let firstCache = try LMRemoteResourceDiskCache(directoryURL: directory)
        let cold = try await LMRemoteResourceLoader(
            fetcher: firstFetcher,
            cache: firstCache
        ).resource(for: request)

        #expect(!cold.cacheHit)
        #expect(cold.downloadedBytes == payload.count)
        #expect(cold.attemptCount == 1)
        #expect(cold.elapsedMilliseconds >= 0)
        #expect(await firstFetcher.fetchCount == 1)

        // A new cache actor represents a later process launch. Its first read
        // must use the durable file and never ask the empty fetcher for bytes.
        let secondFetcher = FixtureFetcher(payloads: [])
        let secondCache = try LMRemoteResourceDiskCache(directoryURL: directory)
        let warm = try await LMRemoteResourceLoader(
            fetcher: secondFetcher,
            cache: secondCache
        ).resource(for: request)

        #expect(warm.cacheHit)
        #expect(warm.data == payload)
        #expect(warm.downloadedBytes == 0)
        #expect(warm.attemptCount == 0)
        #expect(warm.elapsedMilliseconds >= 0)
        #expect(await secondFetcher.fetchCount == 0)
    }

    @Test func bundledOnlyReadsWarmDataButNeverStartsANetworkFetch() async throws {
        let directory = temporaryDirectory("bundled-only")
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = Data("already offline".utf8)
        let request = try fixtureRequest(payload: payload)
        let cache = try LMRemoteResourceDiskCache(directoryURL: directory)
        try await cache.insert(payload, sha256: request.sha256)
        let fetcher = FixtureFetcher(payloads: [])
        let loader = LMRemoteResourceLoader(
            fetcher: fetcher,
            cache: cache,
            bundledOnly: true
        )

        #expect(try await loader.resource(for: request).cacheHit)

        let missingPayload = Data("not cached".utf8)
        let missing = try fixtureRequest(payload: missingPayload)
        await #expect(throws: LMRemoteResourceError.networkDisabled) {
            try await loader.resource(for: missing)
        }
        #expect(await fetcher.fetchCount == 0)
    }

    @Test func hashFailuresAreBoundedAndNeverDisplayedOrCached() async throws {
        let directory = temporaryDirectory("bad-hash")
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = Data("measured elevation".utf8)
        let corrupt = Data("invented elevation".utf8)
        let request = try fixtureRequest(
            payload: expected,
            expectedByteCount: corrupt.count
        )
        let fetcher = FixtureFetcher(payloads: [corrupt, corrupt, corrupt, corrupt])
        let cache = try LMRemoteResourceDiskCache(directoryURL: directory)
        let loader = LMRemoteResourceLoader(
            fetcher: fetcher,
            cache: cache,
            maximumAttempts: 3
        )

        do {
            _ = try await loader.resource(for: request)
            Issue.record("Hash-invalid bytes must never become a resource product")
        } catch let error as LMRemoteResourceError {
            guard case .hashMismatch(let expectedHash, let actualHash) = error else {
                Issue.record("Expected hashMismatch; got \(error)")
                return
            }
            #expect(expectedHash == request.sha256)
            #expect(actualHash == LMContentDigest.sha256(corrupt))
        }
        #expect(await fetcher.fetchCount == 3)
        let statistics = try await cache.statistics()
        #expect(statistics.entryCount == 0)
        #expect(statistics.byteCount == 0)
    }

    @Test func diskCacheEvictsLeastRecentlyUsedBytes() async throws {
        let directory = temporaryDirectory("lru")
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = Data([1, 1, 1])
        let b = Data([2, 2, 2])
        let c = Data([3, 3, 3])
        let aHash = LMContentDigest.sha256(a)
        let bHash = LMContentDigest.sha256(b)
        let cHash = LMContentDigest.sha256(c)
        let cache = try LMRemoteResourceDiskCache(
            directoryURL: directory,
            byteLimit: 6
        )
        try await cache.insert(a, sha256: aHash)
        try await Task.sleep(for: .milliseconds(10))
        try await cache.insert(b, sha256: bHash)
        try await Task.sleep(for: .milliseconds(10))
        #expect(try await cache.data(sha256: aHash, expectedByteCount: 3) == a)
        try await Task.sleep(for: .milliseconds(10))
        try await cache.insert(c, sha256: cHash)

        #expect(try await cache.data(sha256: aHash, expectedByteCount: 3) == a)
        #expect(try await cache.data(sha256: bHash, expectedByteCount: 3) == nil)
        #expect(try await cache.data(sha256: cHash, expectedByteCount: 3) == c)
        let statistics = try await cache.statistics()
        #expect(statistics.entryCount == 2)
        #expect(statistics.byteCount == 6)
        #expect(statistics.evictionCount == 1)
    }

    @Test func manifestHashChangeCannotReuseOldBytes() async throws {
        let directory = temporaryDirectory("manifest-version")
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = Data("v1 terrain".utf8)
        let new = Data("v2 terrain".utf8)
        let oldRequest = try fixtureRequest(payload: old)
        let newRequest = try fixtureRequest(payload: new)
        let cache = try LMRemoteResourceDiskCache(directoryURL: directory)
        try await cache.insert(old, sha256: oldRequest.sha256)

        #expect(try await cache.data(
            sha256: newRequest.sha256,
            expectedByteCount: new.count
        ) == nil)
    }

    private func fixtureRequest(
        payload: Data,
        expectedByteCount: Int? = nil,
        range: ClosedRange<Int>? = nil
    ) throws -> LMRemoteResourceRequest {
        let url = try #require(URL(string: "https://example.invalid/lunar.img"))
        return LMRemoteResourceRequest(
            id: "fixture",
            url: url,
            byteRange: range,
            expectedByteCount: expectedByteCount ?? payload.count,
            sha256: LMContentDigest.sha256(payload)
        )
    }

    private func temporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "LMRemoteResourceStreamingTests-\(name)-\(UUID().uuidString)",
                isDirectory: true
            )
    }
}

private actor FixtureFetcher: LMRemoteResourceFetching {
    private var payloads: [Data]
    private(set) var fetchCount = 0

    init(payloads: [Data]) {
        self.payloads = payloads
    }

    func fetch(_ request: LMRemoteResourceRequest) async throws -> Data {
        fetchCount += 1
        guard !payloads.isEmpty else {
            throw URLError(.notConnectedToInternet)
        }
        return payloads.removeFirst()
    }
}

private final class RangeFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var payload = Data()
    nonisolated(unsafe) private static var statusCode = 206
    nonisolated(unsafe) private(set) static var lastRange: String?

    static func configure(payload: Data, statusCode: Int) {
        lock.lock()
        self.payload = payload
        self.statusCode = statusCode
        lastRange = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let payload = Self.payload
        let statusCode = Self.statusCode
        Self.lastRange = request.value(forHTTPHeaderField: "Range")
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: statusCode == 206
                ? ["Content-Range": "bytes 92160-92163/1061775360"]
                : nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
