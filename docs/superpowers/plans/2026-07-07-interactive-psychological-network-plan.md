# Implementation Plan: Interactive GGM Network Graph

This plan details the steps to build the interactive features, edge tap gesture mapping, highlighting/dimming modifiers, and explanation card inside [NetworkGraphView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/Licenta/GJournal/Views/NetworkGraphView.swift).

---

## Tasks

### Task 1: Proximity Math Helpers & UI State
- **File:** [NetworkGraphView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/Licenta/GJournal/Views/NetworkGraphView.swift)
- **Changes:**
  - Declare state variables:
    ```swift
    @State private var selectedNode: NetworkVariable? = nil
    @State private var selectedEdge: PsychNetworkEdge? = nil
    ```
  - Implement geometry helper functions inside `NetworkGraphView`:
    ```swift
    private func distanceToSegment(p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat
    private func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat
    ```

### Task 2: Gestures & Drawing Updates
- **File:** [NetworkGraphView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/Licenta/GJournal/Views/NetworkGraphView.swift)
- **Changes:**
  - Wrap the `Canvas` inside a `.gesture(SpatialTapGesture().onEnded { ... })` (or `DragGesture(minimumDistance: 0).onEnded { ... }`) to intercept coordinate taps.
  - Locate the closest edge to the tapped coordinate. If the distance is $< 14.0$, select the edge and deselect nodes. If the click was on empty space, clear all selection.
  - Add `.onTapGesture` to each node button view to select that node (clearing edge selection).
  - Update `Canvas` stroke loop:
    - If a node is selected, set line opacity to `0.85` for connected edges, `0.05` for unconnected.
    - If an edge is selected, set line opacity to `1.0` for selected edge, `0.05` for others. Set selected edge line width to `lw + 1.5`.
    - Otherwise, draw default line opacity `0.75`.

### Task 3: Node Visual Updates (Dimming/Highlighting)
- **File:** [NetworkGraphView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/Licenta/GJournal/Views/NetworkGraphView.swift)
- **Changes:**
  - Calculate visibility opacity for each node based on selection state.
  - If a node is selected:
    - Target node has opacity `1.0`, scale `1.15`, and a subtle ring glow.
    - Neighbor nodes (having an edge connecting them to the target) have opacity `1.0`.
    - Other nodes have opacity `0.15`.
  - If an edge is selected:
    - The two endpoints have opacity `1.0` and scale `1.1`.
    - Other nodes have opacity `0.15`.
  - Apply the opacity and scale animations using standard SwiftUI `.animation(.spring(), value: selectedNode)`/`.animation(.spring(), value: selectedEdge)`.

### Task 4: Dynamic Clinical Analysis Card
- **File:** [NetworkGraphView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/Licenta/GJournal/Views/NetworkGraphView.swift)
- **Changes:**
  - Add a vertical Stack below the Canvas geometry reader to display the details card.
  - Style it with a beautiful translucent glass card modifier, custom padding, and appropriate text hierarchies.
  - Add dynamic logic to construct Triggers & Buffers explanations based on edge partial correlation weights.

---
