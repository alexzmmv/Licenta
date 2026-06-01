//
//  ClusterNamer.swift
//  GJournal
//
//  Uses Apple's NaturalLanguage framework to automatically generate 
//  descriptive names for clusters based on their contents.
//

import Foundation
import NaturalLanguage

struct ClusterNamer {
    
    /// Generates a short, descriptive name for a cluster based on the text of its bits.
    /// Extracts the most frequent nouns/verbs using NLTagger.
    static func generateName(for bits: [Bit], fallbackID: Int) -> String {
        guard !bits.isEmpty else { return "Cluster \(fallbackID)" }
        
        var combinedText = ""
        for bit in bits {
            if let title = bit.title, !title.isEmpty {
                combinedText += title + ". "
            } else {
                combinedText += bit.feel + ". "
            }
        }
        
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = combinedText
        
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        
        var wordCounts: [String: Int] = [:]
        
        tagger.enumerateTags(in: combinedText.startIndex..<combinedText.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
            if let tag = tag {
                let word = String(combinedText[tokenRange]).lowercased()
                
                // Only consider nouns or adjectives/verbs that might be descriptive
                if tag == .noun || tag == .verb || tag == .adjective {
                    // Filter out common meaningless words
                    let ignoreList = ["i", "we", "felt", "feel", "was", "is", "day", "today", "got", "went", "did"]
                    if !ignoreList.contains(word) && word.count > 2 {
                        wordCounts[word, default: 0] += 1
                    }
                }
            }
            return true
        }
        
        // Find the most frequent word
        if let topWord = wordCounts.max(by: { $0.value < $1.value })?.key {
            return topWord.capitalized
        }
        
        // If NLP fails to find a good noun, fall back to the most common emotion
        let emotionCounts = Dictionary(grouping: bits, by: { $0.emotion }).mapValues { $0.count }
        if let topEmotion = emotionCounts.max(by: { $0.value < $1.value })?.key {
            return "\(topEmotion.emoji) \(topEmotion.rawValue)"
        }
        
        return "Cluster \(fallbackID)"
    }
}
