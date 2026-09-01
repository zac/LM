import CryptoKit
import Foundation
import OSLog

/// A hash-pinned byte resource. The range is deliberately data-agnostic:
/// Stage 2 elevation slabs and later reflectance products use the same fetch,
/// integrity, persistence, and eviction path.
struct LMRemoteResourceRequest: Hashable, Sendable {
    let id: String
    let url: URL
    let byteRange: ClosedRange<Int>?
    let expectedByteCount: Int
    let sha256: String

    var rangeHeaderValue: String? {
        byteRange.map { "bytes=\($0.lowerBound)-\($0.upperBound)" }
    }
}

enum LMRemoteResourceError: LocalizedError, Equatable {
    case invalidManifestSource(String)
    case networkDisabled
    case invalidHTTPStatus(Int)
    case rangedResponseRequired
    case byteCount(expected: Int, actual: Int)
    case hashMismatch(expected: String, actual: String)
    case attemptsExhausted(Int)

    var errorDescription: String? {
        switch self {
        case .invalidManifestSource(let id):
            "Terrain manifest source \(id) cannot form a pinned remote request."
        case .networkDisabled:
            "Remote enhancement is disabled; bundled lunar data remains available."
        case .invalidHTTPStatus(let status):
            "Remote lunar resource returned HTTP \(status)."
        case .rangedResponseRequired:
            "Remote lunar resource ignored a required byte-range request."
        case .byteCount(let expected, let actual):
            "Remote lunar resource contains \(actual) bytes; expected \(expected)."
        case .hashMismatch(let expected, let actual):
            "Remote lunar resource hash \(actual) does not match \(expected)."
        case .attemptsExhausted(let attempts):
            "Remote lunar resource failed after \(attempts) bounded attempts."
        }
    }
}

extension LMTerrainManifest.Source {
    /// Converts existing manifest slabs directly into the generic streaming
    /// boundary. This prevents Stage 2 from duplicating URL, inclusive-range,
    /// byte-count, or digest interpretation in an elevation decoder.
    func remoteResourceRequest() throws -> LMRemoteResourceRequest {
        guard let url = URL(string: url), let bytes else {
            throw LMRemoteResourceError.invalidManifestSource(id)
        }
        let range: ClosedRange<Int>?
        switch (byteRangeStart, byteRangeEnd) {
        case (.none, .none):
            range = nil
        case let (.some(start), .some(end)) where start >= 0
            && end >= start
            && end - start + 1 == bytes:
            range = start...end
        default:
            throw LMRemoteResourceError.invalidManifestSource(id)
        }
        return LMRemoteResourceRequest(
            id: id,
            url: url,
            byteRange: range,
            expectedByteCount: bytes,
            sha256: sha256
        )
    }
}

protocol LMRemoteResourceFetching: Sendable {
    func fetch(_ request: LMRemoteResourceRequest) async throws -> Data
}

/// One HTTP attempt. Retry policy belongs to the integrity-aware loader so a
/// truncated or hash-invalid 206 response is retried under the same bound as
/// a transport failure.
struct LMHTTPByteRangeFetcher: LMRemoteResourceFetching {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(_ resource: LMRemoteResourceRequest) async throws -> Data {
        var request = URLRequest(url: resource.url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 45
        if let range = resource.rangeHeaderValue {
            request.setValue(range, forHTTPHeaderField: "Range")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LMRemoteResourceError.invalidHTTPStatus(-1)
        }
        if resource.byteRange != nil {
            guard http.statusCode == 206 else {
                if (200..<300).contains(http.statusCode) {
                    throw LMRemoteResourceError.rangedResponseRequired
                }
                throw LMRemoteResourceError.invalidHTTPStatus(http.statusCode)
            }
        } else if !(200..<300).contains(http.statusCode) {
            throw LMRemoteResourceError.invalidHTTPStatus(http.statusCode)
        }
        return data
    }
}

/// Persistent, content-addressed LRU for verified remote resources.
///
/// The 1 GiB default is intentionally larger than the current appearance
/// working set and small enough to remain bounded on a 256 GB device. Files
/// survive app launches; a manifest hash change naturally selects a new file.
actor LMRemoteResourceDiskCache {
    static let defaultByteLimit = 1_024 * 1_024 * 1_024

    struct Statistics: Equatable, Sendable {
        let entryCount: Int
        let byteCount: Int
        let hitCount: Int
        let missCount: Int
        let evictionCount: Int
    }

    let directoryURL: URL
    let byteLimit: Int
    private var hitCount = 0
    private var missCount = 0
    private var evictionCount = 0

    init(
        directoryURL: URL = LMRemoteResourceDiskCache.defaultDirectoryURL(),
        byteLimit: Int = LMRemoteResourceDiskCache.defaultByteLimit
    ) throws {
        self.directoryURL = directoryURL
        self.byteLimit = max(0, byteLimit)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        let root = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "io.positron.LM",
                isDirectory: true
            )
            .appendingPathComponent("RemoteLunarResources", isDirectory: true)
    }

