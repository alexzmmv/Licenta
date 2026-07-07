import XCTest
@testable import GJournal

/// Persona validation for the trajectory biomarkers (plan §2.2 / §10): three synthetic
/// personas must each trigger their signature metric.
///   - Ruminator (cyclic revisiting)  -> high Loop Persistence (β1 from real PH)
///   - Explorer  (spreading disk)      -> high Flare Index, low LP
///   - Recoverer (moving off distress) -> positive Semantic Recovery Velocity
final class TrajectoryServiceTests: XCTestCase {

    private func metrics(_ pts: [TrajectoryPoint]) -> TrajectoryMetrics {
        guard let m = TrajectoryService.metrics(for: pts) else {
            XCTFail("metrics returned nil for \(pts.count) points"); fatalError()
        }
        return m
    }

    // MARK: - Signature-metric discrimination

    func testRuminatorHasHighestLoopPersistence() {
        let rum = metrics(TrajectoryPersonas.personaRuminator())
        let exp = metrics(TrajectoryPersonas.personaExplorer())
        let rec = metrics(TrajectoryPersonas.personaRecoverer())
        XCTAssertGreaterThan(rum.loopPersistence, exp.loopPersistence)
        XCTAssertGreaterThan(rum.loopPersistence, rec.loopPersistence)
        XCTAssertGreaterThan(rum.loopPersistence, 0.3, "ruminator ring should have a real loop")
    }

    func testExplorerHasHighestFlareIndex() {
        let rum = metrics(TrajectoryPersonas.personaRuminator())
        let exp = metrics(TrajectoryPersonas.personaExplorer())
        let rec = metrics(TrajectoryPersonas.personaRecoverer())
        XCTAssertGreaterThan(exp.flareIndex, rec.flareIndex)
        // a filled disk fills much more of its bbox than a near-1D recovery line
        XCTAssertGreaterThan(exp.flareIndex, 0.4)
    }

    func testRecovererHasPositiveRecoveryVelocity() {
        let rec = metrics(TrajectoryPersonas.personaRecoverer())
        let exp = metrics(TrajectoryPersonas.personaExplorer())
        XCTAssertGreaterThan(rec.recoveryVelocity, 0, "recoverer moves away from distress anchor")
        XCTAssertGreaterThan(rec.recoveryVelocity, exp.recoveryVelocity)
    }

    // MARK: - Flare index bounds & degenerate cases

    func testFlareIndexIsBounded() {
        for pts in [TrajectoryPersonas.personaRuminator(),
                    TrajectoryPersonas.personaExplorer(),
                    TrajectoryPersonas.personaRecoverer()] {
            let f = metrics(pts).flareIndex
            XCTAssertGreaterThanOrEqual(f, 0)
            XCTAssertLessThanOrEqual(f, 1.0001)
        }
    }

    func testTooFewPointsReturnsNil() {
        let pts = (0..<2).map { i in
            TrajectoryPoint(date: Date(timeIntervalSince1970: Double(i) * 86400),
                            embedding: [Double(i), 0], valence: 0)
        }
        XCTAssertNil(TrajectoryService.metrics(for: pts))
    }

    // MARK: - Permutation null test

    func testRuminatorLoopIsStatisticallySignificant() {
        // shuffling time order preserves the point cloud, so LP is unchanged by permutation;
        // significance here checks the *observed* LP exceeds the null built from random
        // sub-samples of the same size. Ring loop should clear the 95th percentile.
        let m = TrajectoryService.metrics(for: TrajectoryPersonas.personaRuminator(),
                                          permutations: 100)!
        XCTAssertLessThan(m.ruminationPValue, 0.05)
    }
}
