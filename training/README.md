# GJournal — AI Training Guide

All scripts to train, convert, and benchmark the on-device NLP models for GJournal.

---

## Hardware

| Machine | Use for | Notes |
|:--------|:--------|:------|
| M1 MacBook (current) | Core ML conversion, benchmarks, backup training | MPS backend (~3-5x slower than RTX 2070) |
| PC with RTX 2070 | Main training (embedding + emotion classifier) | CUDA backend, fp16 support |

Scripts auto-detect the backend — same command on both machines.

---

## Setup (run once)

```bash
cd training
bash setup.sh
source venv/bin/activate
```

Expected output includes: `CUDA available: True` (PC) or `MPS available: True` (M1).

---

## Execution Order

```
Phase 1: Download + Evaluate (any machine — no GPU needed for embedding scripts)
  ├── python train_embedding_mobilebert.py    ~1 min  (download + eval, all-MiniLM-L6-v2)
  ├── python train_embedding_distilbert.py    ~1 min  (download + eval, paraphrase-MiniLM-L6-v2)
  └── python train_emotion_classifier.py      ~35 min (RTX) | ~2.5h  (M1)  [only script that trains]

Phase 2: Conversion (run on Mac — coremltools works best on macOS)
  └── python convert_to_coreml.py

Phase 3: Benchmark (run on Mac first; final benchmark on physical iPhone)
  └── python benchmark_embeddings.py

Phase 4: Validate tokenizer (before Swift integration)
  └── python backup/verify_tokenizer.py
```

---

## Expected Outputs

| Script | Output files | Success criteria |
|:-------|:-------------|:----------------|
| `train_embedding_mobilebert.py` | `models/mobilebert-stsb/` | STS-B Spearman > 0.75 |
| `train_embedding_distilbert.py` | `models/distilbert-stsb/` | STS-B Spearman > 0.75 |
| `train_emotion_classifier.py` | `models/emotion-classifier/` | Overall accuracy > 0.60 |
| `convert_to_coreml.py` | `coreml_models/*.mlpackage` + `vocab_*.txt` + `emotion_labels.json` | Each .mlpackage < 100MB |
| `benchmark_embeddings.py` | `results/embedding_benchmark.txt` | Table with Spearman + latency |
| `backup/verify_tokenizer.py` | Printed token IDs | Match Swift tokenizer output |

---

## Backup Plans

Read `docs/audit/09_AI_PITFALLS.md` Categories 7 and 8 before running any script.

### If all-MiniLM-L6-v2 Core ML conversion fails

`convert_to_coreml.py` automatically tries three paths:
1. Default `ct.convert()`
2. `convert_to="mlprogram"`
3. ONNX → CoreML via `ct.converters.onnx`

If all three fail, swap to the other MiniLM variant (SLOT 2 model):
In `GJournal/Services/ServiceContainer.swift`, change:
```swift
embeddingService: CoreMLEmbeddingService(modelName: "GJournalEmbeddingMiniLM")
// to:
embeddingService: CoreMLEmbeddingService(modelName: "GJournalEmbeddingParaphrase")
```

### If both MiniLM models fail Core ML conversion

Use Apple's built-in `NLEmbedding` (zero training, zero bundle size):
```swift
embeddingService: NLEmbeddingService()
```
This is already implemented in `GJournal/Services/NLEmbeddingService.swift` (Task 2.4).

### If emotion classifier accuracy < 45%

1. Check label mapping — confirm `confusion → Surprise` (not `Anxiety`)
2. Check class weights are applied (`WeightedTrainer` in the script)
3. Try DistilBERT base instead of MobileBERT (`BASE_MODEL = "distilbert-base-uncased"`)
4. Last resort: run the sklearn fallback:
   ```bash
   python backup/train_emotion_simple.py
   ```
   Produces `GJournalEmotionClassifier_simple.mlpackage` — ~50% accuracy, no tokenizer needed

### Full fallback decision tree

```
Embedding:
  all-MiniLM-L6-v2 (SLOT 1)  →  paraphrase-MiniLM-L6-v2 (SLOT 2)  →  ONNX path  →  NLEmbedding

Emotion:
  MobileBERT GoEmotions  →  DistilBERT GoEmotions  →  TF-IDF sklearn  →  keyword SafetyFilter
```

---

## Key Pitfalls (quick reference)

See full details in `docs/audit/09_AI_PITFALLS.md`.

| Pitfall | What goes wrong | Fix |
|:--------|:----------------|:----|
| `confusion → Anxiety` | Wrong label mapping corrupts Anxiety class | Use `confusion → Surprise` |
| `fp16=True` on M1 | Crashes on MPS | Use `bf16=True` on M1, `fp16=True` on CUDA |
| Hardcoded `cuda` device | Crashes on Mac | Auto-detect: `cuda → mps → cpu` |
| `[CLS]` pooling in Swift | Embeddings incompatible with MiniLM training | Use mean pooling — verify with `verify_tokenizer.py` |
| Variable-length Core ML inputs | Conversion or inference crash | Always pad to fixed length 128 |
| LayerNorm FP16 on Neural Engine | ANE arithmetic overflow → garbage embeddings | Force LayerNorm ops to FP32 via `op_selector` in coremltools |

---

## After Conversion

1. Copy all `coreml_models/*.mlpackage` into the Xcode project (drag into GJournal target)
2. Copy `vocab_*.txt` into the Xcode bundle
3. Copy `emotion_labels.json` for Swift label ordering validation
4. Build and verify no missing resource errors
5. Run on physical iPhone 11 for final latency benchmark
