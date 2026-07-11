import Foundation

// MARK: - Inputs / Outputs

/// One journal entry projected into the trajectory space: its embedding, timestamp and
/// emotional valence.
struct TrajectoryPoint: Sendable {
    let date: Date
    let embedding: [Double]
    let valence: Double
}

/// Trajectory biomarkers over a sliding window (plan §2.2). Framing is wellness-only:
/// "patterns", never diagnosis.
struct TrajectoryMetrics: Sendable {
    /// Rumination proxy: Σ(death−birth) over finite H1 bars from real persistent homology.
    let loopPersistence: Double
    /// Permutation-null p-value for the loop (spatial null of matched scale). 1.0 if not tested.
    let ruminationPValue: Double
    /// Exploration proxy: convex-hull area / bounding-box area in PCA-2D, in [0,1].
    let flareIndex: Double
    /// Semantic Recovery Velocity: least-squares slope of distance-from-distress-anchor over time.
    let recoveryVelocity: Double
    let pointCount: Int
    let windowStart: Date
    let windowEnd: Date

    /// A loop is surfaced only if it clears the 95th percentile of the null distribution.
    var ruminationSignificant: Bool { ruminationPValue < 0.05 }
}

// MARK: - Trajectory Service

enum TrajectoryService {

    nonisolated static let minPoints = 5

    /// Computes trajectory metrics for one window. Returns nil below `minPoints`.
    /// `permutations > 0` runs the spatial permutation-null test for the loop metric.
    nonisolated static func metrics(for window: [TrajectoryPoint], permutations: Int = 0) -> TrajectoryMetrics? {
        let pts = window.sorted { $0.date < $1.date }
        guard pts.count >= minPoints else { return nil }
        let embeddings = pts.map(\.embedding)

        let dm = PersistentHomology.euclideanDistanceMatrix(embeddings)
        let bars = PersistentHomology.vietorisRips(distanceMatrix: dm)
        let lp = PersistentHomology.loopPersistence(bars)

        let flare = flareIndex(embeddings)
        let srv = recoveryVelocity(pts)
        let pValue = permutations > 0
            ? loopPValue(observedLP: lp, embeddings: embeddings, trials: permutations)
            : 1.0

        return TrajectoryMetrics(
            loopPersistence: lp,
            ruminationPValue: pValue,
            flareIndex: flare,
            recoveryVelocity: srv,
            pointCount: pts.count,
            windowStart: pts.first!.date,
            windowEnd: pts.last!.date
        )
    }

    // MARK: - Flare Index (exploration)

    /// Convex-hull area of the PCA-2D projection over its *enclosing square* (max extent²).
    /// Normalising by a square rather than the raw axis-aligned bbox makes the index
    /// aspect-invariant: a near-1D "recovery line" fills almost none of its square (→0),
    /// while a genuinely 2D disk/ring spreads to fill it (→~0.78). This is the intended
    /// "flaring outward" signal — a degenerate bbox would otherwise score a line spuriously high.
    nonisolated static func flareIndex(_ embeddings: [[Double]]) -> Double {
        let coords = pca2D(embeddings)
        guard coords.count >= 3 else { return 0 }
        let hullArea = polygonArea(convexHull(coords))
        let xs = coords.map(\.0), ys = coords.map(\.1)
        let extent = max(xs.max()! - xs.min()!, ys.max()! - ys.min()!)
        guard extent > 1e-12 else { return 0 }
        return min(1.0, hullArea / (extent * extent))
    }

    // MARK: - Semantic Recovery Velocity

