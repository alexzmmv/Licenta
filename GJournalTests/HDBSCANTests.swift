import XCTest
@testable import GJournal

/// Validates HDBSCANClusterer using structural pairwise agreement on synthetic data.
///
/// "Structural" means: two points that should share a cluster do share a cluster,
/// regardless of the cluster label assigned. This is robust against label-order
/// differences between hdbscan implementations.
final class HDBSCANTests: XCTestCase {

    // MARK: - Synthetic test data

    /// 15 points across 3 well-separated clusters (5 pts each) in 5-D space.
    /// Cluster A ≈ [1,0,0,0,0], Cluster B ≈ [0,1,0,0,0], Cluster C ≈ [0,0,1,0,0].
    /// 2 orthogonal outliers (cosine distance ≈ 1 to all cluster centroids).
    static let syntheticPoints: [[Float]] = [
        // Cluster A
        [1.00, 0.05, 0.00, 0.00, 0.00],
        [0.95, 0.08, 0.10, 0.00, 0.00],
        [1.00, 0.00, 0.05, 0.05, 0.00],
        [0.92, 0.10, 0.00, 0.00, 0.05],
        [1.00, 0.03, 0.03, 0.03, 0.03],
        // Cluster B
        [0.05, 1.00, 0.00, 0.00, 0.00],
        [0.08, 0.95, 0.10, 0.00, 0.00],
        [0.00, 1.00, 0.05, 0.05, 0.00],
        [0.10, 0.92, 0.00, 0.00, 0.05],
        [0.03, 1.00, 0.03, 0.03, 0.03],
        // Cluster C
        [0.00, 0.05, 1.00, 0.00, 0.00],
        [0.08, 0.00, 0.95, 0.10, 0.00],
        [0.00, 0.05, 1.00, 0.05, 0.00],
        [0.10, 0.00, 0.92, 0.00, 0.05],
        [0.03, 0.03, 1.00, 0.03, 0.03],
        // Outliers — orthogonal to all three cluster directions (cosine dist ≈ 1.0 to A/B/C)
        [0.00, 0.00, 0.00, 1.00, 0.00],
        [0.00, 0.00, 0.00, 0.71, 0.71],
    ]

    // Expected pairwise same-cluster membership (by index groups):
    // A = 0..4, B = 5..9, C = 10..14, outliers = 15..16
    static let clusterGroups: [[Int]] = [
        Array(0...4),   // Cluster A
        Array(5...9),   // Cluster B
        Array(10...14), // Cluster C
    ]

    // MARK: - Helper

    /// Checks that all points within each group share the same label,
    /// and groups have distinct labels. Noise points (label -1) inside a group = failure.
    private func assertStructuralCorrectness(labels: [Int], groups: [[Int]], file: StaticString = #file, line: UInt = #line) {
        for group in groups {
            let groupLabels = group.map { labels[$0] }
            // All non-noise
            for (i, lbl) in zip(group, groupLabels) {
                XCTAssertNotEqual(lbl, -1, "Point \(i) should not be noise", file: file, line: line)
            }
            // All same label
            let first = groupLabels.first!
            for (i, lbl) in zip(group, groupLabels) where lbl != first {
                XCTFail("Points in same group have different labels: \(i) has \(lbl), expected \(first)", file: file, line: line)
            }
        }
        // Groups have distinct labels
        let groupRepresentativeLabels = groups.map { labels[$0.first!] }
        let uniqueLabels = Set(groupRepresentativeLabels)
        XCTAssertEqual(uniqueLabels.count, groups.count,
            "Expected \(groups.count) distinct cluster labels, got \(uniqueLabels.count): \(groupRepresentativeLabels)",
            file: file, line: line)
    }

    // MARK: - Tests

    func testThreeClearClusters() {
        let clusterer = HDBSCANClusterer(minPts: 3, minClusterSize: 3, allowSingleCluster: true)
        let labels = clusterer.hdbscan(points: Self.syntheticPoints)

        XCTAssertEqual(labels.count, Self.syntheticPoints.count)
        assertStructuralCorrectness(labels: labels, groups: Self.clusterGroups)

        let nClusters = Set(labels.filter { $0 >= 0 }).count
        XCTAssertGreaterThanOrEqual(nClusters, 3, "Expected at least 3 clusters")
    }

