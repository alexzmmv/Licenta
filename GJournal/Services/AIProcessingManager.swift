import Foundation
import SwiftData
import Combine
import UIKit

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
        guard let container = modelContext?.container else { return }
        
        isProcessing = true

        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "AI-Pipeline-\(bitID.uuidString)") {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }

        Task {
            defer {
                self.isProcessing = false
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
            }
            do {
                try await self.runPipeline(for: bitID, flattenedText: flattenedText, container: container)
                self.lastError = nil
            } catch {
                AppLogger.error("[AI] Pipeline error for bit \(bitID): \(error)")
                self.lastError = error.localizedDescription
            }
        }
    }

    private func runPipeline(for bitID: UUID, flattenedText: String, container: ModelContainer) async throws {
        AppLogger.log("[AI] Step 1 — \(flattenedText.prefix(80))…")

        let safetyResult = services.safetyFilter.checkSafety(flattenedText)
        AppLogger.log("[AI] Step 2 — \(safetyResult.isSafe ? "safe" : "flagged")")

        // Steps 3-4: ML inference
        let capturedServices = services
        
        let (emb, emo) = try await Task.detached(priority: .utility) {
            let embedding = try await capturedServices.embeddingService.generateEmbedding(for: flattenedText)
            let emotions = try await capturedServices.emotionService.detectEmotions(for: flattenedText)
            
            // Persist on background context
            let backgroundContext = ModelContext(container)
            let predicate = #Predicate<Bit> { $0.id == bitID }
            if let bit = try backgroundContext.fetch(FetchDescriptor<Bit>(predicate: predicate)).first {
                bit.flattenedText = flattenedText
                bit.isSafeContent = safetyResult.isSafe
                bit.embedding = embedding
                bit.emotionProbabilities = emotions.reduce(into: [:]) { $0[$1.emotion] = $1.probability }
                bit.embeddingGeneratedAt = Date()

                // Behavioral tags (Pillar A substrate): extract → canonicalize → persist.
                let tagProcessor = TagProcessor(embeddingService: capturedServices.embeddingService)
                bit.tagLemmas = await tagProcessor.process(event: bit.event, action: bit.action, into: backgroundContext)

                try backgroundContext.save()
            }

            return (embedding, emotions)
        }.value

        AppLogger.log("[AI] Step 3 — \(emb.count)-dim embedding")
        AppLogger.log("[AI] Step 4 — \(emo.first?.emotion ?? "?") (\(String(format: "%.2f", emo.first?.probability ?? 0)))")
        AppLogger.log("[AI] Step 5 — Saved for bit \(bitID)")

        scheduleReclustering()
    }

    private func scheduleReclustering() {
        pendingClusterTask?.cancel()
        pendingClusterTask = Task {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let container = modelContext?.container else { return }
            try? await self.runClustering(forceRecalibrate: false)
        }
    }

    // MARK: - Behavioral Tag Backfill

    /// One-shot backfill of behavioral tags for existing entries that have an embedding but no
    /// tags yet. Reports (processed, total) progress on the main actor. Idempotent.
    func backfillTags(progress: @escaping @MainActor (Int, Int) -> Void) async {
        guard let container = modelContext?.container else { return }
        let capturedServices = services

        await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            let predicate = #Predicate<Bit> { $0.deletedAt == nil && $0.embeddingGeneratedAt != nil }
            guard let bits = try? context.fetch(FetchDescriptor<Bit>(predicate: predicate)) else { return }
            let pending = bits.filter { $0.tagLemmas.isEmpty }
            let total = pending.count
            guard total > 0 else { await progress(0, 0); return }

            let processor = TagProcessor(embeddingService: capturedServices.embeddingService)
            var done = 0
            for bit in pending {
                bit.tagLemmas = await processor.process(event: bit.event, action: bit.action, into: context)
                done += 1
                if done % 5 == 0 || done == total {
                    try? context.save()
                    await progress(done, total)
                }
            }
            try? context.save()
            await progress(total, total)
        }.value
    }

    // MARK: - Batch Clustering

    func runClustering(forceRecalibrate: Bool = false) async throws {
        guard let container = modelContext?.container else { return }
        var needsCalibration = forceRecalibrate || needsInitialCalibration
        if entriesSinceLastCalibration >= calibrationInterval {
            entriesSinceLastCalibration = 0
            needsCalibration = true
        }

        let capturedStrategy = services.clusteringStrategy
        let capturedServices = services
        let currentCalib = lastCalibrationResult
        
        struct ClusterResult {
            let clusterCount: Int
            let noiseCount: Int
            let silScore: Double
            let newCalib: CalibrationResult?
            let clearedCalib: Bool
        }

        guard let result = try await Task.detached(priority: .utility, operation: { () -> ClusterResult? in
            let backgroundContext = ModelContext(container)
            let predicate = #Predicate<Bit> { $0.deletedAt == nil }
            let allBits = try backgroundContext.fetch(FetchDescriptor<Bit>(predicate: predicate, sortBy: [SortDescriptor(\.createdAt)]))
            let clusterableEntries = allBits.compactMap { bit -> ClusterableEntry? in
                guard let emb = bit.embedding, bit.isSafeContent, !emb.isEmpty else { return nil }
                return ClusterableEntry(bitID: bit.id, embedding: emb, createdAt: bit.createdAt)
            }

            guard !clusterableEntries.isEmpty else { return nil }

            let assignments: [ClusterAssignment]
            var newCalib: CalibrationResult? = nil
            var clearedCalib = false

            if needsCalibration, capturedServices.clusteringService is DBSCANClusterer {
                let embeddings = clusterableEntries.map { $0.embedding }
                let n = embeddings.count
                let baseMinPts = DBSCANClusterer.adaptiveMinPoints(for: n)
                let cal: CalibrationResult
                switch capturedStrategy {
                case .mrlAdapted:
                    cal = DBSCANClusterer.calibrateEpsilonMRL(from: embeddings, baseMimPoints: baseMinPts)
                case .classic, .hdbscan:
                    cal = DBSCANClusterer.calibrateEpsilon(from: embeddings, minPoints: baseMinPts)
                }
                let clusterer = DBSCANClusterer(epsilon: cal.epsilon, minPoints: cal.minPoints)
                assignments = try await clusterer.clusterEntries(clusterableEntries)
                newCalib = cal
            } else if let calibResult = currentCalib, capturedServices.clusteringService is DBSCANClusterer {
                let clusterer = DBSCANClusterer(epsilon: calibResult.epsilon, minPoints: calibResult.minPoints)
                assignments = try await clusterer.clusterEntries(clusterableEntries)
            } else if capturedServices.clusteringService is HDBSCANClusterer {
                let n = clusterableEntries.count
                let minPts = HDBSCANClusterer.adaptiveMinPts(for: n)
                let clusterer = HDBSCANClusterer(minPts: minPts, minClusterSize: minPts)
                assignments = try await clusterer.clusterEntries(clusterableEntries)
                clearedCalib = true
            } else {
                assignments = try await capturedServices.clusteringService.clusterEntries(clusterableEntries)
            }

            // Persist cluster assignments on BackgroundContext
            let freshBits = try backgroundContext.fetch(FetchDescriptor<Bit>(predicate: #Predicate<Bit> { $0.deletedAt == nil }))
            let existingClusters = try backgroundContext.fetch(FetchDescriptor<Cluster>())
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
                        backgroundContext.insert(cluster)
                    }
                    cluster.name = ClusterNamer.generateName(for: bitsInCluster, allBits: freshBits, fallbackID: clusterID)
                    bitsInCluster.forEach { $0.cluster = cluster; $0.clusterAssignedAt = Date() }
                }
            }

            let activeIDs = Set(grouped.keys.filter { $0 != -1 })
            existingClusters.filter { !activeIDs.contains($0.index) }.forEach { backgroundContext.delete($0) }

            try backgroundContext.save()

            let clusterCount = activeIDs.count
            let noiseCount = assignments.filter { $0.isNoise }.count
            let finalCalib = newCalib ?? currentCalib
            let silScore = finalCalib?.silhouetteScore ?? -1
            return ClusterResult(clusterCount: clusterCount, noiseCount: noiseCount, silScore: silScore, newCalib: newCalib, clearedCalib: clearedCalib)
        }).value else {
            AppLogger.log("[AI] No entries with embeddings to cluster")
            return
        }

        if let newCalib = result.newCalib {
            lastCalibrationResult = newCalib
            needsInitialCalibration = false
            AppLogger.log("[AI] Calibrated: \(newCalib)")
        } else if result.clearedCalib {
            needsInitialCalibration = false
        }

        AppLogger.log("[AI] Done: \(result.clusterCount) clusters, \(result.noiseCount) noise, silhouette=\(String(format: "%.4f", result.silScore))")
        onClusteringComplete?()
    }
}
