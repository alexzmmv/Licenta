//
//  SemanticUtils.swift
//  GJournal
//

import Foundation
import Accelerate

enum SemanticUtils {

    // MARK: - Core similarity

    /// Cosine similarity in [0, 1]. Assumes vectors are already L2-normalised.
    nonisolated static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return max(0, min(1, dot))
    }

    // MARK: - Related entries

    /// Returns up to `limit` entries from `pool` most semantically similar to `source`,
    /// excluding `source` itself. Only considers entries with embeddings.
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

    // MARK: - Divergent pairs

    /// Pairs of entries that are semantically close (similarity ≥ threshold)
    /// but have different dominant emotions — the "you wrote about the same thing
    /// with very different feelings" insight.
    nonisolated static func divergentPairs(
        in bits: [Bit],
        similarityThreshold: Float = 0.72
    ) -> [(Bit, Bit)] {
        let processed = bits.filter { $0.embedding != nil && $0.topDetectedEmotion != nil && !$0.isDeleted }
        guard processed.count >= 2 else { return [] }

        let normalised = processed.compactMap { bit -> (Bit, [Float])? in
            guard let emb = Self.normalised(bit.embedding) else { return nil }
            return (bit, emb)
        }
        guard normalised.count >= 2 else { return [] }
        var pairs: [(Bit, Bit)] = []

        for i in 0..<normalised.count {
            for j in (i + 1)..<normalised.count {
                let (bitA, embA) = normalised[i]
                let (bitB, embB) = normalised[j]
                guard embA.count == embB.count else { continue }
                let sim = cosineSimilarity(embA, embB)
                guard sim >= similarityThreshold else { continue }
                guard bitA.topDetectedEmotion != bitB.topDetectedEmotion else { continue }
                pairs.append((bitA, bitB))
            }
        }
        return pairs
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
