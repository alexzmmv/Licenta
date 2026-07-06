import XCTest
@testable import GJournal

/// Golden-fixture tests for the hand-rolled BERT WordPiece tokenizer.
/// The vocab is written to a temp file so results are fully deterministic
/// and independent of the bundled model vocabularies.
final class WordPieceTokenizerTests: XCTestCase {

    private var tokenizer: WordPieceTokenizer!

    // Line index == token ID
    private let vocabLines = [
        "[PAD]",   // 0
        "[UNK]",   // 1
        "[CLS]",   // 2
        "[SEP]",   // 3
        "hello",   // 4
        "world",   // 5
        "feel",    // 6
        "##ing",   // 7
        "anxious", // 8
        "!",       // 9
    ]

    override func setUpWithError() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_vocab_\(UUID().uuidString).txt")
        try vocabLines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        tokenizer = try WordPieceTokenizer(vocabURL: url)
    }

    func testSimpleSentenceGoldenIDs() {
        let output = tokenizer.tokenize("Hello world")

        XCTAssertEqual(output.realTokenCount, 4) // [CLS] hello world [SEP]
        XCTAssertEqual(Array(output.inputIDs.prefix(4)), [2, 4, 5, 3])
        // Padding after the real tokens
        XCTAssertEqual(output.inputIDs[4], 0)
        XCTAssertEqual(output.inputIDs.count, WordPieceTokenizer.maxLength)
    }

    func testWordPieceSubwordSplitting() {
        // "feeling" is not in the vocab; it must split into "feel" + "##ing"
        let output = tokenizer.tokenize("feeling anxious!")

        XCTAssertEqual(output.realTokenCount, 6) // [CLS] feel ##ing anxious ! [SEP]
        XCTAssertEqual(Array(output.inputIDs.prefix(6)), [2, 6, 7, 8, 9, 3])
    }

    func testUnknownWordFallsBackToUNK() {
        let output = tokenizer.tokenize("zzz")

        // Implementation maps each unmatched character to [UNK]
        XCTAssertEqual(output.realTokenCount, 5) // [CLS] UNK UNK UNK [SEP]
        XCTAssertEqual(Array(output.inputIDs.prefix(5)), [2, 1, 1, 1, 3])
    }

    func testAttentionMaskMatchesRealTokenCount() {
        let output = tokenizer.tokenize("hello anxious world")

        let onesCount = output.attentionMask.filter { $0 == 1 }.count
        XCTAssertEqual(onesCount, output.realTokenCount)
        // Mask is a prefix of 1s followed by 0s
        XCTAssertEqual(output.attentionMask[output.realTokenCount - 1], 1)
        XCTAssertEqual(output.attentionMask[output.realTokenCount], 0)
    }

    func testLongInputIsTruncatedToMaxLength() {
        let longText = Array(repeating: "hello", count: 300).joined(separator: " ")
        let output = tokenizer.tokenize(longText)

        XCTAssertEqual(output.inputIDs.count, WordPieceTokenizer.maxLength)
        XCTAssertEqual(output.attentionMask.count, WordPieceTokenizer.maxLength)
        XCTAssertLessThanOrEqual(output.realTokenCount, WordPieceTokenizer.maxLength)
        // Last real token must be [SEP]
        XCTAssertEqual(output.inputIDs[output.realTokenCount - 1], 3)
    }

    func testEmptyInput() {
        let output = tokenizer.tokenize("")

        XCTAssertEqual(output.realTokenCount, 2) // [CLS] [SEP]
        XCTAssertEqual(Array(output.inputIDs.prefix(2)), [2, 3])
    }
}
