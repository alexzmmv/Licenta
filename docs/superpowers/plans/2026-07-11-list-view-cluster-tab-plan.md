# List View Cluster Tab & Graph Drilldown Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the "Themes" segmented tab in the entries list view and support tapping on the hub node bottom modal in the graph view to open the focused cluster graph.

---

### Task 1: Implement Segmented Tab in BitsListView

**Files:**
* Modify: [BitsListView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Views/BitsListView.swift)

**Interfaces:**
* Produces: Segmented tab selector ("Entries" vs "Themes") and a cluster grid inside `BitsListView`.

- [ ] **Step 1: Declare Tab Enum and State**
  Add the `Tab` enum and state variable inside `BitsListView` (around line 20):
  ```swift
  @State private var selectedTab: Tab = .entries

  enum Tab: String, CaseIterable {
      case entries = "Entries"
      case themes = "Themes"
  }
  ```

- [ ] **Step 2: Add Segmented Picker to layout**
  Insert the segmented picker in `body` after `headerView`:
  ```swift
  // Find lines around 79 (after headerView)
  headerView

  Picker("View Mode", selection: $selectedTab) {
      ForEach(Tab.allCases, id: \.self) { tab in
          Text(tab.rawValue).tag(tab)
      }
  }
  .pickerStyle(.segmented)
  .padding(.horizontal, 20)
  .padding(.bottom, 12)
  ```

- [ ] **Step 3: Conditionally Render list vs cluster grid**
  Render the search bar, active filters, empty state, and list view only when `selectedTab == .entries`. Render the clusters grid when `selectedTab == .themes`:
  ```swift
  if selectedTab == .entries {
      searchBarView

      if !selectedEmotions.isEmpty || !selectedClusters.isEmpty {
          activeFiltersView
      }

      if filteredBits.isEmpty {
          emptyStateView
      } else {
          bitListView
      }
  } else {
      themesGridView
  }
  ```

- [ ] **Step 4: Implement themesGridView and ClusterCardInList**
  Add the computed properties and `ClusterCardInList` helper:
  ```swift
  private var clustersList: [Cluster] {
      let all = repository.bits
          .compactMap { $0.cluster }
          .filter { $0.index >= 0 }
      var seen = Set<ObjectIdentifier>()
      let uniqueClusters = all.filter { seen.insert(ObjectIdentifier($0)).inserted }
      return uniqueClusters.sorted {
          ($0.bits.compactMap { $0.createdAt }.max() ?? .distantPast) >
          ($1.bits.compactMap { $0.createdAt }.max() ?? .distantPast)
      }
  }

  private var themesGridView: some View {
      ScrollView {
          if clustersList.isEmpty {
              VStack(spacing: 16) {
                  Image(systemName: "circle.hexagongrid")
                      .font(.system(size: 48))
                      .foregroundColor(.gray.opacity(0.4))
                  Text("No themes discovered yet")
                      .foregroundColor(.gray)
              }
              .padding(.top, 60)
          } else {
              LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                  ForEach(clustersList) { cluster in
                      ClusterCardInList(
                          cluster: cluster,
                          journalStart: repository.bits.compactMap { $0.createdAt }.min() ?? Date(),
                          journalEnd: repository.bits.compactMap { $0.createdAt }.max() ?? Date()
                      )
                      .onTapGesture {
                          selectedClusterForGraphID = cluster.index
                      }
                  }
              }
              .padding(.horizontal, 20)
              .padding(.top, 12)
              .padding(.bottom, 40)
          }
      }
  }
  ```
  Add `ClusterCardInList` struct definition at the very bottom of `BitsListView.swift` (similar to `ClusterCard` in `ClusterCardsView.swift`).

- [ ] **Step 5: Verify Build compiles**
  Run: `xcodebuild build -project GJournal.xcodeproj -scheme GJournal -destination "platform=iOS Simulator,name=iPhone 17 Pro"`

---

### Task 2: Implement Spatial Hub Node Bottom Modal Tap in ClusterGraphView

**Files:**
* Modify: [ClusterGraphView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Views/ClusterGraphView.swift)

**Interfaces:**
* Produces: Tap gesture and `.fullScreenCover` navigation from bottom detail card to the focused cluster graph view.

