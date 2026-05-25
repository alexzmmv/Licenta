# Next Steps — GJournal

## Current State

| Subsystem | Status | What runs today |
|:----------|:-------|:----------------|
| SwiftData persistence | ✅ Working | Bits, Clusters, EmotionConfiguration |
| Biometric auth | ✅ Working | Face ID / Touch ID lock |
| UI redesign | ✅ Working | Glass cards, week strip, today mood, animations |
| DBSCAN clustering | ✅ Working | Pure Swift, Accelerate-optimised |
| Embedding service | ⚠️ Fallback | Apple NLEmbedding (no .mlpackage present) |
| Emotion detection | ⚠️ Fallback | Keyword heuristic mock (no .mlpackage present) |
| Graph view | ✅ Working | Canvas-rendered force-directed graph |
| Schema migration | ⚠️ Dev-only | Auto-wipe on mismatch — unsafe for production |

---

## Step 1 — Train the AI Models (Windows PC, RTX 2070)

All scripts are in `training/`. Run them in order from the PC.

### 1.1 Setup

```bash
cd training
bash setup.sh          # creates venv, installs torch + sentence-transformers + coremltools
```

Expected output: prints `CUDA available: True` and the GPU name.

### 1.2 Train the Embedding Model

Try MobileBERT first (smaller, faster on-device):

```bash
python train_embedding_mobilebert.py
```

If it fails during training or Core ML conversion, fall back to DistilBERT:

```bash
python train_embedding_distilbert.py
```

Both scripts:
- Fine-tune on STS-B (semantic textual similarity) for 3 epochs
- Save the HuggingFace model to `models/`
- Automatically detect CUDA / MPS / CPU

Expected output: Spearman correlation ≥ 0.80 on the STS-B dev set.

### 1.3 Train the Emotion Classifier

```bash
python train_emotion_classifier.py
```

- Fine-tunes on GoEmotions (28 labels → 12 app emotions)
- Uses the label map already in the script (Joy, Sadness, Anger, Fear, Love, Surprise, Disgust, Anxiety, Excitement, Gratitude, Hope, Guilt)
- Expected accuracy: ≥ 70% on the GoEmotions test set

If this fails, use the sklearn fallback:

```bash
python backup/train_emotion_simple.py
```

### 1.4 Convert to Core ML

```bash
python convert_to_coreml.py
```

This script tries three conversion paths in order:
1. `ct.convert(traced, ...)` — standard neuralnetwork format
2. `ct.convert(traced, convert_to="mlprogram")` — newer mlprogram format
3. ONNX export → `ct.converters.onnx.convert(...)` — last resort

Output files in `coreml_models/`:
- `GJournalEmbeddingMobileBERT.mlpackage` (or DistilBERT)
- `GJournalEmotionClassifier.mlpackage`

### 1.5 Validate Tokenizer Alignment

Before copying models to iOS, run this to make sure Swift tokenization matches Python:

```bash
python backup/verify_tokenizer.py
```

It prints token IDs for 3 test sentences. Compare them with the WordPieceTokenizer output in `GJournal/Services/WordPieceTokenizer.swift`. They must match exactly or the embeddings will be garbage.

### 1.6 Benchmark

```bash
python benchmark_embeddings.py
```

Prints a table: Spearman correlation on STS-B, latency per entry (ms), model size (MB).  
Target: ≥ 0.78 Spearman, ≤ 100ms on device.

---

## Step 2 — Add Models to Xcode

1. Copy the two `.mlpackage` folders from `training/coreml_models/` to the Mac
2. In Xcode: drag both packages into the `GJournal` target (check "Add to targets: GJournal")
3. Build and run — `ServiceContainer.makeProduction()` will auto-detect and switch from NLEmbedding to the trained model:

```swift
// ServiceContainer.swift — this already exists, nothing to change
if Bundle.main.url(forResource: "GJournalEmbeddingMobileBERT", withExtension: "mlpackage") != nil {
    return CoreMLEmbeddingService(modelName: "GJournalEmbeddingMobileBERT")
}
```

4. Add a new entry, wait ~2 seconds, open the graph — clusters should form with real semantic groupings.

---

## Step 3 — Production Readiness

### 3.1 SwiftData Schema Migration (CRITICAL — do before any TestFlight build)

The current `makeModelContainer()` **deletes all user data** on schema change. This is fine during development but will lose real users' journals on any app update.

Replace the auto-wipe with a versioned migration plan:

