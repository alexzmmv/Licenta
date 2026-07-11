import Foundation
import Accelerate

/// HDBSCAN — Hierarchical DBSCAN with Excess-of-Mass cluster extraction.
///
/// Pipeline:
///   1. Cosine distance matrix (Accelerate)
///   2. Core distances (k-NN, k = minPts)
///   3. Mutual-reachability MST (Prim's, O(n²))
///   4. Single-linkage dendrogram (Union-Find)
///   5. Condense dendrogram → CondensedEdge list
///   6. EOM cluster extraction → flat integer labels
///
/// Distance metric: cosine on pre-normalised unit vectors.
/// Cluster IDs: 0, 1, 2, …; -1 = noise.
final class HDBSCANClusterer: ClusteringServiceProtocol, Sendable {

    let minPts: Int
    let minClusterSize: Int
    /// When false (sklearn default) the root cluster is never selected as a valid cluster.
    /// Set true (app default) so that a single dense group is still labelled rather than
    /// returned as all-noise.
    let allowSingleCluster: Bool

    nonisolated init(
        minPts: Int = 5,
        minClusterSize: Int = 5,
        allowSingleCluster: Bool = false
    ) {
        self.minPts = max(2, minPts)
        self.minClusterSize = max(2, minClusterSize)
        self.allowSingleCluster = allowSingleCluster
    }

    // MARK: - ClusteringServiceProtocol

    func clusterEntries(_ entries: [ClusterableEntry]) async throws -> [ClusterAssignment] {
        guard entries.count >= minPts else {
            return entries.map { ClusterAssignment(bitID: $0.bitID, clusterID: -1) }
        }
        let embeddings = entries.map { $0.embedding }
        let labels = hdbscan(points: embeddings)
        return zip(entries, labels).map { ClusterAssignment(bitID: $0.bitID, clusterID: $1) }
    }

    // MARK: - Public algorithm entry (accessible via @testable import)

    nonisolated func hdbscan(points: [[Float]]) -> [Int] {
        let n = points.count
        guard n >= 2 else { return Array(repeating: -1, count: n) }
        guard n >= minPts else { return Array(repeating: -1, count: n) }

        let normalized = preNormalize(points)
        let dist       = buildDistanceMatrix(normalized)
        let coreDists  = computeCoreDists(dist: dist)
        let mstEdges   = primMST(dist: dist, coreDists: coreDists)
        let (merges, nodeSize) = buildDendrogram(n: n, edges: mstEdges)
        let (condensed, rootCluster) = condenseTree(n: n, merges: merges, nodeSize: nodeSize)
        return extractClusters(n: n, condensed: condensed, rootCluster: rootCluster)
    }

    // MARK: - Step 1: Distance matrix (Accelerate-optimised)

