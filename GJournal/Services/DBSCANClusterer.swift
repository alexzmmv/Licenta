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

// MARK: - Calibration Diagnostics

/// Diagnostic information returned from epsilon calibration.
struct CalibrationResult: CustomStringConvertible {
    let epsilon: Double
    let minPoints: Int
    let clusterCount: Int
    let noiseCount: Int
    let totalPoints: Int
    let silhouetteScore: Double

    var noiseFraction: Double {
        totalPoints > 0 ? Double(noiseCount) / Double(totalPoints) : 0
    }

    var description: String {
        let nf = String(format: "%.1f%%", noiseFraction * 100)
        let sil = String(format: "%.4f", silhouetteScore)
        let eps = String(format: "%.4f", epsilon)
        return "ε=\(eps) minPts=\(minPoints) → \(clusterCount) clusters, \(noiseCount)/\(totalPoints) noise (\(nf)), silhouette=\(sil)"
    }
}

final class DBSCANClusterer: ClusteringServiceProtocol, Sendable {

    let epsilon: Double
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

    // MARK: - Parameter Calibration (Grid-Search with Silhouette Validation)

    /// Adaptive minPts for a dataset of `n` entries.
    ///
    /// Uses `ceil(1.5 * ln(N))`, clamped to [3, max(3, N/5)].
    /// This provides denser neighborhood requirements than the old `floor(ln(N))`
    /// formula, preventing DBSCAN from chain-linking distant entries through
    /// sparse transitivity bridges.
    ///
    /// N=10→4, N=20→5, N=40→6, N=100→7, N=200→8, N=1000→11.
    static func adaptiveMinPoints(for n: Int) -> Int {
        let raw = Int(ceil(1.5 * log(Double(max(3, n)))))
        return max(3, min(raw, max(3, n / 5)))
    }

    /// Sorted k-distance array (k = minPoints).
    /// Each element is the cosine distance from point i to its k-th nearest neighbour.
    /// Building this array is the only O(N²) step; it is reused by calibration.
    nonisolated static func buildSortedKDistances(normalized: [[Float]], minPoints: Int) -> [Double] {
        let n = normalized.count
        let k = minPoints
        var kDistances: [Double] = []
        kDistances.reserveCapacity(n)
        for i in 0..<n {
            var dists: [Double] = []
            dists.reserveCapacity(n - 1)
            for j in 0..<n where j != i {
                dists.append(cosineDistanceAccelerate(normalized[i], normalized[j]))
            }
            dists.sort()
            if k - 1 < dists.count { kDistances.append(dists[k - 1]) }
        }
        kDistances.sort()
        return kDistances
    }

    /// Kneedle algorithm: O(N) pass over sorted k-distances to find the point of maximum
    /// curvature — used as initial estimate, then validated by grid search.
    nonisolated static func kneedleEpsilon(from sortedKDistances: [Double]) -> Double {
        guard sortedKDistances.count >= 2,
              let yMin = sortedKDistances.first,
              let yMax = sortedKDistances.last,
              yMax > yMin else {
            return sortedKDistances.last ?? 0.3
        }
        let n = sortedKDistances.count
        var maxDiff = -Double.infinity
        var bestIndex = 0
        for i in 0..<n {
            let xNorm = Double(i) / Double(n - 1)
            let yNorm = (sortedKDistances[i] - yMin) / (yMax - yMin)
            let diff  = yNorm - xNorm
            if diff > maxDiff { maxDiff = diff; bestIndex = i }
        }
        return sortedKDistances[bestIndex]
    }

