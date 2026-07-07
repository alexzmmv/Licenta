import XCTest
import SwiftData
@testable import GJournal

/// Integration test for TagProcessor against an in-memory SchemaV2 store and the deterministic
/// MockEmbeddingService (same lemma → identical embedding → merge; distinct lemmas → new tags).
final class TagProcessorTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(versionedSchema: SchemaV2.self),
                                           migrationPlan: GJournalMigrationPlan.self,
                                           configurations: config)
        return ModelContext(container)
    }

    func testProcessCreatesCanonicalTags() async throws {
        let ctx = try makeContext()
        let proc = TagProcessor(embeddingService: MockEmbeddingService())

        let assigned = await proc.process(event: "attended a meeting",
                                          action: "argued with my manager", into: ctx)
        try ctx.save()

        let tags = try ctx.fetch(FetchDescriptor<BehavioralTag>())
        let lemmas = Set(tags.map(\.lemma))
        XCTAssertTrue(lemmas.contains("meeting"), "got \(lemmas)")
        XCTAssertTrue(lemmas.contains("manager"), "got \(lemmas)")
        XCTAssertEqual(Set(assigned), lemmas)
        // event-field words → event tags, action-field words → action tags
        XCTAssertEqual(tags.first { $0.lemma == "meeting" }?.category, .event)
        XCTAssertEqual(tags.first { $0.lemma == "manager" }?.category, .action)
    }

    func testRepeatedLemmaIncrementsCountInsteadOfDuplicating() async throws {
        let ctx = try makeContext()
        let proc = TagProcessor(embeddingService: MockEmbeddingService())

        _ = await proc.process(event: "a stressful meeting", action: "", into: ctx)
        try ctx.save()
        _ = await proc.process(event: "another meeting today", action: "", into: ctx)
        try ctx.save()

        let meeting = try ctx.fetch(FetchDescriptor<BehavioralTag>()).filter { $0.lemma == "meeting" }
        XCTAssertEqual(meeting.count, 1, "should not duplicate the tag")
        XCTAssertEqual(meeting.first?.count, 2, "occurrence count should increment across entries")
    }

    func testGGMEligibilityAtThreshold() {
        let tag = BehavioralTag(lemma: "run", category: .action, count: BehavioralTag.ggmThreshold)
        XCTAssertTrue(tag.isGGMEligible)
        let rare = BehavioralTag(lemma: "swim", category: .action, count: 1)
        XCTAssertFalse(rare.isGGMEligible)
    }
}
