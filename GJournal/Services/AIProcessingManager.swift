//
//  AIProcessingManager.swift
//  GJournal
//
//  Orchestrates the full AI processing pipeline for journal entries:
//  Text Flattening → Safety Check → Embedding Generation →
//  Emotion Detection → Storage → DBSCAN Clustering
//
//  Runs as a background job to minimize battery impact (NFR5).
//

import Foundation
import SwiftData
import Combine

/// Orchestrates the AI processing pipeline for journal entries.
///
/// Pipeline (per documentation §3.6):
/// 1. Text Flattening: Combine fields for BERT input
/// 2. Safety & Misuse Filter: Detect harmful content
/// 3. Core ML BERT Model: Generate embedding + emotion probabilities
/// 4. Local Storage: Save embedding, emotions, safety flag
/// 5. Pattern Detection: Run DBSCAN clustering on all embeddings
///
/// All processing runs on background threads with low priority
/// to minimize battery impact (NFR5).
final class AIProcessingManager: ObservableObject {
    private let services: ServiceContainer
    private var modelContext: ModelContext?

    /// Whether a processing job is currently running
    @Published var isProcessing = false

    /// Last processing error, if any
    @Published var lastError: String?

    /// Callback triggered when clustering completes and data is saved to DB
    var onClusteringComplete: (() -> Void)?

    // Epsilon recalibration — recalculate every 10 new processed entries
    private var entriesSinceLastCalibration = 0
    private let calibrationInterval = 10
    // Persisted calibrated epsilon — reused across non-calibration runs to avoid
    // falling back to the hardcoded ε=0.3 that produces excessive noise
    private var lastCalibratedEpsilon: Double?

    // Debounce clustering — cancel pending run and restart timer on each new entry
    private var pendingClusterTask: Task<Void, Never>?

    init(services: ServiceContainer) {
        self.services = services
    }

    /// Configure with SwiftData context for persistence
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Single Entry Processing

