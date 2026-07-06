# GJournal Task List (Tiered)

This list categorizes the remaining tasks from `plan.md` across 4 Tiers of Necessity (from Critical Foundation down to Optional Fallbacks) and 3 Tiers of Difficulty (Easy, Medium, Hard).

> **Status (2026-07-06): Tier 1 complete. Tier 2 Easy complete.** Verified: Debug + Release builds pass on the iPhone 17 simulator; 26/26 unit tests green in the new `GJournalTests` target (tokenizer golden fixtures, SemanticUtils, migration smoke, PBKDF2 legacy upgrade, export/model-choice regressions). Bundled models are now 137 MB (MiniLM 43 MB + emotion classifier 94 MB, not yet quantized — carried over). Views audit complete: all 18 views are active; 4 minor polish items queued for Tier 3. Next: Tier 2 Medium.

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
- [ ] **Emotion Classifier Quantization** *(carried over from Tier 1)*: Write `training/quantize_emotion.py` (coremltools palettization/int8) to shrink `GJournalEmotionClassifier` 94MB → ~47MB. Acceptance gate: macro-F1 delta ≤ 1 point on the eval set; ship fp16 if it fails.

### 🟡 Medium
- [ ] **Semantic Memory Search (Pillar C):** Build `HybridSearchService` combining in-memory BM25 keyword search with vector cosine scans using Reciprocal Rank Fusion.
- [ ] **Network Graph & Trajectory UIs:** Extract the `GraphPhysicsEngine` for the `NetworkGraphView` and build the `TrajectoryView` dashboard.
- [ ] **Paywall (StoreKit 2):** Implement `EntitlementManager`, `PaywallView`, and the non-consumable "GJournal Insights" purchase flow.

### 🔴 Hard
- [ ] **Swift HDBSCAN:** Build HDBSCAN (mutual reachability, MST, cluster extraction) natively in Swift and validate it against a Python oracle.
- [ ] **GGM Estimator (Pillar A):** Implement Ledoit-Wolf shrinkage and partial correlation math to generate the psychological network graph.
- [ ] **Persistent Homology (Pillar B):** Implement exact Vietoris-Rips β0/β1 persistence in Swift for sliding 30-day windows to track "Rumination" loops.
- [ ] **Behavioral Tags Engine:** Implement `TagExtractor` using NLTagger and canonicalize tags dynamically via embedding cosine similarity.

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
