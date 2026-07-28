import XCTest
import SwiftData
@testable import GJournal

/// Export was one-way: a user could save a JSON backup they could never put
/// back, so moving to a new phone meant losing the journal. These cover the
/// round trip and the merge semantics.
@MainActor
final class ImportExportTests: XCTestCase {

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
    private func insert(_ context: ModelContext, feel: String, daysAgo: Int = 0) -> Bit {
        let created = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let bit = Bit(feel: feel, createdAt: created)
        context.insert(bit)
        return bit
    }

    // MARK: - Round trip

    func testExportThenImportRestoresEntries() throws {
        let (source, sourceContext) = try makeRepository()
        insert(sourceContext, feel: "first", daysAgo: 2)
        insert(sourceContext, feel: "second", daysAgo: 1)
        try sourceContext.save()
        source.loadBitsFromContext()

        let url = try source.generateExportFile()
        defer { try? FileManager.default.removeItem(at: url) }

        // A fresh device.
        let (destination, _) = try makeRepository()
        XCTAssertTrue(destination.bits.isEmpty, "precondition: the new store is empty")

        let summary = try destination.importData(from: url)

        XCTAssertEqual(summary.imported, 2)
        XCTAssertEqual(summary.skipped, 0)
        XCTAssertEqual(Set(destination.bits.map(\.feel)), ["first", "second"])
    }

    func testImportPreservesEntryIdentityAndDates() throws {
        let (source, sourceContext) = try makeRepository()
        let original = insert(sourceContext, feel: "keep me", daysAgo: 3)
        let originalID = original.id
        let originalCreated = original.createdAt
        try sourceContext.save()
        source.loadBitsFromContext()

        let url = try source.generateExportFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let (destination, _) = try makeRepository()
        try destination.importData(from: url)

        let restored = try XCTUnwrap(destination.bits.first)
        XCTAssertEqual(restored.id, originalID, "identity must survive the round trip")
        XCTAssertEqual(
            restored.createdAt.timeIntervalSince1970,
            originalCreated.timeIntervalSince1970,
            accuracy: 1.0,
            "the original date must be preserved, not reset to now"
        )
    }

    /// The export doc comment always claimed soft-deleted entries were included;
    /// the code iterated `bits`, which excludes them.
    func testExportIncludesSoftDeletedEntries() throws {
        let (source, sourceContext) = try makeRepository()
        insert(sourceContext, feel: "active")
        let trashed = insert(sourceContext, feel: "trashed")
        trashed.deletedAt = Date()
        try sourceContext.save()
        source.loadBitsFromContext()

        XCTAssertEqual(source.bits.count, 1)
        XCTAssertEqual(source.deletedBits.count, 1)

        let url = try source.generateExportFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let (destination, _) = try makeRepository()
        let summary = try destination.importData(from: url)

        XCTAssertEqual(summary.imported, 2, "the trashed entry must be in the backup")
        XCTAssertEqual(destination.deletedBits.count, 1, "and must come back still trashed")
        XCTAssertEqual(destination.bits.count, 1)
    }

    // MARK: - Merge semantics

    func testImportingTheSameBackupTwiceIsANoOp() throws {
        let (source, sourceContext) = try makeRepository()
        insert(sourceContext, feel: "only one")
        try sourceContext.save()
        source.loadBitsFromContext()

        let url = try source.generateExportFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let (destination, _) = try makeRepository()
        try destination.importData(from: url)
        let second = try destination.importData(from: url)

        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.skipped, 1)
        XCTAssertEqual(destination.bits.count, 1, "re-importing must not duplicate entries")
    }

    func testImportMergesWithoutClobberingLocalEntries() throws {
        let (source, sourceContext) = try makeRepository()
        insert(sourceContext, feel: "from backup")
        try sourceContext.save()
        source.loadBitsFromContext()

        let url = try source.generateExportFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let (destination, destinationContext) = try makeRepository()
        insert(destinationContext, feel: "written on this device")
        try destinationContext.save()
        destination.loadBitsFromContext()

        try destination.importData(from: url)

        XCTAssertEqual(
            Set(destination.bits.map(\.feel)),
            ["from backup", "written on this device"],
            "merge must keep both sides"
        )
    }

    func testReplaceExistingClearsBeforeImporting() throws {
        let (source, sourceContext) = try makeRepository()
        insert(sourceContext, feel: "from backup")
        try sourceContext.save()
        source.loadBitsFromContext()

        let url = try source.generateExportFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let (destination, destinationContext) = try makeRepository()
        insert(destinationContext, feel: "should be replaced")
        try destinationContext.save()
        destination.loadBitsFromContext()

        try destination.importData(from: url, replaceExisting: true)

        XCTAssertEqual(destination.bits.map(\.feel), ["from backup"])
    }

    func testImportRestoresClusterMembership() throws {
        let (source, sourceContext) = try makeRepository()
        let cluster = Cluster(index: 3, name: "Work Stress")
        sourceContext.insert(cluster)
        let bit = insert(sourceContext, feel: "deadline")
        bit.cluster = cluster
        try sourceContext.save()
        source.loadBitsFromContext()

        let url = try source.generateExportFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let (destination, _) = try makeRepository()
        try destination.importData(from: url)

        let restored = try XCTUnwrap(destination.bits.first)
        XCTAssertEqual(restored.clusterID, 3)
        XCTAssertEqual(restored.cluster?.name, "Work Stress")
    }

    // MARK: - Bad input

    func testImportRejectsAFileThatIsNotAnExport() throws {
        let (repo, _) = try makeRepository()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-an-export-\(UUID().uuidString).json")
        try Data("{\"hello\":\"world\"}".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try repo.importData(from: url))
    }

    func testImportRejectsANewerFormatVersion() throws {
        let (repo, _) = try makeRepository()
        let payload: [String: Any] = [
            "formatVersion": LocalJournalRepository.exportFormatVersion + 1,
            "bits": []
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("future-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: payload).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // Refusing beats silently dropping fields we don't understand.
        XCTAssertThrowsError(try repo.importData(from: url))
    }

    func testSummaryMessageReadsPlainly() {
        var summary = LocalJournalRepository.ImportSummary()
        summary.imported = 1
        XCTAssertEqual(summary.message, "Imported 1 entry.")

        summary.imported = 142
        summary.skipped = 8
        XCTAssertEqual(summary.message, "Imported 142 entries. 8 already here.")

        summary.imported = 0
        XCTAssertEqual(summary.message, "Everything in that backup is already here.")
    }
}
