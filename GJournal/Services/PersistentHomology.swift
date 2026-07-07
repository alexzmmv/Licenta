import Foundation

// MARK: - Output

/// A single bar of a persistence diagram. `death == .infinity` marks an essential
/// (never-dying) class — e.g. the final connected component, or a loop that is never
/// filled within `maxEpsilon`.
struct PersistenceBar: Equatable, Sendable {
    let dimension: Int    // 0 = connected component (β0), 1 = loop (β1)
    let birth: Double
    let death: Double     // .infinity for essential classes

    var persistence: Double { death - birth }
    var isFinite: Bool { death.isFinite }
}

// MARK: - Exact Vietoris–Rips Persistent Homology

/// Exact β0/β1 Vietoris–Rips persistent homology over Z/2, computed by standard
/// boundary-matrix reduction. Designed for small windows (≤ ~60 points): at n = 60 the
/// complex has ~1,770 edges and ~34k triangles, tractable on-device.
///
/// The whole diagram (H0 + H1) is produced by one reduction of the boundary matrix on
/// vertices/edges/triangles. Ordering simplices by (filtration, dimension) guarantees every
/// face precedes its cofaces, so the resulting diagram is independent of tie-breaks and
/// matches Ripser/giotto-tda (validated in `PersistentHomologyTests` against `training/ph_oracle.py`).
enum PersistentHomology {

    // Zero-persistence pairs (birth == death) are omitted, matching Ripser.
    private static let zeroBarEpsilon = 1e-12

    // MARK: Distance matrix

    static func euclideanDistanceMatrix(_ points: [[Double]]) -> [[Double]] {
        let n = points.count
        var dm = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                var sum = 0.0
                let a = points[i], b = points[j]
                for k in 0..<a.count {
                    let d = a[k] - b[k]
                    sum += d * d
                }
                let dist = sum.squareRoot()
                dm[i][j] = dist
                dm[j][i] = dist
            }
        }
        return dm
    }

    // MARK: Public API

    /// Computes the VR persistence diagram (dimensions 0 and 1). Edges/triangles whose
    /// filtration value exceeds `maxEpsilon` are excluded; unfilled classes then surface as
    /// essential bars with `death == .infinity`.
    static func vietorisRips(distanceMatrix dm: [[Double]], maxEpsilon: Double = .infinity) -> [PersistenceBar] {
        let n = dm.count
        guard n > 0 else { return [] }

        // ── Build simplices: vertices (dim 0), edges (dim 1), triangles (dim 2) ──────────
        struct Simplex { let dim: Int; let filt: Double; let verts: [Int] }
        var simplices: [Simplex] = []
        simplices.reserveCapacity(n * n)

        for i in 0..<n { simplices.append(Simplex(dim: 0, filt: 0, verts: [i])) }

        for i in 0..<n {
            for j in (i + 1)..<n where dm[i][j] <= maxEpsilon {
                simplices.append(Simplex(dim: 1, filt: dm[i][j], verts: [i, j]))
            }
        }

        for i in 0..<n {
            for j in (i + 1)..<n where dm[i][j] <= maxEpsilon {
                for k in (j + 1)..<n where dm[i][k] <= maxEpsilon && dm[j][k] <= maxEpsilon {
                    let filt = max(dm[i][j], dm[i][k], dm[j][k])
                    simplices.append(Simplex(dim: 2, filt: filt, verts: [i, j, k]))
                }
            }
        }

        // ── Filtration order: (filt asc, dim asc) → every face precedes its cofaces ──────
        let order = simplices.indices.sorted { a, b in
            let sa = simplices[a], sb = simplices[b]
            if sa.filt != sb.filt { return sa.filt < sb.filt }
            if sa.dim != sb.dim { return sa.dim < sb.dim }
            return lexLess(sa.verts, sb.verts)
        }

        let m = order.count
        var filt = [Double](repeating: 0, count: m)
        var dim = [Int](repeating: 0, count: m)
        var vertKeyToIndex = [[Int]: Int](minimumCapacity: m)
        for pos in 0..<m {
            let s = simplices[order[pos]]
            filt[pos] = s.filt
            dim[pos] = s.dim
            vertKeyToIndex[s.verts] = pos
        }

        // ── Boundary columns (sorted row indices, Z/2) ──────────────────────────────────
        var columns = [[Int]](repeating: [], count: m)
        for pos in 0..<m {
            let s = simplices[order[pos]]
            switch s.dim {
            case 1:
                let faces = [[s.verts[0]], [s.verts[1]]]
                columns[pos] = faces.compactMap { vertKeyToIndex[$0] }.sorted()
            case 2:
                let v = s.verts
                let faces = [[v[1], v[2]], [v[0], v[2]], [v[0], v[1]]]
                columns[pos] = faces.compactMap { vertKeyToIndex[$0] }.sorted()
            default:
                columns[pos] = []
            }
        }

        // ── Standard matrix reduction over Z/2 ──────────────────────────────────────────
        var pivotOfLow = [Int: Int]()          // lowRow → columnIndex that owns that pivot
        var deathOf = [Int: Int]()             // birthSimplex → deathSimplex (paired)
        var paired = [Bool](repeating: false, count: m)

        for j in 0..<m {
            var col = columns[j]
            while let low = col.last, let k = pivotOfLow[low] {
                col = symmetricDifference(col, columns[k])
            }
            columns[j] = col
            if let low = col.last {
                pivotOfLow[low] = j
                deathOf[low] = j
                paired[low] = true
                paired[j] = true
            }
        }

        // ── Extract bars ────────────────────────────────────────────────────────────────
        var bars: [PersistenceBar] = []
        for i in 0..<m {
            if let d = deathOf[i] {
                let birth = filt[i], death = filt[d]
                if death - birth > zeroBarEpsilon {
                    bars.append(PersistenceBar(dimension: dim[i], birth: birth, death: death))
                }
            } else if !paired[i] && columns[i].isEmpty {
                // positive & never used as a pivot → essential class
                bars.append(PersistenceBar(dimension: dim[i], birth: filt[i], death: .infinity))
            }
        }
        return bars
    }

    /// Loop Persistence: Σ(death − birth) over finite H1 bars. Rumination proxy.
    static func loopPersistence(_ bars: [PersistenceBar]) -> Double {
        bars.filter { $0.dimension == 1 && $0.death.isFinite }
            .reduce(0) { $0 + ($1.death - $1.birth) }
    }

    // MARK: - Z/2 helpers

    /// Symmetric difference of two ascending, duplicate-free index lists (Z/2 column add).
    private static func symmetricDifference(_ a: [Int], _ b: [Int]) -> [Int] {
        var result = [Int]()
        result.reserveCapacity(a.count + b.count)
        var i = 0, j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { i += 1; j += 1 }
            else if a[i] < b[j] { result.append(a[i]); i += 1 }
            else { result.append(b[j]); j += 1 }
        }
        while i < a.count { result.append(a[i]); i += 1 }
        while j < b.count { result.append(b[j]); j += 1 }
        return result
    }

    private static func lexLess(_ a: [Int], _ b: [Int]) -> Bool {
        for i in 0..<Swift.min(a.count, b.count) {
            if a[i] != b[i] { return a[i] < b[i] }
        }
        return a.count < b.count
    }
}
