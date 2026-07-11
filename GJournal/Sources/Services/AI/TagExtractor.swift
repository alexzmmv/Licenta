import Foundation
import NaturalLanguage

/// Behavioral-tag category (plan §2.0): nouns describe *events*, verbs describe *actions*.
enum TagCategory: String, Codable, Sendable {
    case event
    case action
}

/// A candidate behavioral tag extracted from an entry, before canonicalization.
struct CandidateTag: Equatable, Sendable {
    let lemma: String
    let category: TagCategory
}

/// Extracts behavioral tags from journal text (NLTagger lemma+POS) and canonicalizes them
/// against existing tags by embedding cosine similarity. Feeds the GGM (each tag becomes a
/// binary variable at ≥5 occurrences).
enum TagExtractor {

    /// New candidate merges into an existing tag at cosine ≥ this, else creates a new tag.
    static let mergeThreshold: Float = 0.85

    // MARK: - Extraction

    /// Content words from the Event field become event tags, those from the Action field become
    /// action tags. Tokenization (NLTokenizer) is always available on-device; lemmatization
    /// (NLTagger `.lemma`) is applied when the language model is present (real devices) and falls
    /// back to the surface form otherwise — inflections still coalesce later via embedding-cosine
    /// canonicalization. Stopwords and short/non-alphabetic tokens are dropped; lemmas de-duped
    /// across both fields (event wins ties).
    static func extract(event: String, action: String) -> [CandidateTag] {
        var seen = Set<String>()
        var result: [CandidateTag] = []
        for (text, category) in [(event, TagCategory.event), (action, TagCategory.action)] {
            for lemma in contentLemmas(in: text) where seen.insert(lemma).inserted {
                result.append(CandidateTag(lemma: lemma, category: category))
            }
        }
        return result
    }

    private static func contentLemmas(in text: String) -> [String] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        let lemmatizer = NLTagger(tagSchemes: [.lemma])
        lemmatizer.string = text

        var out: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let surface = String(text[range]).lowercased()
            guard surface.count > 2,
                  surface.allSatisfy({ $0.isLetter }),
                  !stopWords.contains(surface) else { return true }

            let lemmaRaw = lemmatizer.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
            let lemma = (lemmaRaw.flatMap { $0.isEmpty ? nil : $0 } ?? surface).lowercased()

            guard !stopWords.contains(lemma) else { return true }
            out.append(lemma)
            return true
        }
        return out
    }

    // MARK: - Canonicalization

    /// Index of the most-similar existing tag if its cosine ≥ threshold, else nil (→ create new).
    static func matchIndex(candidate: [Float], existing: [[Float]], threshold: Float = mergeThreshold) -> Int? {
        guard !existing.isEmpty else { return nil }
        var bestIndex = -1
        var bestSim: Float = -Float.greatestFiniteMagnitude
        for (i, e) in existing.enumerated() {
            let sim = cosineSimilarity(candidate, e)
            if sim > bestSim { bestSim = sim; bestIndex = i }
        }
        return bestSim >= threshold ? bestIndex : nil
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = (na * nb).squareRoot()
        return denom > 0 ? dot / denom : 0
    }

    // MARK: - Stopwords

    private static let stopWords: Set<String> = [
        // function words (>2 chars survive the length filter, so must be listed)
        "the", "and", "but", "for", "not", "with", "from", "into", "onto", "over",
        "under", "about", "after", "before", "while", "when", "where", "which",
        "what", "who", "whom", "this", "that", "these", "those", "they", "them",
        "their", "there", "then", "than", "your", "you", "our", "ours", "its",
        "his", "her", "him", "she", "was", "were", "are", "been", "being", "have",
        "has", "had", "will", "would", "could", "should", "can", "may", "might",
        "did", "does", "get", "got", "went", "gone", "come", "came", "make", "made",
        "very", "just", "also", "even", "only", "some", "any", "all", "each", "how",
        // journal/time filler
        "day", "days", "time", "week", "month", "year", "thing", "things", "lot",
        "way", "bit", "today", "yesterday", "tomorrow", "morning", "night",
        "feel", "felt", "feeling", "think", "thought", "know", "knew", "want",
        "need", "like", "said", "told", "asked", "put", "take", "took", "give",
        "let", "try", "keep", "start", "look", "see", "saw", "use", "work",
        "people", "person", "guy", "someone", "something", "everything", "nothing",
        "self", "one", "two", "back", "part", "kind", "sort", "point", "case"
    ]
}
