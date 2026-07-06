# Obsidian-Style Graph Focus Mode Design

## 1. Overview
This design document outlines the implementation of an "Obsidian-like" focus mode for GJournal's `ClusterGraphView`. The goal is to enhance the interactive spatial exploration by dimming unrelated nodes, highlighting direct connections, and introducing a 2.5D depth effect during user interactions (tap and drag).

## 2. Interaction Triggers
The focus mode will activate in two scenarios:
1. **Temporary Focus (Drag/Hold):** Pressing and dragging a node temporarily activates focus mode for that node. Releasing it returns the graph to normal.
2. **Locked Focus (Tap):** Tapping a node selects it, locks the focus mode on that node, and displays the detail card. Tapping the background clears the selection and focus.

## 3. State Management & Data Flow
**View State (`ClusterGraphView.swift`):**
- Introduce a new state variable: `@State private var draggedNodeID: UUID?`
- The current active focus is computed dynamically: `let activeFocusID = draggedNodeID ?? selectedNodeID`

**Engine State (`ForceDirectedLayout.swift`):**
- Add a new method: `func updateFocus(to nodeID: UUID?)`
- When invoked, the engine iterates over its edges to find connections to the given `nodeID` and caches two properties:
  - `focusedNeighborIDs: Set<UUID>`
  - `focusedEdgeIDs: Set<UUID>`
- *Why:* Caching these sets ensures $O(1)$ lookups during the 60 FPS Canvas drawing loop, preventing array filtering bottlenecks.

## 4. Rendering Strategy (Two-Pass Canvas Drawing)
To ensure focused elements are never occluded by dimmed background elements and to establish the 3D depth illusion, the `Canvas` will execute a two-pass drawing sequence when an `activeFocusID` is present.

### Pass 1: The Background (Dimmed)
- **Edges:** Draw all edges NOT in `focusedEdgeIDs` with a low opacity (e.g., `0.1`) and default line weight.
- **Nodes:** Draw all nodes NOT in `focusedNeighborIDs` (and not the focused node itself) with:
  - Opacity reduced to `0.2`
  - Scale factor of `0.9x` (receding into the background)

### Pass 2: The Foreground (Highlighted 3D)
- **Edges:** Draw all edges in `focusedEdgeIDs` with full opacity (`1.0`) and a slightly thicker line weight (`2.0`).
- **Nodes:** Draw the focused node and its neighbors with full brightness and a depth effect:
  - **Focused Node:** Scale factor `1.2x`, plus a Canvas drop shadow filter.
  - **Neighbor Nodes:** Scale factor `1.1x`, plus a lighter Canvas drop shadow filter.
  - *Note:* In SwiftUI Canvas, shadows can be applied using `context.addFilter(.shadow(color:radius:x:y:))`.

## 5. Error Handling & Edge Cases
- **No Connections:** If a focused node has no edges (a "noise" or isolated node), only that node is highlighted; everything else dims.
- **Canvas Reset:** When `activeFocusID` becomes `nil`, the Canvas reverts to the standard single-pass drawing with uniform `1.0` scale and standard opacities.

## 6. Testing Strategy
- Verify that dragging a node correctly triggers the temporary focus without permanently selecting it.
- Verify that tapping a node locks the focus and brings up the detail card.
- Profile the CPU/Memory usage during a drag on a dense graph to ensure the two-pass drawing and shadow filters do not drop the frame rate below 60 FPS.
