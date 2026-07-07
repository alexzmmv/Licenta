import Foundation

@Observable
@MainActor
final class InsightEngine {
    var network: PsychologicalNetwork?
    var isComputing = false

    /// Adaptive cap on tags per category as GGM variables (plan §2.1: ≤ n/5, max 8 each).
    private let maxTagsPerCategory = 8

    // Extract the emotion (continuous) + behavioral-tag (binary) matrix from bits on the
    // MainActor (Bit/BehavioralTag are SwiftData models), then dispatch the math to a detached task.
    func compute(bits: [Bit], allTags: [BehavioralTag] = []) async {
        guard !isComputing else { return }
        isComputing = true
        defer { isComputing = false }

        let emotions = Emotion.allCases

        // Build the usable rows explicitly (emotion vector + tag lemma set) in one pass.
        var rows: [[Float]] = []
        var perBitLemmas: [Set<String>] = []
        for bit in bits where !bit.isDeleted {
            guard let probs = bit.emotionProbabilities else { continue }
            var emo = [Float](repeating: 0, count: emotions.count)
            var hasSignal = false
            for (idx, e) in emotions.enumerated() {
                let p = probs[e.rawValue] ?? 0
                emo[idx] = p
                if p > 0 { hasSignal = true }
            }
            guard hasSignal else { continue }
            rows.append(emo)
            perBitLemmas.append(Set(bit.tagLemmas))
        }

        let n = rows.count
        guard n >= GGMEstimator.tier1N else { network = nil; return }

        var labels: [NetworkVariable] = emotions.map { .emotion($0) }

        // Behavioral-tag columns (binary presence): top-K per category among GGM-eligible tags,
        // keeping only tags with non-degenerate variance in this window (present in some, not all).
        let k = min(maxTagsPerCategory, n / 5)
        if k > 0 {
            let eligible = allTags.filter { $0.isGGMEligible }
            func presenceCount(_ lemma: String) -> Int {
                var c = 0
                for lemmas in perBitLemmas where lemmas.contains(lemma) { c += 1 }
                return c
            }
            func select(_ category: TagCategory) -> [BehavioralTag] {
                let ranked = eligible.filter { $0.category == category }.sorted { $0.count > $1.count }
                var chosen: [BehavioralTag] = []
                for tag in ranked {
                    let pc = presenceCount(tag.lemma)
                    if pc > 0 && pc < n {
                        chosen.append(tag)
                        if chosen.count == k { break }
                    }
                }
                return chosen
            }
            for tag in select(.event) + select(.action) {
                let lemma = tag.lemma
                for i in 0..<n { rows[i].append(perBitLemmas[i].contains(lemma) ? 1 : 0) }
                labels.append(.tag(lemma: lemma, category: tag.category))
            }
        }

        let matrix = rows
        let vars = labels
        let result: PsychologicalNetwork = await Task.detached(priority: .utility) {
            if n >= GGMEstimator.tier2N {
                return GGMEstimator.tier2Network(from: matrix, n: n, labels: vars)
            } else {
                return GGMEstimator.tier1Network(from: matrix, n: n, labels: vars)
            }
        }.value

        network = result
        let tagCount = labels.count - emotions.count
        AppLogger.log("[InsightEngine] Network: \(result.edges.count) edges, tier=\(result.tier), n=\(n), tags=\(tagCount)")
    }
}