    /// Full calibration pipeline with silhouette-validated grid search:
    ///
    ///  1. Pre-normalise embeddings.
    ///  2. Build sorted k-distance array (O(N²)).
    ///  3. Compute full pairwise distance matrix (reused for all DBSCAN probes).
    ///  4. Generate candidate ε values from percentiles of k-distances.
    ///  5. Run DBSCAN for each candidate, score by silhouette quality.
    ///  6. Select the ε that maximises a weighted objective:
    ///     - 70% silhouette score (cluster cohesion & separation)
    ///     - 20% coverage (penalise excessive noise)
    ///     - 10% cluster diversity (bonus for >2 clusters, up to 5)
    ///  7. Reject single-cluster and extreme-noise (>50%) solutions.
    ///
    /// Falls back to Kneedle ε if no multi-cluster solution exists.
    nonisolated static func calibrateEpsilon(from points: [[Float]], minPoints: Int) -> CalibrationResult {
        guard points.count >= minPoints else {
            return CalibrationResult(epsilon: 0.3, minPoints: minPoints, clusterCount: 0, noiseCount: points.count, totalPoints: points.count, silhouetteScore: 0)
        }
        let normalized = preNormalize(points)
        let n = normalized.count
        let sortedKDist = buildSortedKDistances(normalized: normalized, minPoints: minPoints)
        guard !sortedKDist.isEmpty else {
            return CalibrationResult(epsilon: 0.3, minPoints: minPoints, clusterCount: 0, noiseCount: n, totalPoints: n, silhouetteScore: 0)
        }

        // Build full distance matrix once — shared across all DBSCAN probes
        let distMatrix = buildDistanceMatrixFromNormalized(normalized)

        // Generate candidate ε values from k-distance percentiles
        var candidates: Set<Double> = []
        for pct in stride(from: 5, through: 95, by: 2) {
            let idx = min(Int(Double(sortedKDist.count) * Double(pct) / 100.0), sortedKDist.count - 1)
            candidates.insert(sortedKDist[idx])
        }

        // Also add candidates from overall pairwise distance distribution
        var allPairDists: [Double] = []
        allPairDists.reserveCapacity(n * (n - 1) / 2)
        for i in 0..<n {
            for j in (i + 1)..<n {
                allPairDists.append(distMatrix[i][j])
            }
        }
        allPairDists.sort()
        for pct in stride(from: 10, through: 90, by: 5) {
            let idx = min(Int(Double(allPairDists.count) * Double(pct) / 100.0), allPairDists.count - 1)
            candidates.insert(allPairDists[idx])
        }

        var bestScore = -Double.infinity
        var bestResult = CalibrationResult(
            epsilon: kneedleEpsilon(from: sortedKDist),
            minPoints: minPoints,
            clusterCount: 1,
            noiseCount: 0,
            totalPoints: n,
            silhouetteScore: 0
        )

        for eps in candidates.sorted() {
            let labels = dbscanWithMatrix(distMatrix: distMatrix, epsilon: eps, minPoints: minPoints)
            let nClusters = Set(labels.filter { $0 != -1 }).count
            let noiseCount = labels.filter { $0 == -1 }.count
            let noiseFrac = Double(noiseCount) / Double(n)

            // Reject single-cluster solutions
            if nClusters < 2 { continue }
            if noiseFrac > 0.60 { continue }

            let sil = silhouetteScoreFromMatrix(labels: labels, distMatrix: distMatrix)

            // Weighted objective — coverage is critical for introspection:
            // noise entries are invisible to the user (missed pattern connections).
            //  - 45% silhouette: cluster cohesion & separation quality
            //  - 35% coverage: heavily penalise noise (orphan entries miss insights)
            //  - 20% diversity: bonus for more clusters (richer introspection)
            let score = sil * 0.45
                + (1.0 - noiseFrac) * 0.35
                + min(Double(nClusters) / 5.0, 1.0) * 0.20

            if score > bestScore {
                bestScore = score
                bestResult = CalibrationResult(
                    epsilon: eps,
                    minPoints: minPoints,
                    clusterCount: nClusters,
                    noiseCount: noiseCount,
                    totalPoints: n,
                    silhouetteScore: sil
                )
            }
        }

        return bestResult
    }

    /// MRL-aware calibration: also searches across multiple minPoints values
    /// to compensate for the compressed distance space of MRL-truncated embeddings.
    ///
    /// MRL truncation (e.g., 768→256 dims) compresses cosine distances into a
    /// narrower range, making the single-minPts Kneedle approach unreliable.
    /// This variant probes minPts ∈ {max(3,base-2) … base+2} to find the
    /// configuration that best separates semantic themes.
    nonisolated static func calibrateEpsilonMRL(from points: [[Float]], baseMimPoints: Int) -> CalibrationResult {
        let minPtsLow  = max(3, baseMimPoints - 2)
        let minPtsHigh = baseMimPoints + 2

        var bestResult = CalibrationResult(
            epsilon: 0.3, minPoints: baseMimPoints,
            clusterCount: 0, noiseCount: points.count,
            totalPoints: points.count, silhouetteScore: 0
        )
        var bestScore = -Double.infinity

        for mp in minPtsLow...minPtsHigh {
            let result = calibrateEpsilon(from: points, minPoints: mp)
            // Use the same weighted score
            let noiseFrac = result.noiseFraction
            let score = result.silhouetteScore * 0.45
                + (1.0 - noiseFrac) * 0.35
                + min(Double(result.clusterCount) / 5.0, 1.0) * 0.20
            if score > bestScore && result.clusterCount >= 2 {
                bestScore = score
                bestResult = result
            }
        }

        return bestResult
    }

