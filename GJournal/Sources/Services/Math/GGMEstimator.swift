import Foundation

// MARK: - Output Models

/// A node in the psychological network: an emotion or a behavioral tag (event/action).
enum NetworkVariable: Hashable, Sendable {
    case emotion(Emotion)
    case tag(lemma: String, category: TagCategory)

    var label: String {
        switch self {
        case .emotion(let e): return e.rawValue
        case .tag(let lemma, _): return lemma.capitalized
        }
    }

    var emotion: Emotion? { if case .emotion(let e) = self { return e }; return nil }
    var isEmotion: Bool { emotion != nil }

    // Explicit nonisolated conformance so math can run in Task.detached
    nonisolated static func == (lhs: NetworkVariable, rhs: NetworkVariable) -> Bool {
        switch (lhs, rhs) {
        case (.emotion(let a), .emotion(let b)): return a == b
        case (.tag(let a, let c), .tag(let b, let d)): return a == b && c == d
        default: return false
        }
    }

    nonisolated func hash(into hasher: inout Hasher) {
        switch self {
        case .emotion(let e): hasher.combine(0); hasher.combine(e.rawValue)
        case .tag(let lemma, let cat): hasher.combine(1); hasher.combine(lemma); hasher.combine(cat)
        }
    }
}

struct PsychNetworkEdge: Identifiable, Sendable {
    let id = UUID()
    let first: NetworkVariable
    let second: NetworkVariable
    let weight: Float     // partial correlation (Tier 2) or Spearman r (Tier 1)

    nonisolated var isPositive: Bool { weight > 0 }
    nonisolated var absWeight: Float { abs(weight) }
}

struct PsychologicalNetwork: Sendable {
    enum Tier: Sendable { case spearman, ledoitWolf }

    let edges: [PsychNetworkEdge]
    let centrality: [NetworkVariable: Float]   // node strength = Σ|weight|
    let tier: Tier
    let n: Int
    let shrinkageCoefficient: Double?  // Tier 2 only
    let computedAt: Date
}

// MARK: - GGM Estimator

enum GGMEstimator {

    // Swift 6: static stored properties are inferred @MainActor; mark nonisolated
    // so the math can run in Task.detached off the main actor.
    nonisolated static let tier1N       = 30
    nonisolated static let tier2N       = 90
    nonisolated static let edgeThreshold: Float = 0.10
    nonisolated static let maxEdges     = 20
    nonisolated static let bootstrapN   = 10
    nonisolated static let bootstrapMin = 8
    nonisolated static let fdrQ         = 0.10

    /// Default variable set when none is supplied: the 12 emotions (backward-compatible).
    nonisolated static var defaultLabels: [NetworkVariable] { Emotion.allCases.map { .emotion($0) } }

    // MARK: - Tier 1: Spearman + BH FDR + Bootstrap

    nonisolated static func tier1Network(from matrix: [[Float]], n: Int,
                             labels: [NetworkVariable] = defaultLabels) -> PsychologicalNetwork {
        let p = labels.count

        let cols: [[Double]] = (0..<p).map { j in matrix.map { Double($0[j]) } }
        let ranked = cols.map { rankVector($0) }

        // Pairwise Spearman + p-values
        var pairs: [(i: Int, j: Int, r: Double, p: Double)] = []
        for i in 0..<p {
            for j in (i+1)..<p {
                let r = pearsonCorrelation(ranked[i], ranked[j])
                let pv = tPValue(r: r, n: n)
                pairs.append((i, j, r, pv))
            }
        }

        let kept = benjaminiHochberg(pairs: pairs, q: fdrQ)
        let candidates: [(NetworkVariable, NetworkVariable, Float)] = kept
            .filter { abs($0.r) >= Double(edgeThreshold) }
            .map { (labels[$0.i], labels[$0.j], Float($0.r)) }

        let stable = bootstrapSpearman(matrix: matrix, labels: labels, candidates: candidates)

        let final = stable
            .sorted { abs($0.2) > abs($1.2) }
            .prefix(maxEdges)
            .map { PsychNetworkEdge(first: $0.0, second: $0.1, weight: $0.2) }

        return PsychologicalNetwork(
            edges: Array(final),
            centrality: computeCentrality(edges: Array(final)),
            tier: .spearman,
            n: n,
            shrinkageCoefficient: nil,
            computedAt: Date()
        )
    }

    // MARK: - Tier 2: Ledoit-Wolf GGM + Bootstrap

