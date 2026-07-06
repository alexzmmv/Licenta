# Obsidian-Style Graph Focus Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement an interactive 2.5D focus mode for the graph view that highlights a selected/dragged node and its connections while dimming the rest of the graph, simulating an Obsidian-style network exploration.

**Architecture:** We add focus state properties to the `ForceDirectedLayout` engine that compute and cache active edges/neighbors in $O(1)$ time. `ClusterGraphView` uses these cached properties to execute a two-pass Canvas render, separating the dimmed background from a scaled, drop-shadowed foreground.

**Tech Stack:** Swift, SwiftUI (Canvas), XCTest

## Global Constraints

- No external dependencies
- Maintain 60 FPS rendering in Canvas (avoid array filtering inside the draw loop)

---

### Task 1: Engine State & Focus Calculation

**Files:**
- Create: `GJournalTests/ForceDirectedLayoutTests.swift`
- Modify: `GJournal/Services/GraphPhysicsEngine.swift`

**Interfaces:**
- Produces: `ForceDirectedLayout.focusedNeighborIDs` (Set<UUID>), `ForceDirectedLayout.focusedEdgeIDs` (Set<UUID>), `ForceDirectedLayout.updateFocus(to: UUID?)`

- [ ] **Step 1: Write the failing test**

```swift
// GJournalTests/ForceDirectedLayoutTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project GJournal.xcodeproj -scheme GJournalTests -destination 'platform=iOS Simulator,name=iPhone 15'`
Expected: FAIL with "Value of type 'ForceDirectedLayout' has no member 'updateFocus'"

- [ ] **Step 3: Write minimal implementation**

Modify `GJournal/Services/GraphPhysicsEngine.swift:28-34` to add properties and the method:

```swift
class ForceDirectedLayout: ObservableObject {
    @Published var nodes: [GraphNode] = []
    @Published var edges: [GraphEdge] = []
    @Published var clusterNames: [Int: String] = [:]
    @Published var isSimulating = false
    
    @Published var focusedNeighborIDs: Set<UUID> = []
    @Published var focusedEdgeIDs: Set<UUID> = []
    
    func updateFocus(to nodeID: UUID?) {
        guard let focusID = nodeID else {
            focusedNeighborIDs.removeAll()
            focusedEdgeIDs.removeAll()
            return
        }
        
        var neighborIDs = Set<UUID>([focusID])
        var edgeIDs = Set<UUID>()
        
        for edge in edges {
            if edge.sourceID == focusID || edge.targetID == focusID {
                edgeIDs.insert(edge.id)
                neighborIDs.insert(edge.sourceID == focusID ? edge.targetID : edge.sourceID)
            }
        }
        
        focusedNeighborIDs = neighborIDs
        focusedEdgeIDs = edgeIDs
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project GJournal.xcodeproj -scheme GJournalTests -destination 'platform=iOS Simulator,name=iPhone 15'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add GJournalTests/ForceDirectedLayoutTests.swift GJournal/Services/GraphPhysicsEngine.swift
git commit -m "feat: add focus state tracking to force directed layout"
```

---

### Task 2: Interaction State & Two-Pass Rendering

**Files:**
- Modify: `GJournal/Views/ClusterGraphView.swift`

**Interfaces:**
- Consumes: `ForceDirectedLayout.focusedNeighborIDs`, `ForceDirectedLayout.focusedEdgeIDs`, `ForceDirectedLayout.updateFocus(to: UUID?)`

- [ ] **Step 1: Update State and Gestures**

Modify `GJournal/Views/ClusterGraphView.swift` around line 14:
```swift
    @State private var selectedNodeID: UUID?
    @State private var draggedNodeID: UUID?
```

Modify the `DragGesture` inside the View body (around line 93):
```swift
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragOffset = value.translation
                            
                            // Temporary focus on drag
                            let graphPoint = adjustPoint(value.location)
                            if let hitID = hitTest(at: graphPoint) {
                                if draggedNodeID != hitID {
                                    draggedNodeID = hitID
                                    layout.updateFocus(to: hitID)
                                }
                            }
                        }
                        .onEnded { value in
                            let t = value.translation
                            dragOffset = .zero
                            let graphPoint = adjustPoint(value.startLocation)
                            let hitID = hitTest(at: graphPoint)
                            
                            if hypot(t.width, t.height) < 8 {
                                withAnimation(.spring(response: 0.3)) {
                                    if let id = hitID {
                                        selectedNodeID = (selectedNodeID == id) ? nil : id
                                    } else {
                                        selectedNodeID = nil
                                    }
                                }
                            } else {
                                offset.width += t.width
                                offset.height += t.height
                            }
                            
                            // Clear drag focus and update layout to current selection
                            draggedNodeID = nil
                            layout.updateFocus(to: selectedNodeID)
                        }
                )
```

