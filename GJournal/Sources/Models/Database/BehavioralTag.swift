import Foundation
import SwiftData

/// Canonical registry of behavioral tags mined from journal entries (plan §2.0). Each tag is a
/// lemma (event noun or action verb) with an occurrence count and a canonical embedding used to
/// merge near-duplicate candidates. Becomes a GGM variable once it reaches `ggmThreshold`
/// occurrences.
///
/// The per-entry association is stored denormalized on `Bit.tagLemmas` (canonical lemma strings)
/// rather than a SwiftData relationship — keeping the SchemaV1→V2 migration purely additive
/// (one optional attribute + one standalone model), the safest lightweight-migration class.
@Model
final class BehavioralTag {
    @Attribute(.unique) var lemma: String
    var categoryRaw: String
    var count: Int
    var lastSeen: Date
    var canonicalEmbeddingData: Data?

    /// A tag participates in the GGM network once it has occurred at least this many times.
    static let ggmThreshold = 5

    init(lemma: String, category: TagCategory, count: Int = 1, lastSeen: Date = .now, embedding: [Float]? = nil) {
        self.lemma = lemma
        self.categoryRaw = category.rawValue
        self.count = count
        self.lastSeen = lastSeen
        self.canonicalEmbeddingData = embedding?.withUnsafeBytes { Data($0) }
    }

    var category: TagCategory { TagCategory(rawValue: categoryRaw) ?? .event }

    var isGGMEligible: Bool { count >= Self.ggmThreshold }

    var canonicalEmbedding: [Float]? {
        get {
            guard let data = canonicalEmbeddingData, !data.isEmpty,
                  data.count % MemoryLayout<Float>.size == 0 else { return nil }
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
        set { canonicalEmbeddingData = newValue?.withUnsafeBytes { Data($0) } }
    }
}