    nonisolated static func tier2Network(from matrix: [[Float]], n: Int,
                             labels: [NetworkVariable] = defaultLabels) -> PsychologicalNetwork {
        let p = labels.count

        guard let (omega, lambda) = ledoitWolfPrecision(from: matrix, p: p, n: n) else {
            return tier1Network(from: matrix, n: n, labels: labels)
        }

        let partialR = partialCorrelations(precision: omega, p: p)

        var candidates: [(NetworkVariable, NetworkVariable, Float)] = []
        for i in 0..<p {
            for j in (i+1)..<p {
                let r = Float(partialR[i * p + j])
                if abs(r) >= edgeThreshold {
                    candidates.append((labels[i], labels[j], r))
                }
            }
        }

        let stable = bootstrapLW(matrix: matrix, labels: labels, candidates: candidates, p: p)

        let final = stable
            .sorted { abs($0.2) > abs($1.2) }
            .prefix(maxEdges)
            .map { PsychNetworkEdge(first: $0.0, second: $0.1, weight: $0.2) }

        return PsychologicalNetwork(
            edges: Array(final),
            centrality: computeCentrality(edges: Array(final)),
            tier: .ledoitWolf,
            n: n,
            shrinkageCoefficient: lambda,
            computedAt: Date()
        )
    }

    // MARK: - Ledoit-Wolf Precision Matrix

    // Returns (precision_flat, shrinkage_lambda) or nil if inversion fails.
    // Uses biased covariance (1/n) to match sklearn.covariance.LedoitWolf.
    nonisolated static func ledoitWolfPrecision(from matrix: [[Float]], p: Int, n: Int) -> ([Double], Double)? {
        // Biased sample covariance S = (1/n) Σ (x_t - μ)(x_t - μ)^T
        let means = (0..<p).map { j in matrix.map { Double($0[j]) }.reduce(0, +) / Double(n) }
        var S = [Double](repeating: 0, count: p * p)
        for i in 0..<p {
            for j in i..<p {
                var cov = 0.0
                for t in 0..<n {
                    cov += (Double(matrix[t][i]) - means[i]) * (Double(matrix[t][j]) - means[j])
                }
                cov /= Double(n)
                S[i * p + j] = cov
                S[j * p + i] = cov
            }
        }

        let (lambda, mu) = ledoitWolfShrinkage(matrix: matrix, p: p, n: n)

        // Σ_hat = (1-λ)S + λμI
        var Shat = S
        for idx in 0..<(p * p) { Shat[idx] *= (1.0 - lambda) }
        for i in 0..<p { Shat[i * p + i] += lambda * mu }

        guard let omega = invertSymmetricPD(flat: Shat, p: p) else { return nil }
        return (omega, lambda)
    }

    // Exact port of sklearn.covariance.ledoit_wolf_shrinkage (non-blocked path, valid for
    // p ≤ 1000). Uses the biased covariance S = XᵀX/n on centered data X.
    //   μ = trace(S)/p
    //   δ = ‖S − μI‖²_F / p
    //   β = (1/(p·n))·( (Σₜ‖xₜ‖⁴)/n − ‖S‖²_F ),  capped at δ
    //   λ = β/δ
    // Validated to <1e-6 against sklearn on a fixed fixture (training/ggm_oracle.py).
    nonisolated static func ledoitWolfShrinkage(matrix: [[Float]], p: Int, n: Int) -> (lambda: Double, mu: Double) {
        var means = [Double](repeating: 0, count: p)
        for t in 0..<n { for j in 0..<p { means[j] += Double(matrix[t][j]) } }
        for j in 0..<p { means[j] /= Double(n) }

        var S = [Double](repeating: 0, count: p * p)
        var rowNorm4Sum = 0.0
        var xc = [Double](repeating: 0, count: p)
        for t in 0..<n {
            var rowSq = 0.0
            for j in 0..<p { let v = Double(matrix[t][j]) - means[j]; xc[j] = v; rowSq += v * v }
            rowNorm4Sum += rowSq * rowSq
            for i in 0..<p {
                let xi = xc[i]
                for j in i..<p { S[i * p + j] += xi * xc[j] }
            }
        }
        for i in 0..<p {
            for j in i..<p { let v = S[i * p + j] / Double(n); S[i * p + j] = v; S[j * p + i] = v }
        }

        let traceS = (0..<p).reduce(0.0) { $0 + S[$1 * p + $1] }
        let mu = traceS / Double(p)
        let normS2 = S.reduce(0.0) { $0 + $1 * $1 }               // ‖S‖²_F
        let delta = (normS2 - 2 * mu * traceS + Double(p) * mu * mu) / Double(p)
        var beta = (1.0 / (Double(p) * Double(n))) * (rowNorm4Sum / Double(n) - normS2)
        beta = Swift.min(beta, delta)

        let lambda = (beta == 0 || delta <= 0) ? 0.0 : beta / delta
        return (Swift.max(0, Swift.min(1, lambda)), mu)
    }