    func testOutliersAreNoiseOrMinority() {
        let clusterer = HDBSCANClusterer(minPts: 3, minClusterSize: 3, allowSingleCluster: true)
        let labels = clusterer.hdbscan(points: Self.syntheticPoints)

        // Outlier indices 15 and 16: both should be noise OR in very small groups.
        // At minimum they must NOT be in the same cluster as any of the 3 main groups.
        for outlierIdx in [15, 16] {
            let outLabel = labels[outlierIdx]
            if outLabel == -1 { continue }  // noise is fine
            // If assigned to a cluster, it must not overlap with A, B, or C groups
            for group in Self.clusterGroups {
                for memberIdx in group {
                    XCTAssertNotEqual(
                        outLabel, labels[memberIdx],
                        "Outlier \(outlierIdx) was merged into group containing index \(memberIdx)"
                    )
                }
            }
        }
    }

    func testSinglePoint() {
        let clusterer = HDBSCANClusterer(minPts: 3, minClusterSize: 3)
        let labels = clusterer.hdbscan(points: [[1, 0, 0]])
        XCTAssertEqual(labels, [-1])
    }

    func testFewerPointsThanMinPts() {
        let clusterer = HDBSCANClusterer(minPts: 5, minClusterSize: 5)
        let labels = clusterer.hdbscan(points: [[1, 0], [0, 1], [0.5, 0.5]])
        XCTAssertTrue(labels.allSatisfy { $0 == -1 })
    }

    func testIdenticalPointsFormOneCluster() {
        let point: [Float] = [0.6, 0.8, 0.0]
        let points = Array(repeating: point, count: 10)
        let clusterer = HDBSCANClusterer(minPts: 3, minClusterSize: 3, allowSingleCluster: true)
        let labels = clusterer.hdbscan(points: points)
        // All points are identical so all should be in cluster 0
        XCTAssertTrue(labels.allSatisfy { $0 == 0 }, "Identical points should cluster together: \(labels)")
    }

    func testClusterEntriesWrapsCorrectly() async throws {
        let clusterer = HDBSCANClusterer(minPts: 3, minClusterSize: 3, allowSingleCluster: true)
        let entries = Self.syntheticPoints.enumerated().map { i, emb in
            ClusterableEntry(bitID: UUID(), embedding: emb, createdAt: Date())
        }
        let assignments = try await clusterer.clusterEntries(entries)
        XCTAssertEqual(assignments.count, entries.count)
        // Check that A-group entries share a cluster ID
        let aLabels = Set(Self.clusterGroups[0].map { assignments[$0].clusterID })
        XCTAssertEqual(aLabels.count, 1, "Cluster A should map to one cluster ID: \(aLabels)")
        XCTAssertFalse(aLabels.contains(-1), "Cluster A should not be noise")
    }

    // MARK: - Oracle agreement

    /// Structural agreement against the Python hdbscan oracle (precomputed on the same data).
    /// Oracle run: hdbscan.HDBSCAN(min_samples=3, min_cluster_size=3, metric='precomputed')
    /// on the cosine distance matrix of the normalized syntheticPoints.
    /// Expected: A→0, B→1, C→2, outliers→-1  (oracle output attached below).
    ///
    /// Oracle labels (python hdbscan 0.8.44, run 2026-07-06):
    ///   [1,1,1,1,1, 2,2,2,2,2, 0,0,0,0,0, -1,-1]
    func testOracleStructuralAgreement() {
        // Oracle expected groups (labels from hdbscan_oracle.py)
        let oracleGroupA = Array(0...4)
        let oracleGroupB = Array(5...9)
        let oracleGroupC = Array(10...14)

        let clusterer = HDBSCANClusterer(minPts: 3, minClusterSize: 3, allowSingleCluster: false)
        let labels = clusterer.hdbscan(points: Self.syntheticPoints)

        // A group: all same label and not noise
        let aLabel = labels[oracleGroupA[0]]
        XCTAssertNotEqual(aLabel, -1, "Oracle group A should not be noise")
        for i in oracleGroupA { XCTAssertEqual(labels[i], aLabel) }

        // B group: all same label and not noise
        let bLabel = labels[oracleGroupB[0]]
        XCTAssertNotEqual(bLabel, -1, "Oracle group B should not be noise")
        for i in oracleGroupB { XCTAssertEqual(labels[i], bLabel) }

        // C group: all same label and not noise
        let cLabel = labels[oracleGroupC[0]]
        XCTAssertNotEqual(cLabel, -1, "Oracle group C should not be noise")
        for i in oracleGroupC { XCTAssertEqual(labels[i], cLabel) }

        // Three distinct labels
        XCTAssertNotEqual(aLabel, bLabel)
        XCTAssertNotEqual(bLabel, cLabel)
        XCTAssertNotEqual(aLabel, cLabel)
    }
}
