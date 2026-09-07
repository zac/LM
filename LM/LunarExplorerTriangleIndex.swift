import simd

/// A bounding hierarchy over unchanged submitted triangles. Retaining the
/// extracted buffers avoids RealityKit's full-buffer conversion on every pick.
/// The owning entity's mesh revision controls invalidation.
struct LunarExplorerTriangleIndex: Sendable {
    private struct Node: Sendable {
        var minimum = SIMD3<Float>(repeating: .infinity)
        var maximum = SIMD3<Float>(repeating: -.infinity)
        var first = 0
        var count = 0
    }
    private var nodes: [Node] = []
    let positions: [SIMD3<Float>]
    let indices: [UInt32]
    var byteCount: Int {
        nodes.count * MemoryLayout<Node>.stride
            + positions.count * MemoryLayout<SIMD3<Float>>.stride
            + indices.count * MemoryLayout<UInt32>.stride
    }

    init(positions: [SIMD3<Float>], indices: [UInt32]) {
        self.positions = positions
        self.indices = indices
        guard !indices.isEmpty else { return }
        nodes = [Node()]
        func build(_ slot: Int, _ start: Int, _ count: Int) {
            if count <= 96 * 3 {
                var node = Node()
                node.first = start; node.count = count
                for i in start..<(start + count) {
                    let point = positions[Int(indices[i])]
                    node.minimum = simd_min(node.minimum, point)
                    node.maximum = simd_max(node.maximum, point)
                }
                nodes[slot] = node
            } else {
                let left = nodes.count
                nodes.append(Node()); nodes.append(Node())
                let half = (count / 6) * 3
                build(left, start, half)
                build(left + 1, start + half, count - half)
                nodes[slot] = Node(minimum: simd_min(nodes[left].minimum, nodes[left + 1].minimum),
                                   maximum: simd_max(nodes[left].maximum, nodes[left + 1].maximum),
                                   first: left, count: 0)
            }
        }
        build(0, 0, indices.count)
    }

    func candidates(origin: SIMD3<Float>, direction: SIMD3<Float>) -> [Range<Int>] {
        guard !nodes.isEmpty else { return [] }
        var result: [Range<Int>] = []
        func visit(_ slot: Int) {
            let node = nodes[slot]
            guard LunarExplorerPinchGeometry.intersectsBounds(origin: origin, direction: direction,
                minimum: node.minimum, maximum: node.maximum) else { return }
            if node.count > 0 { result.append(node.first..<(node.first + node.count)) }
            else { visit(node.first); visit(node.first + 1) }
        }
        visit(0)
        return result
    }
}