    // MARK: - Matrix Inversion (pure-Swift Cholesky, no deprecated LAPACK)

    // Inverts a symmetric positive-definite p×p matrix stored row-major.
    // Uses Cholesky A = L L^T then A^{-1} = L^{-T} L^{-1}.
    // Returns nil if A is not positive definite (pivot ≤ ε).
    nonisolated static func invertSymmetricPD(flat A: [Double], p: Int) -> [Double]? {
        // Step 1 — Cholesky decomposition: L[i,j] stored at L[i*p+j]
        var L = [Double](repeating: 0, count: p * p)
        for j in 0..<p {
            for i in j..<p {
                var s = A[i * p + j]
                for k in 0..<j { s -= L[i * p + k] * L[j * p + k] }
                if i == j {
                    guard s > 1e-14 else {
                        AppLogger.error("[GGM] Cholesky: non-positive pivot at (\(i),\(j))")
                        return nil
                    }
                    L[i * p + j] = s.squareRoot()
                } else {
                    L[i * p + j] = s / L[j * p + j]
                }
            }
        }

        // Step 2 — Compute L^{-1} (lower triangular) by column forward-substitution
        // Linv[i*p+j] = element at row i, col j of L^{-1}
        var Linv = [Double](repeating: 0, count: p * p)
        for col in 0..<p {
            Linv[col * p + col] = 1.0 / L[col * p + col]
            for row in (col + 1)..<p {
                var s = 0.0
                for k in col..<row { s += L[row * p + k] * Linv[k * p + col] }
                Linv[row * p + col] = -s / L[row * p + row]
            }
        }

        // Step 3 — A^{-1} = L^{-T} L^{-1}; result[i,j] = Σ_{k≥max(i,j)} Linv[k,i]*Linv[k,j]
        var result = [Double](repeating: 0, count: p * p)
        for i in 0..<p {
            for j in i..<p {
                var s = 0.0
                for k in j..<p { s += Linv[k * p + i] * Linv[k * p + j] }
                result[i * p + j] = s
                result[j * p + i] = s
            }
        }
        return result
    }

    // MARK: - Partial Correlations

    // P_ij = -Ω_ij / sqrt(Ω_ii * Ω_jj)
    nonisolated static func partialCorrelations(precision: [Double], p: Int) -> [Double] {
        var result = [Double](repeating: 0, count: p * p)
        for i in 0..<p {
            for j in 0..<p where i != j {
                let denom = (precision[i * p + i] * precision[j * p + j]).squareRoot()
                result[i * p + j] = denom > 0 ? -precision[i * p + j] / denom : 0
            }
        }
        return result
    }

    // MARK: - Spearman

    // Replaces each value with its rank (1-based, average ties).
    nonisolated static func rankVector(_ v: [Double]) -> [Double] {
        let n = v.count
        guard n > 0 else { return [] }
        let indexed = v.enumerated().sorted { $0.element < $1.element }
        var ranks = [Double](repeating: 0, count: n)
        var i = 0
        while i < n {
            var j = i
            while j < n - 1 && indexed[j].element == indexed[j + 1].element { j += 1 }
            let avgRank = Double(i + j) / 2.0 + 1.0  // average of 1-based ranks
            for k in i...j { ranks[indexed[k].offset] = avgRank }
            i = j + 1
        }
        return ranks
    }

    nonisolated static func pearsonCorrelation(_ x: [Double], _ y: [Double]) -> Double {
        let n = x.count
        guard n > 1 else { return 0 }
        let mx = x.reduce(0, +) / Double(n)
        let my = y.reduce(0, +) / Double(n)
        var num = 0.0, sx = 0.0, sy = 0.0
        for i in 0..<n {
            let dx = x[i] - mx, dy = y[i] - my
            num += dx * dy; sx += dx * dx; sy += dy * dy
        }
        let denom = (sx * sy).squareRoot()
        return denom > 0 ? num / denom : 0
    }

