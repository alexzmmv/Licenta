//
//  ServiceContainer.swift
//  GJournal
//
//  Dependency injection container that holds all service instances.
//  Provides factory methods for mock and production configurations.
//

import Foundation
import Combine

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

    static func makeMock() -> ServiceContainer {
        ServiceContainer(
            embeddingService: MockEmbeddingService(),
            emotionService: MockEmotionDetectionService(),
            clusteringService: MockClusteringService(),
            safetyFilter: SafetyFilter()
        )
    }

    static func makeProduction() -> ServiceContainer {
        makeProduction(
            embeddingModel: EmbeddingModelChoice.current,
            clusteringStrategy: ClusteringStrategyChoice.current
        )
    }

    static func makeProduction(
        embeddingModel: EmbeddingModelChoice,
        clusteringStrategy: ClusteringStrategyChoice
    ) -> ServiceContainer {
        let embeddingService: EmbeddingServiceProtocol
        let embeddingDim: Int

        switch embeddingModel {
        case .miniLM:
            embeddingService = CoreMLEmbeddingService(modelName: "GJournalEmbeddingMiniLM", poolingMode: .mean)
            embeddingDim = 384

        case .nomicMRL:
            embeddingService = NomicEmbeddingService(truncateDim: 256)
            embeddingDim = 256

        case .appleNLP:
            embeddingService = NLEmbeddingService()
            embeddingDim = 512
        }

        let clusteringService = DBSCANClusterer(
            epsilon: 0.3,
            minPoints: 3,
            embeddingDim: embeddingDim,
            strategy: clusteringStrategy
        )

        return ServiceContainer(
            embeddingService: embeddingService,
            emotionService: CoreMLEmotionService(modelName: "GJournalEmotionClassifier"),
            clusteringService: clusteringService,
            safetyFilter: SafetyFilter()
        )
    }
}
