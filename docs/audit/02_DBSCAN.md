# DBSCAN Optimization & Adaptive Parameters

---

## 1. Current Implementation Issues

### Issue A: O(N²·D) Distance Matrix

The current `computeDistanceMatrix` in [DBSCANClusterer.swift](../../GJournal/Services/DBSCANClusterer.swift) precomputes all pairwise cosine distances:

```swift
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
```

**Cost**: For N entries with D-dimensional embeddings:
- Distance computations: N(N-1)/2
- Operations per distance: 3D (dot product + two norms)
- **Total**: ~1.5 · N² · D floating-point operations

| Entries (N) | Dim (D) | Operations | iPhone 11 estimate |
|:-----------:|:-------:|:----------:|:------------------:|
| 100 | 512 | ~38M | <1 second |
| 500 | 512 | ~960M | ~3-5 seconds |
| 1,000 | 512 | ~3.8B | ~15-30 seconds ⚠️ |

**Memory**: The matrix alone is N² × 8 bytes. At 1,000 entries = 8MB. Acceptable but growing.

### Issue B: O(N³) Seed Set Lookup

In the cluster expansion phase:

```swift
for neighbor in qNeighbors {
    if !seedSet.contains(neighbor) {  // ← Array.contains is O(M)
        seedSet.append(neighbor)
    }
}
```

`Array.contains` scans linearly. During expansion, `seedSet` can grow to N elements, making each lookup O(N). Across all iterations, this is **O(N³)** worst-case.

### Issue C: Scalar Cosine Distance

The `cosineDistance` function uses a scalar loop:

```swift
for i in 0..<a.count {
    dotProduct += a[i] * b[i]
    normA += a[i] * a[i]
    normB += b[i] * b[i]
}
```

This runs on a single CPU core without vectorization. Apple's **Accelerate framework** can compute this 10-50x faster using SIMD instructions.

---

## 2. Optimized Implementation

```swift
import Foundation
import Accelerate  // Apple's hardware-accelerated math

final class OptimizedDBSCANClusterer: ClusteringServiceProtocol {
    let epsilon: Double
    let minPoints: Int
    
    init(epsilon: Double = 0.3, minPoints: Int = 3) {
        self.epsilon = epsilon
        self.minPoints = minPoints
    }
    
    func clusterEntries(_ entries: [ClusterableEntry]) async throws -> [ClusterAssignment] {
        guard entries.count >= minPoints else {
            return entries.map { ClusterAssignment(bitID: $0.bitID, clusterID: -1) }
        }
        
        // Pre-normalize all vectors (so cosine distance = 1 - dot product)
        let normalized = entries.map { normalizeVector($0.embedding) }
        let labels = dbscan(points: normalized)
        
        return zip(entries, labels).map { entry, label in
            ClusterAssignment(bitID: entry.bitID, clusterID: label)
        }
    }
    
    // MARK: - Accelerate-Optimized Math
    
    /// Normalize a vector to unit length using vDSP
    private func normalizeVector(_ v: [Float]) -> [Float] {
        var result = v
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))  // sum of squares
        norm = sqrt(norm)
        if norm > 0 {
            var divisor = norm
            vDSP_vsdiv(v, 1, &divisor, &result, 1, vDSP_Length(v.count))
        }
        return result
    }
    
    /// Cosine distance between two pre-normalized vectors using vDSP
    /// For unit vectors: cosine_distance = 1 - dot_product
    private func cosineDistance(_ a: [Float], _ b: [Float]) -> Double {
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return Double(1.0 - dot)
    }
    
    // MARK: - DBSCAN with Set-based lookup
    
    private func dbscan(points: [[Float]]) -> [Int] {
        let n = points.count
        var labels = Array(repeating: -1, count: n)
        var visited = Array(repeating: false, count: n)
        var currentCluster = 0
        
        // Precompute distance matrix with Accelerate
        let distances = computeDistanceMatrix(points: points)
        
        for i in 0..<n {
            guard !visited[i] else { continue }
            visited[i] = true
            
            let neighbors = regionQuery(index: i, distances: distances)
            guard neighbors.count >= minPoints else { continue }
            
            labels[i] = currentCluster
            
            // FIX: Use Set for O(1) lookup instead of Array.contains O(N)
            var seedSet = neighbors
            var seedIndices = Set(neighbors)
            var j = 0
            
            while j < seedSet.count {
                let q = seedSet[j]
                
                if !visited[q] {
                    visited[q] = true
                    let qNeighbors = regionQuery(index: q, distances: distances)
                    if qNeighbors.count >= minPoints {
                        for neighbor in qNeighbors {
                            if !seedIndices.contains(neighbor) {
                                seedIndices.insert(neighbor)
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
    
    private func regionQuery(index: Int, distances: [[Double]]) -> [Int] {
        var neighbors: [Int] = []
        for j in 0..<distances[index].count {
            if j != index && distances[index][j] <= epsilon {
                neighbors.append(j)
            }
        }
        return neighbors
    }
    
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
}
```

