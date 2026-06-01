//
//  DBSCANClusterer.swift
//  GJournal
//
//  Pure Swift implementation of DBSCAN (Density-Based Spatial Clustering
//  of Applications with Noise) for clustering journal entry embeddings.
//
//  Uses cosine similarity as the distance metric, suitable for
//  high-dimensional embedding vectors from BERT-family models.
//

import Foundation
import Accelerate

final class DBSCANClusterer: ClusteringServiceProtocol {

    let epsilon: Double
    let minPoints: Int
    private let effectiveEpsilon: Double

    init(epsilon: Double = 0.3, minPoints: Int = 3, embeddingDim: Int = 384,
         strategy: ClusteringStrategyChoice = .classic) {
        self.epsilon = epsilon
        self.minPoints = minPoints
        switch strategy {
        case .classic:
            self.effectiveEpsilon = epsilon
        case .mrlAdapted:
            // Cosine distances shrink as dimensionality decreases — scale epsilon accordingly.
            self.effectiveEpsilon = epsilon * sqrt(Double(embeddingDim) / 768.0)
        }
    }

    // MARK: - ClusteringServiceProtocol

    func clusterEntries(_ entries: [ClusterableEntry]) async throws -> [ClusterAssignment] {
        guard entries.count >= minPoints else {
            // Not enough entries to form any cluster — all are noise
            return entries.map { ClusterAssignment(bitID: $0.bitID, clusterID: -1) }
        }

        let embeddings = entries.map { $0.embedding }
        let labels = dbscan(points: embeddings)

        return zip(entries, labels).map { entry, label in
            ClusterAssignment(bitID: entry.bitID, clusterID: label)
        }
    }

    // MARK: - DBSCAN Core Algorithm

    /// Run DBSCAN on a set of embedding vectors.
    /// - Parameter points: Array of embedding vectors (each is [Float])
    /// - Returns: Array of cluster labels (-1 = noise, 0+ = cluster ID)
    func dbscan(points: [[Float]]) -> [Int] {
        let n = points.count
        var labels = Array(repeating: -1, count: n) // -1 = unvisited/noise
        var visited = Array(repeating: false, count: n)
        var currentCluster = 0

        // Precompute distance matrix for efficiency with small datasets
        let distances = computeDistanceMatrix(points: points)

        for i in 0..<n {
            guard !visited[i] else { continue }
            visited[i] = true

            let neighbors = regionQuery(index: i, distances: distances)

            if neighbors.count < minPoints {
                // Mark as noise (stays -1)
                continue
            }

            // Start a new cluster
            labels[i] = currentCluster

            // Expand cluster — Set<Int> for O(1) membership checks (vs O(N) Array.contains)
            var seedSet = neighbors
            var seedMembership = Set(neighbors)
            var j = 0
            while j < seedSet.count {
                let q = seedSet[j]

                if !visited[q] {
                    visited[q] = true
                    let qNeighbors = regionQuery(index: q, distances: distances)
                    if qNeighbors.count >= minPoints {
                        for neighbor in qNeighbors {
                            if seedMembership.insert(neighbor).inserted {
                                seedSet.append(neighbor)
                            }
                        }
                    }
                }

                if labels[q] == -1 {
                    labels[q] = currentCluster
                }

                j += 1
            }

            currentCluster += 1
        }

        return labels
    }

    // MARK: - Adaptive Epsilon

    /// minPoints appropriate for a dataset of `n` entries.
    /// Formula: max(2, min(5, ⌊ln(n)⌋)) — the standard DBSCAN heuristic from the literature.
    /// Grows logarithmically: N=10→2, N=40→3, N=60→4, N=150→5.
    static func adaptiveMinPoints(for n: Int) -> Int {
        max(2, min(5, Int(log(Double(max(2, n))))))
    }

    /// Target cluster count range for `n` entries.
    /// Keeps the Clusters view useful: not too few (useless), not too many (overwhelming).
    static func targetClusterRange(for n: Int) -> ClosedRange<Int> {
        let lo = max(2, n / 12)
        let hi = max(lo + 1, n / 5)
        return lo...hi
    }

    /// Estimate a good epsilon using the k-distance heuristic (90th percentile of k-NN distances).
    /// Call this periodically — recalibrate every 10 new entries (see AIProcessingManager).
    static func estimateEpsilon(from points: [[Float]], minPoints: Int) -> Double {
        guard points.count > minPoints else { return 0.3 }
        let k = minPoints
        let normalized = preNormalize(points)

        var kDistances: [Double] = []
        for i in 0..<normalized.count {
            var dists: [Double] = []
            for j in 0..<normalized.count where j != i {
                dists.append(cosineDistanceAccelerate(normalized[i], normalized[j]))
            }
            dists.sort()
            if k - 1 < dists.count { kDistances.append(dists[k - 1]) }
        }

        kDistances.sort()
        let idx = Int(Double(kDistances.count) * 0.9)
        return kDistances[min(idx, kDistances.count - 1)]
    }

