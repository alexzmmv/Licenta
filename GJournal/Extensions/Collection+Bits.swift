import Foundation

extension Collection where Element == Bit {
    /// Most frequent emotion among elements, or nil if empty.
    var dominantEmotion: Emotion? {
        var counts: [Emotion: Int] = [:]
        forEach { counts[$0.emotion, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}

extension Cluster {
    /// Display name with a safe fallback.
    var displayName: String {
        name.isEmpty ? "Cluster \(index)" : name
    }
}