- [ ] **Step 1: Add state variable and Local IdentifiableClusterID Helper**
  Add `@State private var selectedClusterForGraphID: Int? = nil` inside `ClusterGraphView`.
  Add `IdentifiableClusterID` struct at the bottom of the file.

- [ ] **Step 2: Add fullScreenCover modifier to ClusterGraphView**
  Append the cover routing to the body of `ClusterGraphView`:
  ```swift
  .fullScreenCover(item: Binding(
      get: { selectedClusterForGraphID.map { IdentifiableClusterID(id: $0) } },
      set: { selectedClusterForGraphID = $0?.id }
  )) { ident in
      NavigationView {
          ClusterGraphView(repository: repository, filterClusterID: ident.id)
      }
  }
  ```

- [ ] **Step 3: Update nodeDetailCard design for Hub Nodes**
  Modify `nodeDetailCard` in `ClusterGraphView.swift` to:
  * Count entries in the cluster if `node.isHub == true`.
  * Display theme entries count subtitle: `Text("Theme Hub \u{2022} \(entryCount) entries")`.
  * Wrap the card content in a clickable container or button that sets `selectedClusterForGraphID = node.clusterID`.

  ```swift
  @ViewBuilder
  private func nodeDetailCard(_ node: GraphNode) -> some View {
      VStack(alignment: .leading, spacing: 12) {
          HStack {
              if node.isHub {
                  Image(systemName: "circle.grid.hex.fill")
                      .font(.title2)
                      .foregroundColor(colorForCluster(node.clusterID))
              } else {
                  Text(node.emotion.emoji).font(.title2)
              }

              VStack(alignment: .leading, spacing: 2) {
                  Text(node.title).font(.headline).foregroundColor(.white).lineLimit(1)

                  HStack(spacing: 8) {
                      if node.isHub {
                          let entryCount = repository.bits.filter { !$0.isDeleted && $0.clusterID == node.clusterID }.count
                          Text("Theme Hub \u{2022} \(entryCount) \(entryCount == 1 ? "entry" : "entries")")
                              .font(.caption)
                              .foregroundColor(.gray)
                      } else {
                          Text(node.emotion.rawValue).font(.caption).foregroundColor(node.emotion.color)
                          Text("\u{2022}").foregroundColor(.gray)
                          Text(node.createdAt.dayMonth).font(.caption).foregroundColor(.gray)
                      }

                      if !node.isHub, let clusterID = node.clusterID, clusterID >= 0 {
                          Text("\u{2022}").foregroundColor(.gray)
                          HStack(spacing: 4) {
                              Circle().fill(colorForCluster(clusterID)).frame(width: 8, height: 8)
                              Text(layout.clusterNames[clusterID] ?? "Cluster \(clusterID)")
                                  .font(.caption).foregroundColor(.gray)
                          }
                      }
                  }
              }

              Spacer()

              if node.isHub {
                  Image(systemName: "chevron.right.circle.fill")
                      .font(.title2)
                      .foregroundColor(colorForCluster(node.clusterID))
              } else {
                  HStack(spacing: 2) {
                      ForEach(1...4, id: \.self) { level in
                          Circle()
                              .fill(level <= node.intensity ? Color.pink : Color.gray.opacity(0.3))
                              .frame(width: 6, height: 6)
                      }
                  }

                  Button {
                      if let bit = repository.bits.first(where: { $0.id == node.id }) {
                          bitToEdit = bit
                      }
                  } label: {
                      Image(systemName: "chevron.right.circle.fill").font(.title2).foregroundColor(.pink)
                  }
                  .padding(.leading, 8)
              }
          }
      }
      .padding(16)
      .background(
          RoundedRectangle(cornerRadius: 16)
              .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
              .shadow(color: .black.opacity(0.3), radius: 10, y: -5)
      )
      .onTapGesture {
          if node.isHub, let clusterID = node.clusterID {
              selectedClusterForGraphID = clusterID
          }
      }
      .padding(.horizontal, 20).padding(.bottom, 8)
  }
  ```

- [ ] **Step 4: Verify test suite runs successfully**
  Run: `xcodebuild test -project GJournal.xcodeproj -scheme GJournal -destination "platform=iOS Simulator,name=iPhone 17 Pro"`
