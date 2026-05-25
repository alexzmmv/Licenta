"""
Fine-tune DistilBERT on STS-B for sentence-level semantic similarity.
Output: training/models/distilbert-stsb/

Run: python train_embedding_distilbert.py
Time: ~20 min (RTX 2070) | ~90 min (M1 MPS) | ~5h (CPU)

DistilBERT produces higher-quality embeddings than MobileBERT but is 2.5x larger.
Use as Backup A if MobileBERT Core ML conversion fails.

Pitfall refs: 09_AI_PITFALLS.md — Pitfall 7.4 (pooling mismatch)
"""

import json
from pathlib import Path

import torch
import datasets
from sentence_transformers import SentenceTransformer, InputExample, losses
from sentence_transformers.evaluation import EmbeddingSimilarityEvaluator
from torch.utils.data import DataLoader

BASE_MODEL = "distilbert-base-uncased"
OUTPUT_DIR = Path("models/distilbert-stsb")
BATCH_SIZE = 16 if torch.cuda.is_available() else 8
EPOCHS     = 4
WARMUP_STEPS = 100

device = (
    "cuda" if torch.cuda.is_available() else
    "mps"  if torch.backends.mps.is_available() else
    "cpu"
)
print(f"Device: {device} | Model: {BASE_MODEL}")

print("Loading STS-B dataset...")
stsb = datasets.load_dataset("glue", "stsb", cache_dir="./hf_cache")

def to_examples(split):
    return [
        InputExample(
            texts=[row["sentence1"], row["sentence2"]],
            label=float(row["label"]) / 5.0,
        )
        for row in stsb[split]
    ]

train_examples = to_examples("train")
val_examples   = to_examples("validation")

model     = SentenceTransformer(BASE_MODEL, device=device)
train_dl  = DataLoader(train_examples, shuffle=True, batch_size=BATCH_SIZE)
train_loss = losses.CosineSimilarityLoss(model)
evaluator  = EmbeddingSimilarityEvaluator.from_input_examples(val_examples, name="stsb-val")

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

print("Starting training...")
model.fit(
    train_objectives=[(train_dl, train_loss)],
    evaluator=evaluator,
    epochs=EPOCHS,
    warmup_steps=WARMUP_STEPS,
    output_path=str(OUTPUT_DIR),
    save_best_model=True,
    show_progress_bar=True,
)

pooling_cfg = OUTPUT_DIR / "1_Pooling" / "config.json"
if pooling_cfg.exists():
    with open(pooling_cfg) as f:
        cfg = json.load(f)
    print(f"Pooling mode — mean: {cfg.get('pooling_mode_mean_tokens')} | CLS: {cfg.get('pooling_mode_cls_token')}")

final_model = SentenceTransformer(str(OUTPUT_DIR), device=device)
evaluator2  = EmbeddingSimilarityEvaluator.from_input_examples(val_examples, name="stsb-final")
score = evaluator2(final_model)

Path("results").mkdir(exist_ok=True)
with open("results/distilbert_stsb.txt", "w") as f:
    f.write(f"Model: {BASE_MODEL}\nDevice: {device}\nEpochs: {EPOCHS}\n")
    f.write(f"STS-B Spearman correlation: {score:.4f}\n")

print(f"\nFinal STS-B Spearman: {score:.4f} (target > 0.75)")
print(f"Model saved to: {OUTPUT_DIR}")
