# List View Graph Navigation Design Document

## 1. Overview
This specification details the implementation of navigation triggers in GJournal to transition from standard entry list views to spatial cluster graph views. This improves spatial navigation by linking static text lists to the physics-based graph canvas.

---

## 2. Targeted Features & Interactions

### 2.1 "See Theme Graph" Button in list filters
* **Interaction:** In `BitsListView`, when the list is filtered by a single cluster (`selectedClusters.count == 1`), a purple **"See Theme Graph"** button will appear in the active filters scroll view.
* **Result:** Tapping the button opens `ClusterGraphView` pre-filtered for that specific cluster in a fullScreenCover.

### 2.2 Clickable Cluster Badge on Bit Card
* **Interaction:** On each `BitCard` in lists, if the entry belongs to a cluster (i.e., `bit.clusterID != nil && bit.clusterID! >= 0`), a small interactive cluster pill/badge (e.g., `"🏷️ Work Stress"`) will be shown.
* **Result:** Tapping this badge directly opens `ClusterGraphView` for that cluster in a fullScreenCover.

### 2.3 Clickable Cluster Row in Bit Detail View
* **Interaction:** In `BitDetailView` (read-only entry details view), the "Cluster" metadata row is converted to a button.
* **Result:** Tapping this row opens `ClusterGraphView` for that cluster in a fullScreenCover (if opened outside the graph itself).

---

## 3. Implementation Plan & File Structure

### 3.1 State variables to add in `BitsListView`
We will define state variables to track the active cluster graph we want to show:
```swift
@State private var selectedClusterForGraphID: Int? = nil
```
And bind this to a `.fullScreenCover`:
```swift
.fullScreenCover(item: Binding(
    get: { selectedClusterForGraphID.map { IdentifiableInt(id: $0) } },
    set: { selectedClusterForGraphID = $0?.id }
)) { ident in
    NavigationStack {
        ClusterGraphView(repository: repository, filterClusterID: ident.id)
    }
}
```

### 3.2 Displaying the cluster badge on `BitCard`
Inside [BitCard.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Views/BitCard.swift), we will add a new closure property:
```swift
let onClusterTap: ((Int) -> Void)?
```
If a cluster is present on the bit, we render the badge and trigger the closure on click:
```swift
if let clusterID = bit.clusterID, clusterID >= 0 {
    Button {
        onClusterTap?(clusterID)
    } label: {
        HStack(spacing: 4) {
            Image(systemName: "circle.grid.hex.fill")
                .font(.caption2)
            Text(bit.cluster?.displayName ?? "Cluster \(clusterID)")
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(red: 0.55, green: 0.4, blue: 0.95).opacity(0.15))
        .cornerRadius(10)
        .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
    }
    .buttonStyle(.plain)
}
```

### 3.3 Clickable Cluster Row in `BitDetailView`
Convert the static metadata row into an active button:
```swift
if let clusterID = currentBit.clusterID, clusterID >= 0 {
    Button {
        // Triggers transition
        onClusterTap?(clusterID)
    } label: {
        metadataRow(
            title: "Cluster", 
            value: clusterName ?? "Cluster \(clusterID)"
        )
    }
    .buttonStyle(.plain)
}
```

---

## 4. Testing Strategy
1. Filter the list in `BitsListView` to a single cluster. Verify the "See Theme Graph" button appears and tapping it opens the filtered graph view.
2. Verify that `BitCard` in the list displays a cluster badge when it has been processed and clustered. Verify tapping the badge navigates to `ClusterGraphView` for that cluster.
3. Verify that tapping the cluster metadata row in `BitDetailView` opens the correct filtered graph view.