    /// Binary-search epsilon to land cluster count inside `targetRange`.
    /// Starts from the k-distance estimate and brackets with up to `maxIterations` DBSCAN runs.
    /// Falls back to the k-distance estimate if the target is unreachable.
    static func calibrateEpsilon(
        from points: [[Float]],
        minPoints: Int,
        targetRange: ClosedRange<Int>,
        maxIterations: Int = 8
    ) -> Double {
        let baseEpsilon = estimateEpsilon(from: points, minPoints: minPoints)
        guard points.count >= minPoints else { return baseEpsilon }

        let baseCount = clusterCount(points: points, epsilon: baseEpsilon, minPoints: minPoints)
        if targetRange.contains(baseCount) { return baseEpsilon }

        // Determine search direction:
        // Too few clusters (or 1 giant cluster) → decrease epsilon to split things apart.
        // Too many clusters (or all noise) → increase epsilon to merge neighbors.
        var lo: Double = 0.05
        var hi: Double = 0.95
        var bestEpsilon = baseEpsilon

        for _ in 0..<maxIterations {
            let mid = (lo + hi) / 2
            let count = clusterCount(points: points, epsilon: mid, minPoints: minPoints)
            if targetRange.contains(count) {
                return mid
            }
            if count == 0 {
                // All noise — epsilon too small, no core points form
                lo = mid
            } else if count < targetRange.lowerBound {
                // Too few clusters (1 giant cluster) — epsilon too large, tighten it
                hi = mid
            } else {
                // Too many clusters — epsilon too small, loosen it
                lo = mid
            }
            bestEpsilon = mid
        }
        return bestEpsilon
    }

    /// Run DBSCAN and return the number of non-noise clusters.
    private static func clusterCount(points: [[Float]], epsilon: Double, minPoints: Int) -> Int {
        let tmp = DBSCANClusterer(epsilon: epsilon, minPoints: minPoints)
        let labels = tmp.dbscan(points: points)
        return Set(labels.filter { $0 >= 0 }).count
    }

    /// Silhouette score for evaluating cluster quality (range −1…1; higher is better).
    static func silhouetteScore(labels: [Int], points: [[Float]]) -> Double {
        let n = points.count
        guard n > 1 else { return 0 }
        let normalized = preNormalize(points)
        var scores: [Double] = []

        for i in 0..<n {
            let ci = labels[i]
            guard ci != -1 else { continue }

            let sameCluster   = (0..<n).filter { labels[$0] == ci && $0 != i }
            let otherClusters = Set(labels.filter { $0 != -1 && $0 != ci })

            guard !sameCluster.isEmpty, !otherClusters.isEmpty else { continue }

            let a = sameCluster.map { cosineDistanceAccelerate(normalized[i], normalized[$0]) }
                                .reduce(0, +) / Double(sameCluster.count)

            let b = otherClusters.map { otherID -> Double in
                let members = (0..<n).filter { labels[$0] == otherID }
                return members.map { cosineDistanceAccelerate(normalized[i], normalized[$0]) }
                              .reduce(0, +) / Double(members.count)
            }.min() ?? 0

            let s = max(a, b) > 0 ? (b - a) / max(a, b) : 0
            scores.append(s)
        }

        return scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
    }

    // MARK: - Distance Computations (Accelerate-optimised)

    private func regionQuery(index: Int, distances: [[Double]]) -> [Int] {
        let row = distances[index]
        var neighbors: [Int] = []
        for j in 0..<row.count where j != index && row[j] <= effectiveEpsilon {
            neighbors.append(j)
        }
        return neighbors
    }

    /// Pre-normalise all vectors once with vDSP — avoids re-computing norms per pair.
    private static func preNormalize(_ points: [[Float]]) -> [[Float]] {
        return points.map { v in
            var normSq: Float = 0
            vDSP_svesq(v, 1, &normSq, vDSP_Length(v.count))
            let norm = sqrt(normSq)
            guard norm > 0 else { return v }
            var result = v
            var scalar = 1.0 / norm
            vDSP_vsmul(v, 1, &scalar, &result, 1, vDSP_Length(v.count))
            return result
        }
    }

    /// Cosine distance using vDSP dot product on pre-normalised vectors (O(D) per pair).
    private static func cosineDistanceAccelerate(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 2.0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return Double(max(0, 1.0 - dot))
    }

    private func computeDistanceMatrix(points: [[Float]]) -> [[Double]] {
        let n = points.count
        let normalized = DBSCANClusterer.preNormalize(points)
        var matrix = Array(repeating: Array(repeating: 0.0, count: n), count: n)

        for i in 0..<n {
            for j in (i + 1)..<n {
                let d = DBSCANClusterer.cosineDistanceAccelerate(normalized[i], normalized[j])
                matrix[i][j] = d
                matrix[j][i] = d
            }
        }
        return matrix
    }

    private func cosineDistance(_ a: [Float], _ b: [Float]) -> Double {
        DBSCANClusterer.cosineDistanceAccelerate(a, b)
    }
}
