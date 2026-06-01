//
//  LocalJournalRepository.swift
//  GJournal
//
//  Local-only repository implementation with no backend integration
//

import Foundation
import Combine
import SwiftData

class LocalJournalRepository: BaseJournalRepository {
    private var cancellables = Set<AnyCancellable>()

    /// AI processing manager for background embedding/clustering
    var aiProcessingManager: AIProcessingManager?

    init() {
        super.init(bool: false)
    }

    override func configure(with modelContext: ModelContext) {
        super.configure(with: modelContext)
        aiProcessingManager?.configure(with: modelContext)
        
        // Ensure UI stays in sync when background clustering finishes
        aiProcessingManager?.onClusteringComplete = { [weak self] in
            DispatchQueue.main.async {
                self?.loadBitsFromContext()
            }
        }
    }
    
    // MARK: - CRUD Operations

    override func createBit(title: String?, feel: String, event: String, action: String, intensity: Int) {
        guard let modelContext = modelContext else {
            errorMessage = "Data context not available"
            return
        }

        let newBit = Bit(
            id: UUID(),
            title: title,
            feel: feel,
            event: event,
            action: action,
            intensity: intensity,
            lastModified: Date(),
            createdAt: Date(),
            isHidden: false
        )

        modelContext.insert(newBit)

        do {
            try modelContext.save()
            loadBitsFromContext()
            AppLogger.log("[LocalRepository] Created micro-journal bit: \(newBit.id)")

            // Trigger background AI processing
            aiProcessingManager?.processBit(newBit)
        } catch {
            errorMessage = "Failed to save micro-journal bit: \(error.localizedDescription)"
            AppLogger.log("[LocalRepository] Failed to create micro-journal bit: \(error)")
        }
    }

    override func updateBit(id: UUID, title: String?, feel: String, event: String, action: String, intensity: Int) {
        guard let modelContext = modelContext else {
            errorMessage = "Data context not available"
            return
        }

        if let index = bits.firstIndex(where: { $0.id == id }) {
            bits[index].title = title
            bits[index].feel = feel
            bits[index].event = event
            bits[index].action = action
            bits[index].intensity = intensity
            bits[index].lastModified = Date()

            do {
                let updatedBit = bits[index]
                try modelContext.save()
                loadBitsFromContext()
                AppLogger.log("[LocalRepository] Updated micro-journal bit: \(id)")

                // Re-trigger AI processing for updated content (capture before reload)
                aiProcessingManager?.processBit(updatedBit)
            } catch {
                errorMessage = "Failed to update micro-journal bit: \(error.localizedDescription)"
                AppLogger.log("[LocalRepository] Failed to update micro-journal bit: \(error)")
            }
        } else {
            errorMessage = "Bit not found"
        }
    }
    
    // MARK: - Soft Delete

    override func deleteBit(id: UUID) {
        guard let modelContext = modelContext else {
            errorMessage = "Data context not available"
            return
        }
        
        if let index = bits.firstIndex(where: { $0.id == id }) {
            bits[index].deletedAt = Date()
            bits[index].lastModified = Date()
            
            do {
                try modelContext.save()
                loadBitsFromContext()
                AppLogger.log("[LocalRepository] Soft-deleted bit: \(id)")
            } catch {
                errorMessage = "Failed to delete bit: \(error.localizedDescription)"
                AppLogger.log("[LocalRepository] Failed to soft-delete bit: \(error)")
            }
        } else {
            errorMessage = "Bit not found"
        }
    }

    /// Restore a soft-deleted bit
    func restoreBit(id: UUID) {
        guard let modelContext = modelContext else {
            errorMessage = "Data context not available"
            return
        }

        if let index = bits.firstIndex(where: { $0.id == id }) {
            bits[index].deletedAt = nil
            bits[index].lastModified = Date()

            do {
                try modelContext.save()
                loadBitsFromContext()
                AppLogger.log("[LocalRepository] Restored bit: \(id)")
            } catch {
                errorMessage = "Failed to restore bit: \(error.localizedDescription)"
                AppLogger.log("[LocalRepository] Failed to restore bit: \(error)")
            }
        }
    }

    /// Permanently delete entries past the 3-day retention period
    func purgeExpiredBits() {
        guard let modelContext = modelContext else { return }

        let expiredBits = bits.filter { $0.isPastRetention }
        guard !expiredBits.isEmpty else { return }

        for bit in expiredBits {
            modelContext.delete(bit)
        }

        do {
            try modelContext.save()
            loadBitsFromContext()
            AppLogger.log("[LocalRepository] Purged \(expiredBits.count) expired bits")
        } catch {
            AppLogger.log("[LocalRepository] Failed to purge expired bits: \(error)")
        }
    }
    
    override func toggleHideBit(id: UUID) {
        guard let modelContext = modelContext else {
            errorMessage = "Data context not available"
            return
        }

        if let index = bits.firstIndex(where: { $0.id == id }) {
            bits[index].isHidden.toggle()
            bits[index].lastModified = Date()

            do {
                try modelContext.save()
                loadBitsFromContext()
                AppLogger.log("[LocalRepository] Toggled hide for bit: \(id)")
            } catch {
                errorMessage = "Failed to toggle bit: \(error.localizedDescription)"
                AppLogger.log("[LocalRepository] Failed to toggle bit: \(error)")
            }
        } else {
            errorMessage = "Bit not found"
        }
    }
}

// MARK: - Seed Data Generation

struct SeedDataManager {

    // MARK: - JSON model

    private struct SeedFile: Decodable {
        let entries: [SeedEntry]
    }

    private struct SeedEntry: Decodable {
        let title: String
        let feel: String
        let event: String
        let action: String
        let intensity: Int
        let daysAgo: Int
    }

    // MARK: - Loading

    @MainActor
    static func generateSeedData(context: ModelContext) {
        guard let url = Bundle.main.url(forResource: "seed_data", withExtension: "json") else {
            AppLogger.log("[SeedData] seed_data.json not found in bundle.")
            return
        }
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(SeedFile.self, from: data) else {
            AppLogger.log("[SeedData] Failed to decode seed_data.json.")
            return
        }

        let now = Date()
        let calendar = Calendar.current

        for entry in file.entries {
            let entryDate = calendar.date(byAdding: .day, value: -entry.daysAgo, to: now) ?? now
            let bit = Bit(
                id: UUID(),
                title: entry.title,
                feel: entry.feel,
                event: entry.event,
                action: entry.action,
                intensity: min(max(entry.intensity, 1), 4),
                lastModified: entryDate,
                createdAt: entryDate,
                isHidden: false
            )
            context.insert(bit)
        }

        do {
            try context.save()
            AppLogger.log("[SeedData] Inserted \(file.entries.count) unclustered entries.")
        } catch {
            AppLogger.log("[SeedData] Failed to save: \(error)")
        }
    }
}
