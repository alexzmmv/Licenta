import Foundation

/// Extracts a sliding embedding window from journal entries and computes trajectory
/// biomarkers off the main actor. Mirrors `InsightEngine` for the GGM network.
@Observable
@MainActor
final class TrajectoryEngine {
    var metrics: TrajectoryMetrics?
    var isComputing = false

    /// Sliding window length (plan §2.2: 30-day windows).
    private let windowDays = 30.0
    /// Hard cap on window size to bound the persistent-homology cost (plan caps at ≤60).
    private let maxPoints = 45

    func compute(bits: [Bit]) async {
        guard !isComputing else { return }
        isComputing = true
        defer { isComputing = false }

        // Extract on the main actor (Bit is @MainActor-bound SwiftData).
        let active = bits.filter { !$0.isDeleted && $0.embedding != nil }
        guard let latest = active.map(\.createdAt).max() else { metrics = nil; return }
        let windowStart = latest.addingTimeInterval(-windowDays * 86_400)

        var points: [TrajectoryPoint] = active
            .filter { $0.createdAt >= windowStart }
            .sorted { $0.createdAt < $1.createdAt }
            .compactMap { bit -> TrajectoryPoint? in
                guard let emb = bit.embedding else { return nil }
                return TrajectoryPoint(
                    date: bit.createdAt,
                    embedding: Self.l2Normalized(emb),
                    valence: Self.valence(of: bit)
                )
            }

        // Keep the most recent `maxPoints` to bound PH cost on large windows.
        if points.count > maxPoints { points = Array(points.suffix(maxPoints)) }

        guard points.count >= TrajectoryService.minPoints else { metrics = nil; return }

        // Permutation budget scales down with window size to keep it responsive.
        let perms = points.count <= 30 ? 99 : 30

        let result = await Task.detached(priority: .utility) {
            TrajectoryService.metrics(for: points, permutations: perms)
        }.value

        metrics = result
        if let m = result {
            AppLogger.log("[TrajectoryEngine] LP=\(m.loopPersistence) p=\(m.ruminationPValue) flare=\(m.flareIndex) srv=\(m.recoveryVelocity) n=\(m.pointCount)")
        }
    }

    // MARK: - Extraction helpers

    /// Weighted valence: Σ p(emotion)·valence(emotion), falling back to the top emotion.
    private static func valence(of bit: Bit) -> Double {
        if let probs = bit.emotionProbabilities, !probs.isEmpty {
            var total: Double = 0, weight: Double = 0
            for (key, p) in probs {
                guard let e = Emotion(rawValue: key) else { continue }
                total += Double(p) * e.valence
                weight += Double(p)
            }
            if weight > 0 { return total / weight }
        }
        return bit.emotion.valence
    }

    /// L2-normalise so Euclidean distance approximates cosine distance on the sphere.
    private static func l2Normalized(_ v: [Float]) -> [Double] {
        let d = v.map(Double.init)
        let norm = d.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 1e-12 else { return d }
        return d.map { $0 / norm }
    }
}
