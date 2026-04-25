//
//  EmotionProbability.swift
//  GJournal
//
//  Model for AI-detected emotion probabilities.
//

import Foundation

/// Represents a detected emotion with its confidence probability.
struct EmotionProbability: Codable, Identifiable {
    var id: String { emotion }

    /// The emotion label (matches Emotion.rawValue)
    let emotion: String

    /// Confidence probability between 0.0 and 1.0
    let probability: Float

    /// Convenience: convert to the Emotion enum if the label matches
    var emotionEnum: Emotion? {
        Emotion(rawValue: emotion)
    }
}
