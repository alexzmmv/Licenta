//
//  CoreMLEmotionService.swift
//  GJournal
//
//  Runs the GoEmotions fine-tuned classifier on-device.
//  Emotion detection is background-only — no UI shown during entry creation.
//  (See 00_OVERVIEW.md design-principle callout.)
//

import Foundation
import CoreML

final class CoreMLEmotionService: EmotionDetectionServiceProtocol {
    // Must match TARGET_LABELS order in train_emotion_classifier.py
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

        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlpackage") else {
            throw AIServiceError.modelNotLoaded
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all
        model = try MLModel(contentsOf: modelURL, configuration: config)

        if let url = Bundle.main.url(forResource: "vocab_emotion", withExtension: "txt") {
            tokenizer = try WordPieceTokenizer(vocabURL: url)
        } else {
            tokenizer = try WordPieceTokenizer(vocabResource: "vocab")
        }
    }

    func detectEmotions(for text: String) async throws -> [EmotionProbability] {
        return try await Task.detached(priority: .utility) { [self] in
            try self.loadIfNeeded()
            guard let model = self.model, let tokenizer = self.tokenizer else {
                throw AIServiceError.modelNotLoaded
            }

            let tokens = tokenizer.tokenize(text)
            let maxLen = WordPieceTokenizer.maxLength

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

            let output = try model.prediction(from: input)

            guard let logitsArray = output.featureValue(for: "logits")?.multiArrayValue else {
                throw AIServiceError.emotionDetectionFailed
            }

            let numLabels = Self.targetLabels.count
            var logits = (0..<numLabels).map { logitsArray[$0].doubleValue }
            let probs = CoreMLEmotionService.softmax(logits)

            let results: [EmotionProbability] = Self.targetLabels.enumerated().map { idx, label in
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
