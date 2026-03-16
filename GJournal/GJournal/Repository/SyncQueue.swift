//
//  SyncQueue.swift
//  GJournal
//
//  Offline operation tracking for sync - now using SwiftData
//

import Foundation
import Combine
import SwiftData

// Helper for encoding Any values (still needed for temporary data handling)
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else {
            value = ""
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        default:
            try container.encode("")
        }
    }
}

class SyncQueue: ObservableObject {
    static let shared = SyncQueue()
    
    @Published var pendingOperations: [SyncOperationModel] = []
    @Published var isSyncing = false
    
    private var modelContext: ModelContext?
        
    init() {
        // ModelContext will be injected after SwiftData is set up
    }
    
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        loadQueue()
    }
    
    func addOperation(type: SyncOperationType, bitId: UUID, data: [String: Any]? = nil) {
        guard let modelContext = modelContext else {
            print("[SyncQueue] ModelContext not configured")
            return
        }
        
        // Remove conflicting operations (last modification wins)
        let existingOps = pendingOperations.filter { $0.bitId == bitId && $0.type == type }
        existingOps.forEach { modelContext.delete($0) }
        
        // Create new operation
        let operation = SyncOperationModel(type: type, bitId: bitId)
        operation.data = data
        
        modelContext.insert(operation)
        
        do {
            try modelContext.save()
            loadQueue()
            print("[SyncQueue] Added \(type) operation for bit \(bitId)")
        } catch {
            print("[SyncQueue] Failed to save operation: \(error)")
        }
    }
    
    func removeOperation(_ operationId: UUID) {
        guard let modelContext = modelContext else { return }
        
        if let operation = pendingOperations.first(where: { $0.id == operationId }) {
            modelContext.delete(operation)
            
            do {
                try modelContext.save()
                loadQueue()
                print("[SyncQueue] Removed operation \(operationId)")
            } catch {
                print("[SyncQueue] Failed to remove operation: \(error)")
            }
        }
    }
    
    func clearQueue() {
        guard let modelContext = modelContext else { return }
        
        pendingOperations.forEach { modelContext.delete($0) }
        
        do {
            try modelContext.save()
            pendingOperations.removeAll()
            print("[SyncQueue] Cleared all operations")
        } catch {
            print("[SyncQueue] Failed to clear queue: \(error)")
        }
    }
    
    func markOperationFailed(_ operationId: UUID, error: String) {
        guard let modelContext = modelContext else { return }
        
        if let operation = pendingOperations.first(where: { $0.id == operationId }) {
            operation.retryCount += 1
            operation.lastError = error
            
            // Remove if too many retries
            if operation.retryCount >= 3 {
                modelContext.delete(operation)
                print("[SyncQueue] Operation \(operationId) failed 3 times, removing")
            }
            
            do {
                try modelContext.save()
                loadQueue()
            } catch {
                print("[SyncQueue] Failed to mark operation as failed: \(error)")
            }
        }
    }
    
    private func loadQueue() {
        guard let modelContext = modelContext else { return }
        
        let descriptor = FetchDescriptor<SyncOperationModel>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        
        do {
            pendingOperations = try modelContext.fetch(descriptor)
            print("[SyncQueue] Loaded \(pendingOperations.count) pending operations")
        } catch {
            print("[SyncQueue] Failed to load operations: \(error)")
            pendingOperations = []
        }
    }
}
