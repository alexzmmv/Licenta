# AI Pipeline — Model Strategy & Training Plan

> The entire AI pipeline is currently mocked. This document covers the plan to build it.

---

## 1. The Three-Model Embedding Comparison

Your thesis will compare three approaches for generating sentence embeddings from journal entries, evaluating each on **quality**, **latency**, **model size**, and **memory footprint** on-device.

### Model A: Fine-tuned DistilBERT (Sentence-Transformer)

| Property | Value |
|:---------|:------|
| Base model | `distilbert-base-uncased` (HuggingFace) |
| Parameters | ~66M |
| Output dim | 768 (can project to 256 via pooling head) |
| Core ML size | ~250MB (float32) / ~65MB (float16 quantized) |
| Training | Sentence-Transformers contrastive fine-tuning |
| Pros | Best embedding quality; widely studied; strong academic citations |
| Cons | Largest model; slowest inference on iPhone 11 |

### Model B: Fine-tuned MobileBERT

| Property | Value |
|:---------|:------|
| Base model | `google/mobilebert-uncased` (HuggingFace) |
| Parameters | ~25M |
| Output dim | 512 (can project to 256) |
| Core ML size | ~100MB (float32) / ~25MB (float16 quantized) |
| Training | Same sentence-transformers pipeline as Model A |
| Pros | Designed for mobile; 3-4x faster than DistilBERT; smaller memory |
| Cons | Slightly lower embedding quality than DistilBERT |

### Model C: Apple NLEmbedding (Baseline — No Training)

| Property | Value |
|:---------|:------|
| Base model | Apple's built-in sentence encoder (ships with iOS) |
| Parameters | N/A (OS-level, not in your bundle) |
| Output dim | 512 (fixed) |
| Core ML size | **0 bytes** (pre-installed on device) |
| Training | None required |
| Pros | Zero bundle size; runs on Apple Neural Engine; near-zero battery impact |
| Cons | Not fine-tuned for emotional/journal text; opaque model; can't cite architecture in thesis |

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

### Thesis Benchmark Table (to fill after training)

| Metric | DistilBERT | MobileBERT | NLEmbedding |
|:-------|:----------:|:----------:|:-----------:|
| Model size (Core ML, float16) | ~65MB | ~25MB | 0MB |
| Inference latency (iPhone 11) | TBD ms | TBD ms | TBD ms |
| Peak memory usage | TBD MB | TBD MB | TBD MB |
| STS-B Spearman correlation | TBD | TBD | TBD |
| Cluster silhouette score | TBD | TBD | TBD |
| Battery impact (100 inferences) | TBD % | TBD % | TBD % |

---

## 2. Embedding Fine-Tuning Pipeline

### Why Fine-Tuning is Required

Raw BERT `[CLS]` token embeddings produce poor cosine similarity results. This is well-documented:

> *"BERT embeddings without fine-tuning perform poorly for semantic similarity tasks, often worse than GloVe averages."*  
> — Reimers & Gurevych, 2019 (*Sentence-BERT*)

You must fine-tune using the **Sentence-Transformers** framework to produce embeddings where cosine similarity correlates with semantic similarity.

### Training Dataset

Use **STS-Benchmark** (Semantic Textual Similarity) — 8,628 sentence pairs with human-rated similarity scores (0-5). This is the standard academic benchmark for sentence embedding quality.

Optionally augment with **AllNLI** (SNLI + MultiNLI) using `MultipleNegativesRankingLoss` for stronger generalization.

### Training Script (Python — run on your RTX 2070)

