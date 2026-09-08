import Foundation
import LMKit
import RealityKit
import Testing
@testable import LM

@MainActor
@Suite(.serialized)
struct LMCockpitConsoleEnclosureTests {
    private func urls(_ kind: LMCockpitConsoleEnclosure.Kind) -> (URL, URL) {
        switch kind {
        case .instrument: (LMKitAssets.instrumentConsoleURL, LMKitAssets.instrumentConsoleInterfaceURL)
        case .lower: (LMKitAssets.lowerConsoleURL, LMKitAssets.lowerConsoleInterfaceURL)
        case .windows: (LMKitAssets.windowSurroundsURL, LMKitAssets.windowSurroundsInterfaceURL)
        }
    }
    private func load(_ kind: LMCockpitConsoleEnclosure.Kind,
                      mutate: ((inout [String: Any]) -> Void)? = nil) throws -> LMCockpitConsoleEnclosure {
        let (asset, metadata) = urls(kind)
        var contract = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        mutate?(&contract)
        return try LMCockpitConsoleEnclosure(kind: kind, asset: Entity.load(contentsOf: asset),
            interfaceData: JSONSerialization.data(withJSONObject: contract))
    }
    private func component(_ name: String, _ assembly: LMCommanderStationAssembly) -> Entity {
        ["Cabin": assembly.cabin, "CommanderPanels": assembly.panels,
         "PanelInventory": assembly.panelInventory, "WindowsLPD": assembly.windows][name]!
    }
    private func enabledState(_ assembly: LMCommanderStationAssembly) -> [ObjectIdentifier: Bool] {
        Dictionary(uniqueKeysWithValues: LMCommanderStationAssembly.descendants(assembly.root).map { (ObjectIdentifier($0), $0.isEnabled) })
    }

    @Test func opticalInspectionUsesFrozenCommanderEyeAndWindowCenter() {
        let pose = LMCommanderStationAssemblyObserver.pose(for: .lpd)
        let optics = LMLandingPointDesignator()
        #expect(pose.eye == optics.commanderEyeMeters)
        let center = LMLPDWindowCorner.allCases.reduce(SIMD3<Float>.zero) {
            $0 + optics.windowCorner($1, on: .inner)
        } / Float(LMLPDWindowCorner.allCases.count)
        #expect(pose.target == center)
        #expect(LMCommanderStationAssemblyObserver.selected(arguments: ["--assembly-validation-view=lpd"]) == .lpd)
    }

    @Test func allThreeEnclosuresPreserveMountsOccupancyAndRestoreQualifiedCasters() throws {
        let assembly = try LMCommanderStationAssembly.load()
        let occupancy = assembly.slotOccupancy
        for kind in LMCockpitConsoleEnclosure.Kind.allCases {
            let enclosure = try load(kind)
            let before = enabledState(assembly)
            let changed = Set(try enclosure.contract.suppressions.map {
                ObjectIdentifier(try LMCommanderStationAssembly.path($0.path, in: component($0.component, assembly)))
            })
            try assembly.installConsoleEnclosure(enclosure)
            #expect(enclosure.root.parent === assembly.root)
            for node in LMCommanderStationAssembly.descendants(assembly.root) {
                if let original = before[ObjectIdentifier(node)] {
                    #expect(node.isEnabled == (changed.contains(ObjectIdentifier(node)) ? false : original))
                }
            }
            for group in enclosure.contract.groups {
                let root = try LMCommanderStationAssembly.path(group.path, in: enclosure.root)
                for mesh in LMCommanderStationAssembly.descendants(root) where mesh.components[ModelComponent.self] != nil {
                    #expect(mesh.components[DynamicLightShadowComponent.self]?.castsShadow == group.casts_shadows)
                    #expect(mesh.components[InputTargetComponent.self] == nil)
                }
            }
            for ref in enclosure.contract.protected_mounts {
                let root = component(ref.component, assembly)
                let node = try LMCommanderStationAssembly.path(ref.path, in: root)
                #expect(LMCommanderStationAssembly.near(node.transformMatrix(relativeTo: root), try ref.pose.matrix()))
            }
        }
        #expect(assembly.consoleEnclosures.count == 3)
        #expect(assembly.slotOccupancy.keys.sorted() == occupancy.keys.sorted())
        #expect(assembly.slotOccupancy.isEmpty)
    }

