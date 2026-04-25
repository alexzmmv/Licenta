//
//  AIServiceProtocol.swift
//  GJournal
//
//  Protocols defining the AI service interfaces for dependency injection.
//  Each protocol represents a distinct capability in the AI pipeline.
//

import Foundation

// MARK: - Embedding Service

/// Generates semantic embedding vectors from text using a BERT-family model.
protocol EmbeddingServiceProtocol {
    /// Generate a 768-dimensional embedding vector for the given text.
    /// - Parameter text: Flattened journal entry text.
    /// - Returns: Array of Float values representing the semantic embedding.
    func generateEmbedding(for text: String) async throws -> [Float]
}

// MARK: - Emotion Detection Service

/// Detects emotion probabilities from text.
protocol EmotionDetectionServiceProtocol {
    /// Detect emotion probabilities for the given text.
    /// - Parameter text: Flattened journal entry text.
    /// - Returns: Array of emotion probabilities sorted by confidence.
    func detectEmotions(for text: String) async throws -> [EmotionProbability]
}

// MARK: - Clustering Service

/// Groups journal entries into semantically coherent clusters.
protocol ClusteringServiceProtocol {
    /// Cluster the given entries based on their embeddings.
    /// - Parameter entries: Array of entries with their embedding vectors.
    /// - Returns: Array of cluster assignments (clusterID = -1 means noise).
    func clusterEntries(_ entries: [ClusterableEntry]) async throws -> [ClusterAssignment]
}

// MARK: - Safety Filter Service

/// Filters content for harmful, illegal, or unsafe material.
protocol SafetyFilterServiceProtocol {
    /// Check whether the given text is safe for storage and pattern detection.
    /// - Parameter text: Raw journal entry text.
    /// - Returns: Safety check result.
    func checkSafety(_ text: String) -> SafetyResult
}

// MARK: - Supporting Types

/// An entry that can be clustered, holding its ID and embedding vector.
struct ClusterableEntry {
    let bitID: UUID
    let embedding: [Float]
    let createdAt: Date
}

/// Result of a safety check on text content.
struct SafetyResult {
    let isSafe: Bool
    let reason: String?

    static let safe = SafetyResult(isSafe: true, reason: nil)
}

// MARK: - Errors

enum AIServiceError: LocalizedError {
    case modelNotLoaded
    case embeddingGenerationFailed
    case emotionDetectionFailed
    case clusteringFailed
    case insufficientData

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "AI model is not loaded"
        case .embeddingGenerationFailed:
            return "Failed to generate embedding"
        case .emotionDetectionFailed:
            return "Failed to detect emotions"
        case .clusteringFailed:
            return "Failed to cluster entries"
        case .insufficientData:
            return "Not enough data for analysis"
        }
    }
}
