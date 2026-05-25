//
//  Bit.swift
//  GJournal
//
//  Created by Constantin-Alexandru Dumitrascu on 21.10.2025.
//

import Foundation
import SwiftData

@Model
final class Bit {
    @Attribute(.unique) var id: UUID
    var title: String?

    // Micro-journaling fields: Feel, Event, Action
    var feel: String
    var event: String
    var action: String

    // Individual emotions for each field
    var feelEmotionRawValue: String
    var eventEmotionRawValue: String
    var actionEmotionRawValue: String

    var intensity: Int // 1-4
    var lastModified: Date
    var createdAt: Date
    var isHidden: Bool

    // MARK: - Soft Delete

    /// When the entry was soft-deleted (nil = not deleted)
    var deletedAt: Date?

    /// 3-day retention period before permanent deletion (in seconds)
    private static let retentionPeriod: TimeInterval = 3 * 24 * 60 * 60

    /// Whether this entry is soft-deleted
    var isDeleted: Bool {
        deletedAt != nil
    }

    /// Whether this entry is past the retention period and can be permanently removed
    var isPastRetention: Bool {
        guard let deletedAt = deletedAt else { return false }
        return Date().timeIntervalSince(deletedAt) > Bit.retentionPeriod
    }

    /// Number of hours remaining before permanent deletion
    var retentionHoursRemaining: Int? {
        guard let deletedAt = deletedAt else { return nil }
        let elapsed = Date().timeIntervalSince(deletedAt)
        let remaining = Bit.retentionPeriod - elapsed
        return max(0, Int(remaining / 3600))
    }

    // MARK: - AI Pipeline Fields

    /// Embedding vector stored as raw IEEE-754 Float bytes (50x faster than JSON decode)
    var embeddingData: Data?

    /// AI-detected emotion probabilities stored as JSON Data ([String: Float])
    var emotionProbabilitiesData: Data?

    /// Relationship to the cluster this bit belongs to
    var cluster: Cluster?
    
    /// Backward compatibility for clustering logic
    var clusterID: Int? {
        cluster?.id
    }

    /// Combined text used for embedding generation
    var flattenedText: String?

    /// Whether content passed the safety filter
    var isSafeContent: Bool = true

    /// When the embedding was generated
    var embeddingGeneratedAt: Date?

    /// When the cluster was last assigned
    var clusterAssignedAt: Date?

    // MARK: - Graph Layout Cache

    /// Cached X position in the knowledge graph (avoids re-simulation on reopen)
    var graphX: Double?

    /// Cached Y position in the knowledge graph
    var graphY: Double?

    // MARK: - Typed Wrappers for Per-Field Emotion Raw Values

    var feelEmotion: Emotion {
        get { Emotion(rawValue: feelEmotionRawValue) ?? .joy }
        set { feelEmotionRawValue = newValue.rawValue }
    }

    var eventEmotion: Emotion {
        get { Emotion(rawValue: eventEmotionRawValue) ?? .joy }
        set { eventEmotionRawValue = newValue.rawValue }
    }

    var actionEmotion: Emotion {
        get { Emotion(rawValue: actionEmotionRawValue) ?? .joy }
        set { actionEmotionRawValue = newValue.rawValue }
    }

    // MARK: - Computed Properties for AI Data

    /// Typed access to the embedding vector — raw binary Float storage (see 04_UI_PERFORMANCE.md §3)
    var embedding: [Float]? {
        get {
            guard let data = embeddingData else { return nil }
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
        set {
            embeddingData = newValue?.withUnsafeBytes { Data($0) }
        }
    }

    /// Typed access to emotion probabilities dictionary
    var emotionProbabilities: [String: Float]? {
        get {
            guard let data = emotionProbabilitiesData else { return nil }
            return try? JSONDecoder().decode([String: Float].self, from: data)
        }
        set {
            emotionProbabilitiesData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    /// Top AI-detected emotion (highest probability). Falls back to .joy for unprocessed entries.
    var topDetectedEmotion: Emotion? {
        guard let probs = emotionProbabilities,
              let topKey = probs.max(by: { $0.value < $1.value })?.key else { return nil }
        return Emotion(rawValue: topKey)
    }

    /// Primary emotion for UI display — AI-detected when available, .joy otherwise
    var emotion: Emotion {
        topDetectedEmotion ?? .joy
    }

    /// Whether this bit has been processed by the AI pipeline
    var hasBeenProcessed: Bool {
        embeddingGeneratedAt != nil
    }

    // MARK: - Initializer

    init(id: UUID = UUID(), title: String? = nil, feel: String = "", event: String = "", action: String = "", feelEmotion: Emotion = .joy, eventEmotion: Emotion = .joy, actionEmotion: Emotion = .joy, intensity: Int = 1, lastModified: Date = Date(), createdAt: Date = Date(), isHidden: Bool = false) {
        self.id = id
        self.title = title

        // Micro-journaling fields
        self.feel = feel
        self.event = event
        self.action = action

        // Individual emotions
        self.feelEmotionRawValue = feelEmotion.rawValue
        self.eventEmotionRawValue = eventEmotion.rawValue
        self.actionEmotionRawValue = actionEmotion.rawValue

        self.intensity = min(max(intensity, 1), 4) // Clamp between 1-4
        self.lastModified = lastModified
        self.createdAt = createdAt
        self.isHidden = isHidden

        // AI fields default to nil/true
        self.isSafeContent = true
    }
}
