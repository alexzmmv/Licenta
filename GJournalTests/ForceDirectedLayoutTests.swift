import XCTest
import SwiftData
@testable import GJournal

final class ForceDirectedLayoutTests: XCTestCase {
    func testUpdateFocus() {
        let layout = ForceDirectedLayout()
        
        let node1 = GraphNode(id: UUID(), title: "1", emotion: .joy, clusterID: 1, createdAt: Date(), intensity: 1, position: .zero)
        let node2 = GraphNode(id: UUID(), title: "2", emotion: .joy, clusterID: 1, createdAt: Date(), intensity: 1, position: .zero)
        let node3 = GraphNode(id: UUID(), title: "3", emotion: .joy, clusterID: 1, createdAt: Date(), intensity: 1, position: .zero)
        
        layout.nodes = [node1, node2, node3]
        
        let edge = GraphEdge(sourceID: node1.id, targetID: node2.id, clusterID: 1)
        layout.edges = [edge]
        
        layout.updateFocus(to: node1.id)
        
        XCTAssertEqual(layout.focusedEdgeIDs.count, 1)
        XCTAssertTrue(layout.focusedEdgeIDs.contains(edge.id))
        
        XCTAssertEqual(layout.focusedNeighborIDs.count, 2) // Should include the node itself and its neighbor
        XCTAssertTrue(layout.focusedNeighborIDs.contains(node1.id))
        XCTAssertTrue(layout.focusedNeighborIDs.contains(node2.id))
        XCTAssertFalse(layout.focusedNeighborIDs.contains(node3.id))
        
        layout.updateFocus(to: nil)
        XCTAssertTrue(layout.focusedEdgeIDs.isEmpty)
        XCTAssertTrue(layout.focusedNeighborIDs.isEmpty)
    }

    func testBuildGraphAndSpreading() throws {
        let layout = ForceDirectedLayout()
        
        let schema = Schema([Bit.self, Cluster.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        
        var bits: [Bit] = []
        var clusterCache: [Int: Cluster] = [:]
        
        func makeBit(clusterID: Int) -> Bit {
            let bit = Bit(feel: "Test feel", event: "event", action: "action", intensity: 2)
            if clusterCache[clusterID] == nil {
                let cluster = Cluster(index: clusterID, name: "Cluster \(clusterID)")
                context.insert(cluster)
                clusterCache[clusterID] = cluster
            }
            bit.cluster = clusterCache[clusterID]
            context.insert(bit)
            return bit
        }
        
        // Create 3 clusters:
        // Cluster 1 has 5 nodes (largest)
        // Cluster 2 has 3 nodes
        // Cluster 3 has 2 nodes (smallest)
        for _ in 0..<5 { bits.append(makeBit(clusterID: 1)) }
        for _ in 0..<3 { bits.append(makeBit(clusterID: 2)) }
        for _ in 0..<2 { bits.append(makeBit(clusterID: 3)) }
        
        try context.save()
        
        layout.buildGraph(from: bits, in: CGSize(width: 800, height: 800))
        
        XCTAssertEqual(layout.nodes.count, 13) // 10 bits + 3 virtual hub nodes
        XCTAssertEqual(layout.clusterNames.count, 3)
        
        // Wait for the asynchronous simulation task to complete
        let expectation = XCTestExpectation(description: "Physics simulation converges")
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            if !layout.isSimulating {
                timer.invalidate()
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Calculate cluster centroids
        let groups = Dictionary(grouping: layout.nodes) { $0.clusterID! }
        var centroids: [CGPoint] = []
        for (_, clusterNodes) in groups {
            let avgX = clusterNodes.reduce(0.0) { $0 + $1.position.x } / CGFloat(clusterNodes.count)
            let avgY = clusterNodes.reduce(0.0) { $0 + $1.position.y } / CGFloat(clusterNodes.count)
            centroids.append(CGPoint(x: avgX, y: avgY))
        }
        
        XCTAssertEqual(centroids.count, 3)
        
        // Verify centroids of different clusters are properly spaced out (no overlaps)
        for i in 0..<centroids.count {
            for j in (i+1)..<centroids.count {
                let d = hypot(centroids[i].x - centroids[j].x, centroids[i].y - centroids[j].y)
                XCTAssertGreaterThan(d, 80.0, "Cluster centers are too close together! Overlap detected.")
            }
        }
    }
}
