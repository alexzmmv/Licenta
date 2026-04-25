//
//  Cluster.swift
//  GJournal
//
//  Created by AI on 25.04.2026.
//

import Foundation
import SwiftData

@Model
final class Cluster {
    /// The unique ID from DBSCAN clustering (-1 is reserved for noise, so we store 0+)
    @Attribute(.unique) var id: Int
    
    /// The human-readable name generated for this cluster
    var name: String
    
    /// When the cluster was first created/named
    var createdAt: Date
    
    /// Relationship to bits belonging to this cluster
    @Relationship(deleteRule: .nullify, inverse: \Bit.cluster)
    var bits: [Bit] = []
    
    init(id: Int, name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
