import Foundation
import CoreML
import Accelerate

final class NomicEmbeddingService: EmbeddingServiceProtocol {
    let truncateDim: Int

    private let modelName: String
    private var model: MLModel?
    private var tokenizer: WordPieceTokenizer?

    init(modelName: String = "GJournalEmbeddingNomic", truncateDim: Int = 256) {
        self.modelName = modelName
        self.truncateDim = truncateDim
    }

    private func loadIfNeeded() throws {
        guard model == nil else { return }

        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            throw AIServiceError.modelNotLoaded
        }

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        model = try MLModel(contentsOf: modelURL, configuration: config)

        if let url = Bundle.main.url(forResource: "vocab_nomic", withExtension: "txt") {
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

            // Nomic task prefix for clustering / journaling use-case
            let prefixedText = "clustering: \(text)"
            let tokens = await tokenizer.tokenize(prefixedText)
            let maxLen = await WordPieceTokenizer.maxLength

            let inputIDs      = try MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
            let attentionMask = try MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
            for i in 0..<maxLen {
                inputIDs[i]      = NSNumber(value: tokens.inputIDs[i])
                attentionMask[i] = NSNumber(value: tokens.attentionMask[i])
            }

            let input = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids":      MLFeatureValue(multiArray: inputIDs),
                "attention_mask": MLFeatureValue(multiArray: attentionMask),
            ])

            let output = try await model.prediction(from: input)
            guard let hiddenState = output.featureValue(for: "last_hidden_state")?.multiArrayValue else {
                throw AIServiceError.embeddingGenerationFailed
            }

            let fullDim  = hiddenState.shape[2].intValue
            let strides  = hiddenState.strides
            let seqStride = strides[1].intValue
            let dimStride = strides[2].intValue
            let realLen  = tokens.realTokenCount

            // Mean pooling over real tokens
            var sum = [Double](repeating: 0, count: fullDim)
            for pos in 0..<realLen {
                for d in 0..<fullDim {
                    sum[d] += hiddenState[pos * seqStride + d * dimStride].doubleValue
                }
            }
            var embedding = sum.map { Float($0 / Double(realLen)) }

            // MRL truncation: keep only the first truncateDim dimensions
            let activeDim = min(self.truncateDim, fullDim)
            if activeDim < embedding.count {
                embedding = Array(embedding.prefix(activeDim))
            }

            return await NomicEmbeddingService.l2Normalize(embedding)
        }.value
    }

    private static func l2Normalize(_ v: [Float]) -> [Float] {
        var normSq: Float = 0
        vDSP_svesq(v, 1, &normSq, vDSP_Length(v.count))
        let norm = sqrt(normSq)
        guard norm > 0 else { return v }
        var result = v
        var scalar: Float = 1.0 / norm
        vDSP_vsmul(v, 1, &scalar, &result, 1, vDSP_Length(v.count))
        return result
    }
}
