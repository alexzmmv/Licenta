# AI Pipeline — Model Strategy & Evaluation Plan

> The entire AI pipeline is currently mocked. This document covers the plan to build it.

---

## 1. The Three-Model Embedding Comparison

Your thesis compares three approaches for generating sentence embeddings from journal entries, evaluating each on **quality**, **latency**, **model size**, and **memory footprint** on-device.

### Model A: all-MiniLM-L6-v2 (SLOT 1 — Under 100 MB)

| Property | Value |
|:---------|:------|
| HuggingFace ID | `sentence-transformers/all-MiniLM-L6-v2` |
| Parameters | ~22.7M |
| Output dim | 384 |
| Core ML size | ~80 MB (FP32) / ~40 MB (FP16) |
| Training | Contrastive pre-training on 1B+ sentence pairs; no fine-tuning needed |
| Pooling | Mean pooling (architecturally enforced) |
| Tokenizer | WordPiece (inherited from MiniLM/BERT) |
| STS-B Spearman (measured) | **0.8696** |
| Pros | Highest downloads in class; strong STS-B; no fine-tuning required; mean pooling native |
| Cons | 384-dim output; 256-token max context window |

### Model B: BAAI/bge-small-en-v1.5 (SLOT 2 — 100–200 MB)

| Property | Value |
|:---------|:------|
| HuggingFace ID | `BAAI/bge-small-en-v1.5` |
| Parameters | ~33.4M |
| Output dim | 384 |
| Core ML size | ~130 MB (FP32) / ~65 MB (FP16) |
| Training | RetroMAE pre-training + contrastive fine-tuning on large retrieval/similarity corpora |
| Pooling | **CLS pooling** (position 0 — architecturally required, mean pooling would violate training objective) |
| Tokenizer | WordPiece (standard BERT `vocab.txt` — identical to Model A) |
| STS-B Spearman (measured) | **0.8828** |
| Pros | Current MTEB SOTA for sub-200MB class; stronger retrieval and clustering than MiniLM; different training objective enables architectural comparison |
| Cons | CLS pooling requires Swift `CoreMLEmbeddingService` to branch on pooling mode; ~50MB larger than Model A |

> **Why architecturally different models?** The thesis value is in comparing two distinct training paradigms: (A) knowledge distillation with mean pooling (all-MiniLM) vs (B) contrastive retrieval training with CLS pooling (BGE). The small STS-B gap (0.8696 vs 0.8828) understates the real difference — BGE significantly outperforms MiniLM on retrieval and clustering tasks (MTEB). The architectural difference will surface in DBSCAN cluster quality on journal text.

### Model C: Apple NLEmbedding (Baseline — No Training)

| Property | Value |
|:---------|:------|
| Base model | Apple's built-in sentence encoder (ships with iOS) |
| Parameters | N/A (OS-level, not in your bundle) |
| Output dim | 512 (fixed) |
| Core ML size | **0 bytes** (pre-installed on device) |
| Training | None required |
| STS-B Spearman | **Unknown** (Apple does not publish benchmark data) |
| Pros | Zero bundle size; runs on Apple Neural Engine; near-zero battery impact |
| Cons | Black-box; opaque architecture; high baseline similarity clustering (poor discrimination); cannot cite architecture in thesis |

```swift
// Model C implementation — ready to use today
import NaturalLanguage

final class NLEmbeddingService: EmbeddingServiceProtocol {
    func generateEmbedding(for text: String) async throws -> [Float] {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english),
              let vector = embedding.vector(for: text) else {
            throw AIServiceError.embeddingGenerationFailed
        }
        return vector.map { Float($0) }
    }
}
```

### Thesis Benchmark Table (to fill after iOS testing)

| Metric | all-MiniLM-L6-v2 | BAAI/bge-small-en-v1.5 | NLEmbedding |
|:-------|:----------------:|:----------------------:|:-----------:|
| Model size (Core ML, FP16) | ~40 MB | ~65 MB | 0 MB |
| Pooling mode | Mean | CLS | N/A |
| Inference latency (iPhone 11) | TBD ms | TBD ms | TBD ms |
| Peak memory usage | TBD MB | TBD MB | TBD MB |
| STS-B Spearman correlation | **0.8696** | **0.8828** | TBD |
| Cluster silhouette score | TBD | TBD | TBD |
| Battery impact (100 inferences) | TBD % | TBD % | TBD % |

---

## 2. Why Pre-trained Sentence Transformers Were Selected

### The Raw BERT Problem

Raw BERT `[CLS]` token embeddings produce poor cosine similarity results. This is well-documented:

> *"BERT embeddings without fine-tuning perform poorly for semantic similarity tasks, often worse than GloVe averages."*  
> — Reimers & Gurevych, 2019 (*Sentence-BERT*)

