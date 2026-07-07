# Implementation Plan: Hybrid Search & Dashboard UX Realignment

This plan outlines the steps required to implement the de-gated Hybrid Search, the glassmorphic dashboard search bar, and the relevance-based sorting inside the list view.

---

## Tasks

### Task 1: Repository Search Implementation
- **File:** [BaseJournalRepository.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/Licenta/GJournal/Repository/BaseJournalRepository.swift)
- **Changes:**
  - Update `searchBits(...)` to call `hybridSearch.search(query: trimmedQuery)` when the search query is non-empty.
  - If a search query is active, return the results directly (which are already sorted by relevance score from the hybrid search engine).
  - Apply the active filters (emotions, clusters, intensities, date ranges) on top of the search results.

### Task 2: Search List UI & Relevance Sorting
- **File:** [BitsListView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/Licenta/GJournal/Views/BitsListView.swift)
- **Changes:**
  - Add `@FocusState private var isSearchFieldFocused: Bool` to manage keyboard focus.
  - Add `focusSearchOnAppear: Bool` parameter to initializers (defaulting to `false`).
  - In `.onAppear`, if `focusSearchOnAppear` is true, set `isSearchFieldFocused = true` inside a short `DispatchQueue.main.asyncAfter` delay to ensure keyboard focuses cleanly.
  - Add `.relevance = "Relevance"` case to `SortOrder` enum.
  - In `updateFilteredData()`:
    - If `searchText` is not empty, and the current `sortOrder` is `.newestFirst`, set `sortOrder = .relevance`.
    - If `sortOrder == .relevance`, skip the sorting step since `searchBits` already returns relevance-sorted results.
    - If `searchText` becomes empty, reset `sortOrder = .newestFirst`.
  - In the sorting picker selection sheet (inside `FilterSheetView`), conditionally hide the `.relevance` sorting option if `searchText` is empty.

### Task 3: Dashboard Layout Rearrangement & Search Bar UI
- **File:** [ContentView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/Licenta/GJournal/ContentView.swift)
- **Changes:**
  - In the vertical ScrollView, reorder the sections to:
    - `headerSection`
    - `TodayMoodCard` + `WeekMoodStrip`
    - **Glassmorphic Search Bar**
    - `recentEntriesSection`
    - `CalendarView`
    - `TopEmotionsView`
    - `InsightGatingSection`
  - Implement the Glassmorphic Search Bar:
    - Design a glassmorphic pill view (`.ultraThinMaterial` background, circular border with slight opacity, search glass icon, and placeholder text).
    - Attach an `.onTapGesture` that triggers `showingBitsList = true` and passes `focusSearchOnAppear: true` in the navigation presentation.
  - In `InsightGatingSection`, update the "Smart Search" `InsightGateCard` parameters to pass `isPurchased: true`.

### Task 4: Testing & Verification
- Run compilation: verify no errors.
- Run unit test suite: verify all tests pass.
- Manually verify in the simulator:
  - Search bar exists on dashboard, tapping it presents search list with keyboard open.
  - Typing in search automatically sorts by relevance, showing the most semantically relevant memories at the top.
  - Tapping "Smart Search" opens it without showing the paywall, even on the free tier.

---
