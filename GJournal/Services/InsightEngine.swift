import Foundation

@Observable
@MainActor
final class InsightEngine {
    var network: PsychologicalNetwork?
    var isComputing = false

    // Extract emotion matrix from bits on MainActor (Bit is a SwiftData model,
    // bound to MainActor), then dispatch the heavy math to a detached task.
    func compute(bits: [Bit]) async {
        guard !isComputing else { return }
        isComputing = true
        defer { isComputing = false }

        let emotions = Emotion.allCases
        let matrix: [[Float]] = bits
            .filter { !$0.isDeleted }
            .compactMap { bit -> [Float]? in
                guard let probs = bit.emotionProbabilities else { return nil }
                let row = emotions.map { probs[$0.rawValue] ?? 0 }
                guard row.contains(where: { $0 > 0 }) else { return nil }
                return row
            }

        let n = matrix.count
        guard n >= GGMEstimator.tier1N else {
            network = nil
            return
        }

        let result: PsychologicalNetwork = await Task.detached(priority: .utility) {
            if n >= GGMEstimator.tier2N {
                return GGMEstimator.tier2Network(from: matrix, n: n)
            } else {
                return GGMEstimator.tier1Network(from: matrix, n: n)
            }
        }.value

        network = result
        AppLogger.log("[InsightEngine] Network: \(result.edges.count) edges, tier=\(result.tier), n=\(n)")
    }
}
