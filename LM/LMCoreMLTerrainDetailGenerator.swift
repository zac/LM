import CoreML
import Foundation

/// One-pass 4x lunar reflectance reconstruction backed by the bundled compact
/// Core ML student. Geometry and normal detail remain procedural, so a model
/// failure cannot change the landing surface or leave a tile uncovered.
actor LMCoreMLTerrainDetailGenerator: LMTerrainDetailGenerating {
    enum ModelError: Error, Equatable {
        case missingCompiledModel
        case missingOutput
        case unexpectedShape
    }

    nonisolated let modelID = "lunar-terrain-sr-nac-v2"
    nonisolated static let inputResolution = 128
    nonisolated static let outputResolution = 512

    private let model: MLModel
    private let fallback = LMProceduralTerrainDetailGenerator()

    init(bundle: Bundle = .main) throws {
        guard let url = bundle.url(
            forResource: "LunarTerrainSR",
            withExtension: "mlmodelc"
        ) else {
            throw ModelError.missingCompiledModel
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        model = try MLModel(contentsOf: url, configuration: configuration)
    }

    func prepare() async {
        _ = try? await predictionMilliseconds(iterations: 1)
    }

    func generate(
        plan: LMTerrainTilePlan,
        albedoField: LMMeasuredAlbedoField?
    ) async throws -> LMTerrainTileDetailTextures {
        let procedural = try await fallback.generate(
            plan: plan,
            albedoField: albedoField
        )
        guard procedural.resolution == Self.outputResolution else {
            throw ModelError.unexpectedShape
        }
        try Task.checkCancellation()

        let input = try MLMultiArray(
            shape: [1, 1, Self.inputResolution, Self.inputResolution] as [NSNumber],
            dataType: .float16
        )
        downsample(procedural.albedo, into: input)
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "low_resolution": MLFeatureValue(multiArray: input),
        ])
        let output = try await predict(provider: provider)
        try Task.checkCancellation()

        return LMTerrainTileDetailTextures(
            resolution: procedural.resolution,
            albedo: blendedAlbedo(neural: output, procedural: procedural.albedo),
            normal: procedural.normal
        )
    }

    /// Measures only Core ML execution, excluding procedural synthesis and
    /// texture conversion. Tests use this to avoid treating debug-build pixel
    /// loops or simulator launch time as model latency.
    func predictionMilliseconds(iterations: Int) async throws -> [Int] {
        guard iterations > 0 else { return [] }
        let input = try MLMultiArray(
            shape: [1, 1, Self.inputResolution, Self.inputResolution] as [NSNumber],
            dataType: .float16
        )
        let values = input.dataPointer.bindMemory(
            to: Float16.self,
            capacity: input.count
        )
        for index in 0..<input.count {
            values[index] = 0.25
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "low_resolution": MLFeatureValue(multiArray: input),
        ])
        var measurements = [Int]()
        measurements.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let started = ContinuousClock.now
            _ = try await predict(provider: provider)
            measurements.append(Self.milliseconds(started.duration(to: .now)))
        }
        return measurements
    }

    private func predict(provider: MLFeatureProvider) async throws -> MLMultiArray {
        let prediction = try await model.prediction(from: provider)
        guard let output = prediction.featureValue(
            for: "super_resolution"
        )?.multiArrayValue else {
            throw ModelError.missingOutput
        }
        guard output.count == Self.outputResolution * Self.outputResolution else {
            throw ModelError.unexpectedShape
        }
        return output
    }

    private static func milliseconds(_ duration: ContinuousClock.Duration) -> Int {
        Int(
            duration.components.seconds * 1_000
                + duration.components.attoseconds / 1_000_000_000_000_000
        )
    }

    private func downsample(_ rgba: [UInt8], into input: MLMultiArray) {
        let scale = Self.outputResolution / Self.inputResolution
        let values = input.dataPointer.bindMemory(
            to: Float16.self,
            capacity: input.count
        )
        for lowRow in 0..<Self.inputResolution {
            for lowColumn in 0..<Self.inputResolution {
                var sum = 0
                for rowOffset in 0..<scale {
                    let highRow = lowRow * scale + rowOffset
                    for columnOffset in 0..<scale {
                        let highColumn = lowColumn * scale + columnOffset
                        sum += Int(
                            rgba[(highRow * Self.outputResolution + highColumn) * 4]
                        )
                    }
                }
                let average = Float(sum) / Float(scale * scale * 255)
                values[lowRow * Self.inputResolution + lowColumn] = Float16(average)
            }
        }
    }

    private func blendedAlbedo(
        neural: MLMultiArray,
        procedural: [UInt8]
    ) -> [UInt8] {
        let values = neural.dataPointer.bindMemory(
            to: Float16.self,
            capacity: neural.count
        )
        var result = procedural
        let collar = max(
            1.0,
            Double(Self.outputResolution) * LMTerrainTileDetailBaker.edgeFadeFraction
        )
        for row in 0..<Self.outputResolution {
            for column in 0..<Self.outputResolution {
                let distance = Double(
                    min(
                        min(column, Self.outputResolution - 1 - column),
                        min(row, Self.outputResolution - 1 - row)
                    )
                )
                let normalized = min(max(distance / collar, 0), 1)
                let fade = normalized * normalized * (3 - 2 * normalized)
                let pixel = row * Self.outputResolution + column
                let offset = pixel * 4
                let base = Double(procedural[offset])
                let reconstructed = Double(
                    min(max(Float(values[pixel]), 0), 1) * 255
                )
                let byte = UInt8(
                    min(max(Int((base + (reconstructed - base) * fade).rounded()), 0), 255)
                )
                result[offset] = byte
                result[offset + 1] = byte
                result[offset + 2] = byte
            }
        }
        return result
    }
}

/// Loads the neural model when it is present and keeps the established
/// procedural baker as the per-request fallback. The fallback is intentionally
/// inside the generator so cache entries always contain a complete usable tile.
struct LMAutomaticTerrainDetailGenerator: LMTerrainDetailGenerating {
    private let neural: LMCoreMLTerrainDetailGenerator?
    private let fallback = LMProceduralTerrainDetailGenerator()

    var modelID: String {
        neural?.modelID ?? fallback.modelID
    }

    init(bundle: Bundle = .main) {
        neural = try? LMCoreMLTerrainDetailGenerator(bundle: bundle)
    }

    func prepare() async {
        await neural?.prepare()
    }

    func generate(
        plan: LMTerrainTilePlan,
        albedoField: LMMeasuredAlbedoField?
    ) async throws -> LMTerrainTileDetailTextures {
        guard let neural else {
            return try await fallback.generate(plan: plan, albedoField: albedoField)
        }
        do {
            return try await neural.generate(plan: plan, albedoField: albedoField)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.generate(plan: plan, albedoField: albedoField)
        }
    }
}
