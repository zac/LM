import CryptoKit
import Foundation
import RealityKit
import Testing
@testable import LMKit

private enum LandingResource: String, CaseIterable, Sendable {
    case altitudeRate, attitudeMode, descentRate, crossPointer, interiorDetails, breakerBanks

    var asset: URL {
        switch self {
        case .altitudeRate: LMKitAssets.altitudeRateURL
        case .attitudeMode: LMKitAssets.attitudeModeURL
        case .descentRate: LMKitAssets.descentRateURL
        case .crossPointer: LMKitAssets.crossPointerURL
        case .interiorDetails: LMKitAssets.interiorDetailsURL
        case .breakerBanks: LMKitAssets.breakerBanksURL
        }
    }
    var contract: URL {
        switch self {
        case .altitudeRate: LMKitAssets.altitudeRateInterfaceURL
        case .attitudeMode, .descentRate: LMKitAssets.descentControlsInterfaceURL
        case .crossPointer: LMKitAssets.crossPointerInterfaceURL
        case .interiorDetails: LMKitAssets.interiorDetailsInterfaceURL
        case .breakerBanks: LMKitAssets.breakerBanksInterfaceURL
        }
    }
}

private struct LandingReceipt: Decodable {
    struct File: Decodable { let sha256: String; let bytes: Int }
    let component: String
    let files: [String: File]
}

@MainActor private func landingNodes(_ entity: Entity) -> [Entity] {
    [entity] + entity.children.flatMap { landingNodes($0) }
}

@Test(arguments: LandingResource.allCases)
@MainActor private func landingResourcesLoadWithoutOwningInteraction(_ resource: LandingResource) throws {
    let scene = try Entity.load(contentsOf: resource.asset)
    let nodes = landingNodes(scene)
    #expect(nodes.contains { $0.components[ModelComponent.self] != nil })
    for entity in nodes {
        #expect(entity.components[InputTargetComponent.self] == nil)
        #expect(entity.components[CollisionComponent.self] == nil)
        let bounds = entity.visualBounds(relativeTo: entity)
        if entity.components[ModelComponent.self] != nil {
            #expect(bounds.extents.x.isFinite && bounds.extents.y.isFinite && bounds.extents.z.isFinite)
            #expect(simd_length(bounds.extents) > 0)
        }
    }
    let contract = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: resource.contract)) as? [String: Any])
    #expect(!contract.isEmpty)
}

@Test(arguments: LandingResource.allCases)
private func packagedLandingResourcesPreserveAuthoringBytes(_ resource: LandingResource) throws {
    let directory = resource.asset.deletingLastPathComponent()
    let receipt = try JSONDecoder().decode(LandingReceipt.self, from: Data(contentsOf: directory.appendingPathComponent("packaging.json")))
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Assets/Cockpit/Components").appendingPathComponent(receipt.component)
    for url in [resource.asset, resource.contract] {
        let data = try Data(contentsOf: url)
        let entry = try #require(receipt.files[url.lastPathComponent])
        #expect(data == (try Data(contentsOf: source.appendingPathComponent(url.lastPathComponent))))
        #expect(data.count == entry.bytes)
        #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == entry.sha256)
    }
}
