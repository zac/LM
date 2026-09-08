import Foundation

/// Serializes terrain publication with complete simulation steps. Main-actor
/// isolation alone does not prevent overlap across an awaited AGC/GPU call.
@MainActor
public final class LMTerrainSimulationGate {
    public init() {}

    private var occupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public func withAccess<T>(_ operation: @MainActor () async throws -> T) async rethrows -> T {
        if occupied {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            occupied = true
        }
        defer {
            if waiters.isEmpty { occupied = false }
            else { waiters.removeFirst().resume() }
        }
        return try await operation()
    }
}
