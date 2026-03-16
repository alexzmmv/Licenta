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
    
    override func createBit(title: String?, text: String, emotion: Emotion, intensity: Int) {
        guard let modelContext = modelContext else {
            errorMessage = "Data context not available"
            return
        }
        
        let newBit = Bit(
            id: UUID(),
            serverId: nil,
            title: title,
            text: text,
            emotion: emotion,
            intensity: intensity,
            lastModified: Date(),
            createdAt: Date(),
            isHidden: false
        )
        
        modelContext.insert(newBit)
        
        do {
            try modelContext.save()
            bits.append(newBit)
            print("[LocalRepository] Created bit: \(newBit.id)")
        } catch {
            errorMessage = "Failed to save bit: \(error.localizedDescription)"
            print("[LocalRepository] Failed to create bit: \(error)")
        }
    }
    
    override func updateBit(id: UUID, title: String?, text: String, emotion: Emotion, intensity: Int) {
        guard let modelContext = modelContext else {
            errorMessage = "Data context not available"
            return
        }
        
        if let index = bits.firstIndex(where: { $0.id == id }) {
            bits[index].title = title
            bits[index].text = text
            bits[index].emotion = emotion
            bits[index].intensity = intensity
            bits[index].lastModified = Date()
            
            do {
                try modelContext.save()
                print("[LocalRepository] Updated bit: \(id)")
            } catch {
                errorMessage = "Failed to update bit: \(error.localizedDescription)"
                print("[LocalRepository] Failed to update bit: \(error)")
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
