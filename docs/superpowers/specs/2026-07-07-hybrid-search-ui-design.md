# Design Spec: Hybrid Search & Dashboard UX Realignment

This spec details the integration of GJournal's Hybrid Semantic Search into the free tier (de-gating it from the paywall), introducing a prominent dashboard search bar, and implementing relevance-based result ranking.

---

## 1. Architectural Changes & Interfaces

### 1.1 Search Gating De-gating
- The **Smart Search** feature is currently gated behind the StoreKit paywall (`isPurchased` checked in [ContentView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/Licenta/GJournal/ContentView.swift)).
- We will change `isPurchased` for the Smart Search `InsightGateCard` to always return `true` (unconditional). The only constraint will be the entry-count data gate ($\ge 10$ entries).
- **Psychological Network Graph** ($\ge 30$ entries) and **Trajectory Analysis** ($\ge 21$ entries) remain fully gated behind the `hasInsights` StoreKit subscription.

### 1.2 Dashboard Section Reordering
We will modify the layout flow inside the vertical ScrollView of [ContentView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/Licenta/GJournal/ContentView.swift) to:
1. `headerSection`
2. `TodayMoodCard` + `WeekMoodStrip` (Current state reflection)
3. **Glassmorphic Search Bar** (New; quick access to memories)
4. `recentEntriesSection` (Moved up for immediate recall)
5. `CalendarView` (Moved below Recent Entries)
6. `TopEmotionsView`
7. `InsightGatingSection` (Network Graph + Trajectory Analysis)

---

## 2. Component Design & User Interactions

### 2.1 The Glassmorphic Search Bar
- **UI:** A rounded-rectangle search bar with an `ultraThinMaterial` background, a thin border matching the dark brand, a search icon (`magnifyingglass`), and placeholder text `"Search memories, emotions, or days..."`.
- **Interactions:**
  - Tapping the search bar sets `showingBitsList = true` and passes `focusSearchOnAppear: true` to [BitsListView](file:///Users/constantin-alexandrudumitrascu/Desktop/Licenta/GJournal/Views/BitsListView.swift).
  - This ensures tapping the search bar on the home screen immediately transitions the user into the search view with the keyboard open.

### 2.2 Search Relevance Sorting in [BitsListView](file:///Users/constantin-alexandrudumitrascu/Desktop/Licenta/GJournal/Views/BitsListView.swift)
- **Sorting Case:** We add a new case to `SortOrder`:
  ```swift
  enum SortOrder: String, CaseIterable {
      case relevance = "Relevance"
      case newestFirst = "Newest First"
      case oldestFirst = "Oldest First"
      case highIntensity = "Highest Intensity"
      case lowIntensity = "Lowest Intensity"
  }
  ```
- **Dynamic Defaulting:**
  - When `searchText` is not empty, the system automatically sets the sort order to `.relevance` (if it was previously newestFirst).
  - While `searchText` is active, the `relevance` option is visible in the sort picker sheet.
  - When `searchText` is cleared, the system resets the sort order back to `.newestFirst` and hides the `.relevance` option from the filter/sort picker (since relevance is meaningless without a search query).
- **Filtering Logic:**
  - If `searchText` is active, [BitsListView](file:///Users/constantin-alexandrudumitrascu/Desktop/Licenta/GJournal/Views/BitsListView.swift) runs the advanced hybrid search engine `hybridSearch.search(query: searchText)`.
  - The results are intersected with other selected filters (emotions, clusters, intensity) while preserving the relevance-ranked order.

---

## 3. Testing and Verification Plan

### 3.1 Unit Testing
- Verify that `BaseJournalRepository.searchBits(query: ...)` runs the hybrid search.
- Add unit tests in `GJournalTests` to assert:
  - Non-empty search query returns relevance-sorted results.
  - Intersection of search query with emotion/cluster filters compiles and filters correctly.

### 3.2 UI Integration Testing
- Verify that clicking the dashboard search bar focuses the keyboard in `BitsListView`.
- Verify that clearing search resets the sort order and hides the relevance option.
- Verify that the paywall does not show up when tapping "Smart Search" on the dashboard.

---
