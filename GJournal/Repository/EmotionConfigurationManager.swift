//
//  EmotionConfigurationManager.swift
//  GJournal
//
//  Created by Constantin-Alexandru Dumitrascu on 16.03.2026.
//

import Foundation
import SwiftData

@Observable
class EmotionConfigurationManager {
    private var configurationCache: EmotionConfiguration?
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadConfiguration()
    }

    // Get current configuration, create default if none exists
    func getConfiguration() -> EmotionConfiguration {
        if let cached = configurationCache {
            return cached
        }

        loadConfiguration()
        return configurationCache ?? createDefaultConfiguration()
    }

    // Load configuration from storage
    private func loadConfiguration() {
        var descriptor = FetchDescriptor<EmotionConfiguration>(
            sortBy: [SortDescriptor(\.lastModified, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        do {
            let configurations = try modelContext.fetch(descriptor)
            configurationCache = configurations.first
        } catch {
            print("Failed to load emotion configuration: \(error)")
            configurationCache = nil
        }
    }

    // Create default configuration and save it
    private func createDefaultConfiguration() -> EmotionConfiguration {
        let defaultConfig = EmotionConfiguration.defaultConfiguration

        do {
            modelContext.insert(defaultConfig)
            try modelContext.save()
            configurationCache = defaultConfig
            return defaultConfig
        } catch {
            print("Failed to create default configuration: \(error)")
            return defaultConfig
        }
    }

    // Save configuration changes
    func saveConfiguration(_ configuration: EmotionConfiguration) {
        configuration.lastModified = Date()

        do {
            try modelContext.save()
            configurationCache = configuration
        } catch {
            print("Failed to save configuration: \(error)")
        }
    }

    // Update feel emotions
    func updateFeelEmotions(_ emotions: [Emotion]) {
        let config = getConfiguration()
        config.feelEmotions = emotions
        saveConfiguration(config)
    }

    // Update event emotions
    func updateEventEmotions(_ emotions: [Emotion]) {
        let config = getConfiguration()
        config.eventEmotions = emotions
        saveConfiguration(config)
    }

    // Update action emotions
    func updateActionEmotions(_ emotions: [Emotion]) {
        let config = getConfiguration()
        config.actionEmotions = emotions
        saveConfiguration(config)
    }

    // Get emotions for specific field type
    func getEmotionsForField(_ fieldType: MicroJournalFieldType) -> [Emotion] {
        let config = getConfiguration()

        switch fieldType {
        case .feel:
            return config.feelEmotions
        case .event:
            return config.eventEmotions
        case .action:
            return config.actionEmotions
        }
    }

    // Reset to default configuration
    func resetToDefaults() {
        let config = getConfiguration()
        config.feelEmotions = Emotion.defaultFeelEmotions
        config.eventEmotions = Emotion.defaultEventEmotions
        config.actionEmotions = Emotion.defaultActionEmotions
        saveConfiguration(config)
    }
}

// Enum to represent field types
enum MicroJournalFieldType: CaseIterable {
    case feel
    case event
    case action

    var displayName: String {
        switch self {
        case .feel:
            return "Feel"
        case .event:
            return "Event"
        case .action:
            return "Action"
        }
    }
}