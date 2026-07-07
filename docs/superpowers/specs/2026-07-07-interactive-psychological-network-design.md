# Design Spec: Interactive Psychological Network Graph (GGM)

This specification outlines the technical design for making the GGM Psychological Network Graph fully interactive, implementing tap-focus selections (Obsidian mode), edge tap detection, and a dynamic, clinically-framed correlation breakdown card.

---

## 1. Architectural Changes & Data Structures

### 1.1 UI Selection State
In [NetworkGraphView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/Licenta/GJournal/Views/NetworkGraphView.swift), we will introduce two state properties:
```swift
@State private var selectedNode: NetworkVariable? = nil
@State private var selectedEdge: PsychNetworkEdge? = nil
```
Tapping a node will select it. Tapping an edge (by proximity) will select it. Deselecting is achieved by tapping empty canvas space or repeating the tap.

### 1.2 Proximity Math for Edge Selection
To detect which line segment is tapped, we calculate the shortest distance from the tap point $P$ to the line segment between two nodes $A$ and $B$ (representing positions of the edge endpoints).
- Vector calculation:
  Let $v = B - A$ and $w = P - A$.
  The projection factor $t$ is:
  $$t = \max\left(0, \min\left(1, \frac{w \cdot v}{\|v\|^2}\right)\right)$$
  The projection point $Proj = A + t \cdot v$.
  The distance is:
  $$\text{distance} = \|P - Proj\|$$
- If the shortest distance is $< 14.0$ points, we mark that edge as tapped.

---

## 2. Component Design & Layout

### 2.1 Focus Visuals (Opacity & Scale)
- **Node Opacity:**
  - If a node $N$ is selected: $Opacity(N) = 1.0$, $Opacity(Neighbors) = 1.0$, $Opacity(Others) = 0.15$.
  - If an edge $E$ (connecting $U$ and $V$) is selected: $Opacity(U) = 1.0$, $Opacity(V) = 1.0$, $Opacity(Others) = 0.15$.
  - Otherwise: $Opacity(N) = 1.0$.
- **Edge Opacity & Thickness:**
  - If a node $N$ is selected: Connected edges are fully visible (opacity $0.85$), unconnected edges are dimmed to $0.05$.
  - If an edge $E$ is selected: Selected edge is fully visible (opacity $1.0$, line width $+1.0$), other edges are dimmed to $0.05$.
  - Otherwise: Default opacity $0.75$.

### 2.2 The Interactive Clinical Explanation Card
Below the canvas, we will display a glassmorphic detail card:
- **Default State:** *"Tap any node or edge connection line to analyze emotional triggers, feedback loops, and buffers in your psychological network."*
- **Node Selected:**
  - Displays Name and Category (Emotion vs. Behavioral Tag).
  - Displays Centrality (Expected Influence): `Σ|partial correlation weights|`.
  - Explains its importance: *"This variable is highly central. Changes in it trigger strong ripple effects."*
- **Edge Selected (Triggers & Buffers):**
  - Identifies Variable A and Variable B.
  - If weight $> 0$ (Trigger/Coupling):
    - *"**Variable A** and **Variable B** are directly coupled (+X.XX). This indicates a trigger pathway where one tends to amplify the other, independent of other factors."*
  - If weight $< 0$ (Buffer/Compensation):
    - *"**Variable A** acts as a buffer for **Variable B** (-X.XX). This indicates a protective pathway where higher presence of one is associated with a suppression of the other."*

---

## 3. Verification Plan

### 3.1 Unit Testing
Add unit tests to verify:
- Proximity calculations detect segments accurately.
- Centrality values are calculated correctly for custom edge sets.

### 3.2 Manual Verification
- Tap nodes and confirm direct connections are highlighted while others are dimmed.
- Tap edges and confirm the dynamic clinical explanation card renders with correct weights and trigger/buffer descriptions.

---
