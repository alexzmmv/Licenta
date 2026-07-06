import XCTest
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
}
