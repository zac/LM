import Foundation
import LMKit
import RealityKit
import Testing
import simd
@testable import LM

@MainActor
@Suite(.serialized)
struct LMCommanderStationAssemblyTests {
    @Test func structuralShellCastsShadowsWithoutLayeredPanelCasters() throws {
        let assembly = try LMCommanderStationAssembly.load()
        let shell = try LMCommanderStationAssembly.path("/Cabin/Shell", in: assembly.cabin)
        let shellModels = LMCommanderStationAssembly.descendants(shell).filter { $0.components[ModelComponent.self] != nil }
        #expect(!shellModels.isEmpty)
        #expect(shellModels.allSatisfy { $0.components[DynamicLightShadowComponent.self]?.castsShadow == true })
        for layered in [assembly.panels, assembly.panelInventory, assembly.windows] {
            #expect(LMCommanderStationAssembly.descendants(layered).filter { $0.components[ModelComponent.self] != nil }
                .allSatisfy { $0.components[DynamicLightShadowComponent.self]?.castsShadow == false })
        }
    }

    @Test func translationPlanningNoteDoesNotClaimDescentRateOrOccupySlot() throws {
        let assembly = try LMCommanderStationAssembly.load()
        let slotID = "Panel5__Translation"
        #expect(assembly.planningAnnotationTexts[slotID] == "Translation controls pending")
        #expect(assembly.slotOccupancy[slotID] == nil)
        let slot = try #require(assembly.inventory.panels.flatMap(\.slots).first { $0.id == slotID })
        #expect(try LMCommanderStationAssembly.path(slot.default_placeholder_node, in: assembly.panelInventory).isEnabled)
        #expect(!assembly.planningLabelsVisible)
        assembly.setPlanningLabelsVisible(true)
        #expect(assembly.planningLabelsVisible)
    }

    @Test func assemblesEnclosureAtIdentityAndKeepsEveryDatum() throws {
        let assembly = try LMCommanderStationAssembly.load()
        #expect(Set(assembly.root.children.map(\.name)) == ["Cabin", "WindowsLPD", "PanelInventory", "CommanderPanels"])
        for component in assembly.root.children {
            #expect(LMCommanderStationAssembly.near(component.transform.matrix, matrix_identity_float4x4))
        }
        for name in ["Forward", "CDR", "LMP", "Ceiling", "Aft", "Deck"] {
            #expect(try LMCommanderStationAssembly.path("/Cabin/Shell/Cutaway_\(name)", in: assembly.cabin).isEnabled)
        }
        #expect(try LMCommanderStationAssembly.path("/Cabin/Shell/Hatches", in: assembly.cabin).isEnabled)
        for (name, proposed) in assembly.manifest.mounts {
            let position = SIMD3<Float>(proposed.position[0], proposed.position[1], proposed.position[2])
            let entity = try LMCommanderStationAssembly.path(proposed.path, in: assembly.cabin)
            #expect(entity.name == name)
            #expect(simd_distance(entity.position(relativeTo: assembly.cabin), position) < 0.00001)
        }
        for index in [1, 4] {
            let backing = try LMCommanderStationAssembly.path("/CommanderPanels/Panel_\(index)/Panel_\(index)_RemovableBacking", in: assembly.panels)
            #expect(!backing.isEnabled)
            for suffix in ["Shell", "Trim", "Fasteners"] {
                #expect(try LMCommanderStationAssembly.path("/CommanderPanels/Panel_\(index)/Panel_\(index)_\(suffix)", in: assembly.panels).isEnabled)
            }
        }
        #expect(!assembly.planningLabelsVisible)
        #expect(assembly.inventory.panels.flatMap(\.slots).count == 66)
        #expect(!LMCommanderStationAssembly.descendants(assembly.root).contains { $0.name.hasPrefix("VisualOnly_") })
        for suffix in ["Inner", "Outer"] {
            let path = "/WindowsLPD/CDR_FlightWindow/CDR_Window_\(suffix)/LPD_\(suffix)"
            let marks = try LMCommanderStationAssembly.path(path, in: assembly.windows)
            #expect(marks.isEnabled)
            #expect(LMCommanderStationAssembly.descendants(marks).contains { $0.components[ModelComponent.self] != nil })
        }
    }

    @Test func normalStartupInstallsFoundationAndExplicitFallbackKeepsProcedural() async throws {
        let station = LMCommanderStationScene()
        #expect(try await !station.loadArtistCabinIfAvailable(arguments: ["--procedural-cockpit"]))
        #expect(station.commanderAssembly == nil)
        #expect(station.landingPointMarkingOwner == .appGenerated)
        #expect(try await station.loadArtistCabinIfAvailable(arguments: []))
        #expect(station.commanderAssembly != nil)
        #expect(station.landingPointMarkingOwner == .importedWindows)
    }

    @Test func atomicFallbackAndInstallKeepLiveIdentitiesAndTransferOpticalOwnership() throws {
        let station = LMCommanderStationScene()
        let keys = station.dskyKeyEntities
        let transforms = keys.map { $0.transformMatrix(relativeTo: station.dskyFaceRoot) }
        let nodes = LMCommanderStationAssembly.descendants(station.root)
        let enabledBefore = nodes.map(\.isEnabled)
        let aca = station.acaHandle
        let acaTransform = aca.transform
        #expect(!station.installCommanderAssembly { throw LMCommanderStationAssembly.AssemblyError.invalidContract("test failure") })
        #expect(station.commanderAssembly == nil)
        #expect(nodes.map(\.isEnabled) == enabledBefore)
        #expect(station.landingPointMarkingOwner == .appGenerated)
        station.setPlanningLabelsVisible(true)
        #expect(station.installCommanderAssembly())
        let assembly = try #require(station.commanderAssembly)
        #expect(assembly.planningLabelsVisible)
        #expect(station.landingPointMarkingOwner == .importedWindows)
        #expect(station.installCommanderAssembly { throw LMCommanderStationAssembly.AssemblyError.invalidContract("must not reload") })
        #expect(aca === station.acaHandle)
        #expect(LMCommanderStationAssembly.near(aca.transform.matrix, acaTransform.matrix))
        for (i, key) in keys.enumerated() {
            #expect(key === station.dskyKeyEntities[i])
            #expect(station.dskyKeyCode(for: key) != nil)
            #expect(LMCommanderStationAssembly.near(key.transformMatrix(relativeTo: station.dskyFaceRoot), transforms[i]))
        }
        station.setLandingPointCalledAngle(47, trainingOverlayVisible: true)
        #expect(!station.landingPointCalledAngleMarker.isEnabled)
        station.recenterAtCurrentHeadPose()
        #expect(station.landingPointMarkingOwner == .importedWindows)
        station.setPlanningLabelsVisible(false)
        #expect(!assembly.planningLabelsVisible)
        let active = LMCommanderStationAssembly.descendants(station.root).filter { entity in
            var node: Entity? = entity
            while let current = node { if !current.isEnabled { return false }; node = current.parent }
            return true
        }
        #expect(active.filter { $0.name == "DSKY_Key_PRO" }.count == 1)
        #expect(active.filter { $0.name == "FDAI_Ball_Pivot" }.count == 1)
        #expect(active.filter { $0.name == "WindowsLPD" }.count == 1)
        #expect(!active.contains { $0.name.hasPrefix("LPD ") || $0.name == "Training LPD called-angle marker" })
        for id in ["Panel1__FDAI", "Panel4__DSKY"] {
            let slot = try #require(assembly.inventory.panels.flatMap(\.slots).first { $0.id == id })
            #expect(try !LMCommanderStationAssembly.path(slot.default_placeholder_node, in: assembly.panelInventory).isEnabled)
        }
    }

    @Test func slotReplacementIsLocalTransactionalAndHonorsBlockedTimer() throws {
        let assembly = try LMCommanderStationAssembly.load()
        let slots = assembly.inventory.panels.flatMap(\.slots)
        let slot = try #require(slots.first { $0.id == "Panel1__Warning" })
        let blank = try LMCommanderStationAssembly.path(slot.default_placeholder_node, in: assembly.panelInventory)
        let peer = try #require(slots.first { $0.id == "Panel1__Timers" })
        let peerBlank = try LMCommanderStationAssembly.path(peer.default_placeholder_node, in: assembly.panelInventory)
        #expect(throws: (any Error).self) {
            try assembly.installOccupant(slotID: slot.id) { throw LMCommanderStationAssembly.AssemblyError.invalidContract("load failed") }
        }
        #expect(blank.isEnabled && peerBlank.isEnabled)
        #expect(assembly.slotOccupancy[slot.id] == nil)
        #expect(assembly.planningStatusLabels[slot.id] == nil)
        #expect(throws: (any Error).self) { try assembly.installOccupant(slotID: slot.id) { Entity() } }
        #expect(blank.isEnabled)
        var attemptedBlockedLoad = false
        #expect(throws: (any Error).self) {
            try assembly.installOccupant(slotID: "Panel5__Timer") { attemptedBlockedLoad = true; return Entity() }
        }
        #expect(!attemptedBlockedLoad)
        let model = ModelEntity(mesh: .generateBox(size: 0.01), materials: [SimpleMaterial()])
        try assembly.installOccupant(slotID: slot.id, componentID: "Test equipment") { model }
        #expect(assembly.slotOccupancy[slot.id]?.componentIDs == ["Test equipment"])
        #expect(assembly.slotOccupancy[slot.id]?.coverage == .occupiedRegion)
        #expect(assembly.slotOccupancy["Panel5__Timer"] == nil)
        #expect(!blank.isEnabled && peerBlank.isEnabled)
        #expect(model.parent?.name == slot.id)
        assembly.setPlanningLabelsVisible(true)
        #expect(assembly.planningLabelsVisible)
        #expect(!blank.isEnabled && peerBlank.isEnabled)
    }

    @Test func partialPlanningStatusRetainsBackingAndPendingEquipmentCaveat() throws {
        let assembly = try LMCommanderStationAssembly.load()
        let slot = try #require(assembly.inventory.panels.flatMap(\.slots).first { $0.id == "Panel1__RangeThrust" })
        let blank = try LMCommanderStationAssembly.path(slot.default_placeholder_node, in: assembly.panelInventory)
        let label = try LMCommanderStationAssembly.path(slot.label_node, in: assembly.panelInventory)
        let originalTransform = label.transform
        #expect(throws: (any Error).self) {
            try assembly.installPartialOccupant(slotID: slot.id, componentID: "AltitudeRate") { Entity() }
        }
        #expect(label.isEnabled && blank.isEnabled)
        #expect(assembly.slotOccupancy[slot.id] == nil)
        try assembly.installPartialOccupant(slotID: slot.id, componentID: "AltitudeRate") {
            ModelEntity(mesh: .generateBox(size: 0.01), materials: [SimpleMaterial()])
        }
        let status = try #require(assembly.slotOccupancy[slot.id])
        #expect(status.coverage == .partialRegion)
        #expect(status.planningText.contains("Other equipment pending"))
        #expect(!status.planningText.contains("not modeled"))
        #expect(blank.isEnabled && !label.isEnabled)
        let replacement = try #require(assembly.planningStatusLabels[slot.id])
        #expect(replacement.parent === label.parent)
        #expect(replacement.transform == originalTransform)
        #expect(LMCommanderStationAssembly.descendants(replacement).allSatisfy {
            $0.components[InputTargetComponent.self] == nil && $0.components[CollisionComponent.self] == nil
        })
        #expect(!assembly.planningLabelsVisible)
        assembly.setPlanningLabelsVisible(true)
        #expect(assembly.planningLabelsVisible && replacement.isEnabled)
        assembly.setPlanningLabelsVisible(false)
        #expect(!assembly.planningLabelsVisible && replacement.isEnabled)
        #expect(blank.isEnabled)
    }

    @Test func planningLayerRetainsTextMeshesAndTogglePreservesAllBlankStates() throws {
        let assembly = try LMCommanderStationAssembly.load()
        let labels = try LMCommanderStationAssembly.path(assembly.inventory.planning_label_layer, in: assembly.panelInventory)
        let slots = assembly.inventory.panels.flatMap(\.slots)
        let blanks = try slots.map { try LMCommanderStationAssembly.path($0.default_placeholder_node, in: assembly.panelInventory) }
        let states = blanks.map(\.isEnabled)
        for slot in slots {
            let label = try LMCommanderStationAssembly.path(slot.label_node, in: assembly.panelInventory)
            let models = LMCommanderStationAssembly.descendants(label).compactMap { $0.components[ModelComponent.self] }
            #expect(!models.isEmpty)
            #expect(models.allSatisfy { !$0.materials.isEmpty && !$0.mesh.contents.models.isEmpty })
        }
        #expect(!labels.isEnabled)
        assembly.setPlanningLabelsVisible(true)
        #expect(labels.isEnabled)
        #expect(blanks.map(\.isEnabled) == states)
        assembly.setPlanningLabelsVisible(false)
        #expect(!labels.isEnabled)
        #expect(blanks.map(\.isEnabled) == states)
        // These checks establish retained geometry and app state only. Authored USD
        // visibility can still suppress rendering; packaged visibility and simulator
        // captures must verify the labels actually appear when enabled.
    }

    @Test func rejectsMisregisteredWindowsAndPanelInterfacesBeforeInstall() throws {
        let invalid = try Entity.load(contentsOf: LMKitAssets.windowsURL)
        let pane = try LMCommanderStationAssembly.unique("CDR_Window_Inner", in: invalid)
        pane.position.x += 0.01
        #expect(throws: (any Error).self) {
            try LMCommanderStationAssembly(asset: Entity.load(contentsOf: LMKitAssets.cabinURL),
                manifestData: Data(contentsOf: LMKitAssets.cabinMountsURL), loadWindows: { invalid })
        }
        let invalidPanels = try Entity.load(contentsOf: LMKitAssets.commanderPanelsURL)
        let interface = try LMCommanderStationAssembly.unique("FDAI_Interface", in: invalidPanels)
        interface.position.x += 0.01
        #expect(throws: (any Error).self) {
            try LMCommanderStationAssembly(asset: Entity.load(contentsOf: LMKitAssets.cabinURL),
                manifestData: Data(contentsOf: LMKitAssets.cabinMountsURL), loadPanels: { invalidPanels })
        }
    }

    @Test func rejectsBadManifestWithoutPublishing() throws {
        let data = try Data(contentsOf: LMKitAssets.cabinMountsURL)
        let corrupted = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "NOT parent-local", with: "parent-local").utf8)
        #expect(throws: (any Error).self) {
            try LMCommanderStationAssembly(asset: Entity.load(contentsOf: LMKitAssets.cabinURL), manifestData: corrupted)
        }
    }
    @Test func outerWindowAndLegacyReferenceSharePlaneDespiteDifferentTangentOrigins() throws {
        let assembly = try LMCommanderStationAssembly.load()
        let legacy = try LMCommanderStationAssembly.path("/Cabin/Optical/CDR_Window_Outer", in: assembly.cabin)
        let pane = try LMCommanderStationAssembly.path("/WindowsLPD/CDR_FlightWindow/CDR_Window_Outer", in: assembly.windows)
        let delta = pane.position(relativeTo: assembly.windows) - legacy.position(relativeTo: assembly.cabin)
        #expect(simd_length(delta) > 0.01)
        let normal = pane.orientation(relativeTo: assembly.windows).act(SIMD3<Float>(0, 0, 1))
        #expect(abs(simd_dot(delta, normal)) < 0.00001)
    }

    @Test func instrumentObserverHasPrecedence() {
        for name in ["cdr", "lmp", "rear", "overhead", "control-closeup", "detail-side", "cross-pointer"] {
            #expect(LMCommanderStationAssemblyObserver.selected(arguments: ["--assembly-validation-view=\(name)"]) != nil)
        }
        #expect(LMCommanderStationAssemblyObserver.selected(arguments: []) == nil)
        #expect(LMCommanderStationAssemblyObserver.selected(arguments: ["--assembly-validation-view=side"]) == .side)
        #expect(LMCommanderStationAssemblyObserver.selected(arguments: ["--assembly-validation-view=front", "--instrument-validation"]) == nil)
    }
}