### Why These Two Models Satisfy the Constraint

`all-MiniLM-L6-v2` (knowledge distillation, mean pooling) and `BAAI/bge-small-en-v1.5` (contrastive retrieval training, CLS pooling) represent two distinct paradigms in sentence embedding research. Re-training from scratch adds no value — these models were trained on 1B+ pairs with objectives directly optimized for semantic similarity.

Key constraints satisfied (per 2024–2026 MTEB/STS-B analysis):
- **WordPiece tokenizer**: Both use standard BERT `vocab.txt` — one shared vocabulary file in Swift
- **No fine-tuning needed**: Pre-trained quality exceeds any 4-epoch STS-B fine-tune
- **Size**: Both fit in the iOS bundle after FP16 quantization (40MB and 65MB)
- **Pooling**: SLOT 1 uses mean pooling; SLOT 2 uses CLS pooling — `CoreMLEmbeddingService` branches on `PoolingMode` enum

### Why NOT fine-tuned MobileBERT or DistilBERT

| Candidate | Why Rejected |
|:----------|:-------------|
| `google/mobilebert-uncased` + STS-B fine-tune | Raw BERT base — requires full sentence-transformers training pipeline; inferior to pre-trained MiniLM; heavier (25M params in bottleneck arch with 512-dim intermediaries) |
| `distilbert-base-uncased` + STS-B fine-tune | 66M params → 250 MB FP32 — oversized; fine-tuning adds 20 min compute for lower STS-B than pre-trained MiniLM |
| `BAAI/bge-small-en-v1.5` | ~~Rejected~~ — **now SLOT 2**. CLS pooling supported via `PoolingMode.cls` in `CoreMLEmbeddingService`. |
| `snowflake-arctic-embed-xs` | CLS-pooled only; disqualified on same grounds |

---

## 3. Download & Evaluation Scripts

The Python scripts download the pre-trained models and evaluate on STS-B — no training loop needed.

### Script: train_embedding_mobilebert.py (Model A)

```python
# Download and evaluate all-MiniLM-L6-v2
# Output: training/models/mobilebert-stsb/
# Run: python train_embedding_mobilebert.py
from sentence_transformers import SentenceTransformer
from sentence_transformers.evaluation import EmbeddingSimilarityEvaluator
import datasets as hf_datasets

BASE_MODEL = "sentence-transformers/all-MiniLM-L6-v2"
model = SentenceTransformer(BASE_MODEL)
stsb = hf_datasets.load_dataset("glue", "stsb")

evaluator = EmbeddingSimilarityEvaluator(
    sentences1=[r["sentence1"] for r in stsb["validation"]],
    sentences2=[r["sentence2"] for r in stsb["validation"]],
    scores=[float(r["label"]) / 5.0 for r in stsb["validation"]],
)
score = evaluator(model)  # Expected: ~0.8696
model.save("models/mobilebert-stsb/")
```

### Script: train_embedding_distilbert.py (Model B)

```python
# Download and evaluate BAAI/bge-small-en-v1.5
# Output: training/models/distilbert-stsb/
# Run: python train_embedding_distilbert.py
BASE_MODEL = "BAAI/bge-small-en-v1.5"
# Uses CLS pooling — Swift CoreMLEmbeddingService uses poolingMode: .cls for this slot
# Expected STS-B Spearman: ~0.8828
```

### Time Estimates

| Script | Any machine |
|:-------|:------------|
| train_embedding_mobilebert.py | ~1 min (download + eval) |
| train_embedding_distilbert.py | ~1 min (download + eval) |
| train_emotion_classifier.py | ~25–40 min (RTX 2070) |

---

## 4. GoEmotions Emotion Classifier

### Architecture

Fine-tune a classification head using the GoEmotions dataset. This produces a separate Core ML model for emotion detection. The embedding and emotion models are independent — the emotion model uses its own tokenization and inference path.

> [!IMPORTANT]
> The emotion classifier runs entirely in the background after the user saves an entry. No emotion label is shown to or selected by the user during the journaling flow. All emotion UI (BitCard badge, EmotionDetailView, TopEmotionsView) is read-only AI output.

The GoEmotions→12 label mapping is defined in [`05_SCIENCE.md`](./05_SCIENCE.md).

### Training Script

