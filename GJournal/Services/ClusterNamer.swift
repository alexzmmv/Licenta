//
//  ClusterNamer.swift
//  GJournal
//
//  Generates evocative, introspective names for entry clusters.
//
//  Uses TF-IDF scoring to surface words that are distinctive within a
//  cluster versus the broader journal, producing names that help users
//  recognise emotional and thematic patterns in their entries.
//

import Foundation
import NaturalLanguage

struct ClusterNamer {

    // MARK: - Public API

    /// Generates a short, evocative name for a cluster based on its entries.
    ///
    /// Strategy:
    ///  1. Extract nouns, verbs, and adjectives from cluster titles and feel text.
    ///  2. Score each word by TF-IDF: high frequency *within* this cluster,
    ///     low frequency across all entries — surfaces what makes this cluster unique.
    ///  3. Pick the top 2 distinctive words and combine them into a compact phrase.
    ///  4. If NLP extraction fails, fall back to the dominant emotion.
    ///
    /// - Parameters:
    ///   - bits: The journal entries in this cluster.
    ///   - allBits: All journal entries (for IDF computation). Pass nil to skip TF-IDF and use frequency.
    ///   - fallbackID: Numeric cluster ID for last-resort naming.
    /// - Returns: A human-readable cluster name (2–4 words).
    static func generateName(for bits: [Bit], allBits: [Bit]? = nil, fallbackID: Int) -> String {
        guard !bits.isEmpty else { return "Cluster \(fallbackID)" }

        // Build text from titles + feel (the most introspective fields)
        let clusterWords = extractScoredWords(from: bits)
        guard !clusterWords.isEmpty else {
            return emotionFallbackName(for: bits, fallbackID: fallbackID)
        }

        // If we have the full corpus, apply TF-IDF to find distinctive words
        let topWords: [String]
        if let allBits = allBits, !allBits.isEmpty {
            topWords = tfidfTopWords(clusterWords: clusterWords, allBits: allBits, limit: 2)
        } else {
            // Fall back to frequency-based selection
            topWords = Array(
                clusterWords.sorted { $0.value > $1.value }
                    .prefix(2)
                    .map { $0.key }
            )
        }

        guard !topWords.isEmpty else {
            return emotionFallbackName(for: bits, fallbackID: fallbackID)
        }

        // Capitalise and combine
        let name = topWords.map { $0.capitalized }.joined(separator: " & ")
        return name
    }

    // MARK: - Word Extraction

    /// Extracts meaningful words from cluster entries with frequency counts.
    private static func extractScoredWords(from bits: [Bit]) -> [String: Int] {
        // Combine title + feel for each bit — these are the most introspective fields
        var combinedText = ""
        for bit in bits {
            if let title = bit.title, !title.isEmpty {
                combinedText += title + ". "
            }
            if !bit.feel.isEmpty {
                combinedText += bit.feel + ". "
            }
        }

        return extractWords(from: combinedText)
    }

    /// Uses NLTagger to extract nouns, verbs, and adjectives with frequency counts.
    private static func extractWords(from text: String) -> [String: Int] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        var wordCounts: [String: Int] = [:]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: options
        ) { tag, tokenRange in
            if let tag = tag {
                let word = String(text[tokenRange]).lowercased()

                if (tag == .noun || tag == .verb || tag == .adjective),
                   !stopWords.contains(word),
                   word.count > 2 {
                    wordCounts[word, default: 0] += 1
                }
            }
            return true
        }

        return wordCounts
    }

    // MARK: - TF-IDF Scoring

    /// Returns the top `limit` words by TF-IDF score — words that are frequent
    /// in *this* cluster but rare across *all* entries.
    private static func tfidfTopWords(
        clusterWords: [String: Int],
        allBits: [Bit],
        limit: Int
    ) -> [String] {
        // Build document frequency: how many entries contain each word
        var docFrequency: [String: Int] = [:]
        let totalDocs = allBits.count

        for bit in allBits {
            var text = ""
            if let title = bit.title { text += title + " " }
            text += bit.feel
            let words = Set(extractWords(from: text).keys)
            for word in words {
                docFrequency[word, default: 0] += 1
            }
        }

        // Compute TF-IDF for each cluster word
        let totalClusterWords = clusterWords.values.reduce(0, +)
        guard totalClusterWords > 0 else { return [] }

        var scored: [(word: String, tfidf: Double)] = []
        for (word, count) in clusterWords {
            let tf = Double(count) / Double(totalClusterWords)
            let df = docFrequency[word, default: 1]
            let idf = log(Double(totalDocs + 1) / Double(df + 1)) + 1.0
            scored.append((word, tf * idf))
        }

        return scored
            .sorted { $0.tfidf > $1.tfidf }
            .prefix(limit)
            .map { $0.word }
    }

    // MARK: - Fallback

    /// Generates a name from the dominant emotion when NLP extraction fails.
    private static func emotionFallbackName(for bits: [Bit], fallbackID: Int) -> String {
        let emotionCounts = Dictionary(grouping: bits, by: { $0.emotion }).mapValues { $0.count }
        if let topEmotion = emotionCounts.max(by: { $0.value < $1.value })?.key {
            return "\(topEmotion.emoji) \(topEmotion.rawValue)"
        }
        return "Thread \(fallbackID + 1)"
    }

    // MARK: - Stop Words

    /// Words to ignore during extraction — common journal/English filler words
    /// that don't contribute to meaningful cluster names.
    private static let stopWords: Set<String> = [
        // Pronouns and basic verbs
        "i", "we", "he", "she", "they", "me", "my", "you", "your", "our",
        "was", "is", "are", "am", "were", "be", "been", "being",
        "have", "has", "had", "having",
        "do", "does", "did", "done",
        "get", "got", "gets", "getting",
        "go", "went", "gone", "going",
        "can", "could", "would", "should", "will", "may", "might",
        // Common journal filler
        "felt", "feel", "feeling", "feelings",
        "like", "just", "really", "think", "thought", "know", "knew",
        "want", "wanted", "need", "needed",
        "said", "told", "asked", "made", "let", "put", "take", "took",
        "thing", "things", "something", "anything", "everything", "nothing",
        "way", "time", "times", "today", "day", "days", "week", "month",
        "lot", "much", "many", "bit", "little", "big",
        "good", "bad", "new", "old", "last", "first", "whole",
        "even", "still", "also", "back", "now", "then", "ago",
        "one", "two", "the", "not", "but", "and", "that", "this",
        "out", "about", "into", "over", "than", "other",
        "try", "tried", "start", "started", "keep", "kept",
        "come", "came", "give", "gave", "see", "saw", "seem",
        "right", "long", "own", "same", "sure"
    ]
}
