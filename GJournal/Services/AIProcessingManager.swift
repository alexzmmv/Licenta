//
//  AIProcessingManager.swift
//  GJournal
//
//  Orchestrates the full AI processing pipeline for journal entries:
//  Text Flattening → Safety Check → Embedding → Emotion Detection →
//  Storage → DBSCAN Clustering
//

import Foundation
import SwiftData
import Combine

/// Orchestrates the AI processing pipeline. Isolated to MainActor so all
/// published state and SwiftData access are safe without explicit hops.
/// CPU-heavy ML inference is offloaded via Task.detached.
@MainActor
final class AIProcessingManager: ObservableObject {
    private let services: ServiceContainer
    private var modelContext: ModelContext?

    @Published var isProcessing = false
    @Published var lastError: String?

    var onClusteringComplete: (() -> Void)?

    private var needsInitialCalibration = true
    private var entriesSinceLastCalibration = 0
    private let calibrationInterval = 10
    private(set) var lastCalibrationResult: CalibrationResult?
    private var pendingClusterTask: Task<Void, Never>?

    init(services: ServiceContainer) {
        self.services = services
    }

    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func resetState() {
        pendingClusterTask?.cancel()
        pendingClusterTask = nil
        lastCalibrationResult = nil
        entriesSinceLastCalibration = 0
        needsInitialCalibration = true
    }

    // MARK: - Single Entry Processing

    func processBit(_ bit: Bit) {
        let bitID = bit.id
        let flattenedText = TextFlattener.flatten(bit: bit)
        isProcessing = true

        Task {
            defer { isProcessing = false }
            do {
                try await runPipeline(for: bitID, flattenedText: flattenedText)
                lastError = nil
            } catch {
                AppLogger.error("[AI] Pipeline error for bit \(bitID): \(error)")
                lastError = error.localizedDescription
            }
        }
    }

    private func runPipeline(for bitID: UUID, flattenedText: String) async throws {
        AppLogger.log("[AI] Step 1 — \(flattenedText.prefix(80))…")

        let safetyResult = services.safetyFilter.checkSafety(flattenedText)
        AppLogger.log("[AI] Step 2 — \(safetyResult.isSafe ? "safe" : "flagged")")

        // Steps 3-4: ML inference — hop off MainActor
        let capturedServices = services
        let (embedding, emotions): ([Float], [EmotionProbability]) = try await Task.detached(priority: .utility) {
            let emb = try await capturedServices.embeddingService.generateEmbedding(for: flattenedText)
            let emo = try await capturedServices.emotionService.detectEmotions(for: flattenedText)
            return (emb, emo)
        }.value

        AppLogger.log("[AI] Step 3 — \(embedding.count)-dim embedding")
        AppLogger.log("[AI] Step 4 — \(emotions.first?.emotion ?? "?") (\(String(format: "%.2f", emotions.first?.probability ?? 0)))")

        // Step 5: Persist on MainActor
        guard let modelContext else { return }
        let predicate = #Predicate<Bit> { $0.id == bitID }
        if let bit = try modelContext.fetch(FetchDescriptor<Bit>(predicate: predicate)).first {
            bit.flattenedText = flattenedText
            bit.isSafeContent = safetyResult.isSafe
            bit.embedding = embedding
            bit.emotionProbabilities = emotions.reduce(into: [:]) { $0[$1.emotion] = $1.probability }
            bit.embeddingGeneratedAt = Date()
            try modelContext.save()
            AppLogger.log("[AI] Step 5 — Saved for bit \(bitID)")
        }

        entriesSinceLastCalibration += 1
        scheduleReclustering()
    }

    private func scheduleReclustering() {
        pendingClusterTask?.cancel()
        pendingClusterTask = Task {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            try? await runClustering()
        }
    }

    // MARK: - Batch Clustering

