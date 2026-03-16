//
//  SyncOperationModel.swift
//  GJournal
//
//  SwiftData model for offline sync operations
//

import Foundation
import SwiftData

enum SyncOperationType: String, Codable {
    case create
    case update
    case delete
    case toggleHide
}

@Model
final class SyncOperationModel {
    @Attribute(.unique) var id: UUID
    var typeRawValue: String
    var bitId: UUID
    var timestamp: Date
    var dataJSON: String?  // JSON-encoded data
    var retryCount: Int
    var lastError: String?
    
    var type: SyncOperationType {
        get { SyncOperationType(rawValue: typeRawValue) ?? .create }
        set { typeRawValue = newValue.rawValue }
    }
    
    init(id: UUID = UUID(), type: SyncOperationType, bitId: UUID, timestamp: Date = Date(), dataJSON: String? = nil, retryCount: Int = 0, lastError: String? = nil) {
        self.id = id
        self.typeRawValue = type.rawValue
        self.bitId = bitId
        self.timestamp = timestamp
        self.dataJSON = dataJSON
        self.retryCount = retryCount
        self.lastError = lastError
    }
    
    // Helper to convert to/from dictionary
    var data: [String: Any]? {
        get {
            guard let jsonString = dataJSON,
                  let jsonData = jsonString.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return nil
            }
            return dict
        }
        set {
            guard let dict = newValue,
                  let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                dataJSON = nil
                return
            }
            dataJSON = jsonString
        }
    }
}
