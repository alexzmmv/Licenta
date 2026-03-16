//
//  EmotionConfiguration.swift
//  GJournal
//
//  Created by Constantin-Alexandru Dumitrascu on 16.03.2026.
//

import Foundation
import SwiftData

@Model
final class EmotionConfiguration {
    @Attribute(.unique) var id: UUID
    var feelEmotionsRawValues: [String]
    var eventEmotionsRawValues: [String]
    var actionEmotionsRawValues: [String]
    var lastModified: Date

    // Computed properties for emotions
    var feelEmotions: [Emotion] {
        get {
            feelEmotionsRawValues.compactMap { Emotion(rawValue: $0) }
        }
        set {
            feelEmotionsRawValues = newValue.map { $0.rawValue }
        }
    }

    var eventEmotions: [Emotion] {
        get {
            eventEmotionsRawValues.compactMap { Emotion(rawValue: $0) }
        }
        set {
            eventEmotionsRawValues = newValue.map { $0.rawValue }
        }
    }

    var actionEmotions: [Emotion] {
        get {
            actionEmotionsRawValues.compactMap { Emotion(rawValue: $0) }
        }
        set {
            actionEmotionsRawValues = newValue.map { $0.rawValue }
        }
    }

    init(id: UUID = UUID(), feelEmotions: [Emotion] = Emotion.defaultFeelEmotions, eventEmotions: [Emotion] = Emotion.defaultEventEmotions, actionEmotions: [Emotion] = Emotion.defaultActionEmotions) {
        self.id = id
        self.feelEmotionsRawValues = feelEmotions.map { $0.rawValue }
        self.eventEmotionsRawValues = eventEmotions.map { $0.rawValue }
        self.actionEmotionsRawValues = actionEmotions.map { $0.rawValue }
        self.lastModified = Date()
    }

    // Default configuration
    static var defaultConfiguration: EmotionConfiguration {
        return EmotionConfiguration()
    }
}

// Extension to provide default emotion sets
extension Emotion {
    static let defaultFeelEmotions: [Emotion] = [
        .joy, .sadness, .anger, .fear, .love, .anxiety, .excitement, .gratitude, .hope, .guilt
    ]

    static let defaultEventEmotions: [Emotion] = [
        .surprise, .joy, .anxiety, .excitement, .anger, .sadness, .fear, .hope
    ]

    static let defaultActionEmotions: [Emotion] = [
        .hope, .joy, .gratitude, .excitement, .love, .anxiety, .anger, .guilt
    ]
}