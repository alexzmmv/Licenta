"""
Fine-tune MobileBERT on GoEmotions → 12-class GJournal emotion classifier.
Output: training/models/emotion-classifier/

Run: python train_emotion_classifier.py
Time: ~35 min (RTX 2070) | ~2.5h (M1 MPS) | ~8h (CPU)

IMPORTANT pitfall fixes applied:
- confusion → Surprise (NOT Anxiety — see 09_AI_PITFALLS.md Pitfall 7.5)
- fp16 on CUDA only, bf16 on MPS (Pitfall 7.1)
- WeightedTrainer handles class imbalance (Anxiety has ~500 examples vs Joy ~8000)
- Multi-label examples duplicated once per label (not dropped)
"""

from pathlib import Path
from collections import Counter

import numpy as np
import torch
import torch.nn.functional as F
import datasets
from sklearn.utils.class_weight import compute_class_weight
from transformers import (
    AutoTokenizer,
    AutoModelForSequenceClassification,
    Trainer,
    TrainingArguments,
    EarlyStoppingCallback,
)
import evaluate

# ── Config ────────────────────────────────────────────────────────────────────
BASE_MODEL   = "google/mobilebert-uncased"
OUTPUT_DIR   = Path("models/emotion-classifier")
BATCH_SIZE   = 32 if torch.cuda.is_available() else 16
EPOCHS       = 3
MAX_LENGTH   = 128
LEARNING_RATE = 2e-5

device = (
    "cuda" if torch.cuda.is_available() else
    "mps"  if torch.backends.mps.is_available() else
    "cpu"
)
print(f"Device: {device}")

# ── GoEmotions → 12-class mapping ─────────────────────────────────────────────
# confusion → Surprise (corrected from 01_AI_PIPELINE.md which had confusion → Anxiety)
LABEL_MAP = {
    "joy":           "Joy",
    "amusement":     "Joy",
    "approval":      "Joy",
    "pride":         "Joy",
    "relief":        "Joy",
    "sadness":       "Sadness",
    "grief":         "Sadness",
    "disappointment":"Sadness",
    "anger":         "Anger",
    "annoyance":     "Anger",
    "disapproval":   "Anger",
    "fear":          "Fear",
    "love":          "Love",
    "caring":        "Love",
    "admiration":    "Love",
    "desire":        "Love",
    "surprise":      "Surprise",
    "realization":   "Surprise",
    "confusion":     "Surprise",   # cognitive disorientation, NOT anxiety
    "disgust":       "Disgust",
    "nervousness":   "Anxiety",    # ONLY source for Anxiety
    "excitement":    "Excitement",
    "curiosity":     "Excitement",
    "gratitude":     "Gratitude",
    "optimism":      "Hope",
    "remorse":       "Guilt",
    "embarrassment": "Guilt",
    # "neutral" is intentionally dropped
}

TARGET_LABELS = [
    "Joy", "Sadness", "Anger", "Fear", "Love", "Surprise",
    "Disgust", "Anxiety", "Excitement", "Gratitude", "Hope", "Guilt",
]
LABEL2ID = {label: i for i, label in enumerate(TARGET_LABELS)}
ID2LABEL = {i: label for label, i in LABEL2ID.items()}

# ── Load and remap GoEmotions ──────────────────────────────────────────────────
print("Loading GoEmotions dataset...")
raw = datasets.load_dataset(
    "google-research-datasets/go_emotions",
    "simplified",
    cache_dir="./hf_cache",
    trust_remote_code=True,
)

# Feature name lookup for int → label string conversion
label_feature = raw["train"].features["labels"].feature

def remap(example):
    """Expand multi-label examples into one example per label, drop unmapped."""
    results = []
    for label_id in example["labels"]:
        go_label = label_feature.int2str(label_id)
        mapped = LABEL_MAP.get(go_label)
        if mapped is not None:
            results.append({"text": example["text"], "label": LABEL2ID[mapped]})
    return results

def build_split(split_name):
    rows = []
    for ex in raw[split_name]:
        rows.extend(remap(ex))
    return datasets.Dataset.from_list(rows)

print("Remapping labels...")
train_ds = build_split("train")
val_ds   = build_split("validation")
test_ds  = build_split("test")

print(f"Train: {len(train_ds)} | Val: {len(val_ds)} | Test: {len(test_ds)}")

label_counts = Counter(train_ds["label"])
print("\nClass distribution (train):")
for i, name in enumerate(TARGET_LABELS):
    n = label_counts.get(i, 0)
    print(f"  {name:12s}: {n:5d}")

