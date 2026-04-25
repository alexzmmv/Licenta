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

    override func createBit(title: String?, feel: String, event: String, action: String, feelEmotion: Emotion, eventEmotion: Emotion, actionEmotion: Emotion, intensity: Int) {
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
            feelEmotion: feelEmotion,
            eventEmotion: eventEmotion,
            actionEmotion: actionEmotion,
            intensity: intensity,
            lastModified: Date(),
            createdAt: Date(),
            isHidden: false
        )

        modelContext.insert(newBit)

        do {
            try modelContext.save()
            loadBitsFromContext()
            print("[LocalRepository] Created micro-journal bit: \(newBit.id)")

            // Trigger background AI processing
            aiProcessingManager?.processBit(newBit)
        } catch {
            errorMessage = "Failed to save micro-journal bit: \(error.localizedDescription)"
            print("[LocalRepository] Failed to create micro-journal bit: \(error)")
        }
    }

    override func updateBit(id: UUID, title: String?, feel: String, event: String, action: String, feelEmotion: Emotion, eventEmotion: Emotion, actionEmotion: Emotion, intensity: Int) {
        guard let modelContext = modelContext else {
            errorMessage = "Data context not available"
            return
        }

        if let index = bits.firstIndex(where: { $0.id == id }) {
            bits[index].title = title
            bits[index].feel = feel
            bits[index].event = event
            bits[index].action = action
            bits[index].feelEmotion = feelEmotion
            bits[index].eventEmotion = eventEmotion
            bits[index].actionEmotion = actionEmotion
            bits[index].intensity = intensity
            bits[index].lastModified = Date()

            do {
                try modelContext.save()
                loadBitsFromContext()
                print("[LocalRepository] Updated micro-journal bit: \(id)")

                // Re-trigger AI processing for updated content
                aiProcessingManager?.processBit(bits[index])
            } catch {
                errorMessage = "Failed to update micro-journal bit: \(error.localizedDescription)"
                print("[LocalRepository] Failed to update micro-journal bit: \(error)")
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
                print("[LocalRepository] Soft-deleted bit: \(id)")
            } catch {
                errorMessage = "Failed to delete bit: \(error.localizedDescription)"
                print("[LocalRepository] Failed to soft-delete bit: \(error)")
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
                print("[LocalRepository] Restored bit: \(id)")
            } catch {
                errorMessage = "Failed to restore bit: \(error.localizedDescription)"
                print("[LocalRepository] Failed to restore bit: \(error)")
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
            print("[LocalRepository] Purged \(expiredBits.count) expired bits")
        } catch {
            print("[LocalRepository] Failed to purge expired bits: \(error)")
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
                print("[LocalRepository] Toggled hide for bit: \(id)")
            } catch {
                errorMessage = "Failed to toggle bit: \(error.localizedDescription)"
                print("[LocalRepository] Failed to toggle bit: \(error)")
            }
        } else {
            errorMessage = "Bit not found"
        }
    }
}

// MARK: - Seed Data Generation

struct SeedDataManager {
    
    /// Generates seed data for testing
    @MainActor
    static func generateSeedData(context: ModelContext) {
        let now = Date()
        let calendar = Calendar.current
        
        // Define some realistic-looking journal entries
        let seedEntries: [(title: String, feel: String, event: String, action: String, emotion: Emotion, intensity: Int, daysAgo: Int, clusterID: Int?)] = [
            // Cluster 0: Work/Productivity
            ("Productive Day", "Felt really accomplished today", "Finished the big project", "Treated myself to coffee", .joy, 3, 0, 0),
            ("Flow State", "Was super focused", "Coding for 4 hours straight", "Took a short walk", .excitement, 4, 1, 0),
            ("Getting things done", "Productive but tiring", "Cleared my inbox", "Went to bed early", .hope, 2, 3, 0),
            
            // Cluster 1: Social/Friends
            ("Catching up", "Happy to see old friends", "Met Sarah for lunch", "Talked for hours", .joy, 4, 2, 1),
            ("Party", "A bit overwhelmed but fun", "Went to Dave's birthday", "Danced a lot", .excitement, 3, 5, 1),
            ("Coffee date", "Felt connected", "Deep conversation", "Agreed to meet again", .love, 3, 6, 1),
            
            // Cluster 2: Stress/Anxiety
            ("Anxious morning", "Woke up feeling tight in my chest", "Thinking about deadlines", "Did breathing exercises", .anxiety, 4, 4, 2),
            ("Overwhelmed", "Too much to do", "Struggled to focus", "Took a break", .fear, 3, 7, 2),
            ("Stressful meeting", "Frustrated and tense", "Client was difficult", "Vented to a coworker", .anger, 3, 8, 2),
            
            // Unclustered / Noise
            ("Quiet evening", "Peaceful and calm", "Read a book", "Made tea", .gratitude, 2, 1, -1),
            ("Random thoughts", "Feeling okay", "Just doing chores", "Cleaned the house", .joy, 1, 3, -1),
            ("Sad movie", "Felt a bit melancholic", "Watched a drama", "Cried a little", .sadness, 2, 5, -1),
            ("Surprise gift", "Very surprised!", "Got a package", "Called to say thanks", .surprise, 4, 9, -1)
        ]
        
        for entry in seedEntries {
            let entryDate = calendar.date(byAdding: .day, value: -entry.daysAgo, to: now) ?? now
            
            let bit = Bit(
                id: UUID(),
                title: entry.title,
                feel: entry.feel,
                event: entry.event,
                action: entry.action,
                feelEmotion: entry.emotion,
                eventEmotion: entry.emotion,
                actionEmotion: entry.emotion,
                intensity: entry.intensity,
                lastModified: entryDate,
                createdAt: entryDate,
                isHidden: false
            )
            
            // Assign mock AI data directly for testing the graph
            if let cid = entry.clusterID, cid != -1 {
                // Find or create the cluster object
                let cluster: Cluster
                let fetchDescriptor = FetchDescriptor<Cluster>(predicate: #Predicate { $0.id == cid })
                if let existing = try? context.fetch(fetchDescriptor).first {
                    cluster = existing
                } else {
                    let name: String
                    switch cid {
                    case 0: name = "Work & Productivity"
                    case 1: name = "Social Life"
                    case 2: name = "Personal Growth"
                    default: name = "Cluster \(cid)"
                    }
                    cluster = Cluster(id: cid, name: name, createdAt: entryDate)
                    context.insert(cluster)
                }
                bit.cluster = cluster
            }
            
            bit.embeddingGeneratedAt = entryDate
            bit.clusterAssignedAt = entryDate
            
            // Generate a random vector just so it's not empty
            bit.embedding = (0..<768).map { _ in Float.random(in: -1...1) }
            
            context.insert(bit)
        }
        
        do {
            try context.save()
            print("[SeedData] Generated \(seedEntries.count) seed bits with relational clusters.")
        } catch {
            print("[SeedData] Failed to save seed data: \(error)")
        }
    }
}
