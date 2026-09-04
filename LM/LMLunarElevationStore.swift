import Foundation

/// Persistent, content-addressed storage for cataloged PDS elevation slabs.
/// A region resumes at complete verified slabs. Incomplete responses are never
/// published, and conversion remains the elevation grid consumer's job.
actor LMLunarElevationStore {
    enum StoreError: Error, Equatable {
        case invalidDescriptor
        case responseMismatch
        case truncatedResponse
        case digestMismatch
        case capacityExceeded
        case unavailableOffline
    }

    typealias Fetch = @Sendable (LMTerrainManifest.Source) async throws -> Data

    let directory: URL
    let capacityBytes: Int
    private let fetch: Fetch
    private var access = [String: Int]()
    private var clock = 0
    private var inFlight = [String: Task<Data, Error>]()

    init(directory: URL, capacityBytes: Int = 128 * 1_024 * 1_024,
         fetch: @escaping Fetch = LMLunarElevationStore.fetchPDS) throws {
        guard capacityBytes > 0 else { throw StoreError.capacityExceeded }
        self.directory = directory
        self.capacityBytes = capacityBytes
        self.fetch = fetch
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let indexURL = directory.appendingPathComponent("access.json")
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            access = decoded.filter { Self.validDigest($0.key) && $0.value >= 0 }
            clock = access.values.max() ?? 0
        }
        try Self.trimFiles(directory: directory, capacityBytes: capacityBytes, access: &access)
    }

    func data(for source: LMTerrainManifest.Source, offline: Bool = false) async throws -> Data {
        try Self.validate(source)
        guard let expectedBytes = source.bytes, expectedBytes <= capacityBytes else {
            throw StoreError.capacityExceeded
        }
        let url = directory.appendingPathComponent(source.sha256 + ".bin")
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
            if data.count == expectedBytes, LMLunarElevationGrid.digest(data) == source.sha256 {
                try touch(source.sha256)
                try trim()
                return data
            }
            try FileManager.default.removeItem(at: url)
            access.removeValue(forKey: source.sha256)
        }
        guard !offline else { throw StoreError.unavailableOffline }
        if let existing = inFlight[source.sha256] { return try await existing.value }
        let fetch = self.fetch
        let task = Task {
            let data = try await fetch(source)
            try Task.checkCancellation()
            guard data.count == expectedBytes else { throw StoreError.truncatedResponse }
            guard LMLunarElevationGrid.digest(data) == source.sha256 else {
                throw StoreError.digestMismatch
            }
            try data.write(to: url, options: .atomic)
            try touch(source.sha256)
            try trim()
            return data
        }
        inFlight[source.sha256] = task
        defer { inFlight.removeValue(forKey: source.sha256) }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Re-running an interrupted region skips its complete, verified products.
    /// Reject a region larger than the persistent cap instead of evicting its
    /// first tile before the final tile arrives.
    func prefetch(_ sources: [LMTerrainManifest.Source]) async throws {
        let unique = Dictionary(sources.map { ($0.sha256, $0) }, uniquingKeysWith: { first, _ in first })
        let total = try unique.values.reduce(0) { sum, source in
            try Self.validate(source)
            guard let bytes = source.bytes, bytes <= capacityBytes - sum else {
                throw StoreError.capacityExceeded
            }
            return sum + bytes
        }
        guard total <= capacityBytes else { throw StoreError.capacityExceeded }
        for source in unique.values.sorted(by: { $0.sha256 < $1.sha256 }) {
            try Task.checkCancellation()
            _ = try await data(for: source)
        }
    }

    private func touch(_ digest: String) throws {
        clock += 1
        access[digest] = clock
        try JSONEncoder().encode(access).write(
            to: directory.appendingPathComponent("access.json"), options: .atomic
        )
    }

    private func trim() throws {
        try Self.trimFiles(directory: directory, capacityBytes: capacityBytes, access: &access)
    }

    private static func trimFiles(directory: URL, capacityBytes: Int,
                                  access: inout [String: Int]) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]
        ).filter { $0.pathExtension == "bin" && Self.validDigest($0.deletingPathExtension().lastPathComponent) }
        var entries: [(url: URL, bytes: Int, stamp: Int)] = []
        for url in files {
            let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let stamp = access[url.deletingPathExtension().lastPathComponent] ?? -1
            entries.append((url, bytes, stamp))
        }
        entries.sort { lhs, rhs in
            if lhs.stamp == rhs.stamp { return lhs.url.lastPathComponent < rhs.url.lastPathComponent }
            return lhs.stamp < rhs.stamp
        }
        var total = entries.reduce(0) { $0 + $1.bytes }
        while total > capacityBytes, !entries.isEmpty {
            let entry = entries.removeFirst()
            try FileManager.default.removeItem(at: entry.url)
            access.removeValue(forKey: entry.url.deletingPathExtension().lastPathComponent)
            total -= entry.bytes
        }
        try JSONEncoder().encode(access).write(
            to: directory.appendingPathComponent("access.json"), options: .atomic
        )
    }

    private static func validDigest(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func validate(_ source: LMTerrainManifest.Source) throws {
        guard validDigest(source.sha256), let url = URL(string: source.url), url.scheme == "https",
              let count = source.bytes, count > 0,
              let start = source.byteRangeStart, start >= 0,
              let end = source.byteRangeEnd, end >= start,
              let total = source.sourceBytes, end < total,
              end - start + 1 == count, let record = source.sourceRowBytes, record > 0,
              start % record == 0, (end + 1) % record == 0 else {
            throw StoreError.invalidDescriptor
        }
    }

    nonisolated static func validateResponse(_ response: URLResponse, source: LMTerrainManifest.Source) throws {
        try validate(source)
        guard let http = response as? HTTPURLResponse,
              let start = source.byteRangeStart, let end = source.byteRangeEnd,
              let total = source.sourceBytes, let count = source.bytes else {
            throw StoreError.responseMismatch
        }
        if http.statusCode >= 500 || http.statusCode == 429 {
            throw URLError(.resourceUnavailable)
        }
        guard http.statusCode == 206,
              http.value(forHTTPHeaderField: "Content-Range") == "bytes \(start)-\(end)/\(total)",
              http.expectedContentLength == -1 || http.expectedContentLength == count,
              http.value(forHTTPHeaderField: "Content-Encoding").map({ $0 == "identity" }) ?? true else {
            throw StoreError.responseMismatch
        }
    }

    /// Check HTTP status and range before consuming the body. Refuse a server
    /// that ignores Range instead of allocating the complete 1.4 GB product.
    nonisolated static func fetchPDS(_ source: LMTerrainManifest.Source) async throws -> Data {
        try validate(source)
        guard let start = source.byteRangeStart, let end = source.byteRangeEnd,
              let count = source.bytes, let url = URL(string: source.url) else {
            throw StoreError.invalidDescriptor
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        for attempt in 0..<3 {
            do {
                var request = URLRequest(url: url)
                request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                let (bytes, response) = try await session.bytes(for: request)
                try validateResponse(response, source: source)
                var data = Data()
                data.reserveCapacity(count)
                for try await byte in bytes {
                    guard data.count < count else { throw StoreError.responseMismatch }
                    data.append(byte)
                }
                try Task.checkCancellation()
                guard data.count == count else { throw StoreError.truncatedResponse }
                return data
            } catch {
                try Task.checkCancellation()
                guard attempt < 2, error is URLError || error as? StoreError == .truncatedResponse else { throw error }
                try await Task.sleep(for: .milliseconds(250 * (attempt + 1)))
            }
        }
        throw StoreError.responseMismatch
    }
}