    func runClustering(forceRecalibrate: Bool = false) async throws {
        guard let modelContext else {
            AppLogger.log("[AI] ModelContext not configured for clustering")
            return
        }

        let predicate = #Predicate<Bit> { $0.deletedAt == nil }
        let allBits = try modelContext.fetch(
            FetchDescriptor<Bit>(predicate: predicate, sortBy: [SortDescriptor(\.createdAt)])
        )
        let clusterableEntries = allBits.compactMap { bit -> ClusterableEntry? in
            guard let emb = bit.embedding, bit.isSafeContent, !emb.isEmpty else { return nil }
            return ClusterableEntry(bitID: bit.id, embedding: emb, createdAt: bit.createdAt)
        }

        guard !clusterableEntries.isEmpty else {
            AppLogger.log("[AI] No entries with embeddings to cluster")
            return
        }

        AppLogger.log("[AI] Step 6 — Clustering \(clusterableEntries.count) entries…")

        // Determine whether calibration is needed
        var needsCalibration = forceRecalibrate || needsInitialCalibration
        if entriesSinceLastCalibration >= calibrationInterval {
            entriesSinceLastCalibration = 0
            needsCalibration = true
        }

        let capturedStrategy = services.clusteringStrategy
        let capturedServices = services
        let assignments: [ClusterAssignment]

        if needsCalibration, capturedServices.clusteringService is DBSCANClusterer {
            let embeddings = clusterableEntries.map { $0.embedding }
            let n = embeddings.count
            let baseMinPts = DBSCANClusterer.adaptiveMinPoints(for: n)

            let (calibResult, result) = try await Task.detached(priority: .utility) {
                let cal: CalibrationResult
                switch capturedStrategy {
                case .mrlAdapted:
                    cal = DBSCANClusterer.calibrateEpsilonMRL(from: embeddings, baseMimPoints: baseMinPts)
                case .classic:
                    cal = DBSCANClusterer.calibrateEpsilon(from: embeddings, minPoints: baseMinPts)
                }
                let clusterer = DBSCANClusterer(epsilon: cal.epsilon, minPoints: cal.minPoints)
                let a = try await clusterer.clusterEntries(clusterableEntries)
                return (cal, a)
            }.value

            lastCalibrationResult = calibResult
            needsInitialCalibration = false
            assignments = result
            AppLogger.log("[AI] Calibrated: \(calibResult)")

        } else if let calibResult = lastCalibrationResult, capturedServices.clusteringService is DBSCANClusterer {
            assignments = try await Task.detached(priority: .utility) {
                let clusterer = DBSCANClusterer(epsilon: calibResult.epsilon, minPoints: calibResult.minPoints)
                return try await clusterer.clusterEntries(clusterableEntries)
            }.value

        } else {
            assignments = try await capturedServices.clusteringService.clusterEntries(clusterableEntries)
        }

        // Persist cluster assignments on MainActor
        let freshBits = try modelContext.fetch(FetchDescriptor<Bit>(predicate: #Predicate<Bit> { $0.deletedAt == nil }))
        let existingClusters = try modelContext.fetch(FetchDescriptor<Cluster>())
        let grouped = Dictionary(grouping: assignments) { $0.clusterID }

        for (clusterID, group) in grouped {
            let bitIDs = group.map { $0.bitID }
            let bitsInCluster = freshBits.filter { bitIDs.contains($0.id) }

            if clusterID == -1 {
                bitsInCluster.forEach { $0.cluster = nil; $0.clusterAssignedAt = Date() }
            } else {
                let cluster: Cluster
                if let existing = existingClusters.first(where: { $0.index == clusterID }) {
                    cluster = existing
                } else {
                    cluster = Cluster(index: clusterID, name: "Cluster \(clusterID)")
                    modelContext.insert(cluster)
                }
                cluster.name = ClusterNamer.generateName(for: bitsInCluster, allBits: freshBits, fallbackID: clusterID)
                bitsInCluster.forEach { $0.cluster = cluster; $0.clusterAssignedAt = Date() }
            }
        }

        let activeIDs = Set(grouped.keys.filter { $0 != -1 })
        existingClusters.filter { !activeIDs.contains($0.index) }.forEach { modelContext.delete($0) }

        try modelContext.save()

        let clusterCount = activeIDs.count
        let noiseCount = assignments.filter { $0.isNoise }.count
        let silScore = lastCalibrationResult?.silhouetteScore ?? -1
        AppLogger.log("[AI] Done: \(clusterCount) clusters, \(noiseCount) noise, silhouette=\(String(format: "%.4f", silScore))")
        onClusteringComplete?()
    }
}
