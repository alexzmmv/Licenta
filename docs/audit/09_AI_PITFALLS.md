# AI Implementation Pitfalls — Claude Code Ready Reference

> This document lists **specific, common mistakes** that AI coding assistants make when implementing changes to this codebase. Reference this document before and during any implementation session to avoid known pitfalls.
> 
> Format: Each pitfall has a ❌ Wrong pattern and a ✅ Correct pattern.

---

## Category 1: Swift Concurrency & SwiftData

### Pitfall 1.1: Accessing ModelContext from wrong thread

SwiftData's `ModelContext` is **not thread-safe**. It must be accessed from the same actor (typically `@MainActor`) it was created on.

```swift
// ❌ WRONG: Accessing modelContext inside a detached Task
Task.detached(priority: .background) {
    let bits = try modelContext.fetch(FetchDescriptor<Bit>())  // CRASH
    // modelContext was created on MainActor, can't use here
}

// ✅ CORRECT: Use @MainActor for SwiftData access, background for computation
let bits = try modelContext.fetch(FetchDescriptor<Bit>())  // MainActor
let embeddings = bits.map { $0.embedding }

Task.detached(priority: .background) {
    let clusters = try await clusterer.cluster(embeddings)  // background
    
    await MainActor.run {
        // Write results back on MainActor
        for assignment in clusters {
            if let bit = bits.first(where: { $0.id == assignment.bitID }) {
                bit.clusterID = assignment.clusterID
            }
        }
        try? modelContext.save()
    }
}
```

### Pitfall 1.2: @Published + Swift 6 strict concurrency

With Swift 6 strict concurrency, `@Published` properties on `ObservableObject` must be updated on `@MainActor`.

```swift
// ❌ WRONG: Updating @Published from background
class Repository: ObservableObject {
    @Published var bits: [Bit] = []
    
    func loadBits() async {
        let fetched = try await fetchFromDB()
        bits = fetched  // ⚠️ Swift 6 warning: mutation of @Published not on MainActor
    }
}

// ✅ CORRECT: Ensure MainActor for @Published updates
@MainActor
class Repository: ObservableObject {
    @Published var bits: [Bit] = []
    
    func loadBits() async {
        let fetched = await Task.detached { try fetchFromDB() }.value
        bits = fetched  // ✅ on MainActor
    }
}
```

### Pitfall 1.3: Forgetting to register all SwiftData models

```swift
// ❌ WRONG: Only registering Bit (other models silently fail)
let container = try ModelContainer(for: Bit.self)

// ✅ CORRECT: Register ALL @Model types explicitly
let container = try ModelContainer(
    for: Bit.self, Cluster.self, EmotionConfiguration.self
)
```

---

## Category 2: Core ML Integration

### Pitfall 2.1: Wrong tokenizer implementation

BERT models require **WordPiece tokenization**. A common AI mistake is using simple whitespace/character splitting instead.

```swift
// ❌ WRONG: Naive tokenization
let tokens = text.split(separator: " ").map { String($0) }
let inputIDs = tokens.map { vocab[$0] ?? vocab["[UNK]"]! }

// ✅ CORRECT: WordPiece tokenization
func wordPieceTokenize(_ text: String, vocab: [String: Int]) -> [Int] {
    var tokens: [Int] = [vocab["[CLS]"]!]  // BERT requires [CLS] at start
    
    let words = text.lowercased()
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
    
    for word in words {
        var remaining = word
        var isFirst = true
        
        while !remaining.isEmpty {
            var longestMatch = ""
            var matchLength = 0
            
            // Try longest subword first
            for endIndex in stride(from: remaining.count, through: 1, by: -1) {
                let candidate = String(remaining.prefix(endIndex))
                let lookup = isFirst ? candidate : "##\(candidate)"
                
                if vocab[lookup] != nil {
                    longestMatch = lookup
                    matchLength = endIndex
                    break
                }
            }
            
            if longestMatch.isEmpty {
                tokens.append(vocab["[UNK]"]!)
                break
            } else {
                tokens.append(vocab[longestMatch]!)
                remaining = String(remaining.dropFirst(matchLength))
                isFirst = false
            }
        }
    }
    
    tokens.append(vocab["[SEP]"]!)  // BERT requires [SEP] at end
    return tokens
}
```

