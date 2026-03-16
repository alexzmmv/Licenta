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
    var serverId: Int?  // Server-managed ID
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

    // Computed properties for emotions
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

    // Primary emotion (based on feel emotion for UI compatibility)
    var emotion: Emotion {
        return feelEmotion
    }

    init(id: UUID = UUID(), serverId: Int? = nil, title: String? = nil, feel: String = "", event: String = "", action: String = "", feelEmotion: Emotion = .joy, eventEmotion: Emotion = .joy, actionEmotion: Emotion = .joy, intensity: Int = 1, lastModified: Date = Date(), createdAt: Date = Date(), isHidden: Bool = false) {
        self.id = id
        self.serverId = serverId
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
    }
}