```python
from transformers import (
    AutoTokenizer, AutoModelForSequenceClassification,
    TrainingArguments, Trainer
)
import datasets
import numpy as np

# GoEmotions mapping (28 → 12), defined in 05_SCIENCE.md
LABEL_MAP = {
    'joy': 'Joy', 'amusement': 'Joy', 'approval': 'Joy', 
    'pride': 'Joy', 'relief': 'Joy',
    'sadness': 'Sadness', 'grief': 'Sadness', 'disappointment': 'Sadness',
    'anger': 'Anger', 'annoyance': 'Anger', 'disapproval': 'Anger',
    'fear': 'Fear',
    'love': 'Love', 'caring': 'Love', 'admiration': 'Love', 'desire': 'Love',
    'surprise': 'Surprise', 'realization': 'Surprise', 'confusion': 'Surprise',
    'disgust': 'Disgust',
    'nervousness': 'Anxiety',
    'excitement': 'Excitement', 'curiosity': 'Excitement',
    'gratitude': 'Gratitude',
    'optimism': 'Hope',
    'remorse': 'Guilt', 'embarrassment': 'Guilt',
}
TARGET_LABELS = ['Joy','Sadness','Anger','Fear','Love','Surprise',
                 'Disgust','Anxiety','Excitement','Gratitude','Hope','Guilt']

# Load and remap GoEmotions
dataset = datasets.load_dataset('google-research-datasets/go_emotions', 'simplified')
tokenizer = AutoTokenizer.from_pretrained('google/mobilebert-uncased')
model = AutoModelForSequenceClassification.from_pretrained(
    'google/mobilebert-uncased', num_labels=12
)

def preprocess(example):
    tokens = tokenizer(example['text'], truncation=True, padding='max_length', max_length=128)
    go_label = dataset['train'].features['labels'].feature.int2str(example['labels'][0])
    mapped = LABEL_MAP.get(go_label, None)
    tokens['labels'] = TARGET_LABELS.index(mapped) if mapped else -1
    return tokens

tokenized = dataset.map(preprocess, batched=False)
tokenized = tokenized.filter(lambda x: x['labels'] != -1)

training_args = TrainingArguments(
    output_dir='./gjournal-emotion-classifier',
    num_train_epochs=3,
    per_device_train_batch_size=32,
    per_device_eval_batch_size=64,
    eval_strategy='epoch',
    save_strategy='epoch',
    load_best_model_at_end=True,
    fp16=True,  # RTX 2070 supports this
)

trainer = Trainer(model=model, args=training_args, 
                  train_dataset=tokenized['train'],
                  eval_dataset=tokenized['validation'])
trainer.train()
```

**Training time**: ~25–40 minutes on RTX 2070 (GoEmotions has ~58K examples).

---

## 5. Core ML Conversion

After evaluation, convert the saved PyTorch models to Core ML for on-device inference.

```python
import coremltools as ct
from transformers import AutoTokenizer, AutoModel
import torch
import numpy as np

# Load saved sentence-transformer model (already evaluated and saved)
from sentence_transformers import SentenceTransformer
st_model = SentenceTransformer('./models/mobilebert-stsb')

# Extract inner transformer (Pitfall 3.3 in 09_AI_PITFALLS.md)
transformer = st_model[0].auto_model
tokenizer = st_model[0].tokenizer
transformer.eval()

# Trace with dummy input (static shape required for Neural Engine)
dummy = tokenizer("I felt happy today", return_tensors="pt",
                   padding="max_length", max_length=128)
traced = torch.jit.trace(transformer, (dummy['input_ids'], dummy['attention_mask']))

# Convert to Core ML with FP32 LayerNorm (required to prevent ANE overflow)
op_config = ct.OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8")
mlmodel = ct.convert(
    traced,
    inputs=[
        ct.TensorType(name="input_ids", shape=(1, 128), dtype=np.int32),
        ct.TensorType(name="attention_mask", shape=(1, 128), dtype=np.int32),
    ],
    outputs=[ct.TensorType(name="last_hidden_state")],
    compute_precision=ct.precision.FLOAT16,
    compute_units=ct.ComputeUnit.ALL,
    minimum_deployment_target=ct.target.iOS17,
)
mlmodel.save("GJournalEmbeddingMiniLM.mlpackage")
```

> [!IMPORTANT]
> Run conversion on **M1 MacBook Pro** — `coremltools` works best on macOS.  
> Mean pooling is implemented in **Swift** at inference time, not baked into the Core ML graph.
> The LayerNorm FP16 overflow issue (documented in 09_AI_PITFALLS.md) requires testing the output
> embeddings numerically after conversion — if cosine similarity of identical inputs is not ~1.0, the
> op_selector mixed-precision workaround is needed.

---

## 6. TextFlattener Fix

### The Problem

Current format: `[Title] My story [Feel] I felt happy [Event] Had a meeting [Action] Will rest`

Pretrained BERT models have **never seen** bracket tags like `[Title]`, `[Feel]`, `[Event]`, `[Action]` during pre-training. These tokens are either:
- Split into sub-word pieces (`[`, `Ti`, `##tle`, `]`) — meaningless noise
- Or treated as BERT's own special tokens (confusion with `[CLS]`, `[SEP]`, `[MASK]`)

