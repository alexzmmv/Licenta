# GJournal Task List (Tiered)

This list categorizes the remaining tasks from `plan.md` across 4 Tiers of Necessity (from Critical Foundation down to Optional Fallbacks) and 3 Tiers of Difficulty (Easy, Medium, Hard).

> **Status (2026-07-07): Tier 1 + Tier 2 (Easy/Medium/Hard) all complete.** All four Tier 2 Hard innovation pillars shipped and tested — Swift HDBSCAN, GGM Estimator (Pillar A, exact sklearn Ledoit-Wolf parity + behavioral-tag variables), Persistent Homology (Pillar B, ripser-validated β0/β1 + trajectory biomarkers), and the Behavioral Tags Engine (SchemaV2, field-scoped extraction, embedding canonicalization). **88 unit tests green.** Python oracles: `training/{hdbscan_oracle,ggm_oracle,ph_oracle}.py`. Next: Tier 3 (Crisis Safety, Onboarding, TestFlight, Accessibility).

## 🟥 Tier 1: Essential – The Non-Negotiable Foundation ✅
*These are critical tasks that block the app from being safe, stable, or accepted into the App Store.*

### 🟢 Easy
- [x] **Dead Model Cleanup:** Delete 261MB of unused Nomic/MobileBERT models, services, and vocab files to drastically reduce bundle size. *(Done: ~440MB → 137MB. Removed the `.nomicFull`/`.nomicMRL` enum cases too — old stored preferences fall back to MiniLM, covered by a regression test. The last step to ~90MB is quantizing the emotion classifier — carried over to Tier 2.)*
- [x] **App Store Mechanics:** Add the App Icon, `PrivacyInfo.xcprivacy`, FaceID reason string, and bump the minimum iOS version to 18.0.
- [x] **Compute Units Optimization:** Request `.all` compute units (ANE) for CoreML services.
- [x] **Settings Refactor:** Set `.miniLM` as the single source of truth, split `SettingsView`, and hide destructive debug tools behind `#if DEBUG`.

### 🟡 Medium
- [x] **Data Loss Prevention:** Remove the dangerous "wipe-store-and-recreate" fallback in `makeModelContainer` and implement the `StoreRecoveryView`.
- [x] **Versioned Backup:** Implement explicit JSON export/backup in `LocalJournalRepository`.
- [x] **Test Suite Foundation:** Set up the `GJournalTests` target with smoke tests and WordPiece golden fixtures.

### 🔴 Hard
- [x] **Schema Migration:** Implement `SchemaV1` and `GJournalMigrationPlan` to safely handle future data model updates without corrupting user journals.

---

## 🟧 Tier 2: High Necessity – The Innovation Core
*These are the flagship features that define the paid product and differentiate GJournal from competitors.*

### 🟢 Easy ✅
- [x] **Gating Logic:** Implement minimum data gates (e.g., ≥30 entries for Network Graph, ≥21 for Trajectory). *(Done: `InsightGatingSection` added to dashboard with animated progress rings; gates at 30 entries+14 days for Network, 21+21 for Trajectory, 10 for Smart Search.)*
- [x] **Noise UX:** Update `ClusterCardsView` to handle unclustered "Unsorted" entries gracefully instead of hiding them. *(Done: `UnsortedCard` added — noise entries with `clusterID == -1` surface as a dedicated card in the cluster grid.)*
- [x] **Emotion Classifier Quantization** *(carried over from Tier 1)*: Write `training/quantize_emotion.py` (coremltools palettization/int8) to shrink `GJournalEmotionClassifier` 94MB → ~47MB. *(Done: int8 linear per-channel symmetric quantization via coremltools 9. 93.9 MB → 25.0 MB (−73%). top-1 agreement 100/100, softmax-MAE = 0.000000. fp32 backup in `training/`. Total model bundle: 43 MB MiniLM + 25 MB emotion = 68 MB.)*

### 🟡 Medium ✅
- [x] **Semantic Memory Search (Pillar C):** Build `HybridSearchService` combining in-memory BM25 keyword search with vector cosine scans using Reciprocal Rank Fusion. *(Done: BM25 with k1=1.2, b=0.75, prefix fallback; pseudo-relevance centroid as query vector; RRF k=60. Wired into BitsListView (hybrid ranking preserved, intersected with emotion/cluster filters) and DayDetailView (Related entries section, cos ≥ 0.45, top-3). Related entries in BitDetailView now use full cross-cluster pool via allBits param.)*
- [x] **Network Graph & Trajectory UIs:** Extract the `GraphPhysicsEngine` for the `NetworkGraphView` and build the `TrajectoryView` dashboard. *(Done: GraphNode, GraphEdge, ForceDirectedLayout extracted from ClusterGraphView into Services/GraphPhysicsEngine.swift. Full NetworkGraphView/TrajectoryView deferred — pending GGM Estimator and PersistentHomology (Tier 2 Hard).)*
- [x] **Paywall (StoreKit 2):** Implement `EntitlementManager`, `PaywallView`, and the non-consumable "GJournal Insights" purchase flow. *(Done: EntitlementManager using @Observable + Transaction.updates listener; PaywallView with 3 feature rows, gradient purchase button, restore; GJournal.storekit config (product ID: com.gjournal.insights, $4.99, familyShareable). InsightGatingSection updated with Unlock/Open/Soon badge logic. Note: set GJournal.storekit in Xcode scheme → Run → Options → StoreKit Configuration for local sandbox.)*

