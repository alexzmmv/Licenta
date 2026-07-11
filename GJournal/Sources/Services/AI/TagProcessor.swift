import Foundation
import SwiftData

/// Turns a journal entry's Event/Action text into canonical behavioral tags: extracts
/// lemmatized noun/verb candidates, embeds each, merges into an existing `BehavioralTag` at
/// cosine ≥ threshold (else creates one), bumps occurrence counts, and returns the canonical
/// lemmas to store on the entry. Operates on whatever `ModelContext` it is given (designed to
/// run on the AI pipeline's background context).
struct TagProcessor {
    let embeddingService: EmbeddingServiceProtocol
    var mergeThreshold: Float = TagExtractor.mergeThreshold

    @discardableResult
    func process(event: String, action: String, into context: ModelContext) async -> [String] {
        let candidates = TagExtractor.extract(event: event, action: action)
        guard !candidates.isEmpty else { return [] }

        // Working registry, extended as new tags are created within this batch.
        var working = (try? context.fetch(FetchDescriptor<BehavioralTag>())) ?? []
        var assigned = Set<String>()

        for candidate in candidates {
            guard let embedding = try? await embeddingService.generateEmbedding(for: candidate.lemma),
                  !embedding.isEmpty else { continue }

            let sameCategory = working.filter {
                $0.category == candidate.category && $0.canonicalEmbedding != nil
            }
            let existingEmbeddings = sameCategory.map { $0.canonicalEmbedding! }

            if let idx = TagExtractor.matchIndex(candidate: embedding,
                                                 existing: existingEmbeddings,
                                                 threshold: mergeThreshold) {
                let tag = sameCategory[idx]
                tag.count += 1
                tag.lastSeen = .now
                assigned.insert(tag.lemma)
            } else {
                let tag = BehavioralTag(lemma: candidate.lemma, category: candidate.category,
                                        count: 1, lastSeen: .now, embedding: embedding)
                context.insert(tag)
                working.append(tag)
                assigned.insert(tag.lemma)
            }
        }
        return Array(assigned)
    }
}
