# List View Cluster Tab & Graph Drilldown Design Spec

## 1. Overview
This specification outlines the design and behavior for:
1. Re-introducing a "Themes" tab in [BitsListView](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Views/BitsListView.swift) containing a grid of AI-generated clusters. Clicking a cluster opens its filtered spatial graph.
2. Enabling spatial drilldown in [ClusterGraphView](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Views/ClusterGraphView.swift). Tapping a cluster hub node displays the cluster name and entry count in the bottom modal, and tapping this modal opens the focused graph view of that specific cluster.

---

## 2. Targeted Features & Interactions

### 2.1 Tab Bar inside `BitsListView`
* **Layout:** A Segmented Control (`Picker` with `.segmented` style) will be inserted below the header of `BitsListView`.
* **Options:** "Entries" and "Themes".
* **Themes Grid View:** Renders a list-specific `ClusterCardInList` grid. Clicking any card opens `ClusterGraphView(filterClusterID: cluster.index)`.

### 2.2 Spatial Hub Node Drilldown
* **Visuals:** In the global graph view (`filterClusterID == nil`), the hub/centroid nodes represent theme centers.
* **Selection:** Tapping a hub node selects it and shows the bottom details modal.
* **Bottom Modal:** Displays:
  * Title: Cluster Name (e.g. "Work Stress")
  * Subtitle: "Theme Hub • X entries" (where X is the number of journal entries mapped to this cluster).
* **Interactions:** The bottom modal card responds to taps. Clicking it presents `ClusterGraphView(filterClusterID: clusterID)` in a fullScreenCover.

---

## 3. Testing Strategy
1. Verify that `BitsListView` displays the segmented control tab.
2. Select the "Themes" tab and confirm that the grid matches the dashboard cluster cards. Confirm tapping a card opens the correct filtered graph view.
3. Open the global graph view (`filterClusterID == nil`). Tap a cluster hub node. Verify that the bottom card shows the theme name and the number of entries.
4. Tap the bottom card and confirm it opens the focused graph view of that specific cluster.