### Pitfall 2.2: Wrong input shape for Core ML

```swift
// ❌ WRONG: Passing variable-length input
let inputArray = try MLMultiArray(shape: [1, NSNumber(value: tokens.count)], 
                                   dataType: .int32)

// ✅ CORRECT: Pad/truncate to fixed length (must match training)
let maxLength = 128  // MUST match the max_length used during conversion
var paddedTokens = Array(tokens.prefix(maxLength))
while paddedTokens.count < maxLength {
    paddedTokens.append(0)  // pad token ID
}

let inputIDs = try MLMultiArray(shape: [1, NSNumber(value: maxLength)], dataType: .int32)
for (i, token) in paddedTokens.enumerated() {
    inputIDs[i] = NSNumber(value: token)
}

// Don't forget attention_mask!
let attentionMask = try MLMultiArray(shape: [1, NSNumber(value: maxLength)], dataType: .int32)
for i in 0..<maxLength {
    attentionMask[i] = NSNumber(value: i < tokens.count ? 1 : 0)
}
```

### Pitfall 2.3: Extracting wrong output from Core ML BERT

```swift
// ❌ WRONG: Taking the entire last_hidden_state as embedding
let output = try model.prediction(from: input)
let hiddenState = output.featureValue(for: "last_hidden_state")
// This is shape [1, 128, 768] — NOT a sentence embedding!

// ✅ CORRECT: Extract [CLS] token embedding (index 0) for sentence representation
let hiddenState = output.featureValue(for: "last_hidden_state")!.multiArrayValue!
let embeddingDim = hiddenState.shape[2].intValue
var embedding = [Float](repeating: 0, count: embeddingDim)
for i in 0..<embeddingDim {
    embedding[i] = hiddenState[[0, 0, NSNumber(value: i)]].floatValue  // [batch=0, token=0, dim=i]
}

// Even better: Use mean pooling (average all non-padding tokens)
// This is what sentence-transformers uses by default
var embedding = [Float](repeating: 0, count: embeddingDim)
let seqLen = tokens.count  // actual token count before padding
for dim in 0..<embeddingDim {
    var sum: Float = 0
    for pos in 0..<seqLen {
        sum += hiddenState[[0, NSNumber(value: pos), NSNumber(value: dim)]].floatValue
    }
    embedding[dim] = sum / Float(seqLen)
}
```

### Pitfall 2.4: Core ML compute units configuration

```swift
// ❌ WRONG: Defaulting to CPU-only
let config = MLModelConfiguration()
// Uses CPU by default — ignores Neural Engine

// ✅ CORRECT: Enable all compute units including ANE
let config = MLModelConfiguration()
config.computeUnits = .all  // CPU + GPU + Neural Engine
// The system will pick the fastest available unit
```

---

## Category 3: coremltools Conversion (Python Side)

### Pitfall 3.1: HuggingFace model tracing with wrong inputs

```python
# ❌ WRONG: Tracing with just input_ids
traced = torch.jit.trace(model, dummy_input['input_ids'])

# ✅ CORRECT: Trace with ALL required inputs as a tuple
traced = torch.jit.trace(
    model, 
    (dummy_input['input_ids'], dummy_input['attention_mask'])
)
```

### Pitfall 3.2: Wrong output naming in coremltools

```python
# ❌ WRONG: Not specifying output names (auto-generated names are unpredictable)
mlmodel = ct.convert(traced, inputs=[...])

# ✅ CORRECT: Name outputs explicitly so Swift can reference them
mlmodel = ct.convert(
    traced,
    inputs=[
        ct.TensorType(name="input_ids", shape=(1, 128), dtype=np.int32),
        ct.TensorType(name="attention_mask", shape=(1, 128), dtype=np.int32),
    ],
    outputs=[
        ct.TensorType(name="last_hidden_state"),  # for embedding model
        # or ct.TensorType(name="logits"),         # for classifier
    ],
    compute_precision=ct.precision.FLOAT16,
    minimum_deployment_target=ct.target.iOS17,
)
```

### Pitfall 3.3: Sentence-Transformers model structure

Sentence-transformers wraps the base model in a wrapper. You need to export the inner model correctly:

