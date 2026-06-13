import Foundation
class SafetyFilter: SafetyFilterServiceProtocol {

    // MARK: - Harmful Content Categories

    private enum ContentCategory: String {
        case selfHarm = "self-harm"
        case violence = "violence"
        case illegalActivity = "illegal-activity"
        case exploitation = "exploitation"
    }

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
