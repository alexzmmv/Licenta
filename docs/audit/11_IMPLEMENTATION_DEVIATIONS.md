# Implementation Deviations from Original Plan

> This document records **every place where the actual implementation diverged from the original design**
> in `01_AI_PIPELINE.md`, `02_DBSCAN.md`, `09_AI_PITFALLS.md`, `10_IMPLEMENTATION_TASKS.md`, and `nextstep.md`.
> It does NOT describe what was built — only how it differs from the plan.

---

## 1. Embedding Model Names vs File Slot Names

### Original plan (`01_AI_PIPELINE.md`, `10_IMPLEMENTATION_TASKS.md`)
- SLOT 1 (MobileBERT file): `all-MiniLM-L6-v2` — mean pooling
- SLOT 2 (DistilBERT file): `paraphrase-MiniLM-L6-v2` — mean pooling (Task 1.3 in `10_IMPLEMENTATION_TASKS.md`)

### What actually happened
- SLOT 1 (`GJournalEmbeddingMobileBERT.mlpackage`): `all-MiniLM-L6-v2` — **mean pooling** ✅ matches plan
- SLOT 2 (`GJournalEmbeddingDistilBERT.mlpackage`): **`BAAI/bge-small-en-v1.5`** — **CLS pooling** ❗ differs from plan

`paraphrase-MiniLM-L6-v2` was replaced by `BAAI/bge-small-en-v1.5` for SLOT 2. This was an intentional upgrade documented in `01_AI_PIPELINE.md §1` (where SLOT 2 was re-evaluated) and in `training/train_embedding_distilbert.py` docstring. However `10_IMPLEMENTATION_TASKS.md §Task 1.3` still refers to `paraphrase-MiniLM-L6-v2` and was **never updated**.

### Impact
- `CoreMLEmbeddingService` correctly uses `.cls` pooling for the DistilBERT slot
- `09_AI_PITFALLS.md §Pitfall 7.4` documents the correct pooling per slot
- `nextstep.md §1.2` documents the final slot assignments correctly
- `10_IMPLEMENTATION_TASKS.md §Task 1.3` and `§Task 1.5` are **stale** — they still name `paraphrase-MiniLM-L6-v2` and `GJournalEmbeddingParaphrase.mlpackage`

---

## 2. Runtime Bundle Lookup: `.mlpackage` → `.mlmodelc`

### Original plan (`nextstep.md §Step 2`, `10_IMPLEMENTATION_TASKS.md §Task 2.6`)
```swift
// nextstep.md shows this exact check:
if Bundle.main.url(forResource: "GJournalEmbeddingMobileBERT", withExtension: "mlpackage") != nil {
```

### What actually happened
All three runtime bundle checks were changed from `.mlpackage` to `.mlmodelc`:
- `ServiceContainer.swift` — 2 embedding checks + 1 emotion check
- `CoreMLEmbeddingService.swift` — model load
- `CoreMLEmotionService.swift` — model load

### Why
Xcode **compiles** `.mlpackage` into `.mlmodelc` at build time. The `.mlpackage` directory never exists in the app bundle at runtime — only the compiled `.mlmodelc` form does. The original plan's `.mlpackage` check always returned `nil`, causing permanent fallback to `NLEmbedding`.

### Impact
The `nextstep.md §Step 2` code snippet is now **incorrect** and misleading. Any future developer following it will get permanent NLEmbedding fallback. The correct check is:
```swift
if Bundle.main.url(forResource: "GJournalEmbeddingMobileBERT", withExtension: "mlmodelc") != nil {
```

---

## 3. User-Selectable Embedding Model (Not in Original Plan)

### Original plan
`ServiceContainer.makeProduction()` chose a single fixed embedding model at startup. There was no mechanism to switch models at runtime.

### What was added (not in any doc)
- **`EmbeddingModelChoice.swift`** (new file, not in `10_IMPLEMENTATION_TASKS.md`): enum with 3 cases (`.appleNLP`, `.mobileBERT`, `.distilBERT`), persisted via `UserDefaults` / `@AppStorage`
- **`ServiceContainer.makeProduction()`**: now reads `EmbeddingModelChoice.current` and instantiates the corresponding service
- **`SettingsView.swift`**: added a `Picker` for model selection; selection posts `embeddingModelDidChange` notification
- **`MainAppView.swift`**: observes the notification and hot-swaps `ServiceContainer` + `AIProcessingManager` without restarting the app

### Impact
This is an **unplanned feature**. None of `01_AI_PIPELINE.md`, `10_IMPLEMENTATION_TASKS.md`, or `nextstep.md` mention it. It is thesis-relevant (enables live model comparison on-device) and should be documented in `01_AI_PIPELINE.md §7` and the thesis benchmark chapter.

---

## 4. DBSCAN Adaptive Epsilon: Force-Recalibrate on Model Switch

### Original plan (`02_DBSCAN.md §3`, `10_IMPLEMENTATION_TASKS.md §Task 3.3`)
```swift
// recalibrate every 10 new entries
private let calibrationInterval = 10
```
`runClustering()` had no parameter — recalibration only triggered automatically every 10 entries.

