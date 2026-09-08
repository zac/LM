import Foundation
import Testing
import RealityKit
@testable import LMKit

@Test @MainActor func legacySceneRetainsSimulationNodes() throws {
    let scene = try Entity.load(contentsOf: LMKitAssets.legacySceneURL)
    for name in ["lunarlander", "Physics", "group13_pC", "group13_g5", "group13_g7", "group13_g6", "group13_g4", "group13_10", "group13_g8", "group13_g9", "group13_11", "group13_12", "group13_13", "group13_14", "group13_p1", "group13_g2", "group13_g1", "group13_gr", "group13_g3"] {
        #expect(scene.findEntity(named: name) != nil, "Missing simulation node: \(name)")
    }
}
@Test @MainActor func neutralDSKYRetainsAddressableParts() throws {
    let scene = try Entity.load(contentsOf: LMKitAssets.dskyURL)
    let mount = try #require(scene.findEntity(named: "DSKY_Mount"))
    for key in ["VERB", "NOUN", "PLUS", "MINUS", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "CLR", "PRO", "KEY_REL", "ENTR", "RSET"] {
        let entity = try #require(mount.findEntity(named: "DSKY_Key_" + key))
        #expect(entity.parent === mount)
    }
    #expect(mount.findEntity(named: "DSKY_Display_Mount") != nil)
}
@Test func resourcePayloadsAreHydrated() throws {
    for url in [LMKitAssets.legacySceneURL, LMKitAssets.lunarModuleURL, LMKitAssets.dskyURL] {
        let data = try Data(contentsOf: url)
        #expect(!data.starts(with: Data("version https://git-lfs".utf8)))
        #expect(data.count > 1000)
    }
}

@Test func packagedDSKYMatchesAcceptedAuthoringExport() throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = repository.appendingPathComponent("Assets/Cockpit/Components/DSKY/DSKY.usdz")
    #expect(try Data(contentsOf: source) == Data(contentsOf: LMKitAssets.dskyURL))
}