    // Two-tailed p-value via normal approximation (adequate for n ≥ 30, df ≥ 28).
    nonisolated static func tPValue(r: Double, n: Int) -> Double {
        guard abs(r) < 1.0 - 1e-9, n > 2 else { return abs(r) >= 1.0 - 1e-9 ? 0.0 : 1.0 }
        let t = r * ((Double(n - 2) / (1.0 - r * r)).squareRoot())
        return 2.0 * (1.0 - normalCDF(abs(t)))
    }

    nonisolated static func normalCDF(_ x: Double) -> Double {
        0.5 * (1.0 + erf(x / 2.0.squareRoot()))
    }

    // MARK: - Benjamini-Hochberg FDR

    nonisolated static func benjaminiHochberg(
        pairs: [(i: Int, j: Int, r: Double, p: Double)],
        q: Double
    ) -> [(i: Int, j: Int, r: Double)] {
        let m = pairs.count
        guard m > 0 else { return [] }
        let sorted = pairs.sorted { $0.p < $1.p }
        var lastReject = -1
        for k in 0..<m where sorted[k].p <= Double(k + 1) / Double(m) * q {
            lastReject = k
        }
        guard lastReject >= 0 else { return [] }
        return sorted.prefix(lastReject + 1).map { (i: $0.i, j: $0.j, r: $0.r) }
    }

    // MARK: - Bootstrap Stability

    // Tier 1: check Spearman |r| ≥ threshold in each resample.
    private nonisolated static func bootstrapSpearman(
        matrix: [[Float]],
        labels: [NetworkVariable],
        candidates: [(NetworkVariable, NetworkVariable, Float)]
    ) -> [(NetworkVariable, NetworkVariable, Float)] {
        guard !candidates.isEmpty else { return [] }
        let idx = Dictionary(uniqueKeysWithValues: labels.enumerated().map { ($1, $0) })
        let p = labels.count
        let n = matrix.count
        var passes = [Int](repeating: 0, count: candidates.count)
        var rng = SystemRandomNumberGenerator()

        for _ in 0..<bootstrapN {
            let sample = (0..<n).map { _ in matrix[Int.random(in: 0..<n, using: &rng)] }
            let sampledCols: [[Double]] = (0..<p).map { j in sample.map { Double($0[j]) } }
            let ranked = sampledCols.map { rankVector($0) }
            for (k, (v1, v2, _)) in candidates.enumerated() {
                guard let i = idx[v1], let j = idx[v2] else { continue }
                let r = Float(pearsonCorrelation(ranked[i], ranked[j]))
                if abs(r) >= edgeThreshold { passes[k] += 1 }
            }
        }

        return zip(candidates, passes).filter { $0.1 >= bootstrapMin }.map { $0.0 }
    }

    // Tier 2: recompute full LW + partial correlations for each resample.
    private nonisolated static func bootstrapLW(
        matrix: [[Float]],
        labels: [NetworkVariable],
        candidates: [(NetworkVariable, NetworkVariable, Float)],
        p: Int
    ) -> [(NetworkVariable, NetworkVariable, Float)] {
        guard !candidates.isEmpty else { return [] }
        let idx = Dictionary(uniqueKeysWithValues: labels.enumerated().map { ($1, $0) })
        let n = matrix.count
        var passes = [Int](repeating: 0, count: candidates.count)
        var rng = SystemRandomNumberGenerator()

        for _ in 0..<bootstrapN {
            let sample = (0..<n).map { _ in matrix[Int.random(in: 0..<n, using: &rng)] }
            guard let (omega, _) = ledoitWolfPrecision(from: sample, p: p, n: sample.count) else { continue }
            let partialR = partialCorrelations(precision: omega, p: p)
            for (k, (v1, v2, _)) in candidates.enumerated() {
                guard let i = idx[v1], let j = idx[v2] else { continue }
                if abs(Float(partialR[i * p + j])) >= edgeThreshold { passes[k] += 1 }
            }
        }

        return zip(candidates, passes).filter { $0.1 >= bootstrapMin }.map { $0.0 }
    }

    // MARK: - Centrality

    nonisolated static func computeCentrality(edges: [PsychNetworkEdge]) -> [NetworkVariable: Float] {
        var strength = [NetworkVariable: Float]()
        for e in edges {
            strength[e.first,  default: 0] += e.absWeight
            strength[e.second, default: 0] += e.absWeight
        }
        return strength
    }
}
