import AGC
import Foundation
import RealityKit
import Testing
@testable import LM

struct LMInstrumentInteractionTests {
    @Test @MainActor func completedEntitySelectionsReachFIFOInOrder() async throws {
        let station = LMCommanderStationScene()
        let queue = LMDSKYInputQueue()
        var events: [String] = []
        let sequence: [DSKYKeyCode] = [.verb, .digit1, .digit6, .noun, .digit3, .digit6, .enter,
                                        .digit7, .digit8, .pro, .pro]
        for key in sequence {
            let entity = try #require(station.dskyKeyEntities.first { station.dskyKeyCode(for: $0) == key })
            // Use a mesh descendant, as a targeted gesture may report that child.
            let target = entity.children.first ?? entity
            #expect(LMInstrumentInteraction.completedTap(on: target, station: station, sendKey: { code in
                queue.enqueue(code, sendKey: { events.append($0.label) },
                              sendPRO: { events.append($0 ? "PRO down" : "PRO up") })
            }))
        }
        await queue.waitUntilIdle()
        #expect(events == ["VERB", "1", "6", "NOUN", "3", "6", "ENTR", "7", "8",
                           "PRO down", "PRO up", "PRO down", "PRO up"])
        let impostor = Entity(); impostor.name = "DSKY_Key_PRO"
        #expect(!LMInstrumentInteraction.completedTap(on: impostor, station: station,
                                                      sendKey: { _ in Issue.record("Impostor dispatched") }))
        #expect(!LMInstrumentInteraction.completedTap(on: Entity(), station: station,
                                                      sendKey: { _ in Issue.record("Face dispatched") }))
    }

    @Test @MainActor func completedAdapterSequenceProducesLiveLuminaryResponse() async throws {
        // Synthetic calls to the production completion adapter, NOT OS pinch evidence.
        let station = LMCommanderStationScene()
        let session = PoweredDescentSession()
        session.start(from: .p64Approach)
        defer { session.stop() }
        func waitFor(_ condition: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(15)
            while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
            #expect(condition())
        }
        try await waitFor { session.dsky?.mode == "64" }
        for key in [DSKYKeyCode.verb, .digit1, .digit6, .noun, .digit3, .digit6, .enter] {
            let entity = try #require(station.dskyKeyEntities.first { station.dskyKeyCode(for: $0) == key })
            #expect(LMInstrumentInteraction.completedTap(on: entity, station: station,
                                                          sendKey: { session.sendDSKYKey($0) }))
            try await Task.sleep(for: .milliseconds(200))
        }
        try await waitFor { session.dsky?.verb == "16" && session.dsky?.noun == "36" }
        let pro = try #require(station.dskyKeyEntities.first { station.dskyKeyCode(for: $0) == .pro })
        #expect(LMInstrumentInteraction.completedTap(on: pro, station: station,
                                                      sendKey: { session.sendDSKYKey($0) }))
        try await waitFor {
            session.dsky?.verb == "06" && session.dsky?.noun == "64" && session.dsky?.proKeyPressed == false
        }
    }
}
