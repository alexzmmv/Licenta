//
//  ServiceContainer.swift
//  GJournal
//
//  Dependency injection container that holds all service instances.
//  Provides factory methods for mock and production configurations.
//

import Foundation
import Combine

/// Central DI container for all AI and processing services.
///
/// Usage:
/// ```swift
/// let services = ServiceContainer.makeMock()
/// let manager = AIProcessingManager(services: services)
/// ```
final class ServiceContainer: ObservableObject {
    let embeddingService: EmbeddingServiceProtocol
    let emotionService: EmotionDetectionServiceProtocol
    let clusteringService: ClusteringServiceProtocol
    let safetyFilter: SafetyFilterServiceProtocol

    init(
        embeddingService: EmbeddingServiceProtocol,
        emotionService: EmotionDetectionServiceProtocol,
        clusteringService: ClusteringServiceProtocol,
        safetyFilter: SafetyFilterServiceProtocol
    ) {
        self.embeddingService = embeddingService
        self.emotionService = emotionService
        self.clusteringService = clusteringService
        self.safetyFilter = safetyFilter
    }

    /// Create a container with mock services for development and testing.
    static func makeMock() -> ServiceContainer {
        return ServiceContainer(
            embeddingService: MockEmbeddingService(),
            emotionService: MockEmotionDetectionService(),
            clusteringService: MockClusteringService(),
            safetyFilter: SafetyFilter()  // Safety filter is real (keyword-based)
        )
    }

    /// Create a container wired to real Core ML services.
    /// Automatically picks the best available embedding model:
    ///   MobileBERT (primary) → DistilBERT (backup A) → NLEmbedding (backup C)
    /// Falls back to MockEmotionDetectionService if the classifier .mlpackage is missing.
    static func makeProduction() -> ServiceContainer {
        let embeddingService: EmbeddingServiceProtocol = {
            if Bundle.main.url(forResource: "GJournalEmbeddingMobileBERT", withExtension: "mlpackage") != nil {
                return CoreMLEmbeddingService(modelName: "GJournalEmbeddingMobileBERT")
            } else if Bundle.main.url(forResource: "GJournalEmbeddingDistilBERT", withExtension: "mlpackage") != nil {
                return CoreMLEmbeddingService(modelName: "GJournalEmbeddingDistilBERT")
            } else {
                print("[ServiceContainer] No embedding .mlpackage found — using NLEmbedding fallback")
                return NLEmbeddingService()
            }
        }()

        let emotionService: EmotionDetectionServiceProtocol = {
            if Bundle.main.url(forResource: "GJournalEmotionClassifier", withExtension: "mlpackage") != nil {
                return CoreMLEmotionService(modelName: "GJournalEmotionClassifier")
            } else {
                print("[ServiceContainer] No emotion .mlpackage found — using MockEmotionDetectionService")
                return MockEmotionDetectionService()
            }
        }()

        return ServiceContainer(
            embeddingService: embeddingService,
            emotionService: emotionService,
            clusteringService: DBSCANClusterer(epsilon: 0.3, minPoints: 3),
            safetyFilter: SafetyFilter()
        )
    }
}
