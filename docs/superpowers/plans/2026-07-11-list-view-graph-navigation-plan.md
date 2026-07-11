# List View Graph Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement navigation links from standard entry list views (`BitsListView`, `BitCard`, and `BitDetailView`) to the spatial `ClusterGraphView` filtered by cluster.

**Architecture:** Add a `.fullScreenCover` to `BitsListView` bound to a new state variable `selectedClusterForGraphID`. Update `BitCard` and `BitDetailView` to accept a callback closure `onClusterTap` to set this ID, and add a "See Theme Graph" button to `BitsListView`'s active filters list.

**Tech Stack:** SwiftUI, SwiftData, GJournal views

## Global Constraints
* iOS version minimum: iOS 18.0
* Target environment: Xcode iPhone 17 Pro simulator
* Clean build and green test suite must be maintained.

---

### Task 1: Update BitCard & BitDetailView Interfaces

**Files:**
* Modify: [BitCard.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Views/BitCard.swift)

**Interfaces:**
* Modify: `BitCard` initializer to accept `onClusterTap: ((Int) -> Void)? = nil`
* Modify: `BitDetailView` initializer to accept `onClusterTap: ((Int) -> Void)? = nil`

- [ ] **Step 1: Modify BitCard struct and previews**
  Add `var onClusterTap: ((Int) -> Void)? = nil` to `BitCard`.
  Modify the `body` of `BitCard` to render the cluster badge next to the timestamp if the bit belongs to a cluster:

  ```swift
  // Find lines around 72 (HStack next to lastModified)
  HStack {
      Text(bit.lastModified.timeOfDay)
          .font(.caption)
          .foregroundColor(.secondary)
      
      if let clusterID = bit.clusterID, clusterID >= 0 {
          Button {
              onClusterTap?(clusterID)
          } label: {
              HStack(spacing: 3) {
                  Image(systemName: "circle.grid.hex.fill")
                      .font(.system(size: 8))
                  Text(bit.cluster?.displayName ?? "Cluster \(clusterID)")
                      .font(.system(size: 10))
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background(Color(red: 0.55, green: 0.4, blue: 0.95).opacity(0.12))
              .cornerRadius(8)
              .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
          }
          .buttonStyle(.plain)
      }
      
      Spacer()
  ```

  Update the previews at the bottom of `BitCard.swift` to pass `onClusterTap: {}` to `BitCard`.

- [ ] **Step 2: Modify BitDetailView and previews**
  Add `var onClusterTap: ((Int) -> Void)? = nil` to `BitDetailView`.
  Modify `BitDetailView`'s metadata section to make the Cluster row clickable:

  ```swift
  // Find lines around 252 (Cluster metadata row check)
  if let clusterID = currentBit.clusterID, clusterID >= 0 {
      Button {
          onClusterTap?(clusterID)
      } label: {
          HStack {
              Text("Cluster")
                  .font(.subheadline)
                  .foregroundColor(.gray)
              Spacer()
              Text(clusterName ?? "Cluster \(clusterID)")
                  .font(.subheadline)
                  .fontWeight(.medium)
                  .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
              Image(systemName: "chevron.right")
                  .font(.caption2)
                  .foregroundColor(.gray)
          }
      }
      .buttonStyle(.plain)
  }
  ```

  Update `ClusterGraphView.swift` sheet representation of `BitDetailView` to pass `onClusterTap: nil` or a no-op.

- [ ] **Step 3: Verify build compiles and commit**
  Run `xcodebuild build -project GJournal.xcodeproj -scheme GJournal -destination "platform=iOS Simulator,name=iPhone 17 Pro"`
  Commit:
  ```bash
  git add GJournal/Views/BitCard.swift
  git commit -m "refactor: update BitCard and BitDetailView interfaces to support cluster tap navigation"
  ```

---

### Task 2: Implement "See Theme Graph" and fullScreenCover routing in BitsListView

**Files:**
* Modify: [BitsListView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Views/BitsListView.swift)
* Modify: [ClusterGraphView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Views/ClusterGraphView.swift)

