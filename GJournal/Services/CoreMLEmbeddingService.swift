//
//  CoreMLEmbeddingService.swift
//  GJournal
//
//  Generates sentence embeddings from a BERT .mlpackage.
//  Supports mean pooling (all-MiniLM) and CLS pooling (BGE).
//  Pooling mode must match the model's training objective.
//

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

        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlpackage") else {
            throw AIServiceError.modelNotLoaded
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all
        model = try MLModel(contentsOf: modelURL, configuration: config)

        let vocabName = "vocab_\(modelName.lowercased().replacingOccurrences(of: "-", with: "_"))"
        if let url = Bundle.main.url(forResource: vocabName, withExtension: "txt") {
            tokenizer = try WordPieceTokenizer(vocabURL: url)
        } else {
            tokenizer = try WordPieceTokenizer(vocabResource: "vocab")
        }
    }

    func generateEmbedding(for text: String) async throws -> [Float] {
        return try await Task.detached(priority: .utility) { [self] in
            try self.loadIfNeeded()
            guard let model = self.model, let tokenizer = self.tokenizer else {
                throw AIServiceError.modelNotLoaded
            }

            let tokens = tokenizer.tokenize(text)
            let maxLen = WordPieceTokenizer.maxLength

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

            let output = try model.prediction(from: input)

            guard let hiddenState = output.featureValue(for: "last_hidden_state")?.multiArrayValue else {
                throw AIServiceError.embeddingGenerationFailed
            }

            let embeddingDim = hiddenState.shape[2].intValue
            var embedding: [Float]

            switch self.poolingMode {
            case .mean:
                // Average over all real (non-padding) token positions
                let realLen = tokens.realTokenCount
                var sum = [Double](repeating: 0, count: embeddingDim)
                for pos in 0..<realLen {
                    for dim in 0..<embeddingDim {
                        sum[dim] += hiddenState[pos * embeddingDim + dim].doubleValue
                    }
                }
                embedding = sum.map { Float($0 / Double(realLen)) }

            case .cls:
                // Take the [CLS] token at position 0 — required for BGE contrastive models
                embedding = (0..<embeddingDim).map { Float(hiddenState[$0].doubleValue) }
            }

            return CoreMLEmbeddingService.l2Normalize(embedding)
        }.value
    }

    private static func l2Normalize(_ v: [Float]) -> [Float] {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }
}