```python
# ❌ WRONG: Trying to trace the SentenceTransformer wrapper directly
from sentence_transformers import SentenceTransformer
model = SentenceTransformer('./my-finetuned-model')
traced = torch.jit.trace(model, ...)  # FAILS — wrapper isn't traceable

# ✅ CORRECT: Extract the inner transformer + pooling, trace separately
from sentence_transformers import SentenceTransformer
st_model = SentenceTransformer('./my-finetuned-model')

# Get the underlying transformer
transformer = st_model[0].auto_model  # the actual BERT model
transformer.eval()

# Trace just the transformer
dummy = tokenizer("test", return_tensors="pt", padding="max_length", max_length=128)
traced = torch.jit.trace(transformer, (dummy['input_ids'], dummy['attention_mask']))

# Convert — you'll implement mean pooling in Swift
mlmodel = ct.convert(traced, ...)
```

---

## Category 4: DBSCAN & Accelerate

### Pitfall 4.1: vDSP function signature mistakes

```swift
// ❌ WRONG: Wrong parameter order or types
var result: Float = 0
vDSP_dotpr(&vectorA, 1, &vectorB, 1, &result, UInt(vectorA.count))  
// ⚠️ vDSP_dotpr takes [Float] not inout [Float]

// ✅ CORRECT: Pass arrays directly, use vDSP_Length
var result: Float = 0
vDSP_dotpr(vectorA, 1, vectorB, 1, &result, vDSP_Length(vectorA.count))
```

### Pitfall 4.2: Forgetting to handle empty or single-entry edge cases

```swift
// ❌ WRONG: Crashing on edge cases
func cluster(_ entries: [ClusterableEntry]) -> [ClusterAssignment] {
    let matrix = computeDistanceMatrix(...)  // crashes if entries.count == 0
    ...
}

// ✅ CORRECT: Guard edge cases
func cluster(_ entries: [ClusterableEntry]) -> [ClusterAssignment] {
    guard entries.count >= minPoints else {
        return entries.map { ClusterAssignment(bitID: $0.bitID, clusterID: -1) }
    }
    // ... proceed with clustering
}
```

---

## Category 5: SwiftUI View Layer

### Pitfall 5.1: Creating DateFormatter in computed properties

```swift
// ❌ WRONG: New DateFormatter on every view render
var formattedDate: String {
    let formatter = DateFormatter()  // ⚠️ Expensive! Created every render cycle
    formatter.dateFormat = "MMMM yyyy"
    return formatter.string(from: date)
}

// ✅ CORRECT: Static formatter, created once
private static let monthYearFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMMM yyyy"
    return f
}()

var formattedDate: String {
    Self.monthYearFormatter.string(from: date)
}
```

### Pitfall 5.2: Using UIScreen.main.bounds (deprecated)

```swift
// ❌ WRONG: Deprecated API
let width = UIScreen.main.bounds.width

// ✅ CORRECT: GeometryReader
GeometryReader { geometry in
    // use geometry.size.width
}
```

### Pitfall 5.3: ObservableObject vs @Observable confusion

```swift
// ❌ WRONG: Using @Observable with @ObservedObject
@Observable  // New observation framework (iOS 17)
class MyService { ... }

struct MyView: View {
    @ObservedObject var service: MyService  // ⚠️ @ObservedObject is for ObservableObject!
}

// ✅ CORRECT: Match the observation system
// Option A: Old system (project currently uses this)
class MyService: ObservableObject {
    @Published var data: [Item] = []
}
struct MyView: View {
    @ObservedObject var service: MyService  // ✅
}

// Option B: New system
@Observable class MyService {
    var data: [Item] = []
}
struct MyView: View {
    var service: MyService  // ✅ No wrapper needed with @Observable
}
```

> [!IMPORTANT]
> GJournal currently uses the **old** `ObservableObject` + `@Published` system (e.g., `BaseJournalRepository`, `ForceDirectedLayout`). The `EmotionConfigurationManager` uses `@Observable`. **Do not mix them carelessly** — pick one system per class and match the view wrappers accordingly.

---

## Category 6: Data & Persistence

### Pitfall 6.1: Binary embedding encode/decode endianness