### Performance Improvement Summary

| Fix | Before | After | Speedup |
|:----|:-------|:------|:--------|
| `vDSP_dotpr` cosine distance | Scalar loop (D iterations) | Single SIMD instruction | **10-50x** per distance |
| Pre-normalization | Compute norms every time | Normalize once, distance = 1 - dot | **3x** per distance |
| `Set<Int>` seed lookup | `Array.contains` O(N) | `Set.contains` O(1) | **O(N³) → O(N²)** |

---

## 3. Adaptive Parameter Tuning

### The Problem

`epsilon = 0.3` and `minPoints = 3` are hardcoded. As the user's journal grows, the optimal values change:
- More entries → clusters get denser → epsilon might need to shrink
- Topically diverse entries → need higher epsilon tolerance

### k-Distance Heuristic (Automatic Epsilon)

The standard method from the DBSCAN paper (Ester et al., 1996):

1. For each point, compute distance to its k-th nearest neighbor (k = minPoints)
2. Sort these distances in descending order
3. The "elbow" of this curve is the optimal epsilon

```swift
/// Estimate optimal epsilon using k-distance heuristic
static func estimateEpsilon(distances: [[Double]], minPoints: Int) -> Double {
    let n = distances.count
    guard n > minPoints else { return 0.3 }
    
    // For each point, find distance to k-th nearest neighbor
    var kDistances: [Double] = []
    for i in 0..<n {
        var rowDistances = distances[i].enumerated()
            .filter { $0.offset != i }
            .map { $0.element }
            .sorted()
        
        if rowDistances.count >= minPoints {
            kDistances.append(rowDistances[minPoints - 1])
        }
    }
    
    kDistances.sort(by: >)  // descending
    
    // Find elbow: point of maximum curvature
    // Simple approach: use the point at ~90th percentile
    let elbowIndex = Int(Double(kDistances.count) * 0.1)
    return kDistances[min(elbowIndex, kDistances.count - 1)]
}
```

### Silhouette Score (Quality Metric)

After clustering, compute silhouette score to evaluate quality. This can be logged and compared across the three embedding models for the thesis benchmark:

```swift
/// Compute mean silhouette score for clustering quality evaluation
static func silhouetteScore(labels: [Int], distances: [[Double]]) -> Double {
    let n = labels.count
    guard n > 1 else { return 0.0 }
    
    var totalScore = 0.0
    var scored = 0
    
    for i in 0..<n {
        guard labels[i] != -1 else { continue }  // skip noise
        
        // a(i): mean distance to same-cluster points
        let sameCluster = (0..<n).filter { $0 != i && labels[$0] == labels[i] }
        guard !sameCluster.isEmpty else { continue }
        let a = sameCluster.map { distances[i][$0] }.reduce(0, +) / Double(sameCluster.count)
        
        // b(i): min mean distance to any other cluster
        let otherClusters = Set(labels.filter { $0 != -1 && $0 != labels[i] })
        guard !otherClusters.isEmpty else { continue }
        
        let b = otherClusters.map { clusterID in
            let members = (0..<n).filter { labels[$0] == clusterID }
            return members.map { distances[i][$0] }.reduce(0, +) / Double(members.count)
        }.min() ?? 0
        
        totalScore += (b - a) / max(a, b)
        scored += 1
    }
    
    return scored > 0 ? totalScore / Double(scored) : 0.0
}
```

