import simd

/// Gesture-only ray march through resident measured height posts. Contact and
/// rendered detail keep their existing samplers; an anchor need not hit a rock
/// or the procedural residual. Points remain in the source's +north,+up,-east frame.
struct LunarExplorerHeightFieldPicker: Sendable {
    private enum Storage: Sendable {
        case heights([Float])
        case residentGrid([SIMD3<Float>])
        subscript(_ index: Int) -> Float {
            switch self {
            case .heights(let values): values[index]
            case .residentGrid(let values): values[index].y
            }
        }
    }
    let posts: Int
    let spacingMeters: Double
    let holeHalfExtentMeters: Double
    private let storage: Storage
    private let minimumHeight: Double
    private let maximumHeight: Double
    var halfExtent: Double { Double(posts - 1) * spacingMeters / 2 }
    var additionalHeightBytes: Int {
        if case .heights(let values) = storage { return values.count * MemoryLayout<Float>.stride }
        return 0 // CoW reference to the near grid the contact/render path already retains.
    }

    init(posts: Int, spacingMeters: Double, heights: [Float], holeHalfExtentMeters: Double = 0) {
        self.init(posts: posts, spacingMeters: spacingMeters, storage: .heights(heights),
                  holeHalfExtentMeters: holeHalfExtentMeters)
    }

    init(grid: LMTerrainMeshBuilder.VertexData, tile: LMTerrainManifest.Tile,
         retainingResidentPositions: Bool, holeHalfExtentMeters: Double) {
        self.init(posts: tile.postsPerSide, spacingMeters: tile.postSpacingMeters,
                  storage: retainingResidentPositions ? .residentGrid(grid.positions) : .heights(grid.positions.map(\.y)),
                  holeHalfExtentMeters: holeHalfExtentMeters)
    }

    private init(posts: Int, spacingMeters: Double, storage: Storage, holeHalfExtentMeters: Double) {
        precondition(posts >= 2 && spacingMeters > 0)
        self.posts = posts
        self.spacingMeters = spacingMeters
        self.holeHalfExtentMeters = holeHalfExtentMeters
        self.storage = storage
        var minimum = Double.infinity, maximum = -Double.infinity
        for i in 0..<(posts * posts) {
            minimum = min(minimum, Double(storage[i]))
            maximum = max(maximum, Double(storage[i]))
        }
        minimumHeight = minimum
        maximumHeight = maximum
    }

    func raycast(origin: SIMD3<Float>, direction: SIMD3<Float>) -> SIMD3<Float>? {
        let o = SIMD3<Double>(origin), d = SIMD3<Double>(direction), half = halfExtent
        guard simd_length_squared(d) > 0 else { return nil }
        var enter = 0.0, exit = Double.infinity
        // Clip before marching. Double avoids cancellation in regional-scale rays.
        for axis in 0..<3 {
            let low = axis == 1 ? minimumHeight - 0.001 : -half
            let high = axis == 1 ? maximumHeight + 0.001 : half
            if abs(d[axis]) < 1e-14 {
                guard o[axis] >= low && o[axis] <= high else { return nil }
            } else {
                let a = (low - o[axis]) / d[axis], b = (high - o[axis]) / d[axis]
                enter = max(enter, min(a, b))
                exit = min(exit, max(a, b))
            }
        }
        guard enter <= exit, exit >= 0 else { return nil }
        let rowOrigin = (half - o.x) / spacingMeters
        let columnOrigin = (half - o.z) / spacingMeters
        let rowSpeed = -d.x / spacingMeters, columnSpeed = -d.z / spacingMeters
        let start = min(exit, enter + 1e-8)
        var row = min(posts - 2, max(0, Int(floor(rowOrigin + rowSpeed * start))))
        var column = min(posts - 2, max(0, Int(floor(columnOrigin + columnSpeed * start))))
        func nextBoundary(_ cell: Int, _ origin: Double, _ speed: Double) -> Double {
            guard abs(speed) > 1e-14 else { return .infinity }
            return (Double(cell + (speed > 0 ? 1 : 0)) - origin) / speed
        }
        func vertex(_ row: Int, _ column: Int) -> SIMD3<Double> {
            SIMD3(half - Double(row) * spacingMeters, Double(storage[row * posts + column]),
                  half - Double(column) * spacingMeters)
        }
        func triangle(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) -> Double? {
            let edge1 = b - a, edge2 = c - a
            let p = simd_cross(d, edge2), determinant = simd_dot(edge1, p)
            guard abs(determinant) > 1e-12 else { return nil }
            let delta = o - a, u = simd_dot(delta, p) / determinant
            guard u >= -1e-9, u <= 1 + 1e-9 else { return nil }
            let q = simd_cross(delta, edge1), v = simd_dot(d, q) / determinant
            guard v >= -1e-9, u + v <= 1 + 1e-9 else { return nil }
            let t = simd_dot(edge2, q) / determinant
            return t >= 0 ? t : nil
        }
        // A ray parallel to an exact grid line belongs to both adjacent
        // cells. This matters at ownership-hole edges, where only one is owned.
        let onRowEdge = abs(rowSpeed) < 1e-14 && abs(rowOrigin - rowOrigin.rounded()) < 1e-9
        let onColumnEdge = abs(columnSpeed) < 1e-14 && abs(columnOrigin - columnOrigin.rounded()) < 1e-9
        // A ray visits at most two grid dimensions' worth of cells.
        for _ in 0..<(2 * posts + 2) {
            guard row >= 0, row < posts - 1, column >= 0, column < posts - 1 else { break }
            let rowEnd = nextBoundary(row, rowOrigin, rowSpeed)
            let columnEnd = nextBoundary(column, columnOrigin, columnSpeed)
            let end = min(exit, min(rowEnd, columnEnd))
            for r in (row - (onRowEdge ? 1 : 0))...row {
                for col in (column - (onColumnEdge ? 1 : 0))...column {
                    guard r >= 0, r < posts - 1, col >= 0, col < posts - 1 else { continue }
                    let north = half - (Double(r) + 0.5) * spacingMeters
                    let east = (Double(col) + 0.5) * spacingMeters - half
                    if abs(north) < holeHalfExtentMeters && abs(east) < holeHalfExtentMeters { continue }
                    let a = vertex(r, col), b = vertex(r, col + 1)
                    let c = vertex(r + 1, col), e = vertex(r + 1, col + 1)
                    let t = min(triangle(a, b, c) ?? .infinity, triangle(b, e, c) ?? .infinity)
                    if t.isFinite, t >= enter - 1e-6, t <= end + 1e-6 {
                        return SIMD3<Float>(o + d * t)
                    }
                }
            }
            if end >= exit { break }
            if rowEnd <= columnEnd { row += rowSpeed > 0 ? 1 : -1 }
            if columnEnd <= rowEnd { column += columnSpeed > 0 ? 1 : -1 }
            enter = end
        }
        return nil
    }
}
