import RealityKit
import Testing
@testable import LM

@MainActor
struct LMCockpitReadabilityTests {
    @Test func structuralTreatmentPreservesColorGeometryAndDoesNotAddEmission() throws {
        var original = PhysicallyBasedMaterial()
        original.metallic = .init(floatLiteral: 0.2)
        original.roughness = .init(floatLiteral: 0.4)
        original.specular = .init(floatLiteral: 0.5)
        let entity = ModelEntity(mesh: .generateBox(size: 0.1), materials: [original])
        let transform = entity.transform
        #expect(LMCockpitMaterialPolicy.apply(.paintedStructure, to: entity) == 1)
        let actual = try #require(entity.model?.materials.first as? PhysicallyBasedMaterial)
        #expect(actual.baseColor.tint == original.baseColor.tint)
        #expect(actual.metallic.scale == original.metallic.scale)
        #expect(actual.emissiveIntensity == original.emissiveIntensity)
        #expect(actual.roughness.scale == 0.9 && actual.specular.scale == 0.08)
        #expect(entity.transform == transform)
    }

    @Test func fixedIndexFillPreservesPBRAndAuthoredColor() throws {
        let original = PhysicallyBasedMaterial()
        let entity = ModelEntity(mesh: .generateBox(size: 0.01), materials: [original])
        LMCockpitMaterialPolicy.apply(.fixedMarking, to: entity)
        let actual = try #require(entity.model?.materials.first as? PhysicallyBasedMaterial)
        #expect(actual.baseColor.tint == original.baseColor.tint)
        #expect(actual.emissiveColor.color == original.baseColor.tint)
        #expect(actual.emissiveIntensity == 0.35)
    }

    @Test func occupancyDescribesPartialRegionsWithoutClaimingCompletion() {
        let partial = LMCockpitSlotOccupancy(coverage: .partialRegion,
            componentIDs: ["AltitudeRate", "Additional equipment"], note: nil)
        #expect(partial.componentIDs.count == 2)
        #expect(partial.planningText.contains("PARTIAL REGION"))
        #expect(partial.planningText.contains("Other equipment pending"))
        let visual = LMCockpitSlotOccupancy(coverage: .occupiedRegion,
            componentIDs: ["BreakerBanks"], note: "Visual hardware only")
        #expect(visual.planningText.contains("Visual hardware only"))
    }
}