    /// Process a single bit through the AI pipeline.
    /// Called after a new entry is saved or an existing entry is updated.
    /// Runs in the background with low priority.
    func processBit(_ bit: Bit) {
        let bitID = bit.id
        let flattenedText = TextFlattener.flatten(bit: bit)
        
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            await MainActor.run { self.isProcessing = true }

            do {
                try await self.runPipeline(for: bitID, flattenedText: flattenedText)
                await MainActor.run { self.lastError = nil }
            } catch {
                print("[AIProcessingManager] Pipeline error for bit \(bitID): \(error)")
                await MainActor.run { self.lastError = error.localizedDescription }
            }

            await MainActor.run { self.isProcessing = false }
        }
    }

    /// Run the full pipeline for a single bit.
    private func runPipeline(for bitID: UUID, flattenedText: String) async throws {
        print("[AIProcessingManager] Step 1 — Flattened text: \(flattenedText.prefix(100))...")

        // Step 2: Safety & Misuse Filter
        let safetyResult = services.safetyFilter.checkSafety(flattenedText)
        print("[AIProcessingManager] Step 2 — Safety check: \(safetyResult.isSafe ? "SAFE" : "FLAGGED: \(safetyResult.reason ?? "")")")

        // Step 3: Generate Embedding (even for flagged content — store but exclude from recommendations)
        let embedding: [Float] = try await services.embeddingService.generateEmbedding(for: flattenedText)
        print("[AIProcessingManager] Step 3 — Generated \(embedding.count)-dim embedding")

        // Step 4: Detect Emotions
        let emotions = try await services.emotionService.detectEmotions(for: flattenedText)
        let topEmotion = emotions.first?.emotion ?? "Unknown"
        print("[AIProcessingManager] Step 4 — Top emotion: \(topEmotion) (\(String(format: "%.2f", emotions.first?.probability ?? 0)))")

        // Step 5: Persist AI results to the Bit on MainActor
        await MainActor.run {
            if let modelContext = self.modelContext {
                do {
                    let predicate = #Predicate<Bit> { $0.id == bitID }
                    let descriptor = FetchDescriptor<Bit>(predicate: predicate)
                    if let bit = try modelContext.fetch(descriptor).first {
                        bit.flattenedText = flattenedText
                        bit.isSafeContent = safetyResult.isSafe
                        bit.embedding = embedding
                        bit.emotionProbabilities = emotions.reduce(into: [String: Float]()) { dict, ep in
                            dict[ep.emotion] = ep.probability
                        }
                        bit.embeddingGeneratedAt = Date()
                        try modelContext.save()
                        print("[AIProcessingManager] Step 5 — Saved AI results for bit \(bitID)")
                    }
                } catch {
                    print("[AIProcessingManager] Failed to save AI results: \(error)")
                }
            }
        }

        // Step 6: Schedule re-clustering — debounced so it fires once after all in-flight entries finish
        await MainActor.run {
            self.entriesSinceLastCalibration += 1
            self.scheduleReclustering()
        }
    }

    private func scheduleReclustering() {
        pendingClusterTask?.cancel()
        pendingClusterTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return // cancelled — a newer entry is still processing
            }
            guard let self else { return }
            try? await self.runClustering()
        }
    }

    // MARK: - Batch Clustering

    /// Run DBSCAN clustering on all entries that have embeddings.
    /// Called after processing a new entry or as a periodic batch job.
    /// - Parameter forceRecalibrate: When true, always recalculate epsilon from the current embeddings.
    ///   Use after switching embedding models or when manually reclustering.
    func runClustering(forceRecalibrate: Bool = false) async throws {
        guard let modelContext = modelContext else {
            print("[AIProcessingManager] ModelContext not configured for clustering")
            return
        }

        // Build clusterable entries by extracting sendable properties on the MainActor
        let clusterableEntries: [ClusterableEntry]
        do {
            clusterableEntries = try await MainActor.run {
                let predicate = #Predicate<Bit> { bit in
                    bit.deletedAt == nil
                }
                let descriptor = FetchDescriptor<Bit>(
                    predicate: predicate,
                    sortBy: [SortDescriptor(\.createdAt)]
                )
                let allBits = try modelContext.fetch(descriptor)
                
                return allBits.compactMap { bit -> ClusterableEntry? in
                    guard let embedding = bit.embedding,
                          bit.isSafeContent,
                          !embedding.isEmpty else {
                        return nil
                    }
                    return ClusterableEntry(
                        bitID: bit.id,
                        embedding: embedding,
                        createdAt: bit.createdAt
                    )
                }
            }
        } catch {
            print("[AIProcessingManager] Failed to fetch bits for clustering: \(error)")
            return
        }

        guard !clusterableEntries.isEmpty else {
            print("[AIProcessingManager] No entries with embeddings to cluster")
            return
        }

        print("[AIProcessingManager] Step 6 — Clustering \(clusterableEntries.count) entries...")

        // Recalibrate epsilon if forced or after calibrationInterval new entries.
        // Read both flags and the cached epsilon atomically on the MainActor.
        let (shouldCalibrate, storedEpsilon): (Bool, Double?) = await MainActor.run {
            var needsCalibration = forceRecalibrate
            if self.entriesSinceLastCalibration >= self.calibrationInterval {
                self.entriesSinceLastCalibration = 0
                needsCalibration = true
            }
            return (needsCalibration, self.lastCalibratedEpsilon)
        }

        let activeClusterer: ClusteringServiceProtocol
        if shouldCalibrate, let dbscan = services.clusteringService as? DBSCANClusterer {
            let embeddings = clusterableEntries.map { $0.embedding }
            let n = embeddings.count
            let minPts = DBSCANClusterer.adaptiveMinPoints(for: n)
            let target = DBSCANClusterer.targetClusterRange(for: n)
            let newEpsilon = DBSCANClusterer.calibrateEpsilon(
                from: embeddings, minPoints: minPts, targetRange: target
            )
            await MainActor.run { self.lastCalibratedEpsilon = newEpsilon }
            activeClusterer = DBSCANClusterer(epsilon: newEpsilon, minPoints: minPts)
            print("[AIProcessingManager] Recalibrated ε=\(String(format: "%.3f", newEpsilon)) minPts=\(minPts) target=\(target.lowerBound)–\(target.upperBound) for N=\(n)")
        } else if let epsilon = storedEpsilon, let dbscan = services.clusteringService as? DBSCANClusterer {
            // Reuse the last empirically derived epsilon instead of falling back to the
            // hardcoded 0.3 (or the mrlAdapted scaling), which produces excessive noise
            let minPts = DBSCANClusterer.adaptiveMinPoints(for: clusterableEntries.count)
            activeClusterer = DBSCANClusterer(epsilon: epsilon, minPoints: minPts)
        } else {
            activeClusterer = services.clusteringService
        }

        // Run DBSCAN off-actor
        let assignments = try await activeClusterer.clusterEntries(clusterableEntries)

        // Persist cluster assignments on the MainActor
        await MainActor.run {
            do {
                let predicate = #Predicate<Bit> { bit in
                    bit.deletedAt == nil
                }
                let descriptor = FetchDescriptor<Bit>(predicate: predicate)
                let allBits = try modelContext.fetch(descriptor)
                
                // Fetch existing clusters to reuse them
                let clusterDescriptor = FetchDescriptor<Cluster>()
                let existingClusters = try modelContext.fetch(clusterDescriptor)
                
                // Group assignments by cluster to generate/update names efficiently
                let groupedAssignments = Dictionary(grouping: assignments) { $0.clusterID }
                
                for (clusterID, clusterAssignments) in groupedAssignments {
                    let bitIDs = clusterAssignments.map { $0.bitID }
                    let bitsInCluster = allBits.filter { bitIDs.contains($0.id) }
                    
                    if clusterID == -1 {
                        // Noise: Remove from any cluster
                        for bit in bitsInCluster {
                            bit.cluster = nil
                            bit.clusterAssignedAt = Date()
                        }
                    } else {
                        // Real Cluster: Find or Create
                        let cluster: Cluster
                        if let existing = existingClusters.first(where: { $0.index == clusterID }) {
                            cluster = existing
                        } else {
                            cluster = Cluster(index: clusterID, name: "Cluster \(clusterID)")
                            modelContext.insert(cluster)
                        }
                        
                        // Update name based on current bits
                        cluster.name = ClusterNamer.generateName(for: bitsInCluster, fallbackID: clusterID)
                        
                        for bit in bitsInCluster {
                            bit.cluster = cluster
                            bit.clusterAssignedAt = Date()
                        }
                    }
                }
                
                // Remove Cluster objects from previous runs that no longer exist
                let activeClusterIDs = Set(groupedAssignments.keys.filter { $0 != -1 })
                for cluster in existingClusters where !activeClusterIDs.contains(cluster.index) {
                    modelContext.delete(cluster)
                }

                try modelContext.save()
                let clusterCount = Set(assignments.map { $0.clusterID }).filter { $0 != -1 }.count
                let noiseCount = assignments.filter { $0.isNoise }.count
                print("[AIProcessingManager] Clustering complete: \(clusterCount) clusters, \(noiseCount) noise points")
                
                // Notify observers that data has changed
                self.onClusteringComplete?()
            } catch {
                print("[AIProcessingManager] Failed to save cluster assignments: \(error)")
            }
        }
    }
}