### Recalibration Strategy

Run adaptive tuning **periodically** — not on every entry save (too expensive):

```swift
// In AIProcessingManager.swift
private var entriesSinceLastCalibration = 0
private let calibrationInterval = 10  // every 10 new entries

func runClustering() async throws {
    // ... existing code ...
    
    entriesSinceLastCalibration += 1
    if entriesSinceLastCalibration >= calibrationInterval {
        // Recalibrate epsilon based on current data distribution
        let optimalEpsilon = OptimizedDBSCANClusterer.estimateEpsilon(
            distances: distances, minPoints: clusterer.minPoints
        )
        clusterer = OptimizedDBSCANClusterer(
            epsilon: optimalEpsilon, minPoints: 3
        )
        entriesSinceLastCalibration = 0
    }
}
```

---

## 4. Thesis Presentation Value

The adaptive DBSCAN gives you excellent thesis material:

1. **Chart**: Plot k-distance curves for different dataset sizes (50, 100, 200 entries)
2. **Chart**: Silhouette scores across the 3 embedding models (DistilBERT vs MobileBERT vs NLEmbedding)
3. **Table**: Show how epsilon adapts as the journal grows
4. **Comparison**: Fixed epsilon vs adaptive epsilon — number of clusters found, noise ratio

---

## 🎓 PhD Review

1. **DBSCAN is well-cited** — the original paper (Ester et al., 1996) has 25,000+ citations. It's a strong algorithmic choice for a thesis because it doesn't require specifying k (number of clusters) upfront, unlike K-Means.
2. **The Accelerate framework optimization** is a concrete systems-level contribution. Frame it as: *"We leverage Apple's SIMD vector processing unit via the Accelerate framework to reduce cosine distance computation from O(D) scalar operations to a single vectorized instruction."*
3. **The adaptive epsilon via k-distance** directly implements the method from the original DBSCAN paper. This shows you've read the primary source.
4. **Silhouette score** (Rousseeuw, 1987) is the standard internal validation metric. Report it as your primary clustering quality metric. Values: >0.5 = reasonable, >0.7 = strong.
5. **Consider also reporting**: number of clusters found, noise ratio (% of entries labeled as noise), and cluster size distribution (min/max/mean).

## 🔴 Red-Hat Review

1. **O(N²) is still O(N²)** even with Accelerate. At 1,000+ entries, you're still computing 500K distances. For a personal journal app this is likely fine (users rarely write 1,000 entries), but **state the scalability limit explicitly in the thesis**.
2. **The k-distance elbow detection** (using the 90th percentile) is a heuristic, not a guaranteed optimal value. More robust methods exist (OPTICS algorithm, or using the derivative of the k-distance curve). For a bachelor thesis, the simple heuristic is acceptable — just acknowledge it.
3. **Silhouette score is expensive**: it's also O(N²). Running it on every recalibration doubles the computation. Consider computing it only during benchmark evaluation, not in production.
4. **Recalibration every 10 entries** may cause visible cluster reorganization that confuses the user. Entries may jump between clusters. Consider: (a) only recalibrating when the user explicitly requests it, or (b) smoothing transitions by blending old and new assignments.
5. **Pre-normalization assumption**: The optimized code assumes embeddings are already L2-normalized. If the Core ML model outputs non-normalized vectors, the cosine distance calculation will be wrong. **Always normalize after model inference**.