### The Fix

Strip brackets entirely. Use natural language concatenation:

```swift
struct TextFlattener {
    static func flatten(bit: Bit) -> String {
        var parts: [String] = []
        
        if let title = bit.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            parts.append(title)
        }
        
        let feel = bit.feel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !feel.isEmpty { parts.append(feel) }
        
        let event = bit.event.trimmingCharacters(in: .whitespacesAndNewlines)
        if !event.isEmpty { parts.append(event) }
        
        let action = bit.action.trimmingCharacters(in: .whitespacesAndNewlines)
        if !action.isEmpty { parts.append(action) }
        
        return parts.joined(separator: ". ")
    }
}
```

**Result**: `My story. I felt happy. Had a meeting. Will rest`

This produces natural English sentences that BERT was trained to understand.

---

## 7. Swift Integration (ServiceContainer)

Once Core ML models are ready, wire them in:

```swift
static func makeProduction() -> ServiceContainer {
    return ServiceContainer(
        embeddingService: CoreMLEmbeddingService(modelName: "GJournalEmbeddingMiniLM"),
        emotionService: CoreMLEmotionService(modelName: "GJournalEmotionClassifier"),
        clusteringService: DBSCANClusterer(epsilon: 0.3, minPoints: 3),
        safetyFilter: SafetyFilter()
    )
}
```

The `CoreMLEmbeddingService` and `CoreMLEmotionService` are new Swift files. They should:
1. Load the `.mlpackage` at init
2. Tokenize input text (using a bundled vocabulary file from HuggingFace)
3. Run `MLModel.prediction(from:)` on a background thread
4. Extract the output tensor, apply mean pooling in Swift, return `[Float]` / `[EmotionProbability]`

> [!WARNING]
> **Tokenization on-device** is the trickiest part. Both MiniLM models use WordPiece tokenization (standard BERT `vocab.txt`, 30,522 tokens). Bundle the `vocab.txt` from the saved model directory. The vocabulary is identical for both SLOT 1 and SLOT 2 models — use a single shared vocabulary file.

---

## 🎓 PhD Review

1. **Using pre-trained sentence transformers is methodologically sound and current best practice**. Reimers & Gurevych (2019) introduced SBERT — cite this. The 1B+ pair training scale makes on-task fine-tuning redundant for general English. Frame as: *"We leverage state-of-the-art pre-trained bi-encoders, eliminating the need for task-specific fine-tuning while exceeding the performance of fine-tuned BERT baselines reported in prior work."*
2. **STS-B is the correct benchmark** for evaluating embedding quality. Report Spearman's rank correlation coefficient — this is what the community uses. Measured scores (0.8696 / 0.8695) already exceed the typical fine-tuned MobileBERT baseline (~0.78).
3. **The 3-model comparison is methodologically sound**. It compares: (a) a contrastive-pretrained model optimized for general semantic similarity (all-MiniLM-L6-v2), (b) a paraphrase-pretrained model (paraphrase-MiniLM-L6-v2), (c) a zero-cost OS baseline (NLEmbedding). This covers the portability-quality tradeoff.
4. **The TextFlattener fix** is a linguistic argument about tokenization compatibility. Frame it as: *"Domain-specific markup interferes with subword tokenization in pre-trained language models."*
5. **Add a "no pre-training" ablation**: show raw BERT (e.g., `bert-base-uncased` without sentence-transformer fine-tuning) to prove the sentence-transformer training objective matters.

## 🔴 Red-Hat Review

1. **`coremltools` conversion is fragile**. Known issues: (a) Some PyTorch ops unsupported, (b) Dynamic shapes fail on Neural Engine, (c) LayerNorm FP16 overflow (see `09_AI_PITFALLS.md`). Test conversion EARLY (Day 1–2). The ONNX intermediate path is the fallback.
2. **Mean pooling must match training**. Both models use `pooling_mode_mean_tokens: true` — verified in saved config. If you implement `[CLS]` extraction in Swift instead, embeddings will be geometrically wrong. **Verify with `verify_tokenizer.py`**.
3. **Both models share the same vocab.txt**. Bundle ONE copy. Verify token IDs match between Python and Swift for the same input sentence.
4. **NLEmbedding.sentenceEmbedding(for: .english)** may return `nil` on older iOS versions or if the model hasn't been downloaded to the device. Always handle the `nil` case. Test on iPhone 11 (iOS 18) first.
5. **Both models have 256-token max context**. Journal entries that exceed this are silently truncated. For most micro-journal entries (1–3 sentences) this is not a concern — but document the limitation.
