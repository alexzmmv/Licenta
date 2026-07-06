import XCTest
import SwiftData
@testable import GJournal

/// Covers the versioned JSON export and the embedding-model configuration
/// fallback after the Nomic model family was removed from the bundle.
final class ExportAndModelChoiceTests: XCTestCase {

    private let defaultsKey = "embeddingModelChoice"
    private var savedChoice: String?

    override func setUp() {
        super.setUp()
        savedChoice = UserDefaults.standard.string(forKey: defaultsKey)
    }

    override func tearDown() {
        if let savedChoice {
            UserDefaults.standard.set(savedChoice, forKey: defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
        super.tearDown()
    }

    // MARK: - EmbeddingModelChoice

    func testDefaultModelIsMiniLM() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        XCTAssertEqual(EmbeddingModelChoice.current, .miniLM)
    }

    func testRemovedNomicRawValueFallsBackToMiniLM() {
        // Users upgrading from a build that offered Nomic must fall back
        // to MiniLM instead of crashing or losing the pipeline.
        UserDefaults.standard.set("nomicMRL", forKey: defaultsKey)
        XCTAssertEqual(EmbeddingModelChoice.current, .miniLM)

        UserDefaults.standard.set("nomicFull", forKey: defaultsKey)
        XCTAssertEqual(EmbeddingModelChoice.current, .miniLM)
    }

    func testModelChoiceRoundTrip() {
        EmbeddingModelChoice.current = .appleNLP
        XCTAssertEqual(EmbeddingModelChoice.current, .appleNLP)
        EmbeddingModelChoice.current = .miniLM
        XCTAssertEqual(EmbeddingModelChoice.current, .miniLM)
    }

    // MARK: - Versioned export

    func testExportFileIsVersionedAndParseable() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema(versionedSchema: SchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: GJournalMigrationPlan.self,
            configurations: config
        )

        let repository = LocalJournalRepository()
        repository.configure(with: ModelContext(container))
        repository.createBit(title: "Entry", feel: "hopeful", event: "shipped tests", action: "reviewed", intensity: 3)

        let url = try repository.generateExportFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(payload["formatVersion"] as? Int, LocalJournalRepository.exportFormatVersion)
        XCTAssertNotNil(payload["schemaVersion"])
        XCTAssertNotNil(payload["exportedAt"])

        let bits = try XCTUnwrap(payload["bits"] as? [[String: Any]])
        XCTAssertEqual(bits.count, 1)
        XCTAssertEqual(bits.first?["feel"] as? String, "hopeful")
        XCTAssertEqual(bits.first?["intensity"] as? Int, 3)

        let summary = try XCTUnwrap(payload["summary"] as? [String: Any])
        XCTAssertEqual(summary["totalBits"] as? Int, 1)
    }

    func testExportWithoutContextThrows() {
        let repository = LocalJournalRepository()
        XCTAssertThrowsError(try repository.generateExportFile())
    }
}
