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

    /// Create a container with production Core ML services.
    /// Currently returns mock services — will be updated when Core ML models are integrated.
    static func makeProduction() -> ServiceContainer {
        // TODO: Replace with real Core ML services when models are ready
        // return ServiceContainer(
        //     embeddingService: CoreMLEmbeddingService(),
        //     emotionService: CoreMLEmotionDetectionService(),
        //     clusteringService: DBSCANClusterer(),
        //     safetyFilter: SafetyFilter()
        // )
        return makeMock()
    }
}