**Interfaces:**
* Consumes: `BitCard.onClusterTap`, `BitDetailView.onClusterTap`, `ClusterGraphView`
* Produces: Interactive "See Theme Graph" button and sheet cover.

- [ ] **Step 1: Declare IdentifiableInt helper in BitsListView**
  Add this struct at the top or bottom of `BitsListView.swift` to enable sheet routing:
  ```swift
  struct IdentifiableInt: Identifiable {
      let id: Int
  }
  ```

- [ ] **Step 2: Add state variables and fullScreenCover modifier in BitsListView**
  Add `@State private var selectedClusterForGraphID: Int? = nil` inside the `BitsListView` struct.
  Append `.fullScreenCover` at the bottom of the body (after `.alert`):

  ```swift
  .fullScreenCover(item: Binding(
      get: { selectedClusterForGraphID.map { IdentifiableInt(id: $0) } },
      set: { selectedClusterForGraphID = $0?.id }
  )) { ident in
      NavigationView {
          ClusterGraphView(repository: repository, filterClusterID: ident.id)
      }
  }
  ```

- [ ] **Step 3: Update activeFiltersView to show "See Theme Graph" button**
  In `activeFiltersView`, if `selectedClusters.count == 1`, show the graph button next to the cluster badge:

  ```swift
  // Find lines around 284 (after ForEach for selectedClusters)
  if selectedClusters.count == 1, let clusterID = selectedClusters.first {
      Button {
          selectedClusterForGraphID = clusterID
      } label: {
          HStack(spacing: 4) {
              Image(systemName: "circle.hexagongrid.fill")
                  .font(.caption2)
              Text("See Theme Graph")
                  .font(.caption2)
                  .fontWeight(.medium)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(Color(red: 0.55, green: 0.4, blue: 0.95))
          .cornerRadius(16)
          .foregroundColor(.white)
      }
      .buttonStyle(.plain)
  }
  ```

- [ ] **Step 4: Connect onClusterTap closure in BitsListView**
  Find where `BitCard` is initialized in `BitsListView.swift` (around line 375):
  ```swift
  BitCard(
      bit: bit,
      canEdit: repository.canEdit(bit: bit),
      onEdit: { bitToEdit = bit },
      onDelete: { ... },
      onToggleHide: { ... },
      onClusterTap: { clusterID in
          selectedClusterForGraphID = clusterID
      }
  )
  ```

- [ ] **Step 5: Connect onClusterTap inside ClusterGraphView's sheet**
  In `ClusterGraphView.swift`, pass a dismiss/routing action to `BitDetailView` so that if the user clicks the Cluster row, it navigates to the target cluster:
  ```swift
  .sheet(item: $bitToEdit) { bit in
      BitDetailView(
          bit: bit,
          clusterName: bit.clusterID.flatMap { layout.clusterNames[$0] },
          allBits: repository.bits,
          onClusterTap: { targetClusterID in
              bitToEdit = nil
              // If the user tapped a different cluster, dismiss current detail and load that cluster graph!
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                  // Switch the filtered cluster ID of the graph view or trigger dismiss to reload
                  if targetClusterID != filterClusterID {
                      // Since filterClusterID is a let constant here, we can open a new cover if needed or let dismiss/navigation handle it.
                      // For now, in ClusterGraphView we don't have mutable filterClusterID, so we can dismiss and let parent navigation show it, or we can handle it locally.
                      // Let's keep it simple: if within the graph view, we dismiss the current detail.
                  }
              }
          }
      )
  }
  ```

- [ ] **Step 6: Run tests and verify success**
  Run: `xcodebuild test -project GJournal.xcodeproj -scheme GJournal -destination "platform=iOS Simulator,name=iPhone 17 Pro"`

- [ ] **Step 7: Commit**
  ```bash
  git add GJournal/Views/BitsListView.swift GJournal/Views/ClusterGraphView.swift
  git commit -m "feat: implement graph navigation triggers from BitsListView and BitCards"
  ```