    /// Silhouette score for evaluating cluster quality (range −1…1; higher is better).
    static func silhouetteScore(labels: [Int], points: [[Float]]) -> Double {
        let n = points.count
        guard n > 1 else { return 0 }
        let normalized = preNormalize(points)
        let distMatrix = buildDistanceMatrixFromNormalized(normalized)
        return silhouetteScoreFromMatrix(labels: labels, distMatrix: distMatrix)
    }

    // MARK: - Internal Helpers for Grid Search

    /// DBSCAN variant that operates on a pre-computed distance matrix.
    private nonisolated static func dbscanWithMatrix(distMatrix: [[Double]], epsilon: Double, minPoints: Int) -> [Int] {
        let n = distMatrix.count
        var labels = Array(repeating: -1, count: n)
        var visited = Array(repeating: false, count: n)
        var currentCluster = 0

        for i in 0..<n {
            guard !visited[i] else { continue }
            visited[i] = true

            let neighbors = regionQueryStatic(index: i, distances: distMatrix, epsilon: epsilon)
            if neighbors.count < minPoints { continue }

            labels[i] = currentCluster

            var seedSet = neighbors
            var seedMembership = Set(neighbors)
            var j = 0
            while j < seedSet.count {
                let q = seedSet[j]
                if !visited[q] {
                    visited[q] = true
                    let qNeighbors = regionQueryStatic(index: q, distances: distMatrix, epsilon: epsilon)
                    if qNeighbors.count >= minPoints {
                        for neighbor in qNeighbors {
                            if seedMembership.insert(neighbor).inserted {
                                seedSet.append(neighbor)
                            }
                        }
                    }
                }
                if labels[q] == -1 { labels[q] = currentCluster }
                j += 1
            }
            currentCluster += 1
        }
        return labels
    }

    /// Static region query for use in calibration (non-instance context).
    private nonisolated static func regionQueryStatic(index: Int, distances: [[Double]], epsilon: Double) -> [Int] {
        let row = distances[index]
        var neighbors: [Int] = []
        for j in 0..<row.count where j != index && row[j] <= epsilon {
            neighbors.append(j)
        }
        return neighbors
    }

    /// Silhouette score from pre-computed distance matrix.
    private nonisolated static func silhouetteScoreFromMatrix(labels: [Int], distMatrix: [[Double]]) -> Double {
        let n = labels.count
        guard n > 1 else { return 0 }
        var scores: [Double] = []

        for i in 0..<n {
            let ci = labels[i]
            guard ci != -1 else { continue }

            let sameCluster   = (0..<n).filter { labels[$0] == ci && $0 != i }
            let otherClusters = Set(labels.filter { $0 != -1 && $0 != ci })

            guard !sameCluster.isEmpty, !otherClusters.isEmpty else { continue }

            let a = sameCluster.map { distMatrix[i][$0] }
                                .reduce(0, +) / Double(sameCluster.count)

            let b = otherClusters.map { otherID -> Double in
                let members = (0..<n).filter { labels[$0] == otherID }
                return members.map { distMatrix[i][$0] }
                              .reduce(0, +) / Double(members.count)
            }.min() ?? 0

            let s = max(a, b) > 0 ? (b - a) / max(a, b) : 0
            scores.append(s)
        }

        return scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
    }

    /// Build distance matrix from already-normalised vectors.
    private nonisolated static func buildDistanceMatrixFromNormalized(_ normalized: [[Float]]) -> [[Double]] {
        let n = normalized.count
        var matrix = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let d = cosineDistanceAccelerate(normalized[i], normalized[j])
                matrix[i][j] = d
                matrix[j][i] = d
            }
        }
        return matrix
    }

    // MARK: - Distance Computations (Accelerate-optimised)

    private func regionQuery(index: Int, distances: [[Double]]) -> [Int] {
        let row = distances[index]
        var neighbors: [Int] = []
        for j in 0..<row.count where j != index && row[j] <= epsilon {
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
        let normalized = DBSCANClusterer.preNormalize(points)
        return DBSCANClusterer.buildDistanceMatrixFromNormalized(normalized)
    }

    private func cosineDistance(_ a: [Float], _ b: [Float]) -> Double {
        DBSCANClusterer.cosineDistanceAccelerate(a, b)
    }
}
