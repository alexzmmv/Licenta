# 2-Week Implementation Timeline

> Deadline context: Bachelor thesis, full working pipeline required.  
> Hardware: RTX 2070 (training) + M1 MacBook Pro (conversion + Xcode)  
> Target: iPhone 11 (iOS 18), iPhone 14 Plus, iPhone 15

---

## Week 1: ML Training, Conversion & Core Integration

### Day 1–2: Training Environment + Embedding Models

| Task | Time | Machine |
|:-----|:----:|:-------:|
| Set up Python env (`sentence-transformers`, `transformers`, `coremltools`, `datasets`) | 1h | PC (RTX 2070) |
| Fine-tune **MobileBERT** on STS-B (sentence-transformer) | 15 min | PC |
| Fine-tune **DistilBERT** on STS-B (sentence-transformer) | 20 min | PC |
| Evaluate both on STS-B test set (Spearman correlation) | 30 min | PC |
| Export both to ONNX / TorchScript | 30 min | PC |
| Convert both to Core ML (`.mlpackage`, float16) via `coremltools` | 1h | M1 Mac |
| Test NLEmbedding baseline in a Swift playground | 30 min | M1 Mac |
| **Checkpoint**: 3 embedding models ready as Core ML / NLEmbedding | | |

### Day 3: GoEmotions Classifier

| Task | Time | Machine |
|:-----|:----:|:-------:|
| Load GoEmotions, apply 28→12 label mapping (from `05_SCIENCE.md`) | 30 min | PC |
| Handle class imbalance (weighted loss / oversampling Anxiety, Disgust) | 30 min | PC |
| Fine-tune MobileBERT classifier on mapped GoEmotions | 40 min | PC |
| Evaluate (accuracy, per-class F1, confusion matrix) | 30 min | PC |
| Convert classifier to Core ML (float16) | 30 min | M1 Mac |
| **Checkpoint**: Emotion classifier Core ML model ready | | |

### Day 4: Swift Integration — Core ML Services

| Task | Time | Machine |
|:-----|:----:|:-------:|
| Create `CoreMLEmbeddingService.swift` (load model, tokenize, inference) | 2h | M1 Mac |
| Bundle WordPiece `vocab.txt` and implement tokenizer (or use `swift-transformers`) | 2h | M1 Mac |
| Create `CoreMLEmotionService.swift` (same pattern) | 1h | M1 Mac |
| Create `NLEmbeddingService.swift` (Apple baseline) | 30 min | M1 Mac |
| **Checkpoint**: 3 embedding services + 1 emotion service compile and run | | |

### Day 5: Wiring + TextFlattener + ServiceContainer

| Task | Time | Machine |
|:-----|:----:|:-------:|
| Fix `TextFlattener` — strip bracket tags, use natural concatenation | 15 min | M1 Mac |
| Update `ServiceContainer.makeProduction()` to return real services | 30 min | M1 Mac |
| Fix `MainAppView.swift` double ServiceContainer instantiation | 15 min | M1 Mac |
| Fix `ModelContainer` — register `Cluster.self`, `EmotionConfiguration.self` | 10 min | M1 Mac |
| Switch embedding storage from JSON string to binary `Data` | 1h | M1 Mac |
| End-to-end test: create a Bit → embedding → emotion → clustering | 1h | M1 Mac |
| **Checkpoint**: Full pipeline works end-to-end on simulator | | |

### Weekend Buffer (Day 6–7)

Use for overflow, debugging tokenizer issues, or Core ML conversion problems. These are the most unpredictable steps.

---

## Week 2: Optimization, Security, Benchmarks & Polish

### Day 8: DBSCAN Optimization

| Task | Time | Machine |
|:-----|:----:|:-------:|
| Implement `OptimizedDBSCANClusterer` with Accelerate/vDSP | 2h | M1 Mac |
| Replace `Array.contains` with `Set<Int>` in seed expansion | 30 min | M1 Mac |
| Implement `estimateEpsilon()` k-distance heuristic | 1h | M1 Mac |
| Implement `silhouetteScore()` for quality evaluation | 1h | M1 Mac |
| Add periodic recalibration logic to `AIProcessingManager` | 30 min | M1 Mac |
| **Checkpoint**: DBSCAN runs 10-50x faster with adaptive params | | |

### Day 9: Security + Data Protection

