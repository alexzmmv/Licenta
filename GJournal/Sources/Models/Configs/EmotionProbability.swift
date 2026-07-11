import Foundation

struct EmotionProbability: Codable, Identifiable {
    var id: String { emotion }

    let emotion: String

    let probability: Float

    var emotionEnum: Emotion? {
        Emotion(rawValue: emotion)
    }
}
