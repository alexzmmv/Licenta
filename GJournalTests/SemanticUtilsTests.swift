import XCTest
import SwiftData
@testable import GJournal

final class SemanticUtilsTests: XCTestCase {

    func testCosineSimilarityIdenticalUnitVectors() {
        let v: [Float] = [0.6, 0.8, 0, 0]
        XCTAssertEqual(SemanticUtils.cosineSimilarity(v, v), 1.0, accuracy: 1e-5)
    }

    func testCosineSimilarityOrthogonalVectors() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0, 1, 0]
        XCTAssertEqual(SemanticUtils.cosineSimilarity(a, b), 0.0, accuracy: 1e-6)
    }

    func testCosineSimilarityMismatchedLengthsReturnsZero() {
        XCTAssertEqual(SemanticUtils.cosineSimilarity([1, 0], [1, 0, 0]), 0)
        XCTAssertEqual(SemanticUtils.cosineSimilarity([], []), 0)
    }

    func testCosineSimilarityIsClampedToUnitInterval() {
        // Un-normalised vectors would produce a raw dot product > 1
        let a: [Float] = [3, 4]
        let b: [Float] = [3, 4]
        let sim = SemanticUtils.cosineSimilarity(a, b)
        XCTAssertLessThanOrEqual(sim, 1.0)
        XCTAssertGreaterThanOrEqual(sim, 0.0)
    }

    func testNormalisedProducesUnitNorm() throws {
        let v: [Float] = [3, 4]
        let n = try XCTUnwrap(SemanticUtils.normalised(v))
        let norm = sqrt(n.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(norm, 1.0, accuracy: 1e-5)
        XCTAssertEqual(n[0], 0.6, accuracy: 1e-5)
        XCTAssertEqual(n[1], 0.8, accuracy: 1e-5)
    }

    func testNormalisedNilAndEmptyInput() {
        XCTAssertNil(SemanticUtils.normalised(nil))
        XCTAssertNil(SemanticUtils.normalised([]))
    }

    func testHybridSearchRelevanceSorting() throws {
        let bit1 = Bit(title: "Yoga session", feel: "relaxed", event: "yoga class", action: "meditated", intensity: 2)
        bit1.embedding = [1.0, 0.0, 0.0, 0.0] // relaxed direction
        
        let bit2 = Bit(title: "Deadline panic", feel: "anxious", event: "missed deadline", action: "worked late", intensity: 4)
        bit2.embedding = [0.0, 1.0, 0.0, 0.0] // anxious direction
        
        let engine = HybridSearchService()
        engine.rebuild(from: [bit1, bit2])
        
        // Querying for anxiety/deadline related terms
        let results = engine.search(query: "anxious deadline panic")
        XCTAssertFalse(results.isEmpty)
        // The anxious bit should come first because it matches query tokens exactly and is semantically closer
        XCTAssertEqual(results.first?.title, "Deadline panic")
    }

    func testRepositorySearchBitsFiltersAndPreservesRelevance() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema(versionedSchema: SchemaV2.self)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)
        
        let repository = LocalJournalRepository()
        repository.configure(with: context)
        
        let bit1 = Bit(title: "Working on Swift project", feel: "focused", event: "code review", action: "merged PR", intensity: 3)
        bit1.embedding = [0.707, 0.707, 0.0, 0.0]
        let cluster1 = Cluster(index: 1, name: "Cluster 1")
        bit1.cluster = cluster1
        context.insert(cluster1)
        context.insert(bit1)
        
        let bit2 = Bit(title: "Relaxing weekend yoga", feel: "relaxed", event: "yoga stretch", action: "rested", intensity: 2)
        bit2.embedding = [0.0, 0.0, 1.0, 0.0]
        let cluster2 = Cluster(index: 2, name: "Cluster 2")
        bit2.cluster = cluster2
        context.insert(cluster2)
        context.insert(bit2)
        
        try context.save()
        repository.loadBitsFromContext()
        
        // Search for "Swift project focused" which should match bit1
        let results = repository.searchBits(query: "Swift project focused", clusterIDs: [1])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Working on Swift project")
    }
}
