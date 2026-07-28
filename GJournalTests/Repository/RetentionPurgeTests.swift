import XCTest
import SwiftData
@testable import GJournal

/// Regression tests for the 72-hour retention promise made in
/// `RecentlyDeletedView` ("kept here for exactly 72 hours before being
/// permanently purged").
///
/// This previously shipped broken in two independent ways: `purgeExpiredBits()`
/// scanned `bits` — which `loadBitsFromContext()` populates with `deletedAt ==
/// nil` entries only, so `isPastRetention` was never true — and nothing in the
/// app ever called it. Deleted entries lived forever while the UI counted down
/// to "0h remaining before purge".
@MainActor
final class RetentionPurgeTests: XCTestCase {

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

    /// `deletedAt` far enough in the past that the 3-day window has elapsed.
    private func makeExpiredBit(context: ModelContext, feel: String) -> Bit {
        let bit = Bit(feel: feel)
        bit.deletedAt = Date().addingTimeInterval(-4 * 24 * 60 * 60)
        context.insert(bit)
        return bit
    }

    private func makeRecentlyDeletedBit(context: ModelContext, feel: String) -> Bit {
        let bit = Bit(feel: feel)
        bit.deletedAt = Date().addingTimeInterval(-1 * 60 * 60)
        context.insert(bit)
        return bit
    }

    func testPurgeRemovesEntriesPastRetention() throws {
        let (repo, context) = try makeRepository()
        _ = makeExpiredBit(context: context, feel: "expired")
        try context.save()
        repo.loadBitsFromContext()

        XCTAssertEqual(repo.deletedBits.count, 1, "precondition: the expired entry is in the trash")

        repo.purgeExpiredBits()

        XCTAssertTrue(repo.deletedBits.isEmpty, "entries past the retention window must be purged")
        let remaining = try context.fetch(FetchDescriptor<Bit>())
        XCTAssertTrue(remaining.isEmpty, "the entry must be gone from the store, not just the array")
    }

    func testPurgeKeepsEntriesStillInsideRetention() throws {
        let (repo, context) = try makeRepository()
        _ = makeRecentlyDeletedBit(context: context, feel: "recent")
        try context.save()
        repo.loadBitsFromContext()

        repo.purgeExpiredBits()

        XCTAssertEqual(repo.deletedBits.count, 1, "entries inside the 72-hour window must survive")
    }

    func testPurgeNeverTouchesActiveEntries() throws {
        let (repo, context) = try makeRepository()
        let active = Bit(feel: "active")
        context.insert(active)
        _ = makeExpiredBit(context: context, feel: "expired")
        try context.save()
        repo.loadBitsFromContext()

        repo.purgeExpiredBits()

        XCTAssertEqual(repo.bits.count, 1, "active entries must be untouched")
        XCTAssertEqual(repo.bits.first?.feel, "active")
        XCTAssertTrue(repo.deletedBits.isEmpty)
    }

    /// `configure(with:)` runs on every launch, so retention is honoured even if
    /// the app is never left running long enough to purge organically.
    func testConfigurePurgesOnLaunch() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema(versionedSchema: SchemaV2.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: GJournalMigrationPlan.self,
            configurations: config
        )
        let context = ModelContext(container)

        let stale = Bit(feel: "expired")
        stale.deletedAt = Date().addingTimeInterval(-4 * 24 * 60 * 60)
        context.insert(stale)
        try context.save()

        let repo = LocalJournalRepository()
        repo.configure(with: context)

        XCTAssertTrue(repo.deletedBits.isEmpty, "launch must purge entries past retention")
    }
}