```python
from sentence_transformers import SentenceTransformer, InputExample, losses
from sentence_transformers.evaluation import EmbeddingSimilarityEvaluator
from torch.utils.data import DataLoader
import datasets

# Load base model
model = SentenceTransformer('google/mobilebert-uncased')  # or 'distilbert-base-uncased'

# Load STS-B
stsb = datasets.load_dataset('glue', 'stsb')

# Prepare training data
train_examples = [
    InputExample(texts=[row['sentence1'], row['sentence2']], 
                 label=row['label'] / 5.0)  # normalize to 0-1
    for row in stsb['train']
]

train_dataloader = DataLoader(train_examples, shuffle=True, batch_size=16)
train_loss = losses.CosineSimilarityLoss(model)

# Evaluator
eval_examples = [
    InputExample(texts=[row['sentence1'], row['sentence2']], 
                 label=row['label'] / 5.0)
    for row in stsb['validation']
]
evaluator = EmbeddingSimilarityEvaluator.from_input_examples(eval_examples)

# Train
model.fit(
    train_objectives=[(train_dataloader, train_loss)],
    evaluator=evaluator,
    epochs=4,
    warmup_steps=100,
    output_path='./mobilebert-stsb-finetuned'
)
```

**Hardware allocation**:
- **RTX 2070 (8GB)**: Fine-tune DistilBERT and MobileBERT (batch_size=16 fits comfortably)
- **M1 MacBook Pro**: Core ML conversion via `coremltools`, testing NLEmbedding baseline

### Training Time Estimates

| Model | RTX 2070 (4 epochs, STS-B) |
|:------|:---------------------------|
| DistilBERT | ~15-20 minutes |
| MobileBERT | ~8-12 minutes |
| NLEmbedding | No training needed |

---

## 3. GoEmotions Emotion Classifier

### Architecture

Fine-tune a classification head on the **same** base model (MobileBERT or DistilBERT) using the GoEmotions dataset. This produces a separate Core ML model for emotion detection.

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
    'surprise': 'Surprise', 'realization': 'Surprise',
    'disgust': 'Disgust',
    'nervousness': 'Anxiety', 'confusion': 'Anxiety',
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

# Preprocessing: map GoEmotions labels → 12 GJournal labels
def preprocess(example):
    tokens = tokenizer(example['text'], truncation=True, padding='max_length', max_length=128)
    # Map first label (GoEmotions can be multi-label; take primary)
    go_label = dataset['train'].features['labels'].feature.int2str(example['labels'][0])
    mapped = LABEL_MAP.get(go_label, None)
    tokens['labels'] = TARGET_LABELS.index(mapped) if mapped else -1
    return tokens

tokenized = dataset.map(preprocess, batched=False)
tokenized = tokenized.filter(lambda x: x['labels'] != -1)  # drop unmapped

# Train
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

**Training time**: ~25-40 minutes on RTX 2070 (GoEmotions has ~58K examples).

---

## 4. Core ML Conversion

After training, convert both PyTorch models to Core ML for on-device inference.

```python
import coremltools as ct
from transformers import AutoTokenizer, AutoModel
import torch

# Load fine-tuned model
model = AutoModel.from_pretrained('./mobilebert-stsb-finetuned')
tokenizer = AutoTokenizer.from_pretrained('google/mobilebert-uncased')
model.eval()

# Trace with dummy input
dummy = tokenizer("I felt happy today", return_tensors="pt", 
                   padding="max_length", max_length=128)
traced = torch.jit.trace(model, (dummy['input_ids'], dummy['attention_mask']))

# Convert to Core ML
mlmodel = ct.convert(
    traced,
    inputs=[
        ct.TensorType(name="input_ids", shape=(1, 128), dtype=np.int32),
        ct.TensorType(name="attention_mask", shape=(1, 128), dtype=np.int32),
    ],
    compute_precision=ct.precision.FLOAT16,  # halves model size
    compute_units=ct.ComputeUnit.ALL,  # enables ANE
)
mlmodel.save("GJournalEmbedding.mlpackage")
```

> [!IMPORTANT]  
> Run conversion on **M1 MacBook Pro** — `coremltools` works best on macOS.
> Use `compute_precision=FLOAT16` to cut model size by ~60% with negligible quality loss.

