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
    
    init() {
        super.init(bool: false)
    }
    
    override func configure(with modelContext: ModelContext) {
        super.configure(with: modelContext)
    }
    
    // MARK: - CRUD Operations

    override func createBit(title: String?, feel: String, event: String, action: String, feelEmotion: Emotion, eventEmotion: Emotion, actionEmotion: Emotion, intensity: Int) {
        guard let modelContext = modelContext else {
            errorMessage = "Data context not available"
            return
        }

        let newBit = Bit(
            id: UUID(),
            serverId: nil,
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
            bits.append(newBit)
            print("[LocalRepository] Created micro-journal bit: \(newBit.id)")
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
                print("[LocalRepository] Updated micro-journal bit: \(id)")
            } catch {
                errorMessage = "Failed to update micro-journal bit: \(error.localizedDescription)"
                print("[LocalRepository] Failed to update micro-journal bit: \(error)")
            }
        } else {
            errorMessage = "Bit not found"
        }
    }
    
    override func deleteBit(id: UUID) {
        guard let modelContext = modelContext else {
            errorMessage = "Data context not available"
            return
        }
        
        if let index = bits.firstIndex(where: { $0.id == id }) {
            let bit = bits.remove(at: index)
            modelContext.delete(bit)
            
            do {
                try modelContext.save()
                print("[LocalRepository] Deleted bit: \(id)")
            } catch {
                errorMessage = "Failed to delete bit: \(error.localizedDescription)"
                print("[LocalRepository] Failed to delete bit: \(error)")
            }
        } else {
            errorMessage = "Bit not found"
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