### What was added
`runClustering(forceRecalibrate: Bool = false)` parameter was added. When `true`, epsilon is always recalculated from the current embedding distribution regardless of the counter.

### Why
When switching from MiniLM (mean pooling, broader distance distribution) to BGE (CLS pooling, tighter distribution), the hardcoded `epsilon = 0.3` was appropriate for MiniLM but caused BGE to collapse everything into one cluster. The counter was at 0, so auto-calibration never fired on the manual recluster action.

### Impact
- `02_DBSCAN.md §3` recalibration strategy does not mention force-recalibration — it should be updated
- The manual **Recluster All** button in Settings always calls `runClustering(forceRecalibrate: true)`
- Any documentation describing the recalibration logic should note that model switches trigger a forced recalibration

---

## 5. Settings View: Debug & Development Section (Not in Original Plan)

### Original plan (`10_IMPLEMENTATION_TASKS.md §Task 4.3`)
The only Settings change planned was:
> Wrap "Generate Seed Data" button in `#if DEBUG` conditional compilation.

### What was added
A complete **Debug & Development** section in `SettingsView.swift` with:
- **AI Pipeline Stats** panel (live counts: entries, embeddings, clusters, dimensions, active model)
- **Recluster All Entries** — re-runs DBSCAN with forced epsilon recalibration
- **Re-embed All Entries** — re-generates embeddings for all entries with the current model
- **Process Unprocessed Entries** — runs pipeline only on entries missing embeddings
- **Clear All Embeddings** — destructive: wipes `embeddingData`, `embeddingGeneratedAt`, `flattenedText`, `emotionProbabilitiesData`
- **Clear All Clusters** — destructive: removes cluster assignments, deletes all `Cluster` objects
- **Generate Seed Data** — `#if DEBUG` only (satisfies Task 4.3)
- **Log Embedding Sample** — `#if DEBUG` only: prints first entry's embedding vector and top emotions to console

`SettingsView` now takes a `repository: BaseJournalRepository` parameter (injected from `ContentView`).

### Impact
`10_IMPLEMENTATION_TASKS.md §Task 4.3` is now fully superseded. The debug flag wrapping is done, plus substantially more. `ContentView.swift` was also modified (not listed in `10_IMPLEMENTATION_TASKS.md §Files Modified`) to pass the repository.

---

## 6. DistilBERT Pooling Mode: Temporary Incorrect Change

### What happened
During debugging of the single-cluster issue (see §4), DistilBERT's pooling was temporarily changed from `.cls` to `.mean` in `ServiceContainer.swift`. This was **reverted** once the root cause was identified as the stale epsilon, not the pooling mode.

### Final state
DistilBERT (`BAAI/bge-small-en-v1.5`) uses `.cls` pooling — **correct** per `09_AI_PITFALLS.md §Pitfall 7.4` and the model's training objective.

### Impact
No lasting code change. Documents the debugging path for the record. The pitfall is already covered in `09_AI_PITFALLS.md §Pitfall 7.4`.

---

## 7. Display Names Reflect Actual Models, Not File Slot Names

### Original plan
No `EmbeddingModelChoice` existed, so no display names were planned.

### What was implemented
`EmbeddingModelChoice.displayName` shows the **real model identity**, not the misleading file slot name:
- `.mobileBERT` → `"MiniLM-L6-v2"` (not "MobileBERT")
- `.distilBERT` → `"BGE-small-v1.5"` (not "DistilBERT")
- `.appleNLP` → `"Apple NLP"`

`EmbeddingModelChoice.subtitle` shows the HuggingFace ID and pooling mode:
- `"all-MiniLM-L6-v2 — mean pooling, ~80 MB"`
- `"BAAI/bge-small-en-v1.5 — CLS pooling, ~130 MB"`

### Impact
The file names `GJournalEmbeddingMobileBERT` and `GJournalEmbeddingDistilBERT` are misleading but are kept for bundle compatibility. The UI correctly exposes the real model names to the user.

---

## Stale Documents That Need Updating

| Document | Stale Section | What's Wrong |
|:---------|:-------------|:-------------|
| `10_IMPLEMENTATION_TASKS.md` | Task 1.3 | Still names `paraphrase-MiniLM-L6-v2` — SLOT 2 is now `bge-small-en-v1.5` |
| `10_IMPLEMENTATION_TASKS.md` | Task 1.5 | Still names `GJournalEmbeddingParaphrase.mlpackage` |
| `10_IMPLEMENTATION_TASKS.md` | Task 2.6 | ServiceContainer wiring now model-selection aware, not a single fixed model |
| `10_IMPLEMENTATION_TASKS.md` | Task 4.3 | Fully superseded by the Debug & Development section |
| `10_IMPLEMENTATION_TASKS.md` | Files Modified | Missing `ContentView.swift`, `EmbeddingModelChoice.swift` |
| `nextstep.md` | Step 2 code snippet | Shows `.mlpackage` check — should be `.mlmodelc` |
| `nextstep.md` | Step 2 | No mention of model picker or hot-swap mechanism |
| `02_DBSCAN.md` | §3 Recalibration Strategy | Does not mention forced recalibration on model switch |
| `01_AI_PIPELINE.md` | §7 Swift Integration | `makeProduction()` example is a single fixed model — now dynamic |
