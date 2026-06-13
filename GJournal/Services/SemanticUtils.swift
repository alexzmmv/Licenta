import Foundation
import Accelerate

enum SemanticUtils {

    // MARK: - Core similarity

    nonisolated static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return max(0, min(1, dot))
    }

    // MARK: - Related entries

    nonisolated static func relatedBits(to source: Bit, in pool: [Bit], limit: Int = 3) -> [(bit: Bit, similarity: Float)] {
        guard let srcEmb = normalised(source.embedding) else { return [] }

        var scored: [(bit: Bit, similarity: Float)] = []
        for candidate in pool {
            guard candidate.id != source.id,
                  let candEmb = normalised(candidate.embedding) else { continue }
            let sim = cosineSimilarity(srcEmb, candEmb)
            scored.append((candidate, sim))
        }
        return scored
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Helpers

    nonisolated static func normalised(_ embedding: [Float]?) -> [Float]? {
        guard let v = embedding, !v.isEmpty else { return nil }
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
