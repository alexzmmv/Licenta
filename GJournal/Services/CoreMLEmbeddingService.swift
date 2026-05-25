//
//  CoreMLEmbeddingService.swift
//  GJournal
//
//  Generates sentence embeddings from a fine-tuned BERT .mlpackage using mean pooling.
//  Mean pooling MUST match sentence-transformers training (see 09_AI_PITFALLS.md Pitfall 7.4).
//

import Foundation
import CoreML

final class CoreMLEmbeddingService: EmbeddingServiceProtocol {
    private let modelName: String
    private var model: MLModel?
    private var tokenizer: WordPieceTokenizer?

    init(modelName: String) {
        self.modelName = modelName
    }

    // Lazy load on first use to avoid blocking app launch
    private func loadIfNeeded() throws {
        guard model == nil else { return }

        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlpackage") else {
            throw AIServiceError.modelNotLoaded
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all  // CPU + GPU + Neural Engine
        model = try MLModel(contentsOf: modelURL, configuration: config)

        // Prefer vocab bundled alongside the model; fall back to generic "vocab.txt"
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

            // Build MLMultiArray inputs — FIXED shape (1, 128), see Pitfall 2.2
            let inputIDs    = try MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
            let attentionMask = try MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)

            for i in 0..<maxLen {
                inputIDs[i]     = NSNumber(value: tokens.inputIDs[i])
                attentionMask[i] = NSNumber(value: tokens.attentionMask[i])
            }

            let input = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids":      MLFeatureValue(multiArray: inputIDs),
                "attention_mask": MLFeatureValue(multiArray: attentionMask),
            ])

            let output = try model.prediction(from: input)

            guard let hiddenState = output.featureValue(for: "last_hidden_state")?.multiArrayValue else {
                throw AIServiceError.embeddingGenerationFailed
            }

            // Mean pooling over real (non-padding) token positions — must match sentence-transformers
            let embeddingDim = hiddenState.shape[2].intValue
            let realLen = tokens.realTokenCount
            var sum = [Double](repeating: 0, count: embeddingDim)

            for pos in 0..<realLen {
                for dim in 0..<embeddingDim {
                    let idx = pos * embeddingDim + dim
                    sum[dim] += hiddenState[idx].doubleValue
                }
            }

            var embedding = sum.map { Float($0 / Double(realLen)) }
            embedding = CoreMLEmbeddingService.l2Normalize(embedding)
            return embedding
        }.value
    }

    private static func l2Normalize(_ v: [Float]) -> [Float] {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }
}