    func data(sha256: String, expectedByteCount: Int) throws -> Data? {
        guard Self.isDigest(sha256) else {
            missCount += 1
            return nil
        }
        let url = fileURL(for: sha256)
        guard FileManager.default.fileExists(atPath: url.path) else {
            missCount += 1
            return nil
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count == expectedByteCount,
              LMContentDigest.sha256(data) == sha256 else {
            // Cache data is recoverable. Never hand corrupted bytes to a
            // decoder, and never leave them eligible for a later warm hit.
            try? FileManager.default.removeItem(at: url)
            missCount += 1
            return nil
        }
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: url.path
        )
        hitCount += 1
        return data
    }

    func insert(_ data: Data, sha256: String) throws {
        guard Self.isDigest(sha256), LMContentDigest.sha256(data) == sha256 else {
            return
        }
        guard data.count <= byteLimit else { return }
        let url = fileURL(for: sha256)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: url.path
        )
        try evictIfNeeded()
    }

    func statistics() throws -> Statistics {
        let entries = try cacheEntries()
        return Statistics(
            entryCount: entries.count,
            byteCount: entries.reduce(0) { $0 + $1.byteCount },
            hitCount: hitCount,
            missCount: missCount,
            evictionCount: evictionCount
        )
    }

    private struct CacheEntry {
        let url: URL
        let byteCount: Int
        let modified: Date
    }

    private func fileURL(for digest: String) -> URL {
        directoryURL.appendingPathComponent(digest, isDirectory: false)
    }

    private func cacheEntries() throws -> [CacheEntry] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
        return try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).compactMap { url in
            guard Self.isDigest(url.lastPathComponent) else { return nil }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { return nil }
            return CacheEntry(
                url: url,
                byteCount: values.fileSize ?? 0,
                modified: values.contentModificationDate ?? .distantPast
            )
        }
    }

    private func evictIfNeeded() throws {
        var entries = try cacheEntries().sorted { $0.modified < $1.modified }
        var total = entries.reduce(0) { $0 + $1.byteCount }
        while total > byteLimit, let oldest = entries.first {
            try FileManager.default.removeItem(at: oldest.url)
            total -= oldest.byteCount
            entries.removeFirst()
            evictionCount += 1
        }
    }

    private nonisolated static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

struct LMRemoteResourceLoader: Sendable {
    struct Product: Sendable {
        let data: Data
        let cacheHit: Bool
        let downloadedBytes: Int
        let attemptCount: Int
        let elapsedMilliseconds: Int
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "io.positron.LM",
        category: "RemoteLunarResources"
    )

    let fetcher: any LMRemoteResourceFetching
    let cache: LMRemoteResourceDiskCache
    let bundledOnly: Bool
    let maximumAttempts: Int

    init(
        fetcher: any LMRemoteResourceFetching = LMHTTPByteRangeFetcher(),
        cache: LMRemoteResourceDiskCache,
        bundledOnly: Bool = false,
        maximumAttempts: Int = 3
    ) {
        self.fetcher = fetcher
        self.cache = cache
        self.bundledOnly = bundledOnly
        self.maximumAttempts = max(1, maximumAttempts)
    }

    func resource(for request: LMRemoteResourceRequest) async throws -> Product {
        let started = ContinuousClock.now
        if let cached = try await cache.data(
            sha256: request.sha256,
            expectedByteCount: request.expectedByteCount
        ) {
            return Product(
                data: cached,
                cacheHit: true,
                downloadedBytes: 0,
                attemptCount: 0,
                elapsedMilliseconds: Self.milliseconds(
                    started.duration(to: .now)
                )
            )
        }
        guard !bundledOnly else {
            throw LMRemoteResourceError.networkDisabled
        }

        var lastError: Error?
        for attempt in 1...maximumAttempts {
            try Task.checkCancellation()
            do {
                let data = try await fetcher.fetch(request)
                guard data.count == request.expectedByteCount else {
                    throw LMRemoteResourceError.byteCount(
                        expected: request.expectedByteCount,
                        actual: data.count
                    )
                }
                let digest = LMContentDigest.sha256(data)
                guard digest == request.sha256 else {
                    throw LMRemoteResourceError.hashMismatch(
                        expected: request.sha256,
                        actual: digest
                    )
                }
                try Task.checkCancellation()
                try await cache.insert(data, sha256: request.sha256)
                return Product(
                    data: data,
                    cacheHit: false,
                    downloadedBytes: data.count,
                    attemptCount: attempt,
                    elapsedMilliseconds: Self.milliseconds(
                        started.duration(to: .now)
                    )
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        if let integrity = lastError as? LMRemoteResourceError {
            switch integrity {
            case .hashMismatch, .byteCount:
                Self.logger.error(
                    "Discarded hash-pinned lunar resource \(request.id, privacy: .public) after \(maximumAttempts) bounded integrity failures"
                )
            default:
                break
            }
            throw integrity
        }
        throw LMRemoteResourceError.attemptsExhausted(maximumAttempts)
    }

    private static func milliseconds(_ duration: ContinuousClock.Duration) -> Int {
        Int(
            duration.components.seconds * 1_000
                + duration.components.attoseconds / 1_000_000_000_000_000
        )
    }
}

enum LMContentDigest {
    nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