- [ ] **Step 2: Update Canvas Rendering**

Replace the Canvas drawing loops (lines 53-81) with the two-pass architecture.

```swift
                    let activeFocus = layout.focusedNeighborIDs.isEmpty ? false : true

                    // PASS 1: BACKGROUND (Dimmed)
                    for edge in layout.edges {
                        if activeFocus && layout.focusedEdgeIDs.contains(edge.id) { continue }
                        guard let src = layout.nodes.first(where: { $0.id == edge.sourceID }),
                              let dst = layout.nodes.first(where: { $0.id == edge.targetID }) else { continue }
                        var path = Path()
                        path.move(to: src.position)
                        path.addLine(to: dst.position)
                        let opacity = activeFocus ? 0.05 : Double(max(0.2, min(0.9, edge.similarity))) * 0.6
                        context.stroke(path, with: .color(colorForCluster(edge.clusterID).opacity(opacity)), lineWidth: 1)
                    }

                    for node in layout.nodes {
                        if activeFocus && layout.focusedNeighborIDs.contains(node.id) { continue }
                        drawNode(node, context: &context, isSelected: false, isDimmed: activeFocus, isFocused: false)
                    }

                    // PASS 2: FOREGROUND (Focused)
                    if activeFocus {
                        for edge in layout.edges {
                            if !layout.focusedEdgeIDs.contains(edge.id) { continue }
                            guard let src = layout.nodes.first(where: { $0.id == edge.sourceID }),
                                  let dst = layout.nodes.first(where: { $0.id == edge.targetID }) else { continue }
                            var path = Path()
                            path.move(to: src.position)
                            path.addLine(to: dst.position)
                            context.stroke(path, with: .color(colorForCluster(edge.clusterID).opacity(1.0)), lineWidth: 2)
                        }

                        for node in layout.nodes {
                            if !layout.focusedNeighborIDs.contains(node.id) { continue }
                            let isTarget = node.id == (draggedNodeID ?? selectedNodeID)
                            drawNode(node, context: &context, isSelected: node.id == selectedNodeID, isDimmed: false, isFocused: isTarget)
                        }
                    }
```

- [ ] **Step 3: Extract and Enhance `drawNode` Method**

Add this helper inside `ClusterGraphView` to handle the rendering and 3D depth.

```swift
    private func drawNode(_ node: GraphNode, context: inout GraphicsContext, isSelected: Bool, isDimmed: Bool, isFocused: Bool) {
        let isNoise = node.clusterID == nil || node.clusterID == -1
        let clusterColor = colorForCluster(node.clusterID)
        
        let scale: CGFloat = isFocused ? 1.2 : (isDimmed ? 0.9 : (isSelected || !isDimmed && layout.focusedNeighborIDs.contains(node.id) ? 1.1 : 1.0))
        let opacity: Double = isDimmed ? 0.2 : 1.0
        
        let rect = CGRect(x: node.position.x - (70 * scale), y: node.position.y - (18 * scale), width: 140 * scale, height: 36 * scale)
        let nodePath = Path(roundedRect: rect, cornerRadius: 12 * scale)
        
        var shadowContext = context
        if !isDimmed && layout.focusedNeighborIDs.contains(node.id) {
            shadowContext.addFilter(.shadow(color: .black.opacity(isFocused ? 0.8 : 0.4), radius: isFocused ? 8 : 4, x: 0, y: isFocused ? 4 : 2))
        }

        shadowContext.fill(nodePath, with: .color(
            isSelected ? clusterColor.opacity(0.3 * opacity) : Color(red: 0.1, green: 0.1, blue: 0.12).opacity(opacity)
        ))
        shadowContext.stroke(nodePath, with: .color(
            isSelected ? Color.white.opacity(opacity) : clusterColor.opacity(isNoise ? (0.4 * opacity) : (0.8 * opacity))
        ), lineWidth: isSelected ? 2 : 1)

        shadowContext.draw(
            Text("\(node.emotion.emoji) \(node.title)").font(.caption2).foregroundColor(Color.white.opacity(opacity)),
            in: CGRect(x: rect.minX + 6, y: rect.minY, width: rect.width - 12, height: rect.height)
        )
    }
```

- [ ] **Step 4: Verify UI Manually**
Build the app and navigate to the Graph View. Verify that holding/dragging a node scales it up, adds a shadow, dims unrelated nodes, and highlights its connections. Releasing it should restore the state. Tapping it should lock the focus.

- [ ] **Step 5: Commit**

```bash
git add GJournal/Views/ClusterGraphView.swift
git commit -m "feat: implement 2.5D focus mode rendering on graph canvas"
```
