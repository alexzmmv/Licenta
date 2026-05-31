"""
Fine-tune DistilBERT on STS-B for sentence-level semantic similarity.
Output: training/models/distilbert-stsb/

Run: python train_embedding_distilbert.py
      python train_embedding_distilbert.py --test    (2 min quick validation)
Time: ~20 min (RTX 2070) | ~90 min (M1 MPS) | ~5h (CPU)

DistilBERT produces higher-quality embeddings than MobileBERT but is 2.5x larger.
Use as Backup A if MobileBERT Core ML conversion fails.

Pitfall refs: 09_AI_PITFALLS.md — Pitfall 7.4 (pooling mismatch)
"""

import json
import sys
from pathlib import Path

import torch
import datasets as hf_datasets
from datasets import Dataset as HFDataset
from sentence_transformers import (
    SentenceTransformer,
    SentenceTransformerTrainer,
    SentenceTransformerTrainingArguments,
)
from sentence_transformers.sentence_transformer.losses import CoSENTLoss
from sentence_transformers.sentence_transformer.modules import Transformer, Pooling
from sentence_transformers.sentence_transformer.evaluation import EmbeddingSimilarityEvaluator

# ── Test mode flag ──────────────────────────────────────────────────────────
TEST_MODE = "--test" in sys.argv
if TEST_MODE:
    print("⚡ TEST MODE: 100 examples, 1 epoch, will finish in ~2 min")

BASE_MODEL = "distilbert-base-uncased"
OUTPUT_DIR = Path("models/distilbert-stsb")
BATCH_SIZE = 16 if torch.cuda.is_available() else 8
EPOCHS     = 1 if TEST_MODE else 4
MAX_LENGTH = 128

device = (
    "cuda" if torch.cuda.is_available() else
    "mps"  if torch.backends.mps.is_available() else
    "cpu"
)
print(f"Device: {device} | Model: {BASE_MODEL}")

print("Loading STS-B dataset...")
stsb = hf_datasets.load_dataset("glue", "stsb", cache_dir="./hf_cache")

def to_hf_dataset(split, limit=None):
    rows = list(stsb[split])
    if limit:
        rows = rows[:limit]
    return HFDataset.from_dict({
        "sentence1": [r["sentence1"] for r in rows],
        "sentence2": [r["sentence2"] for r in rows],
        "label":     [float(r["label"]) / 5.0 for r in rows],
    })

train_dataset = to_hf_dataset("train", limit=100 if TEST_MODE else None)
val_dataset   = to_hf_dataset("validation")
print(f"Train: {len(train_dataset)} pairs | Val: {len(val_dataset)} pairs")

# ── Explicit mean pooling module ─────────────────────────────────────────────
word_embedding_model = Transformer(BASE_MODEL, max_seq_length=MAX_LENGTH)
pooling_model = Pooling(
    word_embedding_model.get_embedding_dimension(),
    pooling_mode="mean",
)
model = SentenceTransformer(modules=[word_embedding_model, pooling_model], device=device)

# CoSENTLoss (ranking loss) — prevents the representation collapse that
# CosineSimilarityLoss causes (all cos_sims converge to ~0.9, Spearman → 0).
train_loss = CoSENTLoss(model)

evaluator = EmbeddingSimilarityEvaluator(
    sentences1=[r["sentence1"] for r in stsb["validation"]],
    sentences2=[r["sentence2"] for r in stsb["validation"]],
    scores=[float(r["label"]) / 5.0 for r in stsb["validation"]],
    name="stsb-val",
)

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

print("Starting training...")
training_args = SentenceTransformerTrainingArguments(
    output_dir=str(OUTPUT_DIR),
    num_train_epochs=EPOCHS,
    per_device_train_batch_size=BATCH_SIZE,
    warmup_steps=0.1 if not TEST_MODE else 0.0,
    fp16=torch.cuda.is_available(),
    eval_strategy="epoch",
    save_strategy="epoch",
    load_best_model_at_end=True,
    metric_for_best_model="stsb-val_spearman_cosine",
    greater_is_better=True,
    save_total_limit=1,
)

trainer = SentenceTransformerTrainer(
    model=model,
    args=training_args,
    train_dataset=train_dataset,
    eval_dataset=val_dataset,
    loss=train_loss,
    evaluator=evaluator,
)
trainer.train()

model.save(str(OUTPUT_DIR))

# ── Verify pooling mode ───────────────────────────────────────────────────────
pooling_cfg = OUTPUT_DIR / "1_Pooling" / "config.json"
if pooling_cfg.exists():
    with open(pooling_cfg) as f:
        cfg = json.load(f)
    mode = cfg.get("pooling_mode", "")
    old_mode = cfg.get("pooling_mode_mean_tokens", False)
    is_mean = (mode == "mean") or old_mode
    print(f"\nPooling check — mode: {mode or ('mean' if old_mode else '?')}")
    if not is_mean:
        print("WARNING: Model is NOT using mean pooling. Swift must match this.")
    else:
        print("OK: Mean pooling confirmed.")
else:
    print("WARNING: Pooling config not found — model may not have saved correctly.")

# ── Final evaluation ──────────────────────────────────────────────────────────
final_model = SentenceTransformer(str(OUTPUT_DIR), device=device)
score_raw = evaluator(final_model)

if isinstance(score_raw, dict):
    spearman = score_raw.get("spearman_cosine", next(iter(score_raw.values())))
else:
    spearman = float(score_raw)

Path("results").mkdir(exist_ok=True)
with open("results/distilbert_stsb.txt", "w") as f:
    f.write(f"Model: {BASE_MODEL}\n")
    f.write(f"Device: {device}\n")
    f.write(f"Epochs: {EPOCHS}\n")
    f.write(f"STS-B Spearman correlation: {spearman:.4f}\n")

print(f"\nFinal STS-B Spearman: {spearman:.4f} (target > 0.75)")
print(f"Model saved to: {OUTPUT_DIR}")
if spearman > 0.75:
    print("PASS ✓")
else:
    print("FAIL ✗ — consider more epochs")