```swift
// ❌ WRONG: Unsafe assumption about memory layout
let data = Data(bytes: &floatArray, count: floatArray.count * MemoryLayout<Float>.size)
// ⚠️ This creates a copy that may not round-trip on different architectures

// ✅ CORRECT: Use withUnsafeBytes for safe round-trip
// Encode
let data = floatArray.withUnsafeBytes { Data($0) }

// Decode  
let floats = data.withUnsafeBytes { buffer in
    Array(buffer.bindMemory(to: Float.self))
}
```

### Pitfall 6.2: SwiftData schema migration

```swift
// ❌ WRONG: Adding a new property and expecting old data to survive
@Model class Bit {
    var embeddingData: Data?  // NEW field — old database doesn't have this column
    // App crashes on launch: "migration required"
}

// ✅ CORRECT: Use lightweight migration (default for optional new fields)
// SwiftData handles optional new properties automatically IF they're Optional
// Non-optional new properties REQUIRE a VersionedSchema and SchemaMigrationPlan
@Model class Bit {
    var embeddingData: Data?  // Optional → auto-migrates to NULL
    var requiredField: String = "default"  // Non-optional with default → also OK
    // var requiredNoDefault: String  // ❌ WILL CRASH — no migration path
}
```

---

---

## Category 7: Training Environment

### Pitfall 7.1: Using fp16=True on M1 MPS

MPS (Apple Silicon GPU) does not support all float16 operations. Using `fp16=True` in `TrainingArguments` will raise a runtime error on M1.

```python
# ❌ WRONG: fp16 on MPS crashes
training_args = TrainingArguments(fp16=True, ...)

# ✅ CORRECT: Detect backend and choose precision
import torch
training_args = TrainingArguments(
    fp16=torch.cuda.is_available(),   # RTX 2070 supports fp16
    bf16=torch.backends.mps.is_available(),  # M1 supports bf16
    ...
)
```

### Pitfall 7.2: Hardcoding the CUDA device

```python
# ❌ WRONG: Crashes on M1 Mac (no CUDA)
device = torch.device("cuda")
model = model.to(device)

# ✅ CORRECT: Auto-detect in priority order
device = (
    torch.device("cuda") if torch.cuda.is_available() else
    torch.device("mps")  if torch.backends.mps.is_available() else
    torch.device("cpu")
)
model = model.to(device)
print(f"Using device: {device}")
```

### Pitfall 7.3: HuggingFace dataset download failures

```python
# ❌ WRONG: No error handling on dataset load
dataset = datasets.load_dataset("google-research-datasets/go_emotions", "simplified")

# ✅ CORRECT: Use local cache, retry logic, trust remote code
dataset = datasets.load_dataset(
    "google-research-datasets/go_emotions",
    "simplified",
    cache_dir="./hf_cache",
    trust_remote_code=True,
)
# If still failing: manually download via browser and load with
# datasets.load_dataset("json", data_files={"train": "go_emotions_train.jsonl"})
```

### Pitfall 7.4: SentenceTransformer pooling mismatch

The sentence-transformers library defaults to **mean pooling** over all token positions. If your Swift `CoreMLEmbeddingService` uses `[CLS]` token extraction instead, embeddings will be incompatible — DBSCAN will cluster garbage.

```python
# Verify pooling mode in the sentence-transformer config
import json
with open("models/mobilebert-stsb/1_Pooling/config.json") as f:
    pooling_config = json.load(f)
print(pooling_config)
# Must show: "pooling_mode_mean_tokens": true
# NOT: "pooling_mode_cls_token": true
```

Then in Swift, **always use mean pooling** to match:
```swift
// Mean pool over non-padding tokens — must match training
var sum = [Float](repeating: 0, count: embeddingDim)
for pos in 0..<realTokenCount {
    for dim in 0..<embeddingDim {
        sum[dim] += hiddenState[[0, NSNumber(value: pos), NSNumber(value: dim)]].floatValue
    }
}
let embedding = sum.map { $0 / Float(realTokenCount) }
```

### Pitfall 7.5: GoEmotions label mapping error — `confusion` is `Surprise`, not `Anxiety`

The doc `01_AI_PIPELINE.md` contains a bug: it maps `confusion` to `Anxiety`. The correct mapping is `Surprise`. Using the wrong mapping contaminates the Anxiety class with confusion examples.

