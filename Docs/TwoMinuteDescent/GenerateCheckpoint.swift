import Foundation
import LMCore

@main struct GenerateTwoMinuteCheckpoint {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let baseline = try LMSimulationCheckpoint.decodeFixture(Data(contentsOf: root.appendingPathComponent("LM/P64ApproachCheckpoint.bplist")))
        let runtime = try LMSimulationRuntime(binFile: root.appendingPathComponent("LM/Luminary099.bin"), scenario: .apollo11SourceBacked)
        var snapshot = try await runtime.restore(from: baseline)
        let step = 1.0 / 30.0
        // The measured baseline lands after 6,278 steps. Capture 3,600 steps before it.
        for _ in 0..<2678 {
            snapshot = await runtime.step(deltaTime: step, input: .autoLand(from: snapshot.vehicleState))
            precondition(!snapshot.vehicleState.flightOutcome.isTerminal)
        }
        let checkpoint = await runtime.captureCheckpoint()
        let data = try checkpoint.encodedFixture()
        let decoded = try LMSimulationCheckpoint.decodeFixture(data)
        precondition(decoded == checkpoint, "Checkpoint round-trip changed state")
        snapshot = try await runtime.restore(from: decoded)
        let start = snapshot.timeSeconds
        let altitude = snapshot.vehicleState.altitudeMeters
        let initialProgram = snapshot.agc.dsky.programNumber
        while !snapshot.vehicleState.flightOutcome.isTerminal && snapshot.timeSeconds - start < 150 {
            snapshot = await runtime.step(deltaTime: step, input: .autoLand(from: snapshot.vehicleState))
        }
        let elapsed = snapshot.timeSeconds - start
        precondition(snapshot.vehicleState.flightOutcome.rawValue == "softLanding", "Must reach a real soft landing")
        precondition(abs(elapsed - 120) < 0.1, "Checkpoint must start two minutes before touchdown")
        precondition(initialProgram == 64, "Expected a P64 approach checkpoint")
        try data.write(to: root.appendingPathComponent("LM/TwoMinuteApproachCheckpoint.bplist"))
        let result: [String: Any] = [
            "baselineStartSeconds": baseline.simulationTimeSeconds,
            "advanceSteps": 2678, "stepSeconds": step,
            "checkpointStartSeconds": start, "initialAltitudeMeters": altitude,
            "initialProgram": initialProgram as Any? ?? NSNull(),
            "elapsedSimulationSeconds": elapsed,
            "terminal": snapshot.vehicleState.flightOutcome.isTerminal,
            "terminalOutcome": snapshot.vehicleState.flightOutcome.rawValue,
            "finalAltitudeMeters": snapshot.vehicleState.altitudeMeters,
            "finalProgram": snapshot.agc.dsky.programNumber as Any? ?? NSNull(),
            "surface": "Default LMCore surface; rendered terrain and user input can change timing/outcome",
            "checkpointRoundTripEqual": decoded == checkpoint
        ]
        let report = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try report.write(to: root.appendingPathComponent("Docs/TwoMinuteDescent/headless-validation.json"))
        print(String(data: report, encoding: .utf8)!)
    }
}
