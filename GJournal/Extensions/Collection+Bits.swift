import Foundation

extension Collection where Element == Bit {
    var dominantEmotion: Emotion? {
        var counts: [Emotion: Int] = [:]
        forEach { counts[$0.emotion, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}

extension Cluster {
    var displayName: String {
        name.isEmpty ? "Cluster \(index)" : name
    }
}
