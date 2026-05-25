"""
Fine-tune MobileBERT on STS-B for sentence-level semantic similarity.
Output: training/models/mobilebert-stsb/

Run: python train_embedding_mobilebert.py
Time: ~10 min (RTX 2070) | ~45 min (M1 MPS) | ~3h (CPU)

Pitfall refs: 09_AI_PITFALLS.md — Pitfall 7.4 (pooling mismatch)
"""

import os
import json
from pathlib import Path

import torch
import datasets
from sentence_transformers import SentenceTransformer, InputExample, losses
from sentence_transformers.evaluation import EmbeddingSimilarityEvaluator
from torch.utils.data import DataLoader

# ── Config ──────────────────────────────────────────────────────────────────
BASE_MODEL   = "google/mobilebert-uncased"
OUTPUT_DIR   = Path("models/mobilebert-stsb")
BATCH_SIZE   = 16 if torch.cuda.is_available() else 8
EPOCHS       = 4
MAX_LENGTH   = 128
WARMUP_STEPS = 100

device = (
    "cuda" if torch.cuda.is_available() else
    "mps"  if torch.backends.mps.is_available() else
    "cpu"
)
print(f"Device: {device}")
print(f"Base model: {BASE_MODEL}")
print(f"Output: {OUTPUT_DIR}")

# ── Load STS-B ───────────────────────────────────────────────────────────────
print("\nLoading STS-B dataset...")
stsb = datasets.load_dataset("glue", "stsb", cache_dir="./hf_cache")

def to_examples(split):
    return [
        InputExample(
            texts=[row["sentence1"], row["sentence2"]],
            label=float(row["label"]) / 5.0,  # normalize 0-5 → 0-1
        )
        for row in stsb[split]
    ]

train_examples = to_examples("train")
val_examples   = to_examples("validation")

print(f"Train: {len(train_examples)} pairs | Val: {len(val_examples)} pairs")

# ── Model + Loss + Evaluator ──────────────────────────────────────────────────
model = SentenceTransformer(BASE_MODEL, device=device)
train_dl = DataLoader(train_examples, shuffle=True, batch_size=BATCH_SIZE)
train_loss = losses.CosineSimilarityLoss(model)

evaluator = EmbeddingSimilarityEvaluator.from_input_examples(
    val_examples,
    name="stsb-val",
)

# ── Train ─────────────────────────────────────────────────────────────────────
print("\nStarting training...")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

model.fit(
    train_objectives=[(train_dl, train_loss)],
    evaluator=evaluator,
    epochs=EPOCHS,
    warmup_steps=WARMUP_STEPS,
    output_path=str(OUTPUT_DIR),
    save_best_model=True,
    show_progress_bar=True,
)

# ── Verify pooling mode ───────────────────────────────────────────────────────
pooling_cfg = OUTPUT_DIR / "1_Pooling" / "config.json"
if pooling_cfg.exists():
    with open(pooling_cfg) as f:
        cfg = json.load(f)
    mean_pooling = cfg.get("pooling_mode_mean_tokens", False)
    cls_pooling  = cfg.get("pooling_mode_cls_token", False)
    print(f"\nPooling check — mean: {mean_pooling} | CLS: {cls_pooling}")
    if not mean_pooling:
        print("WARNING: Model is NOT using mean pooling. Swift must match this.")
    else:
        print("OK: Mean pooling confirmed. Swift CoreMLEmbeddingService must also use mean pooling.")

# ── Final evaluation ──────────────────────────────────────────────────────────
test_examples = to_examples("validation")
test_evaluator = EmbeddingSimilarityEvaluator.from_input_examples(
    test_examples,
    name="stsb-final",
)
final_model = SentenceTransformer(str(OUTPUT_DIR), device=device)
score = test_evaluator(final_model)

results_dir = Path("results")
results_dir.mkdir(exist_ok=True)
with open(results_dir / "mobilebert_stsb.txt", "w") as f:
    f.write(f"Model: {BASE_MODEL}\n")
    f.write(f"Device: {device}\n")
    f.write(f"Epochs: {EPOCHS}\n")
    f.write(f"STS-B Spearman correlation: {score:.4f}\n")

print(f"\nFinal STS-B Spearman: {score:.4f}")
print(f"Target: > 0.75")
if score > 0.75:
    print("PASS")
else:
    print("FAIL — consider more epochs or switching to MultipleNegativesRankingLoss")
print(f"\nModel saved to: {OUTPUT_DIR}")
