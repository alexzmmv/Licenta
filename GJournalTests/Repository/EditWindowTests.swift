import XCTest
import SwiftData
@testable import GJournal

/// The edit window must be a rule enforced by the repository, not a UI hint.
///
/// Previously `canEdit` was consulted only to decide whether to render an edit
/// button, so any caller that reached `updateBit` directly could rewrite an
/// entry of any age.
@MainActor
final class EditWindowTests: XCTestCase {

    private func makeRepository() throws -> (LocalJournalRepository, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema(versionedSchema: SchemaV2.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: GJournalMigrationPlan.self,
            configurations: config
        )
        let context = ModelContext(container)
        let repo = LocalJournalRepository()
        repo.configure(with: context)
        return (repo, context)
    }

    @discardableResult
    private func insertBit(context: ModelContext, daysAgo: Int, feel: String) -> Bit {
        let created = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let bit = Bit(feel: feel, createdAt: created)
        context.insert(bit)
        return bit
    }

    func testTodaysEntryIsEditable() throws {
        let (repo, context) = try makeRepository()
        let bit = insertBit(context: context, daysAgo: 0, feel: "original")
        try context.save()
        repo.loadBitsFromContext()

        XCTAssertTrue(repo.canEdit(bit: bit))

        repo.updateBit(id: bit.id, title: nil, feel: "edited", event: "", action: "", intensity: 2)

        XCTAssertEqual(repo.bits.first(where: { $0.id == bit.id })?.feel, "edited")
        XCTAssertNil(repo.errorMessage)
    }

    func testYesterdaysEntryIsNotEditable() throws {
        let (repo, context) = try makeRepository()
        let bit = insertBit(context: context, daysAgo: 1, feel: "original")
        try context.save()
        repo.loadBitsFromContext()

        XCTAssertFalse(repo.canEdit(bit: bit), "the window is today only")
    }

    /// The important one: the repository must refuse the write even when a
    /// caller ignores `canEdit` entirely.
    func testUpdateIsRejectedForAnOlderEntryEvenWhenCalledDirectly() throws {
        let (repo, context) = try makeRepository()
        let bit = insertBit(context: context, daysAgo: 3, feel: "original")
        try context.save()
        repo.loadBitsFromContext()

        repo.updateBit(id: bit.id, title: "hijacked", feel: "rewritten", event: "", action: "", intensity: 4)

        let stored = repo.bits.first(where: { $0.id == bit.id })
        XCTAssertEqual(stored?.feel, "original", "an out-of-window edit must not be persisted")
        XCTAssertNil(stored?.title)
        XCTAssertNotNil(repo.errorMessage, "the user must be told why the edit was refused")
    }

    func testRejectedEditLeavesLastModifiedUntouched() throws {
        let (repo, context) = try makeRepository()
        let bit = insertBit(context: context, daysAgo: 5, feel: "original")
        let originalModified = bit.lastModified
        try context.save()
        repo.loadBitsFromContext()

        repo.updateBit(id: bit.id, title: nil, feel: "rewritten", event: "", action: "", intensity: 1)

        XCTAssertEqual(
            repo.bits.first(where: { $0.id == bit.id })?.lastModified,
            originalModified,
            "a refused edit must not touch the modification timestamp"
        )
    }
}