    /// Anchor = centroid of the lowest-valence entries; SRV = slope of distance-from-anchor
    /// over time (days). Positive = drifting away from difficult moments.
    nonisolated static func recoveryVelocity(_ pts: [TrajectoryPoint]) -> Double {
        let n = pts.count
        guard n >= 2, let dim = pts.first?.embedding.count, dim > 0 else { return 0 }

        let k = max(3, n / 5)
        let anchorPts = pts.sorted { $0.valence < $1.valence }.prefix(k)
        var anchor = [Double](repeating: 0, count: dim)
        for p in anchorPts { for d in 0..<dim { anchor[d] += p.embedding[d] } }
        for d in 0..<dim { anchor[d] /= Double(anchorPts.count) }

        let t0 = pts.first!.date.timeIntervalSince1970
        var xs = [Double](), ys = [Double]()
        for p in pts {
            var sq = 0.0
            for d in 0..<dim { let diff = p.embedding[d] - anchor[d]; sq += diff * diff }
            ys.append(sq.squareRoot())
            xs.append((p.date.timeIntervalSince1970 - t0) / 86_400.0)  // days
        }
        return leastSquaresSlope(x: xs, y: ys)
    }

    // MARK: - Permutation null (spatial)

    /// The point cloud — and thus LP — is invariant to time order, so the loop's null must be
    /// spatial: draw `trials` random clouds matching the window's per-dimension mean/std and
    /// measure how often their LP reaches the observed value. p = (1 + #{null ≥ obs}) / (trials + 1).
    nonisolated static func loopPValue(observedLP: Double, embeddings: [[Double]], trials: Int) -> Double {
        let n = embeddings.count, dim = embeddings.first?.count ?? 0
        guard n >= minPoints, dim > 0, observedLP > 0 else { return 1.0 }

        var mean = [Double](repeating: 0, count: dim)
        for e in embeddings { for d in 0..<dim { mean[d] += e[d] } }
        for d in 0..<dim { mean[d] /= Double(n) }
        var std = [Double](repeating: 0, count: dim)
        for e in embeddings { for d in 0..<dim { let z = e[d] - mean[d]; std[d] += z * z } }
        for d in 0..<dim { std[d] = (std[d] / Double(n)).squareRoot() }

        var rng = SplitMix64(seed: 0x9E37_79B9_7F4A_7C15)
        var atLeast = 0
        for _ in 0..<trials {
            var cloud = [[Double]](repeating: [Double](repeating: 0, count: dim), count: n)
            for i in 0..<n {
                for d in 0..<dim {
                    cloud[i][d] = mean[d] + std[d] * rng.nextGaussian()
                }
            }
            let dm = PersistentHomology.euclideanDistanceMatrix(cloud)
            let nullLP = PersistentHomology.loopPersistence(PersistentHomology.vietorisRips(distanceMatrix: dm))
            if nullLP >= observedLP { atLeast += 1 }
        }
        return Double(atLeast + 1) / Double(trials + 1)
    }

    // MARK: - Geometry helpers

    /// PCA to 2D via the n×n Gram matrix (n is small): scores_k = sqrt(λ_k)·u_k.
    nonisolated static func pca2D(_ points: [[Double]]) -> [(Double, Double)] {
        let n = points.count
        guard n > 0, let dim = points.first?.count, dim > 0 else { return [] }

        var mean = [Double](repeating: 0, count: dim)
        for p in points { for d in 0..<dim { mean[d] += p[d] } }
        for d in 0..<dim { mean[d] /= Double(n) }
        let centered = points.map { p in (0..<dim).map { p[$0] - mean[$0] } }

        // Gram matrix G = Xc Xcᵀ  (n×n)
        var g = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in i..<n {
                var s = 0.0
                for d in 0..<dim { s += centered[i][d] * centered[j][d] }
                g[i][j] = s; g[j][i] = s
            }
        }

        let (l1, u1) = topEigen(g)
        deflate(&g, value: l1, vector: u1)
        let (l2, u2) = topEigen(g)

