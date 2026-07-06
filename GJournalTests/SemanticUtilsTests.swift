import XCTest
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
}
