import Foundation
import CoreML

final class CoreMLEmotionService: EmotionDetectionServiceProtocol {
    static let targetLabels = [
        "Joy", "Sadness", "Anger", "Fear", "Love", "Surprise",
        "Disgust", "Anxiety", "Excitement", "Gratitude", "Hope", "Guilt",
    ]

    private let modelName: String
    private var model: MLModel?
    private var tokenizer: WordPieceTokenizer?

    init(modelName: String) {
        self.modelName = modelName
    }

    private func loadIfNeeded() throws {
        guard model == nil else { return }

        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            throw AIServiceError.modelNotLoaded
        }

        // Prefer the Neural Engine (lowest power draw); fall back to CPU/GPU
        // if the model can't be scheduled on the ANE.
        let allConfig = MLModelConfiguration()
        allConfig.computeUnits = .all
        if let loaded = try? MLModel(contentsOf: modelURL, configuration: allConfig) {
            model = loaded
        } else {
            let fallback = MLModelConfiguration()
            fallback.computeUnits = .cpuAndGPU
            model = try MLModel(contentsOf: modelURL, configuration: fallback)
        }

        if let url = Bundle.main.url(forResource: "vocab_emotion", withExtension: "txt") {
            tokenizer = try WordPieceTokenizer(vocabURL: url)
        } else {
            tokenizer = try WordPieceTokenizer(vocabResource: "vocab")
        }
    }

    func detectEmotions(for text: String) async throws -> [EmotionProbability] {
        return try await Task.detached(priority: .utility) { [self] in
            try await self.loadIfNeeded()
            guard let model = await self.model, let tokenizer = await self.tokenizer else {
                throw AIServiceError.modelNotLoaded
            }

            let tokens = await tokenizer.tokenize(text)
            let maxLen = await WordPieceTokenizer.maxLength

            let inputIDs     = try MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
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

            guard let logitsArray = output.featureValue(for: "logits")?.multiArrayValue else {
                throw AIServiceError.emotionDetectionFailed
            }

            let numLabels = await Self.targetLabels.count
            let logits = (0..<numLabels).map { logitsArray[$0].doubleValue }
            let probs = await CoreMLEmotionService.softmax(logits)

            let results: [EmotionProbability] = await Self.targetLabels.enumerated().map { idx, label in
                EmotionProbability(emotion: label, probability: Float(probs[idx]))
            }

            return results.sorted { $0.probability > $1.probability }
        }.value
    }

    private static func softmax(_ logits: [Double]) -> [Double] {
        let maxVal = logits.max() ?? 0
        let exps = logits.map { exp($0 - maxVal) }
        let sum = exps.reduce(0, +)
        return sum > 0 ? exps.map { $0 / sum } : exps
    }
}
