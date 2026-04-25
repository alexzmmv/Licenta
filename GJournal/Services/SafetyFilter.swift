//
//  SafetyFilter.swift
//  GJournal
//
//  On-device keyword-based safety filter for detecting harmful,
//  illegal, or unsafe content in journal entries.
//  Prevents recommendations based on flagged content.
//

import Foundation

/// Keyword-based on-device safety filter.
///
/// This filter checks journal entries for harmful, illegal, or unsafe content
/// patterns. It does NOT prevent the user from saving entries — it flags them
/// so the clustering/recommendation engine can exclude them from pattern
/// detection and suggestions.
///
/// Uses Apple's NaturalLanguage framework concepts but implements a lightweight
/// keyword/pattern approach suitable for on-device processing.
final class SafetyFilter: SafetyFilterServiceProtocol {

    // MARK: - Harmful Content Categories

    /// Categories of content that should be flagged
    private enum ContentCategory: String {
        case selfHarm = "self-harm"
        case violence = "violence"
        case illegalActivity = "illegal-activity"
        case exploitation = "exploitation"
    }

    /// Patterns associated with each category.
    /// These are simplified keyword sets — in production, a trained NLP classifier
    /// would be used instead.
    private let flaggedPatterns: [ContentCategory: [String]] = [
        .selfHarm: [
            "kill myself", "end my life", "suicide plan", "want to die",
            "self harm", "self-harm", "cut myself", "hurt myself"
        ],
        .violence: [
            "kill someone", "murder", "assault plan", "bomb threat",
            "mass shooting", "attack plan", "hurt them"
        ],
        .illegalActivity: [
            "sell drugs", "drug deal", "trafficking", "launder money",
            "child abuse", "exploit children"
        ],
        .exploitation: [
            "exploit", "blackmail plan", "extortion plan"
        ]
    ]

    // MARK: - SafetyFilterServiceProtocol

    func checkSafety(_ text: String) -> SafetyResult {
        let lowered = text.lowercased()

        for (category, patterns) in flaggedPatterns {
            for pattern in patterns {
                if lowered.contains(pattern) {
                    return SafetyResult(
                        isSafe: false,
                        reason: "Content flagged for \(category.rawValue) indicators. Entry saved but excluded from pattern recommendations."
                    )
                }
            }
        }

        return .safe
    }
}
