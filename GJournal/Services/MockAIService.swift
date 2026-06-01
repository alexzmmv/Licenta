//
//  MockAIService.swift
//  GJournal
//
//  Lightweight mock implementations of AI service protocols for
//  SwiftUI Previews and unit tests. Value types (struct) — no
//  reference semantics needed since these carry no shared state.
//

import Foundation

// MARK: - Mock Embedding Service

struct MockEmbeddingService: EmbeddingServiceProtocol {
    private let embeddingDim = 768

    func generateEmbedding(for text: String) async throws -> [Float] {
        try await Task.sleep(nanoseconds: 200_000_000)
        let seed = text.hashValue
        var rng = SeededRandomNumberGenerator(seed: UInt64(bitPattern: Int64(seed)))
        var embedding = (0..<embeddingDim).map { _ in Float.random(in: -1...1, using: &rng) }
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if norm > 0 { embedding = embedding.map { $0 / norm } }
        return embedding
    }
}

// MARK: - Mock Emotion Detection Service

struct MockEmotionDetectionService: EmotionDetectionServiceProtocol {

    func detectEmotions(for text: String) async throws -> [EmotionProbability] {
        try await Task.sleep(nanoseconds: 100_000_000)
        let lowered = text.lowercased()
        let emotionKeywords: [Emotion: [String]] = [
            .joy:       ["happy", "great", "wonderful", "amazing", "good", "love", "joy", "smile", "laugh"],
            .sadness:   ["sad", "cry", "miss", "lonely", "depressed", "unhappy", "grief", "loss"],
            .anger:     ["angry", "mad", "furious", "annoyed", "frustrated", "rage", "hate"],
            .fear:      ["scared", "afraid", "worried", "terrified", "nervous", "panic", "dread"],
            .love:      ["love", "care", "adore", "cherish", "affection", "heart", "warm"],
            .surprise:  ["surprise", "shocked", "unexpected", "wow", "sudden", "astonished"],
            .disgust:   ["disgust", "gross", "revolting", "sick", "repulsed", "awful"],
            .anxiety:   ["anxious", "worry", "stress", "tense", "overwhelmed", "uneasy"],
            .excitement:["excited", "thrilled", "eager", "pumped", "enthusiastic", "can't wait"],
            .gratitude: ["grateful", "thankful", "appreciate", "blessed", "fortunate"],
            .hope:      ["hope", "optimistic", "looking forward", "better", "improve", "future"],
            .guilt:     ["guilty", "regret", "sorry", "blame", "fault", "ashamed"]
        ]
        var scores: [Emotion: Float] = [:]
        for emotion in Emotion.allCases {
            let score = (emotionKeywords[emotion] ?? []).reduce(Float(0.05)) { acc, kw in
                acc + (lowered.contains(kw) ? 0.15 : 0)
            }
            scores[emotion] = min(score, 0.95)
        }
        let total = scores.values.reduce(0, +)
        return scores
            .map { EmotionProbability(emotion: $0.key.rawValue, probability: $0.value / total) }
            .sorted { $0.probability > $1.probability }
    }
}

// MARK: - Mock Clustering Service

struct MockClusteringService: ClusteringServiceProtocol {
    func clusterEntries(_ entries: [ClusterableEntry]) async throws -> [ClusterAssignment] {
        entries.map { entry in
            let hash = abs(entry.bitID.hashValue)
            let clusterID = (hash % 10) >= 8 ? -1 : (hash % 5)
            return ClusterAssignment(bitID: entry.bitID, clusterID: clusterID)
        }
    }
}

// MARK: - Seeded Random Number Generator

/// Deterministic RNG for reproducible mock embeddings.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        // xorshift64 algorithm
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
