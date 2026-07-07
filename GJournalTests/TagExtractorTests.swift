import XCTest
@testable import GJournal

/// Behavioral tag extraction (NLTagger lemma+POS) and embedding-cosine canonicalization.
final class TagExtractorTests: XCTestCase {

    // MARK: - Extraction

    func testEventFieldContentWordsBecomeEventTags() {
        let tags = TagExtractor.extract(event: "a stressful meeting with my manager", action: "")
        XCTAssertTrue(tags.allSatisfy { $0.category == .event }, "got \(tags)")
        let lemmas = Set(tags.map(\.lemma))
        XCTAssertTrue(lemmas.contains("meeting"), "got \(lemmas)")
        XCTAssertTrue(lemmas.contains("manager"), "got \(lemmas)")
    }

    func testActionFieldContentWordsBecomeActionTags() {
        // "called" stays "called" on the simulator (no lemma model) or becomes "call" on device;
        // hasPrefix keeps the assertion robust to lemmatization availability.
        let tags = TagExtractor.extract(event: "", action: "called my friend")
        XCTAssertTrue(tags.allSatisfy { $0.category == .action }, "got \(tags)")
        XCTAssertTrue(tags.contains { $0.lemma.hasPrefix("call") }, "got \(tags)")
        XCTAssertTrue(tags.contains { $0.lemma.hasPrefix("friend") }, "got \(tags)")
    }

    func testFiltersStopwordsAndShortTokens() {
        let tags = TagExtractor.extract(event: "It was a day", action: "I did it")
        // "day", "was", "did" are stopwords; "it", "a", "I" are too short -> no tags
        XCTAssertTrue(tags.isEmpty, "got \(tags)")
    }

    func testDeduplicatesRepeatedWords() {
        let tags = TagExtractor.extract(event: "report and report again about the report", action: "")
        XCTAssertEqual(tags.filter { $0.lemma.hasPrefix("report") }.count, 1)
    }

    func testEmptyInputYieldsNoTags() {
        XCTAssertTrue(TagExtractor.extract(event: "", action: "").isEmpty)
    }

    // MARK: - Canonicalization (embedding cosine)

    func testCanonicalizeMergesWhenAboveThreshold() {
        let existing: [[Float]] = [[1, 0, 0], [0, 1, 0]]
        // nearly identical to existing[0]
        let idx = TagExtractor.matchIndex(candidate: [0.99, 0.14, 0], existing: existing, threshold: 0.85)
        XCTAssertEqual(idx, 0)
    }

    func testCanonicalizeCreatesNewWhenBelowThreshold() {
        let existing: [[Float]] = [[1, 0, 0], [0, 1, 0]]
        // orthogonal-ish to both -> no merge
        let idx = TagExtractor.matchIndex(candidate: [0, 0, 1], existing: existing, threshold: 0.85)
        XCTAssertNil(idx)
    }

    func testCanonicalizePicksHighestSimilarity() {
        let existing: [[Float]] = [[1, 0, 0], [0.9, 0.1, 0]]
        // closest to existing[1]
        let idx = TagExtractor.matchIndex(candidate: [0.88, 0.12, 0], existing: existing, threshold: 0.5)
        XCTAssertEqual(idx, 1)
    }

    func testCanonicalizeEmptyExistingReturnsNil() {
        XCTAssertNil(TagExtractor.matchIndex(candidate: [1, 0, 0], existing: [], threshold: 0.85))
    }
}
