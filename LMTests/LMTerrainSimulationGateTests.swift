@testable import LunarMap
import Foundation
import Testing
@testable import LM

@Suite("Terrain simulation publication")
struct LMTerrainSimulationGateTests {
    @Test @MainActor func publicationCannotOverlapAnAwaitingPhysicsStep() async {
        let gate = LMTerrainSimulationGate()
        var events = [String]()
        let (stream, signal) = AsyncStream<Void>.makeStream()
        let physics = Task { @MainActor in
            await gate.withAccess {
                events.append("step-start")
                signal.yield(())
                try? await Task.sleep(for: .milliseconds(30))
                events.append("step-end")
            }
        }
        for await _ in stream { break }
        await gate.withAccess { events.append("publish") }
        await physics.value
        #expect(events == ["step-start", "step-end", "publish"])
        signal.finish()
    }

    @Test @MainActor func cancelledPublicationReleasesGateWithoutChangingSurface() async {
        let gate = LMTerrainSimulationGate()
        var surface = 1
        let (stream, signal) = AsyncStream<Void>.makeStream()
        let first = Task { @MainActor in
            await gate.withAccess {
                signal.yield(())
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
        for await _ in stream { break }
        let cancelled = Task { @MainActor in
            try await gate.withAccess {
                try Task.checkCancellation()
                surface = 2
            }
        }
        cancelled.cancel()
        _ = try? await cancelled.value
        await first.value
        await gate.withAccess { #expect(surface == 1); surface = 3 }
        #expect(surface == 3)
        signal.finish()
    }
}