### 🔴 Hard
- [x] **Swift HDBSCAN:** Build HDBSCAN (mutual reachability, MST, cluster extraction) natively in Swift and validate it against a Python oracle. *(Done: HDBSCANClusterer.swift — cosine dist matrix → core dists → Prim's MST → single-linkage dendrogram (Union-Find) → condensed tree → EOM extraction. Validated against hdbscan 0.8.44 Python oracle (training/hdbscan_oracle.py, precomputed cosine metric). 7/7 HDBSCAN unit tests pass; 33/33 total. Wired as ClusteringStrategyChoice.hdbscan; ServiceContainer + AIProcessingManager updated. Not the default — classic DBSCAN remains default.)*
- [x] **GGM Estimator (Pillar A):** Implement Ledoit-Wolf shrinkage and partial correlation math to generate the psychological network graph. *(Done: `GGMEstimator` — Tier 1 (Spearman + Benjamini-Hochberg FDR q=0.10 + 8/10 bootstrap) and Tier 2 (exact sklearn Ledoit-Wolf shrinkage ported from the data matrix, validated to <1e-9 vs sklearn; Cholesky precision → partial correlations, bootstrap-stable, ≤20 edges). Variables generalized to `NetworkVariable` = 12 continuous emotions + top-K binary behavioral tags (≤n/5, ≤8/category) — `InsightEngine` builds the combined matrix, `NetworkGraphView` renders emotion + behavior nodes. Exact 40×6 sklearn parity fixture (λ=0.0784299, partial corrs to 1e-4). 24 GGM tests green.)*
- [x] **Persistent Homology (Pillar B):** Implement exact Vietoris-Rips β0/β1 persistence in Swift for sliding 30-day windows to track "Rumination" loops. *(Done: `PersistentHomology.swift` — Z/2 boundary-matrix reduction over vertices/edges/triangles yields the full H0+H1 diagram; validated against a ripser oracle (`training/ph_oracle.py`) on deterministic fixtures (square→[1,√2), octagon→[0.765,1.848), triangle/blobs→no loop). `TrajectoryService` computes rumination (loop persistence + spatial permutation-null p<0.05), flare index (convex-hull area / enclosing square in PCA-2D), and Semantic Recovery Velocity (slope of distance-from-distress-anchor). `TrajectoryPersonas` (ruminator/explorer/recoverer) validate each signature metric fires. `TrajectoryEngine` (@Observable) + `TrajectoryView` wired into ContentView's Trajectory card. 18 new tests green (12 PH + 6 trajectory).)*
- [x] **Behavioral Tags Engine:** Implement `TagExtractor` using NLTagger and canonicalize tags dynamically via embedding cosine similarity. *(Done: SchemaV2 adds `BehavioralTag` registry (lemma/category/count/lastSeen/embedding, GGM-eligible ≥5×) + denormalized `Bit.tagLemmas` → purely additive lightweight migration. `TagExtractor` uses field-scoped extraction (Event→event tags, Action→action tags) via NLTokenizer + stopwords, with NLTagger lemmatization best-effort — deliberately not depending on lexicalClass/lemma models which are absent on the iOS simulator. `TagProcessor` extracts→embeds→merges at cosine ≥0.85 (else creates)→bumps counts, wired into `AIProcessingManager` + one-shot backfill. `TagManagementView` in Settings. 87 tests green.)*

---

## 🟨 Tier 3: Moderate Necessity – Launch & Polish
*These are required for a successful public release, user retention, and App Review compliance, but they don't block core development.*

### 🟢 Easy
- [ ] **UI Polish (views audit findings):**
  - [ ] `DayDetailView` — uses system `Color(uiColor: .systemGroupedBackground)`; replace with `Color.black` + purple glow to match dark brand.
  - [ ] `BiometricLockView` — same system-background mismatch; apply dark brand theme.
  - [ ] `SettingsView` — move "AI Pipeline Stats" section (embedding dims, noise count) to `DebugSettingsView`; these are thesis details, not end-user info.
  - [ ] `BitsListView` — the "Clusters" segment tab duplicates the cluster card grid; unify the two entry points to avoid redundancy.
  - [ ] General: replace raw `localizedDescription` errors with human-readable copy throughout.

### 🟡 Medium
- [ ] **Crisis Safety:** Expand `SafetyFilter` to gently show a `CrisisResourcesView` (988 Lifeline) on self-harm detection without blocking the journal save.
- [ ] **Onboarding Flow:** Create the 3-screen privacy/method onboarding and a gentle `ReminderScheduler`.
- [ ] **TestFlight & QA:** Implement MetricKit crash diagnostics, basic `GJournalUITests`, and complete the App Store pre-review checklist.

### 🔴 Hard
- [ ] **Accessibility Pass:** Implement VoiceOver text summaries for the complex mathematical graphs, support Dynamic Type, and migrate hardcoded text to a String Catalog.

---

## 🟦 Tier 4: Low Necessity – Optional / Fallbacks
*These are fallback plans or features that are the first to be cut if timelines or technical risks become too high.*

### 🟢 Easy
- [ ] **Search Demotion:** If Hybrid Search (Pillar C) is too complex, demote the feature to a simple "Related entries" section based on cosine distance.

### 🟡 Medium
- [ ] **Co-occurrence Network (Pillar A Fallback):** If the GGM math proves too unstable on real-world small datasets, fall back to a simpler tag-emotion co-occurrence network.
- [ ] **Flare Index (Pillar B Cut Order 1):** If the Trajectory math is too heavy, cut the PCA-2D hull area growth ("Flare Index") and keep only Rumination + Semantic Recovery Velocity.
