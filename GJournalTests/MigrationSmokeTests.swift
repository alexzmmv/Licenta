import XCTest
import SwiftData
@testable import GJournal

/// Smoke tests for the versioned schema + migration plan: the container must
/// come up through GJournalMigrationPlan and round-trip a Bit. When SchemaV2
/// lands, extend these with a real V1→V2 migration fixture.
final class MigrationSmokeTests: XCTestCase {

    private func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema(versionedSchema: SchemaV2.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: GJournalMigrationPlan.self,
            configurations: config
        )
    }

    func testContainerCreatesWithVersionedSchemaAndMigrationPlan() throws {
        XCTAssertNoThrow(try makeInMemoryContainer())
    }

    func testSchemaV1RegistersBitAndCluster() {
        let modelTypes = SchemaV1.models.map { String(describing: $0) }
        XCTAssertTrue(modelTypes.contains("Bit"))
        XCTAssertTrue(modelTypes.contains("Cluster"))
        XCTAssertEqual(SchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
    }

    func testSchemaV2RegistersBehavioralTag() {
        let modelTypes = SchemaV2.models.map { String(describing: $0) }
        XCTAssertTrue(modelTypes.contains("Bit"))
        XCTAssertTrue(modelTypes.contains("Cluster"))
        XCTAssertTrue(modelTypes.contains("BehavioralTag"))
        XCTAssertEqual(SchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
    }

    func testMigrationPlanChainsV1ToV2Lightweight() {
        XCTAssertEqual(GJournalMigrationPlan.schemas.count, 2)
        XCTAssertTrue(GJournalMigrationPlan.schemas.first == SchemaV1.self)
        XCTAssertTrue(GJournalMigrationPlan.schemas.last == SchemaV2.self)
        XCTAssertEqual(GJournalMigrationPlan.stages.count, 1)
    }

    func testBehavioralTagRoundTripsThroughStore() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let tag = BehavioralTag(lemma: "meeting", category: .event, count: 3)
        tag.canonicalEmbedding = [0.1, 0.2, 0.3]
        context.insert(tag)

        let bit = Bit(feel: "tense", event: "a meeting", action: "spoke up", intensity: 2)
        bit.tagLemmas = ["meeting", "speak"]
        context.insert(bit)
        try context.save()

        let fetchedTag = try context.fetch(FetchDescriptor<BehavioralTag>())
        XCTAssertEqual(fetchedTag.count, 1)
        XCTAssertEqual(fetchedTag.first?.category, .event)
        XCTAssertEqual(fetchedTag.first?.count, 3)
        XCTAssertEqual(fetchedTag.first?.canonicalEmbedding, [0.1, 0.2, 0.3])

        let fetchedBit = try context.fetch(FetchDescriptor<Bit>())
        XCTAssertEqual(fetchedBit.first?.tagLemmas, ["meeting", "speak"])
    }

    func testBitRoundTripsThroughStore() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let bit = Bit(
            title: "Test entry",
            feel: "calm",
            event: "wrote a unit test",
            action: "kept going",
            intensity: 2
        )
        context.insert(bit)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Bit>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.feel, "calm")
        XCTAssertEqual(fetched.first?.intensity, 2)
        XCTAssertFalse(fetched.first?.isDeleted ?? true)
    }

    func testEmbeddingDataRoundTrip() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let bit = Bit(feel: "ok", event: "e", action: "a", intensity: 1)
        bit.embedding = [0.25, -0.5, 1.0]
        context.insert(bit)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Bit>())
        XCTAssertEqual(fetched.first?.embedding, [0.25, -0.5, 1.0])
    }
}