    private nonisolated func buildDistanceMatrix(_ normalized: [[Float]]) -> [[Double]] {
        let n = normalized.count
        var matrix = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let d = cosineDistance(normalized[i], normalized[j])
                matrix[i][j] = d
                matrix[j][i] = d
            }
        }
        return matrix
    }

    // MARK: - Step 2: Core distances

    private nonisolated func computeCoreDists(dist: [[Double]]) -> [Double] {
        let n = dist.count
        let k = min(minPts, n - 1)   // k-th neighbour index (excluding self → row[k-1])
        return (0..<n).map { i in
            var row = dist[i]
            row[i] = Double.infinity  // exclude self
            row.sort()
            return row[k - 1]
        }
    }

    // MARK: - Step 3: Prim's MST on mutual-reachability distances

    private nonisolated func primMST(
        dist: [[Double]],
        coreDists: [Double]
    ) -> [(i: Int, j: Int, weight: Double)] {
        let n = dist.count
        var inMST = Array(repeating: false, count: n)
        var key    = Array(repeating: Double.infinity, count: n)
        var parent = Array(repeating: -1, count: n)
        key[0] = 0

        var edges: [(i: Int, j: Int, weight: Double)] = []
        edges.reserveCapacity(n - 1)

        for _ in 0..<n {
            // O(n) minimum — acceptable for n ≤ a few hundred entries
            var u = -1; var minKey = Double.infinity
            for v in 0..<n where !inMST[v] && key[v] < minKey {
                minKey = key[v]; u = v
            }
            guard u != -1 else { break }
            inMST[u] = true
            if parent[u] != -1 { edges.append((parent[u], u, key[u])) }
            for v in 0..<n where !inMST[v] {
                let mrd = max(coreDists[u], coreDists[v], dist[u][v])
                if mrd < key[v] { key[v] = mrd; parent[v] = u }
            }
        }
        return edges
    }

    // MARK: - Step 4: Single-linkage dendrogram

    private struct DendrogramMerge {
        let left: Int      // child node ID: 0..<n = leaf, >=n = internal
        let right: Int
        let distance: Double
        let size: Int      // total leaf count
    }

    /// Builds the single-linkage dendrogram from n-1 sorted MST edges.
    /// Internal node (n + i) corresponds to merges[i]; root = 2n − 2.
    /// Returns (merges, nodeSize) where nodeSize[id] = leaf count for node id.
    private nonisolated func buildDendrogram(
        n: Int,
        edges: [(i: Int, j: Int, weight: Double)]
    ) -> (merges: [DendrogramMerge], nodeSize: [Int]) {
        let sorted = edges.sorted { $0.weight < $1.weight }
        var ufParent = Array(0..<n)
        var ufRank   = Array(repeating: 0, count: n)
        var ufSz     = Array(repeating: 1, count: n)
        // compNode[uf_root] = dendrogram node ID of this component
        var compNode = Array(0..<n)
        var nextID   = n
        var merges   = [DendrogramMerge]()
        merges.reserveCapacity(n - 1)
        // nodeSize[id] for id >= n stored at index id - n in a parallel array
        var internalSize = [Int]()
        internalSize.reserveCapacity(n - 1)

        // Path-compressed find
        func find(_ x: Int) -> Int {
            var x = x
            while ufParent[x] != x { ufParent[x] = ufParent[ufParent[x]]; x = ufParent[x] }
            return x
        }

        // Size of a component node (leaf = 1, internal = stored)
        func nodeSize(_ id: Int) -> Int {
            id < n ? 1 : internalSize[id - n]
        }

        for edge in sorted {
            let ra = find(edge.i); let rb = find(edge.j)
            guard ra != rb else { continue }
            let idA = compNode[ra]; let idB = compNode[rb]
            let sza = nodeSize(idA); let szb = nodeSize(idB)
            let newID = nextID; nextID += 1
            merges.append(DendrogramMerge(left: idA, right: idB, distance: edge.weight, size: sza + szb))
            internalSize.append(sza + szb)
            // Union by rank
            if ufRank[ra] < ufRank[rb] {
                ufParent[ra] = rb; ufSz[rb] += ufSz[ra]; compNode[rb] = newID
            } else if ufRank[ra] > ufRank[rb] {
                ufParent[rb] = ra; ufSz[ra] += ufSz[rb]; compNode[ra] = newID
            } else {
                ufParent[rb] = ra; ufSz[ra] += ufSz[rb]; ufRank[ra] += 1; compNode[ra] = newID
            }
        }

        // Build flat nodeSize array: leaves 0..<n → size 1, internals n.. → internalSize[id-n]
        var nodeSize = Array(repeating: 1, count: n + merges.count)
        for i in 0..<merges.count { nodeSize[n + i] = internalSize[i] }
        return (merges, nodeSize)
    }

    // MARK: - Step 5: Condense the dendrogram

    struct CondensedEdge {
        let parent: Int    // cluster ID (≥ n)
        let child: Int     // cluster node (≥ n) or leaf index (< n)
        let lambda: Double // 1 / distance at which child splits from parent
        let size: Int      // 1 for leaf, >1 for cluster
    }

    /// Top-down traversal of the dendrogram: real splits become sub-cluster nodes;
    /// components smaller than minClusterSize "fall out" as leaf events.
    private nonisolated func condenseTree(
        n: Int,
        merges: [DendrogramMerge],
        nodeSize: [Int]
    ) -> (edges: [CondensedEdge], rootCluster: Int) {
        guard !merges.isEmpty else {
            return ([], n)
        }
        let rootDendrogramNode = n + merges.count - 1  // 2n − 2
        let rootCluster = rootDendrogramNode            // cluster ID = dendrogram root

        var result = [CondensedEdge]()
        var nextClusterID = 2 * n  // sub-cluster IDs start here

        // Stack: (dendrogram node, owning cluster ID, cluster birth lambda)
        var stack: [(node: Int, clusterID: Int, birthLambda: Double)] =
            [(rootDendrogramNode, rootCluster, 0.0)]

        while let (node, clusterID, _) = stack.popLast() {
            guard node >= n else { continue }  // leaf — nothing to expand
            let merge  = merges[node - n]
            let weight = merge.distance
            let lambda = weight > 0 ? 1.0 / weight : Double.greatestFiniteMagnitude
            let left   = merge.left;  let leftSz  = nodeSize[left]
            let right  = merge.right; let rightSz = nodeSize[right]
            let leftOK  = leftSz  >= minClusterSize
            let rightOK = rightSz >= minClusterSize

            if leftOK && rightOK {
                // Real split → two new sub-clusters
                let lc = nextClusterID; nextClusterID += 1
                let rc = nextClusterID; nextClusterID += 1
                result.append(CondensedEdge(parent: clusterID, child: lc, lambda: lambda, size: leftSz))
                result.append(CondensedEdge(parent: clusterID, child: rc, lambda: lambda, size: rightSz))
                stack.append((left,  lc, lambda))
                stack.append((right, rc, lambda))

            } else if leftOK {
                // Right side falls out as noise leaves; left continues as same cluster
                addLeaves(node: right, parentCluster: clusterID, lambda: lambda,
                          n: n, merges: merges, result: &result)
                stack.append((left, clusterID, 0))   // birthLambda unchanged

            } else if rightOK {
                // Left side falls out; right continues
                addLeaves(node: left, parentCluster: clusterID, lambda: lambda,
                          n: n, merges: merges, result: &result)
                stack.append((right, clusterID, 0))

            } else {
                // Both too small — all points fall out at this lambda
                addLeaves(node: left,  parentCluster: clusterID, lambda: lambda,
                          n: n, merges: merges, result: &result)
                addLeaves(node: right, parentCluster: clusterID, lambda: lambda,
                          n: n, merges: merges, result: &result)
            }
        }
        return (result, rootCluster)
    }

    /// Iteratively collects all leaf indices under `node` and emits them as fall-out edges.
    private nonisolated func addLeaves(
        node: Int, parentCluster: Int, lambda: Double,
        n: Int, merges: [DendrogramMerge],
        result: inout [CondensedEdge]
    ) {
        var stack = [node]
        while let cur = stack.popLast() {
            if cur < n {
                result.append(CondensedEdge(parent: parentCluster, child: cur,
                                            lambda: lambda, size: 1))
            } else {
                let m = merges[cur - n]
                stack.append(m.left)
                stack.append(m.right)
            }
        }
    }

    // MARK: - Step 6: Excess-of-Mass cluster extraction

    private nonisolated func extractClusters(
        n: Int,
        condensed: [CondensedEdge],
        rootCluster: Int
    ) -> [Int] {
        guard !condensed.isEmpty else { return Array(repeating: -1, count: n) }

        // ── Collect cluster nodes (appear as parent or as non-leaf child) ──────────
        var clusterNodes = Set<Int>()
        for e in condensed {
            clusterNodes.insert(e.parent)
            if e.child >= n { clusterNodes.insert(e.child) }
        }

        // ── Birth lambdas ─────────────────────────────────────────────────────────
        var birthLambda = [Int: Double]()
        birthLambda[rootCluster] = 0.0
        for e in condensed where e.child >= n {
            birthLambda[e.child] = e.lambda
        }

        // ── Stability ─────────────────────────────────────────────────────────────
        // stability(C) = Σ_{leaves p falling out of C} (λ_fallout − λ_birth(C))
        //              + Σ_{sub-cluster C'} size(C') × (λ_split − λ_birth(C))
        var stability = [Int: Double]()
        for c in clusterNodes {
            let birth = birthLambda[c] ?? 0.0
            var s = 0.0
            for e in condensed where e.parent == c {
                s += Double(e.size) * (e.lambda - birth)
            }
            stability[c] = s
        }

        // ── Build cluster-children adjacency ─────────────────────────────────────
        var clusterChildren = [Int: [Int]]()
        for e in condensed where e.child >= n {
            clusterChildren[e.parent, default: []].append(e.child)
        }

        // ── Iterative post-order (leaves first, root last) ────────────────────────
        var topoOrder = [Int]()
        topoOrder.reserveCapacity(clusterNodes.count)
        var dfsStack: [(node: Int, processed: Bool)] = [(rootCluster, false)]
        while let (node, processed) = dfsStack.popLast() {
            if processed {
                topoOrder.append(node)
            } else {
                dfsStack.append((node, true))
                for child in clusterChildren[node] ?? [] {
                    dfsStack.append((child, false))
                }
            }
        }

        // ── EOM selection ─────────────────────────────────────────────────────────
        var selected = Set<Int>()
        var propagated = stability  // will be updated bottom-up

        for c in topoOrder {
            // Optionally exclude root (sklearn allow_single_cluster=False behaviour)
            let isRoot = (c == rootCluster)
            if isRoot && !allowSingleCluster { continue }

            let children = clusterChildren[c] ?? []
            let childrenStab = children.reduce(0.0) { $0 + (propagated[$1] ?? 0) }
            let ownStab = stability[c] ?? 0.0

            if ownStab >= childrenStab {
                selected.insert(c)
                for child in children { selected.remove(child) }
                propagated[c] = ownStab
            } else {
                propagated[c] = childrenStab
                // Children already in `selected` if they were chosen
            }
        }

        // ── Assign leaf points to clusters ────────────────────────────────────────
        // For each leaf, walk up through cluster parents until we hit a selected cluster.
        var childToParent = [Int: Int]()
        for e in condensed where e.child >= n {
            childToParent[e.child] = e.parent
        }
        var leafDirectParent = [Int: Int]()  // leaf index → immediate cluster parent
        for e in condensed where e.child < n {
            leafDirectParent[e.child] = e.parent
        }

        var leafLabel = Array(repeating: -1, count: n)
        for leaf in 0..<n {
            guard var cur = leafDirectParent[leaf] else { continue }
            while !selected.contains(cur) {
                guard let p = childToParent[cur] else { cur = -1; break }
                cur = p
            }
            leafLabel[leaf] = (cur == -1 || !selected.contains(cur)) ? -1 : cur
        }

        // ── Normalise cluster IDs to 0, 1, 2, … ─────────────────────────────────
        var labelMap = [Int: Int]()
        var nextLabel = 0
        var result = Array(repeating: -1, count: n)
        for i in 0..<n {
            let cid = leafLabel[i]
            guard cid != -1 else { continue }
            if labelMap[cid] == nil { labelMap[cid] = nextLabel; nextLabel += 1 }
            result[i] = labelMap[cid]!
        }
        return result
    }

    // MARK: - Distance / normalisation helpers

    private nonisolated func preNormalize(_ points: [[Float]]) -> [[Float]] {
        points.map { v in
            var normSq: Float = 0
            vDSP_svesq(v, 1, &normSq, vDSP_Length(v.count))
            let norm = sqrt(normSq)
            guard norm > 1e-6 else { return v }
            var result = v
            var scalar: Float = 1.0 / norm
            vDSP_vsmul(v, 1, &scalar, &result, 1, vDSP_Length(v.count))
            return result
        }
    }

    private nonisolated func cosineDistance(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 2.0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return Double(max(0, 1.0 - dot))
    }

    // MARK: - Adaptive parameter selection

    nonisolated static func adaptiveMinPts(for n: Int) -> Int {
        let raw = Int(ceil(1.5 * log(Double(max(3, n)))))
        return max(3, min(raw, max(3, n / 5)))
    }
}
