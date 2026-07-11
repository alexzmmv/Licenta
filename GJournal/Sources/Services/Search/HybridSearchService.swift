import Foundation
import Accelerate

/// In-memory hybrid search: BM25 keyword ranking fused with vector pseudo-relevance
/// feedback via Reciprocal Rank Fusion (RRF, k=60). Rebuild on every loadBitsFromContext.
/// Search is fully synchronous — no CoreML round-trip required.
final class HybridSearchService {

    // BM25 hyperparameters (standard Okapi BM25)
    private let k1: Float = 1.2
    private let b: Float = 0.75
    private let rrfK: Float = 60

    private var indexedBits: [Bit] = []
    private var docLengths: [Float] = []
    private var avgDocLength: Float = 1
    private var invertedIndex: [String: [Int: Float]] = [:]  // term → [docIdx: tf]
    private var docFrequency: [String: Int] = [:]             // term → # docs containing it
    private var normEmbeddings: [[Float]?] = []

    // MARK: - Index management

    func rebuild(from bits: [Bit]) {
        indexedBits = bits
        docLengths = []
        invertedIndex = [:]
        docFrequency = [:]
        normEmbeddings = bits.map { SemanticUtils.normalised($0.embedding) }

        var total: Float = 0
        for (idx, bit) in bits.enumerated() {
            let tokens = Self.tokenize(Self.textContent(of: bit))
            let len = Float(tokens.count)
            docLengths.append(len)
            total += len

            var tf: [String: Float] = [:]
            for token in tokens { tf[token, default: 0] += 1 }
            for (term, freq) in tf {
                if invertedIndex[term] == nil { invertedIndex[term] = [:] }
                invertedIndex[term]![idx] = freq
                docFrequency[term, default: 0] += 1
            }
        }
        avgDocLength = bits.isEmpty ? 1 : total / Float(bits.count)
    }

    // MARK: - Hybrid search (BM25 + pseudo-relevance cosine via RRF)

    /// Returns bits ranked by hybrid BM25 + vector score. Empty query returns unfiltered bits.
    func search(query: String) -> [Bit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return indexedBits }
        let n = indexedBits.count
        guard n > 0 else { return [] }

        let queryTokens = Self.tokenize(q)
        guard !queryTokens.isEmpty else { return [] }

        // -- BM25 arm --
        var bm25: [Float] = [Float](repeating: 0, count: n)
        for token in queryTokens {
            scoreBM25(token: token, n: n, scores: &bm25, weight: 1.0)
            // Prefix fallback (min 3 chars) when exact term has no hits
            if docFrequency[token] == nil, token.count >= 3 {
                for (indexedTerm, _) in invertedIndex where indexedTerm.hasPrefix(token) && indexedTerm != token {
                    scoreBM25(token: indexedTerm, n: n, scores: &bm25, weight: 0.7)
                }
            }
        }
        let bm25Ranked = (0..<n).filter { bm25[$0] > 0 }.sorted { bm25[$0] > bm25[$1] }

        // -- Vector arm: centroid of top-3 BM25 hits, then cosine scan --
        var cosineRanked: [Int] = []
        let topK = min(3, bm25Ranked.count)
        if topK > 0, let dim = normEmbeddings.compactMap({ $0 }).first?.count, dim > 0 {
            var centroid = [Float](repeating: 0, count: dim)
            var count = 0
            for i in 0..<topK {
                if let emb = normEmbeddings[bm25Ranked[i]] {
                    vDSP_vadd(centroid, 1, emb, 1, &centroid, 1, vDSP_Length(dim))
                    count += 1
                }
            }
            if count > 0 {
                var scale = 1.0 / Float(count)
                vDSP_vsmul(centroid, 1, &scale, &centroid, 1, vDSP_Length(dim))
                if let normCentroid = SemanticUtils.normalised(centroid) {
                    var cosScores = [Float](repeating: 0, count: n)
                    for i in 0..<n {
                        if let emb = normEmbeddings[i] {
                            cosScores[i] = SemanticUtils.cosineSimilarity(normCentroid, emb)
                        }
                    }
                    cosineRanked = (0..<n).filter { cosScores[$0] > 0 }.sorted { cosScores[$0] > cosScores[$1] }
                }
            }
        }

        // -- RRF fusion (k=60) --
        var rrf = [Float](repeating: 0, count: n)
        for (rank, idx) in bm25Ranked.enumerated() {
            rrf[idx] += 1.0 / (rrfK + Float(rank + 1))
        }
        for (rank, idx) in cosineRanked.enumerated() {
            rrf[idx] += 1.0 / (rrfK + Float(rank + 1))
        }

        return (0..<n).filter { rrf[$0] > 0 }
            .sorted { rrf[$0] > rrf[$1] }
            .map { indexedBits[$0] }
    }

    // MARK: - Related entries (pure cosine scan)

    /// Top-N semantically related bits (cos ≥ threshold). Excludes source bit.
    func related(to source: Bit, threshold: Float = 0.45, limit: Int = 3) -> [(bit: Bit, similarity: Float)] {
        let pool = indexedBits.filter { $0.id != source.id && !$0.isDeleted }
        return SemanticUtils.relatedBits(to: source, in: pool, limit: limit)
            .filter { $0.similarity >= threshold }
    }

    // MARK: - Helpers

    private func scoreBM25(token: String, n: Int, scores: inout [Float], weight: Float) {
        let df = Float(docFrequency[token, default: 0])
        let idf = log((Float(n) - df + 0.5) / (df + 0.5) + 1)
        guard let postings = invertedIndex[token] else { return }
        for (idx, tf) in postings {
            let dl = docLengths[idx]
            let score = idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * dl / avgDocLength))
            scores[idx] += score * weight
        }
    }

    static func textContent(of bit: Bit) -> String {
        [(bit.title ?? ""), bit.feel, bit.event, bit.action].joined(separator: " ")
    }

    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }
}
