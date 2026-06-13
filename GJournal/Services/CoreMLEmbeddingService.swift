import Foundation
import CoreML

enum PoolingMode {
    case mean
    case cls
}

final class CoreMLEmbeddingService: EmbeddingServiceProtocol {
    private let modelName: String
    private let poolingMode: PoolingMode
    private var model: MLModel?
    private var tokenizer: WordPieceTokenizer?

    init(modelName: String, poolingMode: PoolingMode = .mean) {
        self.modelName = modelName
        self.poolingMode = poolingMode
    }

    private func loadIfNeeded() throws {
        guard model == nil else { return }

        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            throw AIServiceError.modelNotLoaded
        }

        let allConfig = MLModelConfiguration()
        allConfig.computeUnits = .all
        if let loaded = try? MLModel(contentsOf: modelURL, configuration: allConfig) {
            model = loaded
        } else {
            let fallback = MLModelConfiguration()
            fallback.computeUnits = .cpuAndGPU
            model = try MLModel(contentsOf: modelURL, configuration: fallback)
        }

        let vocabName = "vocab_\(modelName.lowercased().replacingOccurrences(of: "-", with: "_"))"
        if let url = Bundle.main.url(forResource: vocabName, withExtension: "txt") {
            tokenizer = try WordPieceTokenizer(vocabURL: url)
        } else {
            tokenizer = try WordPieceTokenizer(vocabResource: "vocab")
        }
    }

    func generateEmbedding(for text: String) async throws -> [Float] {
        return try await Task.detached(priority: .utility) { [self] in
            try await self.loadIfNeeded()
            guard let model = await self.model, let tokenizer = await self.tokenizer else {
                throw AIServiceError.modelNotLoaded
            }

            let tokens = await tokenizer.tokenize(text)
            let maxLen = await WordPieceTokenizer.maxLength

            let inputIDs      = try MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
            let attentionMask = try MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)

            for i in 0..<maxLen {
                inputIDs[i]       = NSNumber(value: tokens.inputIDs[i])
                attentionMask[i]  = NSNumber(value: tokens.attentionMask[i])
            }

            let input = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids":      MLFeatureValue(multiArray: inputIDs),
                "attention_mask": MLFeatureValue(multiArray: attentionMask),
            ])

            let output = try await model.prediction(from: input)

            guard let hiddenState = output.featureValue(for: "last_hidden_state")?.multiArrayValue else {
                throw AIServiceError.embeddingGenerationFailed
            }

            let embeddingDim = hiddenState.shape[2].intValue
            var embedding: [Float]

            let strides = hiddenState.strides
            let seqStride = strides[1].intValue
            let dimStride = strides[2].intValue

            switch self.poolingMode {
            case .mean:
                let realLen = tokens.realTokenCount
                var sum = [Double](repeating: 0, count: embeddingDim)
                for pos in 0..<realLen {
                    for dim in 0..<embeddingDim {
                        sum[dim] += hiddenState[pos * seqStride + dim * dimStride].doubleValue
                    }
                }
                embedding = sum.map { Float($0 / Double(realLen)) }

            case .cls:
                embedding = (0..<embeddingDim).map { Float(hiddenState[$0 * dimStride].doubleValue) }
            }

            return await CoreMLEmbeddingService.l2Normalize(embedding)
        }.value
    }

    private static func l2Normalize(_ v: [Float]) -> [Float] {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }
}