```swift
// In GJournalApp.swift, replace makeModelContainer() with:
let schema = Schema([Bit.self, Cluster.self, EmotionConfiguration.self])
let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
let migrationPlan = GJournalMigrationPlan.self  // define this

// GJournalMigrationPlan.swift:
enum GJournalMigrationPlan: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] = [
        GJournalSchemaV1.self,
        GJournalSchemaV2.self   // add a new entry each time you change the model
    ]
    static var stages: [MigrationStage] = [
        // lightweight migration for adding optional fields:
        .lightweight(fromVersion: GJournalSchemaV1.self, toVersion: GJournalSchemaV2.self)
    ]
}
```

Each time you add a field to `Bit`, `Cluster`, or `EmotionConfiguration`:
1. Create a new `GJournalSchemaVN.swift` with the old model snapshot
2. Add a `.lightweight` migration stage (works for adding optional fields)
3. Add a `.custom` migration stage only if you rename or remove a field

### 3.2 Privacy Policy

Apple requires a privacy policy URL in App Store Connect for any app that collects data. The app processes journal text locally — no data leaves the device — so the policy is simple:

- Create a single webpage (GitHub Pages works fine)
- State: "All journal data is processed and stored locally on your device. No data is transmitted to external servers."
- Paste the URL in App Store Connect → App Privacy

### 3.3 App Store Metadata

Prepare in App Store Connect:
- **App name**: GJournal
- **Subtitle**: Micro-journal with AI insights
- **Keywords**: journal, mood, emotion, mindfulness, mental health, diary, AI
- **Description**: 3–4 paragraphs covering the Feel/Event/Action framework, AI clustering, privacy-first design
- **Screenshots**: Required sizes — 6.9" (iPhone 16 Pro Max), 6.5" (iPhone 14 Plus), 5.5" (iPhone 8 Plus)
- **App icon**: 1024×1024 PNG, no alpha, no rounded corners (App Store applies them)

### 3.4 Accessibility

Before submission, test with VoiceOver on a real device:

- All interactive elements need `.accessibilityLabel` (emoji-only buttons are invisible to VoiceOver)
- `RecentEntryRow` and `EmotionBarRow` need labels like `"Joy entry from Today, intensity 3"`
- The graph canvas needs a `.accessibilityElement(children: .ignore)` with a descriptive label like `"\(layout.nodes.count) journal entries in \(clusterCount) clusters"`
- Test Dynamic Type at "Accessibility Extra Large" — check nothing clips

### 3.5 Crash Reporting (Optional but recommended)

Add Firebase Crashlytics or Sentry before shipping. Without it, you have no visibility into production crashes.

Firebase (simplest):
1. Add `FirebaseCrashlytics` via Swift Package Manager
2. Call `FirebaseApp.configure()` in `GJournalApp.init()`
3. No user data is sent — only stack traces

---

## Step 4 — Testing Checklist

### Device Testing (do on physical devices, not Simulator)

| Device | Why |
|:-------|:----|
| iPhone 11 | Oldest likely user device; A13 chip, Neural Engine v3 |
| iPhone 14 Plus | Large screen layout check |
| iPhone 15 or 16 | Latest, verify Dynamic Island doesn't clip UI |

For each device:
- Create 3+ entries → verify AI pipeline runs (check Xcode console for `[AIProcessingManager]` logs)
- Open graph view → verify clusters appear after ~5s
- Kill app, reopen → verify entries and clusters persist
- Change to Dark / Light appearance → verify UI (app forces dark, should be consistent)
- Enable VoiceOver → navigate through home screen

### Functional Test Script

1. Fresh install → first-time welcome screen appears
2. Add first entry → FAB disappears (one entry per day limit)
3. Calendar shows a dot/bar on today's date
4. Week strip shows today's emotion emoji
5. Open graph → nodes appear, clusters (if ≥ 3 similar entries) are connected
6. Tap a node → detail card slides up
7. Swipe a recent entry → tapping opens edit sheet
8. Settings → change name → home screen greeting updates
9. Lock screen → Face ID / Touch ID prompt appears on next open

---

## Step 5 — TestFlight

1. Bump version to `1.0.0` (build `1`) in Xcode project settings
2. Archive: Product → Archive
3. Upload to App Store Connect via Xcode Organizer
4. Add internal testers (your own Apple ID first)
5. Test on TestFlight before adding external testers
6. Fix any crashes from Crashlytics before submitting to App Review

---

## Priority Order

```
1. Schema migration plan          ← must do before ANY real users get the app
2. Train models on Windows PC     ← core thesis feature, AI clustering
3. Add models to Xcode + test     ← verify tokenizer alignment first
4. Device testing + VoiceOver     ← required for App Store approval
5. Privacy policy URL             ← required for App Store submission
6. App Store screenshots + meta   ← required for submission
7. Archive + TestFlight           ← final step
```