    @Test func latePoseMismatchRollsBackEverySurfaceAndAllowsRetry() throws {
        let assembly = try LMCommanderStationAssembly.load()
        let before = enabledState(assembly)
        let bad = try load(.windows) { contract in
            var refs = contract["suppressions"] as! [[String: Any]]
            var pose = refs[refs.count - 1]["pose"] as! [String: Any]
            pose["position_m"] = [0, 0, 0.1]
            refs[refs.count - 1]["pose"] = pose
            contract["suppressions"] = refs
        }
        #expect(throws: (any Error).self) { try assembly.installConsoleEnclosure(bad) }
        #expect(enabledState(assembly) == before)
        #expect(bad.root.parent == nil && assembly.consoleEnclosures.isEmpty)
        try assembly.installConsoleEnclosure(load(.windows))
        #expect(assembly.consoleEnclosures.count == 1)
    }

    @Test func protectedPoseMismatchAndUnexpectedPathsAreRejected() throws {
        let assembly = try LMCommanderStationAssembly.load()
        let before = enabledState(assembly)
        let bad = try load(.lower) { contract in
            var refs = contract["protected_mounts"] as! [[String: Any]]
            var pose = refs[0]["pose"] as! [String: Any]
            pose["position_m"] = [0, 0, 0]
            refs[0]["pose"] = pose
            contract["protected_mounts"] = refs
        }
        #expect(throws: (any Error).self) { try assembly.installConsoleEnclosure(bad) }
        #expect(enabledState(assembly) == before)
        #expect(throws: (any Error).self) {
            try load(.instrument) { contract in
                var refs = contract["suppressions"] as! [[String: Any]]
                refs[0]["path"] = "/PanelInventory/Panels/Panel1"
                contract["suppressions"] = refs
            }
        }
    }

    @Test func duplicateOrInteractiveReplacementLeavesPeersUntouched() throws {
        let assembly = try LMCommanderStationAssembly.load()
        let first = try load(.lower)
        let ref = first.contract.suppressions[0]
        let target = try LMCommanderStationAssembly.path(ref.path, in: component(ref.component, assembly))
        target.components.set(InputTargetComponent())
        let before = enabledState(assembly)
        #expect(throws: (any Error).self) { try assembly.installConsoleEnclosure(first) }
        #expect(enabledState(assembly) == before)
        target.components.remove(InputTargetComponent.self)
        try assembly.installConsoleEnclosure(first)
        let installed = enabledState(assembly)
        #expect(throws: (any Error).self) { try assembly.installConsoleEnclosure(load(.lower)) }
        #expect(enabledState(assembly) == installed)
        #expect(assembly.consoleEnclosures.count == 1)
    }

    @Test func invalidOrOverlappingGroupsAndNonfinitePoseAreRejected() throws {
        #expect(throws: (any Error).self) {
            try load(.windows) { contract in
                var groups = contract["groups"] as! [[String: Any]]
                groups.append(groups[0]); contract["groups"] = groups
            }
        }
        #expect(throws: (any Error).self) {
            try load(.windows) { contract in
                var groups = contract["groups"] as! [[String: Any]]
                groups[0]["casts_shadows"] = false; contract["groups"] = groups
            }
        }
        #expect(throws: (any Error).self) {
            try load(.lower) { $0["root_pose"] = ["position_m": [true, false, false], "rotation_quaternion_xyzw": [0, 0, 0, 1], "scale": [1, 1, 1]] }
        }
    }

    @Test func sceneRequiresLiveAperturesAndRepeatedInstallationPreservesInstances() throws {
        let scene = LMCommanderStationScene()
        #expect(!scene.installConsoleEnclosure(.windows))
        #expect(scene.installCommanderAssembly())
        let assembly = try #require(scene.commanderAssembly)
        #expect(!scene.installConsoleEnclosure(.instrument))
        #expect(assembly.consoleEnclosures.isEmpty)
        #expect(scene.installPilotFDAI())
        let commander = try #require(scene.importedFDAI)
        let pilot = try #require(scene.importedPilotFDAI)
        #expect(scene.installConsoleEnclosure(.instrument))
        #expect(scene.installConsoleEnclosure(.instrument))
        #expect(scene.importedFDAI?.root === commander.root)
        #expect(scene.importedPilotFDAI?.root === pilot.root)
        #expect(assembly.consoleEnclosures.count == 1)
    }
}