---

## 5. TextFlattener Fix

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

## 6. Swift Integration (ServiceContainer)

Once Core ML models are ready, wire them in:

```swift
static func makeProduction() -> ServiceContainer {
    return ServiceContainer(
        embeddingService: CoreMLEmbeddingService(modelName: "GJournalEmbedding"),
        emotionService: CoreMLEmotionService(modelName: "GJournalEmotionClassifier"),
        clusteringService: DBSCANClusterer(epsilon: 0.3, minPoints: 3),
        safetyFilter: SafetyFilter()
    )
}
```

The `CoreMLEmbeddingService` and `CoreMLEmotionService` are new Swift files you'll need to create. They should:
1. Load the `.mlpackage` at init
2. Tokenize input text (using a bundled vocabulary file or Apple's `NLTokenizer`)
3. Run `MLModel.prediction(from:)` on a background thread
4. Extract the output tensor and return `[Float]` / `[EmotionProbability]`

> [!WARNING]
> **Tokenization on-device** is the trickiest part. You need to bundle the WordPiece vocabulary (`vocab.txt`) from HuggingFace and implement (or port) the tokenizer in Swift. Alternatively, use Apple's `NLTokenizer` with a custom vocabulary — but this won't match BERT's WordPiece exactly.
> 
> Recommended approach: Use the `swift-transformers` package from HuggingFace or manually port the tokenizer.

---

## 🎓 PhD Review

1. **Sentence-Transformers fine-tuning is the gold standard** for producing sentence embeddings. Cite Reimers & Gurevych (2019) — this paper has 5,000+ citations and is the definitive reference.
2. **STS-B is the correct benchmark** for evaluating embedding quality. Report Spearman's rank correlation coefficient — this is what the community uses.
3. **The 3-model comparison is methodologically sound**. It compares: (a) a large fine-tuned model (DistilBERT), (b) a mobile-optimized fine-tuned model (MobileBERT), (c) a zero-cost baseline (NLEmbedding). This covers the efficiency-quality tradeoff spectrum.
4. **Consider adding a "no fine-tuning" baseline** — run raw DistilBERT/MobileBERT without sentence-transformer training to show that fine-tuning actually matters. This strengthens the thesis argument.
5. **The TextFlattener fix** is not just a practical fix — it's a linguistic argument about tokenization compatibility. Frame it as: *"Domain-specific markup interferes with subword tokenization in pre-trained language models."*

## 🔴 Red-Hat Review

1. **`coremltools` conversion is fragile**. Known issues: (a) Some PyTorch ops aren't supported, (b) Dynamic shapes fail, (c) MobileBERT's bottleneck architecture may need `ct.convert(traced, convert_to="mlprogram")` instead of the default neuralnetwork format. Test conversion EARLY (Day 1-2).
2. **Mean pooling must match training**. Sentence-transformers defaults to mean pooling, but some models use `[CLS]` pooling. If you train with mean pooling but implement `[CLS]` extraction in Swift, embeddings will be wrong. **Verify the pooling mode in the sentence-transformers config**.
3. **GoEmotions is multi-label** (entries can have 2+ emotions). The training script above takes only the first label. This discards information. Consider: (a) training as multi-label (sigmoid per class), or (b) duplicating multi-label examples.
4. **RTX 2070 with 8GB VRAM**: DistilBERT fine-tuning at batch_size=16 should fit. If OOM, reduce to 8. MobileBERT will definitely fit.
5. **NLEmbedding.sentenceEmbedding(for: .english)** may return `nil` on older iOS versions or if the model hasn't been downloaded. Always handle the `nil` case gracefully. Test on iPhone 11 (iOS 18) first.
6. **Vocab file bundling**: The `vocab.txt` for MobileBERT and DistilBERT are different (MobileBERT uses a 30,522-token vocab). Ensure you bundle the correct one for each model.
