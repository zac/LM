import Foundation
import LMCore
@main struct Measure {
 static func main() async throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]);let checkpoint=try LMSimulationCheckpoint.decodeFixture(Data(contentsOf:root.appendingPathComponent("LM/P65TerminalDescentCheckpoint.bplist")))
  let runtime=try LMSimulationRuntime(binFile:root.appendingPathComponent("LM/Luminary099.bin"),scenario:.apollo11SourceBacked)
  var snapshot=try await runtime.restore(from:checkpoint);let start=snapshot.timeSeconds;let altitude=snapshot.vehicleState.altitudeMeters;var probe:Double?;var pad:Double?
  while !snapshot.vehicleState.flightOutcome.isTerminal && snapshot.timeSeconds-start<120 {
   snapshot=await runtime.step(deltaTime:1.0/30.0,input:.autoLand(from:snapshot.vehicleState))
   if probe==nil && snapshot.vehicleState.landingGear?.isProbeContact==true {probe=snapshot.timeSeconds-start}
   if pad==nil && snapshot.vehicleState.surfaceContact != nil {pad=snapshot.timeSeconds-start}
  }
  let result:[String:Any]=["checkpointStartSeconds":start,"initialAltitudeMeters":altitude,"elapsedSimulationSeconds":snapshot.timeSeconds-start,"terminalOutcome":snapshot.vehicleState.flightOutcome.rawValue,"terminal":snapshot.vehicleState.flightOutcome.isTerminal,"finalAltitudeMeters":snapshot.vehicleState.altitudeMeters,"probeSeconds":probe as Any? ?? NSNull(),"padSeconds":pad as Any? ?? NSNull(),"program":snapshot.agc.dsky.programNumber as Any? ?? NSNull(),"stepSeconds":1.0/30.0,"surface":"default LMCore surface; rendered-terrain acceptance separately required"]
  let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]);try data.write(to:root.appendingPathComponent("Docs/OneMinuteDemo/headless-p65.json"));print(String(data:data,encoding:.utf8)!)
 }
}
