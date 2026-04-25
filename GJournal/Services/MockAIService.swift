//
//  MockAIService.swift
//  GJournal
//
//  Mock implementations of AI service protocols for development
//  and testing. These return deterministic/random results that
//  simulate the real Core ML pipeline behavior.
//

import Foundation

// MARK: - Mock Embedding Service

/// Generates random 768-dimensional embedding vectors for development.
/// In production, this will be replaced by a Core ML DistilBERT model.
final class MockEmbeddingService: EmbeddingServiceProtocol {
    /// Embedding dimension matching DistilBERT output
    private let embeddingDim = 768

    func generateEmbedding(for text: String) async throws -> [Float] {
        // Simulate processing delay (real model takes ~1-3s on iPhone 11)
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Generate a deterministic-ish embedding based on text hash
        // so the same text always produces the same embedding
        let seed = text.hashValue
        var rng = SeededRandomNumberGenerator(seed: UInt64(bitPattern: Int64(seed)))

        var embedding = (0..<embeddingDim).map { _ in
            Float.random(in: -1...1, using: &rng)
        }

        // Normalize to unit vector (L2 norm)
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            embedding = embedding.map { $0 / norm }
        }

        return embedding
    }
}

// MARK: - Mock Emotion Detection Service

/// Returns emotion probabilities weighted toward the text content.
/// Uses simple keyword matching to produce plausible results.
final class MockEmotionDetectionService: EmotionDetectionServiceProtocol {

    func detectEmotions(for text: String) async throws -> [EmotionProbability] {
        // Simulate processing delay
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        let lowered = text.lowercased()

        // Score each emotion based on keyword presence
        var scores: [Emotion: Float] = [:]

        let emotionKeywords: [Emotion: [String]] = [
            .joy: ["happy", "great", "wonderful", "amazing", "good", "love", "joy", "smile", "laugh"],
            .sadness: ["sad", "cry", "miss", "lonely", "depressed", "unhappy", "grief", "loss"],
            .anger: ["angry", "mad", "furious", "annoyed", "frustrated", "rage", "hate"],
            .fear: ["scared", "afraid", "worried", "terrified", "nervous", "panic", "dread"],
            .love: ["love", "care", "adore", "cherish", "affection", "heart", "warm"],
            .surprise: ["surprise", "shocked", "unexpected", "wow", "sudden", "astonished"],
            .disgust: ["disgust", "gross", "revolting", "sick", "repulsed", "awful"],
            .anxiety: ["anxious", "worry", "stress", "tense", "overwhelmed", "uneasy"],
            .excitement: ["excited", "thrilled", "eager", "pumped", "enthusiastic", "can't wait"],
            .gratitude: ["grateful", "thankful", "appreciate", "blessed", "fortunate"],
            .hope: ["hope", "optimistic", "looking forward", "better", "improve", "future"],
            .guilt: ["guilty", "regret", "sorry", "blame", "fault", "ashamed"]
        ]

        for emotion in Emotion.allCases {
            let keywords = emotionKeywords[emotion] ?? []
            var score: Float = 0.05 // Base probability

            for keyword in keywords {
                if lowered.contains(keyword) {
                    score += 0.15
                }
            }

            scores[emotion] = min(score, 0.95)
        }

        // Normalize to sum to 1.0
        let total = scores.values.reduce(0, +)
        let normalized = scores.mapValues { $0 / total }

        return normalized
            .map { EmotionProbability(emotion: $0.key.rawValue, probability: $0.value) }
            .sorted { $0.probability > $1.probability }
    }
}

// MARK: - Mock Clustering Service

/// Groups entries by emotion similarity and date proximity.
/// Uses a simplified clustering approach for development.
final class MockClusteringService: ClusteringServiceProtocol {

    func clusterEntries(_ entries: [ClusterableEntry]) async throws -> [ClusterAssignment] {
        // Group entries into ~5 distinct clusters deterministically based on their bitID to simulate clusters
        // without relying on the random distances of mock embeddings.
        return entries.map { entry in
            let hash = abs(entry.bitID.hashValue)
            // 80% chance to be in a cluster (0-4), 20% chance to be noise (-1)
            let isNoise = (hash % 10) >= 8
            let clusterID = isNoise ? -1 : (hash % 5)
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
