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
        #if targetEnvironment(simulator)
        // The xrOS Simulator's MPSGraph backend can accept this model and
        // return a zero-like output while logging an incompatible-OS error.
        // CPU execution provides deterministic A/B evidence in Lunar Explorer;
        // hardware keeps access to the Neural Engine and GPU.
        configuration.computeUnits = .cpuOnly
        #else
        configuration.computeUnits = .all
        #endif
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
        return try await reconstruct(
            procedural,
            transitionEdges: plan.transitionEdges
        )
    }

    /// Applies only the model-backed appearance pass. The automatic production
    /// generator performs its procedural bake before entering this actor so
    /// separate resident tile requests can keep baking concurrently.
    func reconstruct(
        _ procedural: LMTerrainTileDetailTextures,
        transitionEdges: LMTerrainTileEdges = .all
    ) async throws -> LMTerrainTileDetailTextures {
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
            albedo: try blendedAlbedo(
                neural: output,
                lowResolution: input,
                procedural: procedural.albedo,
                transitionEdges: transitionEdges
            ),
            normal: procedural.normal,
            normalDistribution: procedural.normalDistribution
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
        rgba.withUnsafeBufferPointer { source in
            for lowRow in 0..<Self.inputResolution {
                for lowColumn in 0..<Self.inputResolution {
                    var sum = 0
                    for rowOffset in 0..<scale {
                        let highRow = lowRow * scale + rowOffset
                        var sourceOffset = (
                            highRow * Self.outputResolution + lowColumn * scale
                        ) * 4
                        for _ in 0..<scale {
                            sum += Int(source[sourceOffset])
                            sourceOffset += 4
                        }
                    }
                    let average = Float(sum) / Float(scale * scale * 255)
                    values[lowRow * Self.inputResolution + lowColumn] = Float16(
                        average
                    )
                }
            }
        }
    }

    private func blendedAlbedo(
        neural: MLMultiArray,
        lowResolution: MLMultiArray,
        procedural: [UInt8],
        transitionEdges: LMTerrainTileEdges
    ) throws -> [UInt8] {
        // Core ML is allowed to materialize a multi-array using a different
        // scalar type from the model's declared compute precision. Reading a
        // Float32 result through a Float16 pointer produces plausible-looking
        // but badly darkened/smoothed terrain, so specialize on the runtime
        // data type before entering the hot pixel loop.
        switch neural.dataType {
        case .float16:
            return try blendedAlbedo(
                neuralValues: neural.dataPointer.bindMemory(
                    to: Float16.self,
                    capacity: neural.count
                ),
                lowResolution: lowResolution,
                procedural: procedural,
                transitionEdges: transitionEdges
            )
        case .float32:
            return try blendedAlbedo(
                neuralValues: neural.dataPointer.bindMemory(
                    to: Float.self,
                    capacity: neural.count
                ),
                lowResolution: lowResolution,
                procedural: procedural,
                transitionEdges: transitionEdges
            )
        case .double:
            return try blendedAlbedo(
                neuralValues: neural.dataPointer.bindMemory(
                    to: Double.self,
                    capacity: neural.count
                ),
                lowResolution: lowResolution,
                procedural: procedural,
                transitionEdges: transitionEdges
            )
        default:
            throw ModelError.unexpectedShape
        }
    }

    private func blendedAlbedo<Scalar: BinaryFloatingPoint>(
        neuralValues: UnsafeMutablePointer<Scalar>,
        lowResolution: MLMultiArray,
        procedural: [UInt8],
        transitionEdges: LMTerrainTileEdges
    ) throws -> [UInt8] {
        var result = procedural
        let lowValues = lowResolution.dataPointer.bindMemory(
            to: Float16.self,
            capacity: lowResolution.count
        )
        let scale = Double(Self.outputResolution) / Double(Self.inputResolution)
        var sourceColumn0 = [Int](repeating: 0, count: Self.outputResolution)
        var sourceColumn1 = [Int](repeating: 0, count: Self.outputResolution)
        var sourceColumnFraction = [Double](
            repeating: 0,
            count: Self.outputResolution
        )
        for column in 0..<Self.outputResolution {
            let sourceX = (Double(column) + 0.5) / scale - 0.5
            let floorX = floor(sourceX)
            sourceColumn0[column] = min(
                max(Int(floorX), 0),
                Self.inputResolution - 1
            )
            sourceColumn1[column] = min(
                max(Int(floorX) + 1, 0),
                Self.inputResolution - 1
            )
            sourceColumnFraction[column] = sourceX - floorX
        }

        let collar = max(
            1.0,
            Double(Self.outputResolution) * LMTerrainTileDetailBaker.edgeFadeFraction
        )
        let inferenceSeamCollar = 4.0
        let fadesWest = transitionEdges.contains(.west)
        let fadesEast = transitionEdges.contains(.east)
        let fadesNorth = transitionEdges.contains(.north)
        let fadesSouth = transitionEdges.contains(.south)
        var horizontalFade = [Double](repeating: 1, count: Self.outputResolution)
        var verticalFade = [Double](repeating: 1, count: Self.outputResolution)
        for coordinate in 0..<Self.outputResolution {
            var horizontalTransitionDistance = Self.outputResolution
            if fadesWest {
                horizontalTransitionDistance = min(
                    horizontalTransitionDistance,
                    coordinate
                )
            }
            if fadesEast {
                horizontalTransitionDistance = min(
                    horizontalTransitionDistance,
                    Self.outputResolution - 1 - coordinate
                )
            }
            let horizontalPerimeterFade = Self.smoothstep(
                distance: horizontalTransitionDistance,
                scale: collar
            )
            let horizontalSeamFade = Self.smoothstep(
                distance: min(coordinate, Self.outputResolution - 1 - coordinate),
                scale: inferenceSeamCollar
            )
            horizontalFade[coordinate] = min(
                horizontalPerimeterFade,
                horizontalSeamFade
            )

            var verticalTransitionDistance = Self.outputResolution
            if fadesNorth {
                verticalTransitionDistance = min(
                    verticalTransitionDistance,
                    coordinate
                )
            }
            if fadesSouth {
                verticalTransitionDistance = min(
                    verticalTransitionDistance,
                    Self.outputResolution - 1 - coordinate
                )
            }
            let verticalPerimeterFade = Self.smoothstep(
                distance: verticalTransitionDistance,
                scale: collar
            )
            let verticalSeamFade = Self.smoothstep(
                distance: min(coordinate, Self.outputResolution - 1 - coordinate),
                scale: inferenceSeamCollar
            )
            verticalFade[coordinate] = min(
                verticalPerimeterFade,
                verticalSeamFade
            )
        }
        for row in 0..<Self.outputResolution {
            let sourceY = (Double(row) + 0.5) / scale - 0.5
            let floorY = floor(sourceY)
            let sourceRow0 = min(
                max(Int(floorY), 0),
                Self.inputResolution - 1
            )
            let sourceRow1 = min(
                max(Int(floorY) + 1, 0),
                Self.inputResolution - 1
            )
            let sourceRowFraction = sourceY - floorY
            let sourceRow0Offset = sourceRow0 * Self.inputResolution
            let sourceRow1Offset = sourceRow1 * Self.inputResolution
            for column in 0..<Self.outputResolution {
                // Independent inference contexts can disagree by a few byte
                // values at a tile boundary even when the procedural inputs
                // are continuous. Restore the exact procedural edge through a
                // four-pixel collar; unlike the footprint morph, this is too
                // narrow to expose the tile grid at viewing distance.
                let fade = min(horizontalFade[column], verticalFade[row])
                let pixel = row * Self.outputResolution + column
                let offset = pixel * 4
                let base = Double(procedural[offset])
                let reconstructed = Double(
                    min(max(neuralValues[pixel], 0), 1) * 255
                )
                // The network was trained as an improvement over bilinear 4x
                // scaling. Apply only that learned residual to the complete
                // full-resolution procedural tile. Replacing the tile with the
                // reconstruction would discard legitimate measured and
                // deterministic microtexture before the model ever sees it.
                let sourceColumn0Index = sourceColumn0[column]
                let sourceColumn1Index = sourceColumn1[column]
                let sourceColumnWeight = sourceColumnFraction[column]
                let topLeft = Double(Float(
                    lowValues[sourceRow0Offset + sourceColumn0Index]
                ))
                let topRight = Double(Float(
                    lowValues[sourceRow0Offset + sourceColumn1Index]
                ))
                let bottomLeft = Double(Float(
                    lowValues[sourceRow1Offset + sourceColumn0Index]
                ))
                let bottomRight = Double(Float(
                    lowValues[sourceRow1Offset + sourceColumn1Index]
                ))
                let top = topLeft + (topRight - topLeft) * sourceColumnWeight
                let bottom = bottomLeft
                    + (bottomRight - bottomLeft) * sourceColumnWeight
                let bilinear = (
                    top + (bottom - top) * sourceRowFraction
                ) * 255
                let learnedResidual = reconstructed - bilinear
                // The exported architecture bounds its learned residual to
                // +/-0.12 before clamping. Rejecting anything outside a small
                // numerical collar catches silent backend failures (including
                // the Simulator's observed all-zero output) and lets the
                // automatic generator return the exact procedural tile.
                guard abs(learnedResidual) <= 0.125 * 255 else {
                    throw ModelError.unexpectedShape
                }
                let byte = UInt8(
                    min(
                        max(
                            Int((base + learnedResidual * fade).rounded()),
                            0
                        ),
                        255
                    )
                )
                result[offset] = byte
                result[offset + 1] = byte
                result[offset + 2] = byte
            }
        }
        return result
    }

    private static func smoothstep(distance: Int, scale: Double) -> Double {
        let normalized = min(max(Double(distance) / scale, 0), 1)
        return normalized * normalized * (3 - 2 * normalized)
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

    /// Test and dependency-injection seam for environments where the bundled
    /// model is unavailable. Production continues to resolve the model from
    /// the application bundle through `init(bundle:)`.
    init(neural: LMCoreMLTerrainDetailGenerator?) {
        self.neural = neural
    }

    func prepare() async {
        await neural?.prepare()
    }

    func generate(
        plan: LMTerrainTilePlan,
        albedoField: LMMeasuredAlbedoField?
    ) async throws -> LMTerrainTileDetailTextures {
        let procedural = try await fallback.generate(
            plan: plan,
            albedoField: albedoField
        )
        guard let neural else { return procedural }
        do {
            return try await neural.reconstruct(
                procedural,
                transitionEdges: plan.transitionEdges
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return procedural
        }
    }
}