        let s1 = max(0, l1).squareRoot()
        let s2 = max(0, l2).squareRoot()
        return (0..<n).map { (s1 * u1[$0], s2 * u2[$0]) }
    }

    /// Dominant eigenpair of a symmetric matrix by power iteration (deterministic start).
    private nonisolated static func topEigen(_ m: [[Double]], iterations: Int = 300) -> (Double, [Double]) {
        let n = m.count
        guard n > 0 else { return (0, []) }
        var v = (0..<n).map { Double(($0 % 7) + 1) }  // deterministic, non-degenerate
        normalize(&v)
        var lambda = 0.0
        for _ in 0..<iterations {
            var w = [Double](repeating: 0, count: n)
            for i in 0..<n { var s = 0.0; for j in 0..<n { s += m[i][j] * v[j] }; w[i] = s }
            let norm = w.reduce(0) { $0 + $1 * $1 }.squareRoot()
            guard norm > 1e-15 else { return (0, v) }
            for i in 0..<n { w[i] /= norm }
            lambda = norm
            if zip(v, w).allSatisfy({ abs($0 - $1) < 1e-12 }) { v = w; break }
            v = w
        }
        return (lambda, v)
    }

    private nonisolated static func deflate(_ m: inout [[Double]], value: Double, vector v: [Double]) {
        let n = m.count
        for i in 0..<n { for j in 0..<n { m[i][j] -= value * v[i] * v[j] } }
    }

    private nonisolated static func normalize(_ v: inout [Double]) {
        let norm = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 1e-15 else { return }
        for i in v.indices { v[i] /= norm }
    }

    /// Andrew's monotone-chain convex hull.
    nonisolated static func convexHull(_ pts: [(Double, Double)]) -> [(Double, Double)] {
        let p = Array(Set(pts.map { Point2($0.0, $0.1) })).sorted()
        guard p.count >= 3 else { return p.map { ($0.x, $0.y) } }
        func cross(_ o: Point2, _ a: Point2, _ b: Point2) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower = [Point2]()
        for pt in p {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], pt) <= 0 { lower.removeLast() }
            lower.append(pt)
        }
        var upper = [Point2]()
        for pt in p.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], pt) <= 0 { upper.removeLast() }
            upper.append(pt)
        }
        lower.removeLast(); upper.removeLast()
        return (lower + upper).map { ($0.x, $0.y) }
    }

    nonisolated static func polygonArea(_ poly: [(Double, Double)]) -> Double {
        let n = poly.count
        guard n >= 3 else { return 0 }
        var area = 0.0
        for i in 0..<n {
            let j = (i + 1) % n
            area += poly[i].0 * poly[j].1 - poly[j].0 * poly[i].1
        }
        return abs(area) / 2.0
    }

    nonisolated static func leastSquaresSlope(x: [Double], y: [Double]) -> Double {
        let n = Double(x.count)
        guard n >= 2 else { return 0 }
        let mx = x.reduce(0, +) / n, my = y.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for i in x.indices { let dx = x[i] - mx; num += dx * (y[i] - my); den += dx * dx }
        return den > 1e-12 ? num / den : 0
    }
}

// MARK: - Support types

private struct Point2: Hashable, Comparable, Sendable {
    let x: Double, y: Double
    nonisolated init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    nonisolated static func == (lhs: Point2, rhs: Point2) -> Bool { lhs.x == rhs.x && lhs.y == rhs.y }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(x); hasher.combine(y) }
    nonisolated static func < (a: Point2, b: Point2) -> Bool { a.x != b.x ? a.x < b.x : a.y < b.y }
}

/// Deterministic PRNG with a Gaussian sampler (Box–Muller), for reproducible null tests.
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    private var spare: Double?
    nonisolated init(seed: UInt64) { state = seed }

    nonisolated mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    nonisolated mutating func nextUnit() -> Double { Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) }

    nonisolated mutating func nextGaussian() -> Double {
        if let s = spare { spare = nil; return s }
        let u1 = max(nextUnit(), 1e-12), u2 = nextUnit()
        let r = (-2.0 * Foundation.log(u1)).squareRoot()
        let theta = 2.0 * Double.pi * u2
        spare = r * Foundation.sin(theta)
        return r * Foundation.cos(theta)
    }
}
