import Foundation
import Accelerate

// MARK: - Calibration Diagnostics

struct CalibrationResult: CustomStringConvertible {
    let epsilon: Double
    let minPoints: Int
    let clusterCount: Int
    let noiseCount: Int
    let totalPoints: Int
    let silhouetteScore: Double

    nonisolated var noiseFraction: Double {
        totalPoints > 0 ? Double(noiseCount) / Double(totalPoints) : 0
    }

    nonisolated var description: String {
        let nf = String(format: "%.1f%%", noiseFraction * 100)
        let sil = String(format: "%.4f", silhouetteScore)
        let eps = String(format: "%.4f", epsilon)
        return "ε=\(eps) minPts=\(minPoints) → \(clusterCount) clusters, \(noiseCount)/\(totalPoints) noise (\(nf)), silhouette=\(sil)"
    }
}

final class DBSCANClusterer: ClusteringServiceProtocol, Sendable {

    let epsilon: Double
    let minPoints: Int

    nonisolated init(epsilon: Double = 0.3, minPoints: Int = 3) {
        self.epsilon = epsilon
        self.minPoints = minPoints
    }

    // MARK: - ClusteringServiceProtocol

    func clusterEntries(_ entries: [ClusterableEntry]) async throws -> [ClusterAssignment] {
        guard entries.count >= minPoints else {
            return entries.map { ClusterAssignment(bitID: $0.bitID, clusterID: -1) }
        }

        let embeddings = entries.map { $0.embedding }
        let labels = dbscan(points: embeddings)

        return zip(entries, labels).map { entry, label in
            ClusterAssignment(bitID: entry.bitID, clusterID: label)
        }
    }

    // MARK: - DBSCAN Core Algorithm

    func dbscan(points: [[Float]]) -> [Int] {
        let n = points.count
        var labels = Array(repeating: -1, count: n) // -1 = unvisited/noise
        var visited = Array(repeating: false, count: n)
        var currentCluster = 0

        let distances = computeDistanceMatrix(points: points)

        for i in 0..<n {
            guard !visited[i] else { continue }
            visited[i] = true

            let neighbors = regionQuery(index: i, distances: distances)

            if neighbors.count < minPoints {
                continue
            }

            labels[i] = currentCluster

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

    static func adaptiveMinPoints(for n: Int) -> Int {
        let raw = Int(ceil(1.5 * log(Double(max(3, n)))))
        return max(3, min(raw, max(3, n / 5)))
    }

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

        let distMatrix = buildDistanceMatrixFromNormalized(normalized)

        var candidates: Set<Double> = []
        for pct in stride(from: 5, through: 95, by: 2) {
            let idx = min(Int(Double(sortedKDist.count) * Double(pct) / 100.0), sortedKDist.count - 1)
            candidates.insert(sortedKDist[idx])
        }

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

            if nClusters < 2 { continue }
            if noiseFrac > 0.60 { continue }

            let sil = silhouetteScoreFromMatrix(labels: labels, distMatrix: distMatrix)

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

    static func silhouetteScore(labels: [Int], points: [[Float]]) -> Double {
        let n = points.count
        guard n > 1 else { return 0 }
        let normalized = preNormalize(points)
        let distMatrix = buildDistanceMatrixFromNormalized(normalized)
        return silhouetteScoreFromMatrix(labels: labels, distMatrix: distMatrix)
    }

    // MARK: - Internal Helpers for Grid Search

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

    private nonisolated static func regionQueryStatic(index: Int, distances: [[Double]], epsilon: Double) -> [Int] {
        let row = distances[index]
        var neighbors: [Int] = []
        for j in 0..<row.count where j != index && row[j] <= epsilon {
            neighbors.append(j)
        }
        return neighbors
    }

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

    private nonisolated static func preNormalize(_ points: [[Float]]) -> [[Float]] {
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

    private nonisolated static func cosineDistanceAccelerate(_ a: [Float], _ b: [Float]) -> Double {
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
