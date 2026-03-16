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
    var text: String
    var emotionRawValue: String  // Store enum as String
    var intensity: Int // 1-4
    var lastModified: Date
    var createdAt: Date
    var isHidden: Bool
    
    // Computed property for emotion
    var emotion: Emotion {
        get { Emotion(rawValue: emotionRawValue) ?? .joy }
        set { emotionRawValue = newValue.rawValue }
    }
    
    init(id: UUID = UUID(), serverId: Int? = nil, title: String? = nil, text: String, emotion: Emotion, intensity: Int, lastModified: Date = Date(), createdAt: Date = Date(), isHidden: Bool = false) {
        self.id = id
        self.serverId = serverId
        self.title = title
        self.text = text
        self.emotionRawValue = emotion.rawValue
        self.intensity = min(max(intensity, 1), 4) // Clamp between 1-4
        self.lastModified = lastModified
        self.createdAt = createdAt
        self.isHidden = isHidden
    }
}