# ── Tokenize ──────────────────────────────────────────────────────────────────
tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL, cache_dir="./hf_cache")

def tokenize(batch):
    return tokenizer(
        batch["text"],
        truncation=True,
        padding="max_length",
        max_length=MAX_LENGTH,
    )

print("\nTokenizing...")
train_ds = train_ds.map(tokenize, batched=True)
val_ds   = val_ds.map(tokenize, batched=True)
test_ds  = test_ds.map(tokenize, batched=True)

train_ds.set_format("torch", columns=["input_ids", "attention_mask", "label"])
val_ds.set_format("torch",   columns=["input_ids", "attention_mask", "label"])
test_ds.set_format("torch",  columns=["input_ids", "attention_mask", "label"])

# ── Class weights ─────────────────────────────────────────────────────────────
all_labels = np.array(train_ds["label"])
class_weights = compute_class_weight(
    class_weight="balanced",
    classes=np.arange(len(TARGET_LABELS)),
    y=all_labels,
)
weights_tensor = torch.tensor(class_weights, dtype=torch.float)
print(f"\nClass weights range: [{weights_tensor.min():.2f}, {weights_tensor.max():.2f}]")

# ── Weighted Trainer ──────────────────────────────────────────────────────────
class WeightedTrainer(Trainer):
    def __init__(self, class_weights, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._class_weights = class_weights

    def compute_loss(self, model, inputs, return_outputs=False, **kwargs):
        labels = inputs.pop("labels")
        outputs = model(**inputs)
        loss = F.cross_entropy(
            outputs.logits,
            labels,
            weight=self._class_weights.to(outputs.logits.device),
        )
        return (loss, outputs) if return_outputs else loss

# ── Metrics ───────────────────────────────────────────────────────────────────
f1_metric = evaluate.load("f1")

def compute_metrics(eval_pred):
    logits, labels = eval_pred
    preds = np.argmax(logits, axis=-1)
    result = f1_metric.compute(predictions=preds, references=labels, average="macro")
    result["accuracy"] = (preds == labels).mean()
    return result

# ── Training args ─────────────────────────────────────────────────────────────
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

training_args = TrainingArguments(
    output_dir=str(OUTPUT_DIR),
    num_train_epochs=EPOCHS,
    per_device_train_batch_size=BATCH_SIZE,
    per_device_eval_batch_size=64,
    learning_rate=LEARNING_RATE,
    warmup_ratio=0.06,
    eval_strategy="epoch",
    save_strategy="epoch",
    load_best_model_at_end=True,
    metric_for_best_model="f1",
    fp16=torch.cuda.is_available(),
    bf16=torch.backends.mps.is_available(),
    logging_steps=100,
    report_to="none",
)

model = AutoModelForSequenceClassification.from_pretrained(
    BASE_MODEL,
    num_labels=len(TARGET_LABELS),
    id2label=ID2LABEL,
    label2id=LABEL2ID,
    cache_dir="./hf_cache",
)

trainer = WeightedTrainer(
    class_weights=weights_tensor,
    model=model,
    args=training_args,
    train_dataset=train_ds,
    eval_dataset=val_ds,
    compute_metrics=compute_metrics,
    callbacks=[EarlyStoppingCallback(early_stopping_patience=2)],
)

print("\nStarting training...")
trainer.train()

# ── Test evaluation ───────────────────────────────────────────────────────────
print("\nEvaluating on test set...")
test_results = trainer.predict(test_ds)
test_preds   = np.argmax(test_results.predictions, axis=-1)
test_labels  = test_results.label_ids

from sklearn.metrics import classification_report, confusion_matrix
report = classification_report(
    test_labels, test_preds,
    target_names=TARGET_LABELS,
    digits=3,
)
print(report)

Path("results").mkdir(exist_ok=True)
with open("results/emotion_report.txt", "w") as f:
    f.write(f"Base model: {BASE_MODEL}\n")
    f.write(f"Device: {device}\n")
    f.write(f"Epochs: {EPOCHS}\n\n")
    f.write(report)
    f.write("\nConfusion matrix:\n")
    f.write(str(confusion_matrix(test_labels, test_preds)))

overall_acc = (test_preds == test_labels).mean()
print(f"\nOverall accuracy: {overall_acc:.3f} (target > 0.60)")
if overall_acc < 0.45:
    print("WARN: Accuracy very low — check label mapping (Pitfall 7.5) and class weights")
print(f"Full report saved to results/emotion_report.txt")
print(f"Model saved to: {OUTPUT_DIR}")
