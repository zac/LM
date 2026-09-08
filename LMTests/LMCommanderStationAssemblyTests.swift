import Foundation
import LMKit
import RealityKit
import Testing
import simd
@testable import LM

@MainActor
struct LMCommanderStationAssemblyTests {
    @Test func reconcilesNestedMountsAndPreservesOpticalBasis() throws {
        let assembly = try LMCommanderStationAssembly.load()
        for name in ["Mount_DSKY", "Mount_FDAI"] {
            let proposed = try #require(assembly.manifest.mounts[name])
            let position = SIMD3<Float>(proposed.position[0], proposed.position[1], proposed.position[2])
            let entity = try LMCommanderStationAssembly.unique(name, in: assembly.cabin)
            #expect(simd_distance(entity.position(relativeTo: assembly.cabin), position) < 0.00001)
            #expect(simd_length(entity.scale - SIMD3<Float>(repeating: 1)) < 0.00001)
            #expect(entity.children.allSatisfy { !$0.isEnabled })
        }
        let lpd = LMLandingPointDesignator()
        let inner = try LMCommanderStationAssembly.unique("CDR_Window_Inner", in: assembly.cabin)
        let outer = try LMCommanderStationAssembly.unique("CDR_Window_Outer", in: assembly.cabin)
        let normal = inner.orientation(relativeTo: assembly.cabin).act(SIMD3<Float>(0, 0, 1))
        #expect(abs(simd_dot(inner.position(relativeTo: assembly.cabin) - outer.position(relativeTo: assembly.cabin), normal) - 0.020) < 0.00001)
        #expect(simd_distance(inner.position(relativeTo: assembly.cabin), lpd.windowCorners(on: .inner)[0]) < 0.00001)
        for name in ["VisualOnly_MaintainedToggle", "VisualOnly_RotarySelector"] {
            let node = try LMCommanderStationAssembly.unique(name, in: assembly.cabin)
            #expect(LMCommanderStationAssembly.descendants(node).allSatisfy { $0.components[InputTargetComponent.self] == nil && $0.components[CollisionComponent.self] == nil })
        }
    }

    @Test func atomicFallbackAndInstallKeepLiveIdentities() throws {
        let station = LMCommanderStationScene()
        let keys = station.dskyKeyEntities
        let transforms = keys.map { $0.transformMatrix(relativeTo: station.dskyFaceRoot) }
        let nodes = LMCommanderStationAssembly.descendants(station.root)
        let enabledBefore = nodes.map(\.isEnabled)
        let grids = nodes.filter { $0.name == LMCockpitAssetContract.Node.landingPointDesignatorInner.rawValue || $0.name == LMCockpitAssetContract.Node.landingPointDesignatorOuter.rawValue }
        #expect(grids.count == 2)
        let gridTransforms = grids.map { $0.transformMatrix(relativeTo: station.root) }
        #expect(!station.installCommanderAssembly { throw LMCommanderStationAssembly.AssemblyError.invalidContract("test failure") })
        #expect(station.commanderAssembly == nil)
        #expect(nodes.map(\.isEnabled) == enabledBefore)
        #expect(station.installCommanderAssembly())
        let assembly = try #require(station.commanderAssembly)
        let reservation = try LMCommanderStationAssembly.unique("Mount_DSKY", in: assembly.cabin)
        #expect(simd_distance(station.dskyFaceRoot.position, reservation.position(relativeTo: assembly.cabin)) < 0.00001)
        #expect(station.dskyFaceRoot.scale == SIMD3<Float>(repeating: 1))
        #expect(station.installCommanderAssembly { throw LMCommanderStationAssembly.AssemblyError.invalidContract("must not reload") })
        for (i, key) in keys.enumerated() {
            #expect(key === station.dskyKeyEntities[i])
            #expect(station.dskyKeyCode(for: key) != nil)
            #expect(LMCommanderStationAssembly.near(key.transformMatrix(relativeTo: station.dskyFaceRoot), transforms[i]))
        }
        for (i, grid) in grids.enumerated() {
            #expect(grid.isEnabled)
            #expect(LMCommanderStationAssembly.near(grid.transformMatrix(relativeTo: station.root), gridTransforms[i]))
            #expect(grid.parent?.name == "App optical marks and functional control supports")
        }
        let active = LMCommanderStationAssembly.descendants(station.root).filter { entity in
            var node: Entity? = entity
            while let current = node { if !current.isEnabled { return false }; node = current.parent }
            return true
        }
        #expect(active.filter { $0.name == "DSKY_Key_PRO" }.count == 1)
        #expect(active.filter { $0.name == "FDAI_Ball_Pivot" }.count == 1)
        #expect(!active.contains { $0.name == "Panel_1_Reservation" || $0.name == "Panel_4_Reservation" })
    }

    @Test func rejectsBadManifestWithoutPublishing() throws {
        let data = try Data(contentsOf: LMKitAssets.cabinMountsURL)
        let corrupted = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "NOT parent-local", with: "parent-local").utf8)
        #expect(throws: (any Error).self) {
            try LMCommanderStationAssembly(asset: Entity.load(contentsOf: LMKitAssets.cabinSkeletonURL), manifestData: corrupted,
                                           loadControl: { try Entity.load(contentsOf: LMKitAssets.controlURL($0)) })
        }
    }
    @Test func installsPanelSurroundsOnceAndRejectsMismatchedInterfaces() throws {
        let assembly = try LMCommanderStationAssembly.load()
        let panels = try LMCommanderStationAssembly.unique("CommanderPanels", in: assembly.cabin)
        #expect(LMCommanderStationAssembly.near(panels.transformMatrix(relativeTo: assembly.cabin), matrix_identity_float4x4))
        for name in ["DSKY", "FDAI"] {
            let interface = try LMCommanderStationAssembly.unique(name + "_Interface", in: panels)
            let reservation = try LMCommanderStationAssembly.unique("Mount_" + name, in: assembly.cabin)
            #expect(LMCommanderStationAssembly.near(interface.transformMatrix(relativeTo: assembly.cabin), reservation.transformMatrix(relativeTo: assembly.cabin)))
        }
        let invalid = try Entity.load(contentsOf: LMKitAssets.commanderPanelsURL)
        let interface = try LMCommanderStationAssembly.unique("FDAI_Interface", in: invalid)
        interface.position.x += 0.01
        #expect(throws: (any Error).self) {
            try LMCommanderStationAssembly(asset: Entity.load(contentsOf: LMKitAssets.cabinSkeletonURL),
                manifestData: Data(contentsOf: LMKitAssets.cabinMountsURL),
                loadControl: { try Entity.load(contentsOf: LMKitAssets.controlURL($0)) },
                loadPanels: { invalid })
        }
    }
    @Test func instrumentObserverHasPrecedence() {
        #expect(LMCommanderStationAssemblyObserver.selected(arguments: []) == nil)
        #expect(LMCommanderStationAssemblyObserver.selected(arguments: ["--assembly-validation-view=side"]) == .side)
        #expect(LMCommanderStationAssemblyObserver.selected(arguments: ["--assembly-validation-view=front", "--instrument-validation"]) == nil)
    }
}