| Task | Time | Machine |
|:-----|:----:|:-------:|
| Migrate password hash + salt from UserDefaults → Keychain | 1h | M1 Mac |
| Enable `NSFileProtectionCompleteUnlessOpen` on SwiftData container | 30 min | M1 Mac |
| Remove / hide "Generate Seed Data" from Settings (or gate behind dev flag) | 15 min | M1 Mac |
| Clean up deprecated `UIScreen.main.bounds` usages | 1h | M1 Mac |
| **Checkpoint**: Security hardened, deprecated APIs cleaned | | |

### Day 10–11: On-Device Benchmarking (THE THESIS DATA)

| Task | Time | Machine |
|:-----|:----:|:-------:|
| Create benchmark harness (measure latency, memory, battery per model) | 2h | M1 Mac |
| Run 100-entry benchmark on **iPhone 11** (all 3 embedding models) | 2h | iPhone 11 |
| Run same benchmark on **iPhone 15** | 1h | iPhone 15 |
| Measure DBSCAN clustering time (fixed vs adaptive epsilon) | 1h | Both |
| Compute silhouette scores for each model's embeddings | 30 min | M1 Mac |
| Collect results into thesis benchmark tables | 1h | Any |
| **Checkpoint**: All thesis benchmark data collected | | |

### Day 12–13: Polish + Edge Cases

| Task | Time | Machine |
|:-----|:----:|:-------:|
| Test biometric auth flow (lock/unlock/background/foreground) | 1h | Devices |
| Test with 0, 1, 10, 50, 100 entries | 1h | Devices |
| Handle edge cases (empty text, very long text, special characters) | 1h | M1 Mac |
| Verify ClusterGraphView performance with real embeddings | 1h | iPhone 11 |
| Final code review and cleanup | 2h | M1 Mac |
| **Checkpoint**: App is production-ready for personal deployment | | |

### Day 14: Final Testing + Thesis Screenshots

| Task | Time | Machine |
|:-----|:----:|:-------:|
| Full regression test on all 3 devices | 2h | All devices |
| Capture screenshots for thesis (all views, graph, clustering results) | 1h | Devices |
| Archive build for device installation | 30 min | M1 Mac |
| **DONE** | | |

---

## Risk Assessment

| Risk | Likelihood | Mitigation |
|:-----|:----------:|:-----------|
| Core ML conversion fails for MobileBERT | Medium | Fall back to ONNX Runtime or use only DistilBERT + NLEmbedding |
| WordPiece tokenizer in Swift is buggy | Medium | Use `swift-transformers` package or test thoroughly with known inputs |
| DBSCAN produces poor clusters with real embeddings | Low | Adaptive epsilon + silhouette score evaluation |
| iPhone 11 inference is too slow | Low | Use float16 quantization + Neural Engine (`MLComputeUnits.all`) |
| GoEmotions classifier has low Anxiety/Disgust recall | High | Apply class weighting; accept lower recall for rare classes in thesis |

---

## Critical Path

The **critical path** (tasks that block everything else) is:

```
Training → Core ML conversion → Swift tokenizer → ServiceContainer wiring
```

If any of these fail, the entire pipeline is blocked. Prioritize Days 1–5 absolutely. Security and DBSCAN optimization can be cut in an emergency without blocking the thesis demonstration.

---

## 🎓 PhD Review

1. **The comparative methodology** (3 models, same test harness, same device) is solid experimental design. A thesis committee will look for: (a) reproducibility — document exact hyperparameters, (b) statistical significance — run benchmarks 3+ times and report mean ± std, (c) fair comparison — same tokenization pipeline, same test data.
2. **Document negative results**. If MobileBERT produces worse embeddings than NLEmbedding, that's still a valid finding. Thesis value comes from honest evaluation, not from having the "best" model.
3. **Screenshots and figures**: Capture the cluster graph with each model's embeddings. Visual comparison of cluster quality is compelling evidence. Include in your Results chapter.

## 🔴 Red-Hat Review

1. **Day 4 (Swift tokenizer) is the highest-risk day**. If this takes 2 days instead of 1, the entire schedule shifts. **Start this on Day 2 in parallel with training**.
2. **Weekend buffer is essential**. Do NOT schedule work on it. You will need it for `coremltools` debugging or tokenizer edge cases.
3. **If coremltools conversion fails for MobileBERT**: Don't spend more than 4 hours debugging. Fall back to DistilBERT + NLEmbedding (2-model comparison is still valid for a thesis).
4. **Benchmarking on physical devices** requires provisioning profiles and developer account setup. If not already configured, budget an extra 2-3 hours for Xcode signing and device trust setup.
5. **Day 14 is too late for finding major bugs**. Aim to have the pipeline working on a real device by Day 10. Days 11-14 are polish and data collection only.
