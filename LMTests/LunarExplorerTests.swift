@testable import LunarMapExplorer
@testable import LunarMap
import Testing
import RealityKit
import simd
@testable import LM

@Suite("Lunar Explorer")
@MainActor
struct LunarExplorerTests {
    @Test func appModelConfiguresExplorerBeforeRestoredWindowsAppear() {
        let model = MainMenuViewModel(arguments: [
            "LM",
            "--lunar-explorer",
            "--lunar-explorer-preset=surface",
            "--lunar-explorer-focus=northBoulderField",
        ])

        #expect(model.lunarExplorerSession.selectedPreset == .surface)
        #expect(model.lunarExplorerSession.altitudeMeters == 2)
        #expect(model.lunarExplorerSession.selectedFocus == .northBoulderField)
    }
}