```python
# ❌ WRONG (from 01_AI_PIPELINE.md): 
'confusion': 'Anxiety'

# ✅ CORRECT: confusion is cognitive disorientation, not emotional anxiety
'confusion': 'Surprise'   # realization + surprise + confusion = Surprise cluster
'nervousness': 'Anxiety'  # nervousness is the ONLY GoEmotions → Anxiety source
```

---

## Category 8: Backup Model Strategy

Use this decision tree if a model fails at training or Core ML conversion.

### 8.1 Embedding model fallback chain

```
MobileBERT (primary)
    ↓ if Core ML conversion fails
DistilBERT (backup A — better coremltools support)
    ↓ if conversion still fails
ONNX intermediate (backup B — export PyTorch → ONNX → CoreML)
    ↓ if ONNX pipeline fails
NLEmbedding (backup C — Apple's built-in, zero config, no training)
```

```python
# Backup B: ONNX intermediate path
import torch
torch.onnx.export(
    model,
    (input_ids, attention_mask),
    "model.onnx",
    input_names=["input_ids", "attention_mask"],
    output_names=["last_hidden_state"],
    dynamic_axes=None,        # keep static shapes
    opset_version=14,
)

import coremltools as ct
mlmodel = ct.converters.onnx.convert(
    model="model.onnx",
    minimum_ios_deployment_target="17",
)
mlmodel.save("GJournalEmbedding_onnx.mlpackage")
```

### 8.2 Emotion classifier fallback chain

```
MobileBERT fine-tuned on GoEmotions (primary)
    ↓ if accuracy < 45% or conversion fails
DistilBERT fine-tuned on GoEmotions (backup A)
    ↓ if training fails or takes too long
TF-IDF + LogisticRegression sklearn pipeline (backup B — see backup/train_emotion_simple.py)
    ↓ if sklearn export also fails
Keyword-based SafetyFilter extension (backup C — already in codebase, always works)
```

```python
# Backup B: sklearn fallback (produces a valid .mlpackage in minutes)
from sklearn.pipeline import Pipeline
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
import coremltools as ct

pipeline = Pipeline([
    ("tfidf", TfidfVectorizer(max_features=10000, ngram_range=(1, 2))),
    ("clf", LogisticRegression(max_iter=500, class_weight="balanced")),
])
pipeline.fit(X_train, y_train)

mlmodel = ct.converters.sklearn.convert(
    pipeline,
    input_features=[("text", ct.models.datatypes.String())],
    output_feature_names=TARGET_LABELS,
)
mlmodel.save("GJournalEmotionClassifier_simple.mlpackage")
```

### 8.3 When to abandon a path

| Symptom | Action |
|:--------|:-------|
| Core ML conversion error: "Unsupported op" | Try `convert_to="mlprogram"` then ONNX path |
| Training loss NaN after 50 steps | Reduce learning rate by 10x, reduce batch size |
| GoEmotions accuracy stuck < 40% | Check label mapping (Pitfall 7.5), check class weights |
| MPS out of memory during training | Reduce `per_device_train_batch_size` to 8 or 4 |
| STS-B Spearman < 0.65 after 4 epochs | Extend to 6 epochs or switch to `MultipleNegativesRankingLoss` |

---

## Quick Reference: Before Starting Any Implementation

1. ✅ Check which observation system the target class uses (`ObservableObject` vs `@Observable`)
2. ✅ Ensure all SwiftData writes happen on `@MainActor`
3. ✅ Never create `DateFormatter` inside computed properties or `body`
4. ✅ Use `GeometryReader` instead of `UIScreen.main.bounds`
5. ✅ Register ALL `@Model` types in `ModelContainer`
6. ✅ New SwiftData properties must be `Optional` or have defaults
7. ✅ Core ML inputs must be fixed-size (pad to `max_length`)
8. ✅ Core ML outputs: use mean pooling for embeddings, not raw `[CLS]`
9. ✅ WordPiece tokenization — not whitespace splitting
10. ✅ `vDSP_Length` not `UInt` for Accelerate functions
11. ✅ Device detection: `cuda → mps → cpu` (never hardcode `cuda`)
12. ✅ Training precision: `fp16` on CUDA, `bf16` on MPS, neither on CPU
13. ✅ GoEmotions mapping: `confusion → Surprise` (not Anxiety)
14. ✅ Have the backup model chain ready before starting conversion
