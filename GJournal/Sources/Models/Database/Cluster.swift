import Foundation
import SwiftData

@Model
final class Cluster {
    @Attribute(.unique) var index: Int
    
    var name: String
    
    var createdAt: Date
    
    @Relationship(deleteRule: .nullify, inverse: \Bit.cluster)
    var bits: [Bit] = []
    
    var id: Int { index }

    init(index: Int, name: String, createdAt: Date = Date()) {
        self.index = index
        self.name = name
        self.createdAt = createdAt
    }
}
