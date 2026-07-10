import Foundation
import SwiftData

@Model
final class Bit {
    @Attribute(.unique) var id: UUID
    var title: String?

    var feel: String
    var event: String
    var action: String

    var intensity: Int
    var lastModified: Date
    var createdAt: Date
    var isHidden: Bool

    // MARK: - Soft Delete

    var deletedAt: Date?

    private static let retentionPeriod: TimeInterval = 3 * 24 * 60 * 60

    var isDeleted: Bool {
        deletedAt != nil
    }

    var isPastRetention: Bool {
        guard let deletedAt = deletedAt else { return false }
        return Date().timeIntervalSince(deletedAt) > Bit.retentionPeriod
    }

    var retentionHoursRemaining: Int? {
        guard let deletedAt = deletedAt else { return nil }
        let elapsed = Date().timeIntervalSince(deletedAt)
        let remaining = Bit.retentionPeriod - elapsed
        return max(0, Int(remaining / 3600))
    }

    // MARK: - AI Pipeline Fields

    var embeddingData: Data?

    var emotionProbabilitiesData: Data?

    var cluster: Cluster?
    
    var clusterID: Int? {
        cluster?.index
    }

    var flattenedText: String?

    var isSafeContent: Bool = true

    var embeddingGeneratedAt: Date?

    var clusterAssignedAt: Date?

    /// Canonical behavioral-tag lemmas assigned to this entry (denormalized; the canonical
    /// registry lives in `BehavioralTag`). JSON-encoded for a purely additive migration.
    var tagLemmasData: Data?

    // MARK: - Graph Layout Cache

    var graphX: Double?

    var graphY: Double?

    // MARK: - Computed Properties for AI Data

    var embedding: [Float]? {
        get {
            guard let data = embeddingData, !data.isEmpty else { return nil }
            guard data.count % MemoryLayout<Float>.size == 0 else { return nil }
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
        set {
            embeddingData = newValue?.withUnsafeBytes { Data($0) }
        }
    }

    private static let jsonDecoder = JSONDecoder()
    private static let jsonEncoder = JSONEncoder()

    var emotionProbabilities: [String: Float]? {
        get {
            guard let data = emotionProbabilitiesData else { return nil }
            return try? Self.jsonDecoder.decode([String: Float].self, from: data)
        }
        set {
            emotionProbabilitiesData = newValue.flatMap { try? Self.jsonEncoder.encode($0) }
        }
    }

    var tagLemmas: [String] {
        get {
            guard let data = tagLemmasData else { return [] }
            return (try? Self.jsonDecoder.decode([String].self, from: data)) ?? []
        }
        set {
            tagLemmasData = newValue.isEmpty ? nil : try? Self.jsonEncoder.encode(newValue)
        }
    }

    var topDetectedEmotion: Emotion? {
        guard let probs = emotionProbabilities,
              let topKey = probs.max(by: { $0.value < $1.value })?.key else { return nil }
        return Emotion(rawValue: topKey)
    }

    var emotion: Emotion {
        topDetectedEmotion ?? .joy
    }

    var hasBeenProcessed: Bool {
        embeddingGeneratedAt != nil
    }

    // MARK: - Initializer

    init(id: UUID = UUID(), title: String? = nil, feel: String = "", event: String = "", action: String = "", intensity: Int = 1, lastModified: Date = Date(), createdAt: Date = Date(), isHidden: Bool = false) {
        self.id = id
        self.title = title
        self.feel = feel
        self.event = event
        self.action = action
        self.intensity = min(max(intensity, 1), 4) // Clamp between 1-4
        self.lastModified = lastModified
        self.createdAt = createdAt
        self.isHidden = isHidden

        self.isSafeContent = true
    }
}
