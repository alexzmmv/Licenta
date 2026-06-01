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
    let clusteringStrategy: ClusteringStrategyChoice

    init(
        embeddingService: EmbeddingServiceProtocol,
        emotionService: EmotionDetectionServiceProtocol,
        clusteringService: ClusteringServiceProtocol,
        safetyFilter: SafetyFilterServiceProtocol,
        clusteringStrategy: ClusteringStrategyChoice = .classic
    ) {
        self.embeddingService = embeddingService
        self.emotionService = emotionService
        self.clusteringService = clusteringService
        self.safetyFilter = safetyFilter
        self.clusteringStrategy = clusteringStrategy
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

        switch embeddingModel {
        case .miniLM:
            embeddingService = CoreMLEmbeddingService(modelName: "GJournalEmbeddingMiniLM", poolingMode: .mean)
        case .nomicFull:
            embeddingService = NomicEmbeddingService(truncateDim: 768)
        case .nomicMRL:
            embeddingService = NomicEmbeddingService(truncateDim: 256)
        case .appleNLP:
            embeddingService = NLEmbeddingService()
        }

        let clusteringService = DBSCANClusterer()

        return ServiceContainer(
            embeddingService: embeddingService,
            emotionService: CoreMLEmotionService(modelName: "GJournalEmotionClassifier"),
            clusteringService: clusteringService,
            safetyFilter: SafetyFilter(),
            clusteringStrategy: clusteringStrategy
        )
    }
}
