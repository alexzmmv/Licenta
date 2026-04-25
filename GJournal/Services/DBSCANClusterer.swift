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

/// DBSCAN clustering algorithm for grouping journal entries by semantic similarity.
///
/// Parameters:
/// - `epsilon`: Maximum distance threshold for two points to be neighbors (0.0–2.0 for cosine distance)
/// - `minPoints`: Minimum number of points required to form a dense region (cluster)
///
/// The algorithm:
/// 1. For each unvisited point, find its neighbors within epsilon distance
/// 2. If neighbors >= minPoints, start a new cluster and expand it
/// 3. Points not reachable from any cluster are marked as noise (clusterID = -1)
final class DBSCANClusterer: ClusteringServiceProtocol {

    /// Maximum cosine distance for two points to be considered neighbors.
    /// Lower values = tighter clusters. Default 0.3 works well for normalized embeddings.
    let epsilon: Double

    /// Minimum number of points to form a cluster.
    /// Default 3 per documentation §3.9.
    let minPoints: Int

    init(epsilon: Double = 0.3, minPoints: Int = 3) {
        self.epsilon = epsilon
        self.minPoints = minPoints
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
    private func dbscan(points: [[Float]]) -> [Int] {
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

            // Expand cluster
            var seedSet = neighbors
            var j = 0
            while j < seedSet.count {
                let q = seedSet[j]

                if !visited[q] {
                    visited[q] = true
                    let qNeighbors = regionQuery(index: q, distances: distances)
                    if qNeighbors.count >= minPoints {
                        // Add new neighbors to seed set (union)
                        for neighbor in qNeighbors {
                            if !seedSet.contains(neighbor) {
                                seedSet.append(neighbor)
                            }
                        }
                    }
                }

                if labels[q] == -1 {
                    // Was noise or unvisited, assign to current cluster
                    labels[q] = currentCluster
                }

                j += 1
            }

            currentCluster += 1
        }

        return labels
    }

    // MARK: - Distance Computations

    /// Find all points within epsilon distance of the given point.
    private func regionQuery(index: Int, distances: [[Double]]) -> [Int] {
        var neighbors: [Int] = []
        for j in 0..<distances[index].count {
            if j != index && distances[index][j] <= epsilon {
                neighbors.append(j)
            }
        }
        return neighbors
    }

    /// Compute pairwise cosine distance matrix.
    /// Cosine distance = 1 - cosine_similarity
    private func computeDistanceMatrix(points: [[Float]]) -> [[Double]] {
        let n = points.count
        var matrix = Array(repeating: Array(repeating: 0.0, count: n), count: n)

        for i in 0..<n {
            for j in (i + 1)..<n {
                let dist = cosineDistance(points[i], points[j])
                matrix[i][j] = dist
                matrix[j][i] = dist
            }
        }

        return matrix
    }

    /// Cosine distance between two vectors: 1 - cosine_similarity
    /// Returns 0.0 for identical vectors, 2.0 for opposite vectors.
    private func cosineDistance(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 2.0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 2.0 }

        let similarity = Double(dotProduct / denominator)
        return 1.0 - similarity
    }
}
