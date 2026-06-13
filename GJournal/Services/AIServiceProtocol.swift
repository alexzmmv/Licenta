import Foundation

// MARK: - Embedding Service

protocol EmbeddingServiceProtocol {
    func generateEmbedding(for text: String) async throws -> [Float]
}

// MARK: - Emotion Detection Service

protocol EmotionDetectionServiceProtocol {
    func detectEmotions(for text: String) async throws -> [EmotionProbability]
}

// MARK: - Clustering Service

protocol ClusteringServiceProtocol {
    func clusterEntries(_ entries: [ClusterableEntry]) async throws -> [ClusterAssignment]
}

// MARK: - Safety Filter Service

protocol SafetyFilterServiceProtocol {
    func checkSafety(_ text: String) -> SafetyResult
}

// MARK: - Supporting Types

struct ClusterableEntry {
    let bitID: UUID
    let embedding: [Float]
    let createdAt: Date
}

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
